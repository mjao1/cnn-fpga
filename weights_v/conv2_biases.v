// Biases for second conv layer
// Quantization scale: 1234.567

module conv2_biases(
    input wire [7:0] filter_idx,
    output reg signed [7:0] bias
);

    always @* begin
        case(filter_idx)
            8'd0: bias = -8'sd26;
            8'd1: bias = -8'sd93;
            8'd2: bias = -8'sd42;
            8'd3: bias = -8'sd11;
            8'd4: bias = 8'sd94;
            8'd5: bias = -8'sd127;
            8'd6: bias = -8'sd15;
            8'd7: bias = 8'sd28;
            8'd8: bias = -8'sd57;
            8'd9: bias = 8'sd21;
            8'd10: bias = -8'sd19;
            8'd11: bias = 8'sd43;
            8'd12: bias = 8'sd85;
            8'd13: bias = -8'sd36;
            8'd14: bias = 8'sd11;
            8'd15: bias = -8'sd72;
            default: bias = 8'sd0;
        endcase
    end

endmodule
