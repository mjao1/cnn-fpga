// Biases for dense_1
// Quantization scale: 1488.5630379952001

module fc120_biases(
    input wire [7:0] output_idx,  // Output neuron index
    output reg signed [7:0] bias   // Signed 8-bit bias value
);

    always @* begin
        case(output_idx)
            8'd0: bias = 8'sd-39;
            8'd1: bias = 8'sd23;
            8'd2: bias = 8'sd41;
            8'd3: bias = 8'sd90;
            8'd4: bias = 8'sd-15;
            8'd5: bias = 8'sd-20;
            8'd6: bias = 8'sd80;
            8'd7: bias = 8'sd-31;
            8'd8: bias = 8'sd62;
            8'd9: bias = 8'sd84;
            8'd10: bias = 8'sd30;
            8'd11: bias = 8'sd69;
            8'd12: bias = 8'sd84;
            8'd13: bias = 8'sd79;
            8'd14: bias = 8'sd53;
            8'd15: bias = 8'sd41;
            8'd16: bias = 8'sd58;
            8'd17: bias = 8'sd113;
            8'd18: bias = 8'sd34;
            8'd19: bias = 8'sd3;
            8'd20: bias = 8'sd39;
            8'd21: bias = 8'sd53;
            8'd22: bias = 8'sd-3;
            8'd23: bias = 8'sd46;
            8'd24: bias = 8'sd-39;
            8'd25: bias = 8'sd85;
            8'd26: bias = 8'sd-9;
            8'd27: bias = 8'sd-29;
            8'd28: bias = 8'sd127;
            8'd29: bias = 8'sd55;
            8'd30: bias = 8'sd-28;
            8'd31: bias = 8'sd10;
            8'd32: bias = 8'sd-42;
            8'd33: bias = 8'sd-25;
            8'd34: bias = 8'sd37;
            8'd35: bias = 8'sd33;
            8'd36: bias = 8'sd8;
            8'd37: bias = 8'sd22;
            8'd38: bias = 8'sd-53;
            8'd39: bias = 8'sd46;
            8'd40: bias = 8'sd26;
            8'd41: bias = 8'sd62;
            8'd42: bias = 8'sd-82;
            8'd43: bias = 8'sd84;
            8'd44: bias = 8'sd-49;
            8'd45: bias = 8'sd22;
            8'd46: bias = 8'sd-9;
            8'd47: bias = 8'sd54;
            8'd48: bias = 8'sd17;
            8'd49: bias = 8'sd-49;
            8'd50: bias = 8'sd25;
            8'd51: bias = 8'sd-42;
            8'd52: bias = 8'sd6;
            8'd53: bias = 8'sd67;
            8'd54: bias = 8'sd64;
            8'd55: bias = 8'sd17;
            8'd56: bias = 8'sd-34;
            8'd57: bias = 8'sd107;
            8'd58: bias = 8'sd-10;
            8'd59: bias = 8'sd27;
            8'd60: bias = 8'sd7;
            8'd61: bias = 8'sd-30;
            8'd62: bias = 8'sd-31;
            8'd63: bias = 8'sd2;
            8'd64: bias = 8'sd3;
            8'd65: bias = 8'sd-29;
            8'd66: bias = 8'sd61;
            8'd67: bias = 8'sd95;
            8'd68: bias = 8'sd49;
            8'd69: bias = 8'sd43;
            8'd70: bias = 8'sd4;
            8'd71: bias = 8'sd-43;
            8'd72: bias = 8'sd-6;
            8'd73: bias = 8'sd-49;
            8'd74: bias = 8'sd57;
            8'd75: bias = 8'sd25;
            8'd76: bias = 8'sd-52;
            8'd77: bias = 8'sd-66;
            8'd78: bias = 8'sd53;
            8'd79: bias = 8'sd18;
            8'd80: bias = 8'sd48;
            8'd81: bias = 8'sd60;
            8'd82: bias = 8'sd-76;
            8'd83: bias = 8'sd-15;
            default: bias = 8'sd0;
        endcase
    end

endmodule
