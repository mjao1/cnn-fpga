// Biases for conv2d
// Quantization scale: 2337.0908336068633

module conv1_biases(
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
            default: bias = 8'sd0;
        endcase
    end

endmodule
