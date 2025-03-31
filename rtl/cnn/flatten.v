// flatten module
// Input: 16 channels, 4x4 feature maps (output of second pooling layer)
// Output: 256-element vector (16*4*4 = 256)

module flatten #(
    parameter IN_CHANNELS = 16,
    parameter IN_WIDTH = 4,
    parameter IN_HEIGHT = 4,
    parameter DATA_WIDTH = 8,
    parameter OUT_FEATURES = 256
)(
    input wire clk,
    input wire rst,
    input wire valid_in,
    input wire [(DATA_WIDTH*IN_CHANNELS)-1:0] data_in,  // Packed input from 16 channels
    input wire [7:0] x_in,                              // x coordinate from feature map
    input wire [7:0] y_in,                              // y coordinate from feature map
    input wire [3:0] channel_in,                        // Current channel (0-15)
    
    output reg valid_out,
    output reg [DATA_WIDTH-1:0] data_out,
    output reg [7:0] addr_out                           // Address in flattened vector (0-255)
);

    wire [DATA_WIDTH-1:0] channel_data [0:IN_CHANNELS-1];
    genvar c;
    generate
        for (c = 0; c < IN_CHANNELS; c = c + 1) begin : unpack_inputs
            assign channel_data[c] = data_in[((c+1)*DATA_WIDTH)-1:c*DATA_WIDTH];
        end
    endgenerate

    // Flattened address
    wire [7:0] flat_addr = (channel_in * IN_HEIGHT * IN_WIDTH) + (y_in * IN_WIDTH) + x_in;
    
    always @(posedge clk) begin
        if (rst) begin
            valid_out <= 1'b0;
            data_out <= {DATA_WIDTH{1'b0}};
            addr_out <= 8'd0;
        end else begin
            if (valid_in) begin
                valid_out <= 1'b1;
                
                data_out <= channel_data[channel_in];
                
                addr_out <= flat_addr;

            end else begin
                valid_out <= 1'b0;
            end
        end
    end

endmodule
