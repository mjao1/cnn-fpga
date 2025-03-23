// first convolutional Layer for LeNet-5 CNN
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
    
    // Filter weights - 6 filters, each 5x5
    // These would typically be loaded from external memory, but for testing we'll define them here
    // In a real implementation, these should come from trained weights
    
    // Filter 0 - Horizontal edge detector
    reg signed [DATA_WIDTH-1:0] weights_0 [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    // Filter 1 - Vertical edge detector
    reg signed [DATA_WIDTH-1:0] weights_1 [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    // Filter 2 - 45° diagonal
    reg signed [DATA_WIDTH-1:0] weights_2 [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    // Filter 3 - 135° diagonal
    reg signed [DATA_WIDTH-1:0] weights_3 [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    // Filter 4 - Blob detector
    reg signed [DATA_WIDTH-1:0] weights_4 [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    // Filter 5 - Identity (center pixel)
    reg signed [DATA_WIDTH-1:0] weights_5 [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    
    reg signed [DATA_WIDTH-1:0] bias [0:NUM_FILTERS-1];
    
    reg [8:0] x_count, y_count;
    reg window_valid;
    
    wire valid_conv [0:NUM_FILTERS-1];
    wire signed [DATA_WIDTH-1:0] conv_out [0:NUM_FILTERS-1];
    
    wire signed [DATA_WIDTH-1:0] window_flat [0:KERNEL_SIZE*KERNEL_SIZE-1];
    wire signed [DATA_WIDTH-1:0] weights_flat [0:NUM_FILTERS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    
    integer ii, jj, kk;
    
    initial begin
        // Filter 0 - Horizontal edge detector
        weights_0[0][0] = -8'd1; weights_0[0][1] = -8'd1; weights_0[0][2] = -8'd1; weights_0[0][3] = -8'd1; weights_0[0][4] = -8'd1;
        weights_0[1][0] = -8'd1; weights_0[1][1] = -8'd1; weights_0[1][2] = -8'd1; weights_0[1][3] = -8'd1; weights_0[1][4] = -8'd1;
        weights_0[2][0] =  8'd2; weights_0[2][1] =  8'd2; weights_0[2][2] =  8'd2; weights_0[2][3] =  8'd2; weights_0[2][4] =  8'd2;
        weights_0[3][0] = -8'd1; weights_0[3][1] = -8'd1; weights_0[3][2] = -8'd1; weights_0[3][3] = -8'd1; weights_0[3][4] = -8'd1;
        weights_0[4][0] = -8'd1; weights_0[4][1] = -8'd1; weights_0[4][2] = -8'd1; weights_0[4][3] = -8'd1; weights_0[4][4] = -8'd1;
        bias[0] = 8'd0;
        
        // Filter 1 - Vertical edge detector
        weights_1[0][0] = -8'd1; weights_1[0][1] = -8'd1; weights_1[0][2] =  8'd2; weights_1[0][3] = -8'd1; weights_1[0][4] = -8'd1;
        weights_1[1][0] = -8'd1; weights_1[1][1] = -8'd1; weights_1[1][2] =  8'd2; weights_1[1][3] = -8'd1; weights_1[1][4] = -8'd1;
        weights_1[2][0] = -8'd1; weights_1[2][1] = -8'd1; weights_1[2][2] =  8'd2; weights_1[2][3] = -8'd1; weights_1[2][4] = -8'd1;
        weights_1[3][0] = -8'd1; weights_1[3][1] = -8'd1; weights_1[3][2] =  8'd2; weights_1[3][3] = -8'd1; weights_1[3][4] = -8'd1;
        weights_1[4][0] = -8'd1; weights_1[4][1] = -8'd1; weights_1[4][2] =  8'd2; weights_1[4][3] = -8'd1; weights_1[4][4] = -8'd1;
        bias[1] = 8'd0;
        
        // Filter 2 - 45° diagonal
        weights_2[0][0] =  8'd2; weights_2[0][1] = -8'd1; weights_2[0][2] = -8'd1; weights_2[0][3] = -8'd1; weights_2[0][4] = -8'd1;
        weights_2[1][0] = -8'd1; weights_2[1][1] =  8'd2; weights_2[1][2] = -8'd1; weights_2[1][3] = -8'd1; weights_2[1][4] = -8'd1;
        weights_2[2][0] = -8'd1; weights_2[2][1] = -8'd1; weights_2[2][2] =  8'd2; weights_2[2][3] = -8'd1; weights_2[2][4] = -8'd1;
        weights_2[3][0] = -8'd1; weights_2[3][1] = -8'd1; weights_2[3][2] = -8'd1; weights_2[3][3] =  8'd2; weights_2[3][4] = -8'd1;
        weights_2[4][0] = -8'd1; weights_2[4][1] = -8'd1; weights_2[4][2] = -8'd1; weights_2[4][3] = -8'd1; weights_2[4][4] =  8'd2;
        bias[2] = 8'd0;
        
        // Filter 3 - 135° diagonal
        weights_3[0][0] = -8'd1; weights_3[0][1] = -8'd1; weights_3[0][2] = -8'd1; weights_3[0][3] = -8'd1; weights_3[0][4] =  8'd2;
        weights_3[1][0] = -8'd1; weights_3[1][1] = -8'd1; weights_3[1][2] = -8'd1; weights_3[1][3] =  8'd2; weights_3[1][4] = -8'd1;
        weights_3[2][0] = -8'd1; weights_3[2][1] = -8'd1; weights_3[2][2] =  8'd2; weights_3[2][3] = -8'd1; weights_3[2][4] = -8'd1;
        weights_3[3][0] = -8'd1; weights_3[3][1] =  8'd2; weights_3[3][2] = -8'd1; weights_3[3][3] = -8'd1; weights_3[3][4] = -8'd1;
        weights_3[4][0] =  8'd2; weights_3[4][1] = -8'd1; weights_3[4][2] = -8'd1; weights_3[4][3] = -8'd1; weights_3[4][4] = -8'd1;
        bias[3] = 8'd0;
        
        // Filter 4 - Blob detector
        weights_4[0][0] = -8'd1; weights_4[0][1] = -8'd1; weights_4[0][2] = -8'd1; weights_4[0][3] = -8'd1; weights_4[0][4] = -8'd1;
        weights_4[1][0] = -8'd1; weights_4[1][1] =  8'd2; weights_4[1][2] =  8'd2; weights_4[1][3] =  8'd2; weights_4[1][4] = -8'd1;
        weights_4[2][0] = -8'd1; weights_4[2][1] =  8'd2; weights_4[2][2] =  8'd4; weights_4[2][3] =  8'd2; weights_4[2][4] = -8'd1;
        weights_4[3][0] = -8'd1; weights_4[3][1] =  8'd2; weights_4[3][2] =  8'd2; weights_4[3][3] =  8'd2; weights_4[3][4] = -8'd1;
        weights_4[4][0] = -8'd1; weights_4[4][1] = -8'd1; weights_4[4][2] = -8'd1; weights_4[4][3] = -8'd1; weights_4[4][4] = -8'd1;
        bias[4] = 8'd0;
        
        // Filter 5 - Identity (center pixel)
        weights_5[0][0] =  8'd0; weights_5[0][1] =  8'd0; weights_5[0][2] =  8'd0; weights_5[0][3] =  8'd0; weights_5[0][4] =  8'd0;
        weights_5[1][0] =  8'd0; weights_5[1][1] =  8'd0; weights_5[1][2] =  8'd0; weights_5[1][3] =  8'd0; weights_5[1][4] =  8'd0;
        weights_5[2][0] =  8'd0; weights_5[2][1] =  8'd0; weights_5[2][2] =  8'd1; weights_5[2][3] =  8'd0; weights_5[2][4] =  8'd0;
        weights_5[3][0] =  8'd0; weights_5[3][1] =  8'd0; weights_5[3][2] =  8'd0; weights_5[3][3] =  8'd0; weights_5[3][4] =  8'd0;
        weights_5[4][0] =  8'd0; weights_5[4][1] =  8'd0; weights_5[4][2] =  8'd0; weights_5[4][3] =  8'd0; weights_5[4][4] =  8'd0;
        bias[5] = 8'd0;
    end
    
    // Flatten 2D arrays to 1D
    generate
        genvar gi, gj, gk;
        for (gi = 0; gi < KERNEL_SIZE; gi = gi + 1) begin
            for (gj = 0; gj < KERNEL_SIZE; gj = gj + 1) begin
                assign window_flat[gi*KERNEL_SIZE + gj] = window[gi][gj];
            end
        end
        
        for (gk = 0; gk < NUM_FILTERS; gk = gk + 1) begin
            for (gi = 0; gi < KERNEL_SIZE; gi = gi + 1) begin
                for (gj = 0; gj < KERNEL_SIZE; gj = gj + 1) begin
                    if (gk == 0) 
                        assign weights_flat[gk][gi*KERNEL_SIZE + gj] = weights_0[gi][gj];
                    else if (gk == 1)
                        assign weights_flat[gk][gi*KERNEL_SIZE + gj] = weights_1[gi][gj];
                    else if (gk == 2)
                        assign weights_flat[gk][gi*KERNEL_SIZE + gj] = weights_2[gi][gj];
                    else if (gk == 3)
                        assign weights_flat[gk][gi*KERNEL_SIZE + gj] = weights_3[gi][gj];
                    else if (gk == 4)
                        assign weights_flat[gk][gi*KERNEL_SIZE + gj] = weights_4[gi][gj];
                    else // gk == 5
                        assign weights_flat[gk][gi*KERNEL_SIZE + gj] = weights_5[gi][gj];
                end
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
                .valid_in(window_valid),

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

                .weight_00(weights_flat[gf][0]), .weight_01(weights_flat[gf][1]), .weight_02(weights_flat[gf][2]), 
                .weight_03(weights_flat[gf][3]), .weight_04(weights_flat[gf][4]),
                .weight_10(weights_flat[gf][5]), .weight_11(weights_flat[gf][6]), .weight_12(weights_flat[gf][7]), 
                .weight_13(weights_flat[gf][8]), .weight_14(weights_flat[gf][9]),
                .weight_20(weights_flat[gf][10]), .weight_21(weights_flat[gf][11]), .weight_22(weights_flat[gf][12]), 
                .weight_23(weights_flat[gf][13]), .weight_24(weights_flat[gf][14]),
                .weight_30(weights_flat[gf][15]), .weight_31(weights_flat[gf][16]), .weight_32(weights_flat[gf][17]), 
                .weight_33(weights_flat[gf][18]), .weight_34(weights_flat[gf][19]),
                .weight_40(weights_flat[gf][20]), .weight_41(weights_flat[gf][21]), .weight_42(weights_flat[gf][22]), 
                .weight_43(weights_flat[gf][23]), .weight_44(weights_flat[gf][24]),

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
            valid_out <= valid_conv[0];
            
            if (valid_conv[0]) begin
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
            
            if (valid_in) begin
                if (x_in == IMG_WIDTH - 1) begin
                    for (ii = 0; ii < KERNEL_SIZE - 1; ii = ii + 1) begin
                        for (jj = 0; jj < IMG_WIDTH; jj = jj + 1) begin
                            line_buffer[ii][jj] <= line_buffer[ii+1][jj];
                        end
                    end
                    for (jj = 0; jj < IMG_WIDTH; jj = jj + 1) begin
                        line_buffer[KERNEL_SIZE - 1][jj] <= 8'd0;
                    end
                end
                
                line_buffer[y_in % KERNEL_SIZE][x_in] <= data_in;
                
                if (y_in >= KERNEL_SIZE - 1) begin
                    for (ii = 0; ii < KERNEL_SIZE; ii = ii + 1) begin
                        for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                            if (x_in >= jj && y_in >= ii)
                                window[ii][jj] <= line_buffer[(y_in - ii) % KERNEL_SIZE][x_in - jj];
                            else
                                window[ii][jj] <= 8'd0;
                        end
                    end
                    
                    window_valid <= (x_in >= KERNEL_SIZE - 1 && y_in >= KERNEL_SIZE - 1);
                end else begin
                    window_valid <= 1'b0;
                end
                
                if (x_in == IMG_WIDTH - 1) begin
                    x_count <= 9'd0;
                    if (y_in == IMG_HEIGHT - 1)
                        y_count <= 9'd0;
                    else
                        y_count <= y_count + 9'd1;
                end else begin
                    x_count <= x_count + 9'd1;
                end
            end else begin
                window_valid <= 1'b0;
            end
        end
    end

endmodule 
