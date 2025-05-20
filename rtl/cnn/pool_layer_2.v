// pooling layer 2
// Input: 16 channels, 8x8 feature maps (output of second convolutional layer)
// Output: 16 channels, 4x4 feature maps
// Pooling: 2x2 max pooling with stride 2

module pool_layer_2 #(
    parameter IN_WIDTH = 8,       // Input feature map width
    parameter IN_HEIGHT = 8,      // Input feature map height
    parameter OUT_WIDTH = 4,      // Output feature map width (8/2)
    parameter OUT_HEIGHT = 4,     // Output feature map height (8/2)
    parameter NUM_CHANNELS = 16,  // Number of channels (same for input and output)
    parameter DATA_WIDTH = 8      // Data width (8-bit fixed point)
)(
    input wire clk,
    input wire rst,
    input wire valid_in,
    input wire [(DATA_WIDTH*NUM_CHANNELS)-1:0] data_in,
    input wire [7:0] x_in,
    input wire [7:0] y_in,
    
    output wire valid_out,
    output wire [(DATA_WIDTH*NUM_CHANNELS)-1:0] data_out,
    output wire [7:0] x_out,
    output wire [7:0] y_out
);

    reg [DATA_WIDTH-1:0] buffer [0:NUM_CHANNELS-1][0:1][0:IN_WIDTH-1]; // Double buffer for two rows per channel
    
    wire [DATA_WIDTH-1:0] data_in_channel [0:NUM_CHANNELS-1];
    wire [DATA_WIDTH-1:0] data_out_channel [0:NUM_CHANNELS-1];
    
    reg [DATA_WIDTH-1:0] window_00 [0:NUM_CHANNELS-1];
    reg [DATA_WIDTH-1:0] window_01 [0:NUM_CHANNELS-1];
    reg [DATA_WIDTH-1:0] window_10 [0:NUM_CHANNELS-1];
    reg [DATA_WIDTH-1:0] window_11 [0:NUM_CHANNELS-1];
    
    reg pool_valid [0:NUM_CHANNELS-1];
    wire pool_valid_out [0:NUM_CHANNELS-1];
    
    reg [7:0] x_pos;
    reg [7:0] y_pos;
    reg [7:0] pool_x;
    reg [7:0] pool_y;
    
    // Unpack input channels
    genvar c;
    generate
        for (c = 0; c < NUM_CHANNELS; c = c + 1) begin : unpack_inputs
            assign data_in_channel[c] = data_in[((c+1)*DATA_WIDTH)-1:c*DATA_WIDTH];
        end
    endgenerate
    
    // Pack output channels
    generate
        for (c = 0; c < NUM_CHANNELS; c = c + 1) begin : pack_outputs
            assign data_out[((c+1)*DATA_WIDTH)-1:c*DATA_WIDTH] = data_out_channel[c];
        end
    endgenerate
    
    // max_pool_2x2 for each channel
    generate
        for (c = 0; c < NUM_CHANNELS; c = c + 1) begin : max_pool_units
            max_pool_2x2 pool_unit (
                .clk(clk),
                .rst(rst),
                .valid_in(pool_valid[c]),
                .data_in_00(window_00[c]),
                .data_in_01(window_01[c]),
                .data_in_10(window_10[c]),
                .data_in_11(window_11[c]),
                .valid_out(pool_valid_out[c]),
                .data_out(data_out_channel[c])
            );
        end
    endgenerate
    
    // Buffer and window formation
    integer i, j;
    always @(posedge clk) begin
        if (rst) begin
            x_pos <= 0;
            y_pos <= 0;
            pool_x <= 0;
            pool_y <= 0;
            
            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                pool_valid[i] <= 0;
            end

            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                for (j = 0; j < IN_WIDTH; j = j + 1) begin
                    buffer[i][0][j] <= 0;
                    buffer[i][1][j] <= 0;
                end
            end
        end else begin
            if (valid_in) begin
                x_pos <= x_in;
                y_pos <= y_in;

                for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                    buffer[i][y_in % 2][x_in] <= data_in_channel[i];
                end
                
                // form a window for pooling when complete 2x2 window)
                if ((x_in % 2 == 1) && (y_in % 2 == 1)) begin
                    for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                        window_00[i] <= buffer[i][0][x_in-1]; // top left
                        window_01[i] <= buffer[i][0][x_in];   // top right
                        window_10[i] <= buffer[i][1][x_in-1]; // bottom left
                        window_11[i] <= data_in_channel[i];   // bottom right (current input)
                        
                        pool_valid[i] <= 1;
                    end
                    
                    // coordinates now handled by counters on output valid
                end else begin
                    for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                        pool_valid[i] <= 0;
                    end
                end
            end else begin
                for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                    pool_valid[i] <= 0;
                end
            end
            // coordinate counters for POOL2 output
            if (pool_valid_out[0]) begin
                if (pool_x == OUT_WIDTH-1) begin
                    pool_x <= 0;
                    if (pool_y == OUT_HEIGHT-1)
                        pool_y <= 0;
                    else
                        pool_y <= pool_y + 1;
                end else begin
                    pool_x <= pool_x + 1;
                end
            end
        end
    end
    
    assign valid_out = pool_valid_out[0];
    
    assign x_out = pool_x;
    assign y_out = pool_y;

endmodule 
