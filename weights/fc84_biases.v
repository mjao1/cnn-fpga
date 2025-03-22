// Biases for dense_2
// Quantization scale: 2356.791202570871

module fc84_biases(
    input wire [7:0] output_idx,  // Output neuron index
    output reg signed [7:0] bias   // Signed 8-bit bias value
);

    always @* begin
        case(output_idx)
            8'd0: bias = 8'sd102;
            8'd1: bias = 8'sd-27;
            8'd2: bias = 8'sd3;
            8'd3: bias = 8'sd-17;
            8'd4: bias = 8'sd-45;
            8'd5: bias = 8'sd30;
            8'd6: bias = 8'sd-127;
            8'd7: bias = 8'sd-55;
            8'd8: bias = 8'sd99;
            8'd9: bias = 8'sd-11;
            default: bias = 8'sd0;
        endcase
    end

endmodule
