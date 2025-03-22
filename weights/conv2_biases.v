// Biases for conv2d_1
// Quantization scale: 1101.7581277976365

module conv2_biases(
    input wire [7:0] filter_idx,  // Filter index
    output reg signed [7:0] bias   // Signed 8-bit bias value
);

    always @* begin
        case(filter_idx)
            8'd0: bias = 8'sd-53;
            8'd1: bias = 8'sd-43;
            8'd2: bias = 8'sd4;
            8'd3: bias = 8'sd-12;
            8'd4: bias = 8'sd-68;
            8'd5: bias = 8'sd127;
            8'd6: bias = 8'sd59;
            8'd7: bias = 8'sd-40;
            8'd8: bias = 8'sd-35;
            8'd9: bias = 8'sd-58;
            8'd10: bias = 8'sd-49;
            8'd11: bias = 8'sd23;
            8'd12: bias = 8'sd-54;
            8'd13: bias = 8'sd13;
            8'd14: bias = 8'sd-48;
            8'd15: bias = 8'sd-34;
            default: bias = 8'sd0;
        endcase
    end

endmodule
