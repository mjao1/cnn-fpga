// max pooling with stride 2 for CNN

module max_pool_2x2 (
    input wire clk,
    input wire rst,
    input wire valid_in,
    input wire signed [7:0] data_in_00,
    input wire signed [7:0] data_in_01,
    input wire signed [7:0] data_in_10,
    input wire signed [7:0] data_in_11,

    output reg         valid_out,
    output reg signed [7:0] data_out
);

    wire signed [7:0] max_top;
    wire signed [7:0] max_bottom;
    wire signed [7:0] max_value;
    
    assign max_top = ($signed(data_in_00) > $signed(data_in_01)) ? data_in_00 : data_in_01;
    assign max_bottom = ($signed(data_in_10) > $signed(data_in_11)) ? data_in_10 : data_in_11;
    assign max_value = ($signed(max_top) > $signed(max_bottom)) ? max_top : max_bottom;
    
    always @(posedge clk) begin
        if (rst) begin
            valid_out <= 1'b0;
            data_out <= 8'd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                data_out <= max_value;
            end
        end
    end

endmodule 
