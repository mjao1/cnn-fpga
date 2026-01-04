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
    output reg valid_out,
    output reg [DATA_WIDTH-1:0] data_out,
    output reg [7:0] addr_out                           // Address in flattened vector (0-255)
);

    reg [DATA_WIDTH-1:0] flat_mem [0:OUT_FEATURES-1];
    
    reg [3:0] flatten_count;

    reg [7:0] output_counter;

    reg flatten_done;
    
    integer i;
    
    always @(posedge clk) begin
        if (rst) begin
            flatten_count <= 0;
            output_counter <= 0;
            flatten_done <= 1'b0;
            valid_out <= 1'b0;
            addr_out <= 8'd0;
        end else begin
            if (!flatten_done) begin
                if (valid_in) begin
                    // For the current valid_in event, which corresponds to one coordinate of the 4x4 grid,
                    // store each channel's value into flat_mem at the proper offset.
                    // Position major order: all 16 channels
                    // Address = position * 16 + channel
                    for(i = 0; i < IN_CHANNELS; i = i + 1) begin
                        flat_mem[flatten_count*16 + i] <= data_in[((i+1)*DATA_WIDTH)-1 -: DATA_WIDTH];
                    end
                    if (flatten_count == 16 - 1) begin
                        flatten_done <= 1'b1;
                    end else begin
                        flatten_count <= flatten_count + 1;
                    end
                end
            end else begin
                // Once flattened memory is loaded, output all 256 values
                valid_out <= 1'b1;
                data_out <= flat_mem[output_counter];
                addr_out <= output_counter;
                if (output_counter == OUT_FEATURES - 1) begin
                    output_counter <= 0;
                end else begin
                    output_counter <= output_counter + 1;
                end
            end
        end
    end

endmodule
