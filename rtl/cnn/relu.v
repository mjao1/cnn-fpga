// ReLU activation function for CNN

module relu(
    input wire clk,
    input wire rst,
    input wire valid_in,
    input wire signed [7:0] data_in,
    output reg         valid_out,
    output reg signed [7:0] data_out
);

    always @(posedge clk) begin
        if (rst) begin
            data_out <= 8'd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                data_out <= (data_in[7]) ? 8'd0 : data_in;
            end
        end
    end

endmodule 
