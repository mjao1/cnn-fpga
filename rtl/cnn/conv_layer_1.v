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
    parameter DATA_WIDTH = 8      // Data width (8-bit fixed point)
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
    output reg [8:0] y_out                       // Y coordinate of output pixel
);

    reg [DATA_WIDTH-1:0] line_buffer [0:KERNEL_SIZE-1][0:IMG_WIDTH-1];
    reg [DATA_WIDTH-1:0] window [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    
    reg signed [DATA_WIDTH-1:0] weight [0:NUM_FILTERS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    reg signed [DATA_WIDTH-1:0] bias [0:NUM_FILTERS-1];
    
    reg [8:0] x_count, y_count;
    reg window_valid;
    
    wire valid_conv [0:NUM_FILTERS-1];
    wire signed [DATA_WIDTH-1:0] conv_out [0:NUM_FILTERS-1];
    
    wire signed [DATA_WIDTH-1:0] window_flat [0:KERNEL_SIZE*KERNEL_SIZE-1];
    
    integer ii, jj, kk;
    
    localparam INIT = 2'b00;
    localparam LOAD_WEIGHTS = 2'b01;
    localparam RUNNING = 2'b10;
    
    reg [1:0] state;
    reg [7:0] current_filter;
    reg [7:0] current_kernel;
    reg load_bias;
    
    wire signed [DATA_WIDTH-1:0] loaded_weight;
    wire signed [DATA_WIDTH-1:0] loaded_bias;
    
    weight_loader #(
        .DATA_WIDTH(DATA_WIDTH)
    ) weight_loader_inst (
        .clk(clk),
        .rst(rst),
        .layer_select(8'd0),
        .filter_idx(current_filter),
        .in_channel(8'd0),
        .kernel_row(current_kernel / KERNEL_SIZE),
        .kernel_col(current_kernel % KERNEL_SIZE),
        .input_idx(16'd0),
        .neuron_idx(16'd0),
        .weight_out(loaded_weight),
        .bias_out(loaded_bias)
    );
    
    // Weight loading state machine
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
                    state <= LOAD_WEIGHTS;
                    current_filter <= 8'd0;
                    current_kernel <= 8'd0;
                    load_bias <= 1'b0;
                end
                
                LOAD_WEIGHTS: begin
                    if (!load_bias) begin
                        // Store weight
                        weight[current_filter][current_kernel] <= loaded_weight;
                        
                        // Move to next weight
                        if (current_kernel == KERNEL_SIZE*KERNEL_SIZE-1) begin
                            current_kernel <= 8'd0;
                            load_bias <= 1'b1;
                        end else begin
                            current_kernel <= current_kernel + 8'd1;
                        end
                    end else begin
                        // Store  bias
                        bias[current_filter] <= loaded_bias;
                        
                        // Move to next filter
                        if (current_filter == NUM_FILTERS-1) begin
                            state <= RUNNING;
                        end else begin
                            current_filter <= current_filter + 8'd1;
                            load_bias <= 1'b0;
                        end
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
    
    // Instantiate 6 convolution modules for each filter
    generate
        genvar gf;
        for (gf = 0; gf < NUM_FILTERS; gf = gf + 1) begin : conv_units
            conv_5x5 conv_inst (
                .clk(clk),
                .rst(rst),
                .valid_in(window_valid && (state == RUNNING)),

                .data_in_00(window_flat[0]), .data_in_01(window_flat[1]), .data_in_02(window_flat[2]), 
                .data_in_03(window_flat[3]), .data_in_04(window_flat[4]),
                .data_in_10(window_flat[5]), .data_in_11(window_flat[6]), .data_in_12(window_flat[7]), 
                .data_in_13(window_flat[8]), .data_in_14(window_flat[9]),
                .data_in_20(window_flat[10]), .data_in_21(window_flat[11]), .data_in_22(window_flat[12]), 
                .data_in_23(window_flat[13]), .data_in_24(window_flat[14]),
                .data_in_30(window_flat[15]), .data_in_31(window_flat[16]), .data_in_32(window_flat[17]), 
                .data_in_33(window_flat[18]), .data_in_34(window_flat[19]),
                .data_in_40(window_flat[20]), .data_in_41(window_flat[21]), .data_in_42(window_flat[22]), 
                .data_in_43(window_flat[23]), .data_in_44(window_flat[24]),

                .weight_00(weight[gf][0]), .weight_01(weight[gf][1]), .weight_02(weight[gf][2]), 
                .weight_03(weight[gf][3]), .weight_04(weight[gf][4]),
                .weight_10(weight[gf][5]), .weight_11(weight[gf][6]), .weight_12(weight[gf][7]), 
                .weight_13(weight[gf][8]), .weight_14(weight[gf][9]),
                .weight_20(weight[gf][10]), .weight_21(weight[gf][11]), .weight_22(weight[gf][12]), 
                .weight_23(weight[gf][13]), .weight_24(weight[gf][14]),
                .weight_30(weight[gf][15]), .weight_31(weight[gf][16]), .weight_32(weight[gf][17]), 
                .weight_33(weight[gf][18]), .weight_34(weight[gf][19]),
                .weight_40(weight[gf][20]), .weight_41(weight[gf][21]), .weight_42(weight[gf][22]), 
                .weight_43(weight[gf][23]), .weight_44(weight[gf][24]),

                .bias(bias[gf]),

                .valid_out(valid_conv[gf]),
                .data_out(conv_out[gf])
            );
        end
    endgenerate
    
    always @(posedge clk) begin
        if (rst) begin
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
            valid_out <= (state == RUNNING) && valid_conv[0];
            
            if ((state == RUNNING) && valid_conv[0]) begin
                data_out_0 <= conv_out[0];
                data_out_1 <= conv_out[1];
                data_out_2 <= conv_out[2];
                data_out_3 <= conv_out[3];
                data_out_4 <= conv_out[4];
                data_out_5 <= conv_out[5];
                
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
            
            // Process input data and update window
            if (valid_in) begin
                line_buffer[y_in % KERNEL_SIZE][x_in] <= data_in;

                if (y_in >= KERNEL_SIZE - 1 && x_in >= KERNEL_SIZE - 1) begin
                    for (ii = 0; ii < KERNEL_SIZE; ii = ii + 1) begin
                        for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                            window[ii][jj] <= line_buffer[(y_in - (KERNEL_SIZE-1-ii)) % KERNEL_SIZE][x_in - (KERNEL_SIZE-1-jj)];
                        end
                    end
                    window_valid <= 1'b1;
                end else begin
                    window_valid <= 1'b0;
                end
                
                // Line buffer handling
                if (x_in == IMG_WIDTH - 1) begin
                    y_count <= y_count + 9'd1;

                    if (y_count >= KERNEL_SIZE - 1) begin
                        for (ii = 0; ii < KERNEL_SIZE - 1; ii = ii + 1) begin
                            for (jj = 0; jj < IMG_WIDTH; jj = jj + 1) begin
                                line_buffer[ii][jj] <= line_buffer[ii+1][jj];
                            end
                        end
                    end
                end
                
                if (x_in == IMG_WIDTH - 1)
                    x_count <= 9'd0;
                else
                    x_count <= x_count + 9'd1;
            end else begin
                window_valid <= 1'b0;
            end
        end
    end

endmodule 
