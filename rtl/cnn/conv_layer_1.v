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

    localparam MEM_F_W = $clog2(NUM_FILTERS);
    localparam MEM_K_W = $clog2(KERNEL_SIZE);

    reg [DATA_WIDTH-1:0] line_buffer [0:KERNEL_SIZE-1][0:IMG_WIDTH-1];
    reg [DATA_WIDTH-1:0] window [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    
    reg signed [DATA_WIDTH-1:0] weight [0:NUM_FILTERS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    reg signed [DATA_WIDTH-1:0] bias [0:NUM_FILTERS-1];
    
    reg [2:0] row_idx_m1;
    reg [2:0] row_idx_m2;
    reg [2:0] row_idx_m3;
    reg [2:0] row_idx_m4;

    reg [2:0] wr_row_idx;

    always @(*) begin
        case (wr_row_idx)
            3'd0: begin
                row_idx_m1 = 3'd4;
                row_idx_m2 = 3'd3;
                row_idx_m3 = 3'd2;
                row_idx_m4 = 3'd1;
            end
            3'd1: begin
                row_idx_m1 = 3'd0;
                row_idx_m2 = 3'd4;
                row_idx_m3 = 3'd3;
                row_idx_m4 = 3'd2;
            end
            3'd2: begin
                row_idx_m1 = 3'd1;
                row_idx_m2 = 3'd0;
                row_idx_m3 = 3'd4;
                row_idx_m4 = 3'd3;
            end
            3'd3: begin
                row_idx_m1 = 3'd2;
                row_idx_m2 = 3'd1;
                row_idx_m3 = 3'd0;
                row_idx_m4 = 3'd4;
            end
            default: begin
                row_idx_m1 = 3'd3;
                row_idx_m2 = 3'd2;
                row_idx_m3 = 3'd1;
                row_idx_m4 = 3'd0;
            end
        endcase
    end

    reg conv_window_valid;
    assign busy = conv_window_valid;
    
    wire valid_conv [0:NUM_FILTERS-1];
    wire signed [DATA_WIDTH-1:0] conv_out [0:NUM_FILTERS-1];
    
    wire signed [DATA_WIDTH-1:0] window_flat [0:KERNEL_SIZE*KERNEL_SIZE-1];
    wire [(DATA_WIDTH*KERNEL_SIZE*KERNEL_SIZE)-1:0] window_flat_packed;
    
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

    wire [7:0] weight_kernel_row;
    wire [7:0] weight_kernel_col;
    assign weight_kernel_row = current_kernel / KERNEL_SIZE;
    assign weight_kernel_col = current_kernel % KERNEL_SIZE;

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
        .filter_idx(current_filter[MEM_F_W-1:0]),
        .in_channel(1'b0),
        .kernel_row(weight_kernel_row[MEM_K_W-1:0]),
        .kernel_col(weight_kernel_col[MEM_K_W-1:0]),
        .weight_out(loaded_weight)
    );

    conv1_bias_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FILTERS(NUM_FILTERS)
    ) conv1_biases (
        .clk(clk),
        .rst(rst),
        .filter_idx(current_filter[MEM_F_W-1:0]),
        .bias_out(loaded_bias)
    );
    
    // Weight loading state machine
    // Two phase loading: set address, wait for BRAM, then store data
    always @(posedge clk) begin
        if (rst) begin
            state <= INIT;
            current_filter <= 8'd0;
            current_kernel <= 8'd0;

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

    generate
        genvar gp;
        for (gp = 0; gp < KERNEL_SIZE*KERNEL_SIZE; gp = gp + 1) begin : pack_window
            assign window_flat_packed[((gp + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH] = window_flat[gp];
        end
    endgenerate
    
    reg conv_window_valid_q;
    always @(posedge clk) begin
        if (rst)
            conv_window_valid_q <= 1'b0;
        else
            conv_window_valid_q <= conv_window_valid;
    end

    // Instantiate 6 convolution modules for each filter
    generate
        genvar gf;
        for (gf = 0; gf < NUM_FILTERS; gf = gf + 1) begin : conv_units
            // Create local wires for weight array
            wire signed [DATA_WIDTH-1:0] local_weight [0:KERNEL_SIZE*KERNEL_SIZE-1];
            wire [(DATA_WIDTH*KERNEL_SIZE*KERNEL_SIZE)-1:0] local_weight_packed;
            genvar gw;
            for (gw = 0; gw < KERNEL_SIZE*KERNEL_SIZE; gw = gw + 1) begin : weight_assign
                assign local_weight[gw] = weight[gf][gw];
            end
            genvar gw_pack;
            for (gw_pack = 0; gw_pack < KERNEL_SIZE*KERNEL_SIZE; gw_pack = gw_pack + 1) begin : weight_pack
                assign local_weight_packed[((gw_pack + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH] = local_weight[gw_pack];
            end
            
            conv_5x5 #(
                .FRAC_BITS(FRAC_BITS)
            ) conv_inst (
                .clk(clk),
                .rst(rst),
                .valid_in(conv_window_valid_q),
                .data_in(window_flat_packed),
                .weight_in(local_weight_packed),
                .bias_in(bias[gf]),
                .valid_out(valid_conv[gf]),
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
            conv_window_valid <= 1'b0;
            wr_row_idx <= 3'd0;
            valid_out <= 1'b0;
            
            x_out <= 9'd0;
            y_out <= 9'd0;
            
            data_out_0 <= 8'd0;
            data_out_1 <= 8'd0;
            data_out_2 <= 8'd0;
            data_out_3 <= 8'd0;
            data_out_4 <= 8'd0;
            data_out_5 <= 8'd0;
            
            // Initialize buffers and filter outputs
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
            conv_window_valid <= 1'b0;

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
            
            if (valid_in) begin
                line_buffer[wr_row_idx][x_in] <= data_in;

                if (x_in == IMG_WIDTH - 1) begin
                    if (wr_row_idx == KERNEL_SIZE-1)
                        wr_row_idx <= 3'd0;
                    else
                        wr_row_idx <= wr_row_idx + 3'd1;
                end
            end

            // Process input data and update windows
            if (valid_in && !conv_window_valid) begin
                if (y_in >= KERNEL_SIZE - 1 && x_in >= KERNEL_SIZE - 1) begin

                    // Form window when we have enough data
                    if (x_in == KERNEL_SIZE-1) begin
                        for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                            window[0][jj] <= line_buffer[row_idx_m4][jj];
                            window[1][jj] <= line_buffer[row_idx_m3][jj];
                            window[2][jj] <= line_buffer[row_idx_m2][jj];
                            window[3][jj] <= line_buffer[row_idx_m1][jj];
                        end
                        window[4][0] <= line_buffer[wr_row_idx][0];
                        window[4][1] <= line_buffer[wr_row_idx][1];
                        window[4][2] <= line_buffer[wr_row_idx][2];
                        window[4][3] <= line_buffer[wr_row_idx][3];
                        window[4][4] <= data_in;
                    end else begin
                        for (ii = 0; ii < KERNEL_SIZE; ii = ii + 1) begin
                            for (jj = 0; jj < KERNEL_SIZE-1; jj = jj + 1) begin
                                window[ii][jj] <= window[ii][jj+1];
                            end
                        end
                        window[0][KERNEL_SIZE-1] <= line_buffer[row_idx_m4][x_in];
                        window[1][KERNEL_SIZE-1] <= line_buffer[row_idx_m3][x_in];
                        window[2][KERNEL_SIZE-1] <= line_buffer[row_idx_m2][x_in];
                        window[3][KERNEL_SIZE-1] <= line_buffer[row_idx_m1][x_in];
                        window[4][KERNEL_SIZE-1] <= data_in;
                    end
                    conv_window_valid <= 1'b1;
                end
            end
        end
    end

endmodule 
