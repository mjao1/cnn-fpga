// first convolutional layer
// Input: 1 channel, 28x28 image
// Output: 6 channels, 24x24 feature maps
// Filter size: 5x5, stride 1

module conv_layer_1 #(
    parameter IMG_WIDTH = 28,     // Input image width
    parameter IMG_HEIGHT = 28,    // Input image height
    parameter OUT_WIDTH = 24,     // Output feature map width (28-5+1)
    parameter OUT_HEIGHT = 24,    // Output feature map height (28-5+1)
    parameter NUM_FILTERS = 6,    // Number of filters in first layer of LeNet-5
    parameter KERNEL_SIZE = 5,    // Kernel size (5x5)
    parameter DATA_WIDTH = 8,     // Data width (8-bit fixed point)
    parameter FRAC_BITS = 7       // Q1.7 format
)(
    input wire clk,
    input wire rst,
    input wire valid_in,                         // Input valid signal
    input wire [DATA_WIDTH-1:0] data_in,         // Serial pixel input
    input wire [8:0] x_in,                       // X coordinate of current pixel
    input wire [8:0] y_in,                       // Y coordinate of current pixel
    output reg valid_out,                        // Output valid signal
    output reg [DATA_WIDTH-1:0] data_out_0,      // Output for filter 0
    output reg [DATA_WIDTH-1:0] data_out_1,      // Output for filter 1
    output reg [DATA_WIDTH-1:0] data_out_2,      // Output for filter 2
    output reg [DATA_WIDTH-1:0] data_out_3,      // Output for filter 3
    output reg [DATA_WIDTH-1:0] data_out_4,      // Output for filter 4
    output reg [DATA_WIDTH-1:0] data_out_5,      // Output for filter 5
    output reg [8:0] x_out,                      // X coordinate of output pixel
    output reg [8:0] y_out,                      // Y coordinate of output pixel
    output wire busy
);

    reg [DATA_WIDTH-1:0] line_buffer [0:KERNEL_SIZE-1][0:IMG_WIDTH-1];
    reg [DATA_WIDTH-1:0] window [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    
    reg signed [DATA_WIDTH-1:0] weight [0:NUM_FILTERS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    reg signed [DATA_WIDTH-1:0] bias [0:NUM_FILTERS-1];
    
    reg [8:0] x_count, y_count;
    reg window_valid;

    reg serial_busy;
    reg serial_busy_d;
    reg [5:0] ser_step;
    assign busy = serial_busy;
    
    wire valid_conv [0:NUM_FILTERS-1];
    wire signed [DATA_WIDTH-1:0] conv_out [0:NUM_FILTERS-1];
    
    wire signed [DATA_WIDTH-1:0] window_flat [0:KERNEL_SIZE*KERNEL_SIZE-1];
    
    integer ii, jj, kk;
    
    localparam INIT = 3'b000;
    localparam LOAD_WEIGHTS_ADDR = 3'b001;  // Set address, wait for BRAM
    localparam LOAD_WEIGHTS_DATA = 3'b010;  // Store data, advance to next
    localparam LOAD_BIAS_ADDR = 3'b011;     // Set bias address
    localparam LOAD_BIAS_DATA = 3'b100;     // Store bias
    localparam RUNNING = 3'b101;
    
    reg [2:0] state;
    reg [7:0] current_filter;
    reg [7:0] current_kernel;
    reg load_bias;
    
    wire signed [DATA_WIDTH-1:0] loaded_weight;
    wire signed [DATA_WIDTH-1:0] loaded_bias;
    
    conv1_weight_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FILTERS(NUM_FILTERS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .IN_CHANNELS(1)
    ) conv1_weights (
        .clk(clk),
        .rst(rst),
        .filter_idx(current_filter),
        .in_channel(8'd0),
        .kernel_row(current_kernel / KERNEL_SIZE),
        .kernel_col(current_kernel % KERNEL_SIZE),
        .weight_out(loaded_weight)
    );

    conv1_bias_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FILTERS(NUM_FILTERS)
    ) conv1_biases (
        .clk(clk),
        .rst(rst),
        .filter_idx(current_filter),
        .bias_out(loaded_bias)
    );
    
    // Weight loading state machine
    // Two phase loading: set address, wait for BRAM, then store data
    always @(posedge clk) begin
        if (rst) begin
            state <= INIT;
            current_filter <= 8'd0;
            current_kernel <= 8'd0;
            load_bias <= 1'b0;
            
            for (ii = 0; ii < NUM_FILTERS; ii = ii + 1) begin
                bias[ii] <= 8'd0;
                for (jj = 0; jj < KERNEL_SIZE*KERNEL_SIZE; jj = jj + 1) begin
                    weight[ii][jj] <= 8'd0;
                end
            end
        end else begin
            case (state)
                INIT: begin
                    // Start loading, address is set by current_filter/current_kernel
                    state <= LOAD_WEIGHTS_ADDR;
                    current_filter <= 8'd0;
                    current_kernel <= 8'd0;
                    load_bias <= 1'b0;
                end
                
                LOAD_WEIGHTS_ADDR: begin
                    // Address is set, wait one cycle for BRAM to output data
                    state <= LOAD_WEIGHTS_DATA;
                end
                
                LOAD_WEIGHTS_DATA: begin
                    // BRAM output is valid, store weight
                    weight[current_filter][current_kernel] <= loaded_weight;
                    
                    // Move to next weight
                    if (current_kernel == KERNEL_SIZE*KERNEL_SIZE-1) begin
                        current_kernel <= 8'd0;
                        state <= LOAD_BIAS_ADDR;
                    end else begin
                        current_kernel <= current_kernel + 8'd1;
                        state <= LOAD_WEIGHTS_ADDR;
                    end
                end
                
                LOAD_BIAS_ADDR: begin
                    // Wait for bias BRAM output
                    state <= LOAD_BIAS_DATA;
                end
                
                LOAD_BIAS_DATA: begin
                    // Store  bias
                    bias[current_filter] <= loaded_bias;
                    
                    // Move to next filter
                    if (current_filter == NUM_FILTERS-1) begin
                        state <= RUNNING;
                    end else begin
                        current_filter <= current_filter + 8'd1;
                        current_kernel <= 8'd0;
                        state <= LOAD_WEIGHTS_ADDR;
                    end
                end
                
                RUNNING: begin

                end
                
                default: state <= INIT;
            endcase
        end
    end
    
    // Flatten 2D window
    generate
        genvar gi, gj;
        for (gi = 0; gi < KERNEL_SIZE; gi = gi + 1) begin
            for (gj = 0; gj < KERNEL_SIZE; gj = gj + 1) begin
                assign window_flat[gi*KERNEL_SIZE + gj] = window[gi][gj];
            end
        end
    endgenerate
    
    wire conv_start;
    wire signed [DATA_WIDTH-1:0] conv_data_in;
    wire signed [DATA_WIDTH-1:0] conv_weight_in [0:NUM_FILTERS-1];

    assign conv_start = serial_busy & ~serial_busy_d;
    assign conv_data_in = (serial_busy & ser_step >= 6'd1 & ser_step <= 6'd25) ? window_flat[ser_step - 6'd1] : 8'sd0;
    
    genvar gwf;
    generate
        for (gwf = 0; gwf < NUM_FILTERS; gwf = gwf + 1) begin : wt_mux
            assign conv_weight_in[gwf] = (serial_busy & ser_step >= 6'd1 & ser_step <= 6'd25) ? weight[gwf][ser_step - 6'd1] : (serial_busy & (ser_step == 6'd26)) ? bias[gwf] : 8'sd0;
        end
    endgenerate

    // Instantiate 6 convolution modules for each filter
    generate
        genvar gf;
        for (gf = 0; gf < NUM_FILTERS; gf = gf + 1) begin : conv_units
            conv_5x5 #(
                .FRAC_BITS(FRAC_BITS)
            ) conv_inst (
                .clk(clk),
                .rst(rst),
                .start(conv_start),
                .data_in(conv_data_in),
                .weight_in(conv_weight_in[gf]),

                .done(valid_conv[gf]),
                .data_out(conv_out[gf]),
                .raw_sum()
            );
        end
    endgenerate
    
    wire [7:0] relu_out [0:NUM_FILTERS-1];
    wire relu_valid [0:NUM_FILTERS-1];
    
    genvar i;
    generate
        for(i = 0; i < NUM_FILTERS; i = i + 1) begin: relu_inst_block
            relu u_relu (
                .clk(clk),
                .rst(rst),
                .valid_in(valid_conv[i]),
                .data_in(conv_out[i]),
                .valid_out(relu_valid[i]),
                .data_out(relu_out[i])
            );
        end
    endgenerate
    
    always @(posedge clk) begin
        if (rst) begin
            serial_busy <= 1'b0;
            serial_busy_d <= 1'b0;
            ser_step <= 6'd0;
            x_count <= 9'd0;
            y_count <= 9'd0;
            window_valid <= 1'b0;
            valid_out <= 1'b0;
            
            x_out <= 9'd0;
            y_out <= 9'd0;
            
            data_out_0 <= 8'd0;
            data_out_1 <= 8'd0;
            data_out_2 <= 8'd0;
            data_out_3 <= 8'd0;
            data_out_4 <= 8'd0;
            data_out_5 <= 8'd0;
            
            for (ii = 0; ii < KERNEL_SIZE; ii = ii + 1) begin
                for (jj = 0; jj < IMG_WIDTH; jj = jj + 1) begin
                    line_buffer[ii][jj] <= 8'd0;
                end
            end
            
            for (ii = 0; ii < KERNEL_SIZE; ii = ii + 1) begin
                for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                    window[ii][jj] <= 8'd0;
                end
            end
        end else begin
            serial_busy_d <= serial_busy;

            if (serial_busy) begin
                if (ser_step == 6'd28) begin
                    serial_busy <= 1'b0;
                    ser_step <= 6'd0;
                end else
                    ser_step <= ser_step + 6'd1;
            end

            if (valid_out) begin
                if (x_out == OUT_WIDTH - 1) begin
                    x_out <= 9'd0;
                    if (y_out == OUT_HEIGHT - 1)
                        y_out <= 9'd0;
                    else
                        y_out <= y_out + 9'd1;
                end else begin
                    x_out <= x_out + 9'd1;
                end
            end
            
            valid_out <= (state == RUNNING) && relu_valid[0];
            
            if ((state == RUNNING) && relu_valid[0]) begin
                data_out_0 <= relu_out[0];
                data_out_1 <= relu_out[1];
                data_out_2 <= relu_out[2];
                data_out_3 <= relu_out[3];
                data_out_4 <= relu_out[4];
                data_out_5 <= relu_out[5];
            end
            
            // Line buffer must advance on every input pixel; cnn_top may assert valid_in
            // while serial_busy (same-cycle overlap). Window + serial start only when idle.
            if (valid_in) begin
                line_buffer[y_in % KERNEL_SIZE][x_in] <= data_in;

                if (x_in == IMG_WIDTH - 1) begin
                    y_count <= y_count + 9'd1;
                    x_count <= 9'd0;
                end else begin
                    x_count <= x_count + 9'd1;
                end
            end

            if (valid_in && !serial_busy) begin
                if (y_in >= KERNEL_SIZE - 1 && x_in >= KERNEL_SIZE - 1) begin
                    for (ii = 0; ii < KERNEL_SIZE; ii = ii + 1) begin
                        for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                            if (ii == KERNEL_SIZE-1 && jj == KERNEL_SIZE-1)
                                window[ii][jj] <= data_in;
                            else
                                window[ii][jj] <= line_buffer[(y_in - (KERNEL_SIZE-1-ii)) % KERNEL_SIZE][x_in - (KERNEL_SIZE-1-jj)];
                        end
                    end
                    window_valid <= 1'b1;
                    serial_busy <= 1'b1;
                    ser_step <= 6'd0;
                end else begin
                    window_valid <= 1'b0;
                end
            end else begin
                window_valid <= 1'b0;
            end
        end
    end

endmodule 
