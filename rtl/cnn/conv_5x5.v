// SystemVerilog
// 5x5 convolution module for CNN
// Fixed-Point Format: Q1.7
// - Inputs (data, weights, bias): 8-bit signed, Q1.7 format
// - Products: 16-bit signed, Q2.14 format
// - Accumulator: 24-bit signed
// - Output: 8-bit signed, Q1.7 format

module conv_5x5 #(
    parameter integer FRAC_BITS = 7
) (
    input wire clk,
    input wire rst,
    input wire valid_in,

    input wire signed [7:0] data_in_00, data_in_01, data_in_02, data_in_03, data_in_04,
    input wire signed [7:0] data_in_10, data_in_11, data_in_12, data_in_13, data_in_14,
    input wire signed [7:0] data_in_20, data_in_21, data_in_22, data_in_23, data_in_24,
    input wire signed [7:0] data_in_30, data_in_31, data_in_32, data_in_33, data_in_34,
    input wire signed [7:0] data_in_40, data_in_41, data_in_42, data_in_43, data_in_44,

    input wire signed [7:0] weight_00, weight_01, weight_02, weight_03, weight_04,
    input wire signed [7:0] weight_10, weight_11, weight_12, weight_13, weight_14,
    input wire signed [7:0] weight_20, weight_21, weight_22, weight_23, weight_24,
    input wire signed [7:0] weight_30, weight_31, weight_32, weight_33, weight_34,
    input wire signed [7:0] weight_40, weight_41, weight_42, weight_43, weight_44,

    input wire signed [7:0] bias,

    output reg         valid_out,
    output reg signed [7:0] data_out,
    output reg signed [23:0] raw_sum
);

    // Single cycle combinational convolution sum
    wire signed [23:0] sum;
    wire signed [23:0] result;
    
    // Products
    wire signed [23:0] prod_00 = data_in_00 * weight_00;
    wire signed [23:0] prod_01 = data_in_01 * weight_01;
    wire signed [23:0] prod_02 = data_in_02 * weight_02;
    wire signed [23:0] prod_03 = data_in_03 * weight_03;
    wire signed [23:0] prod_04 = data_in_04 * weight_04;
    wire signed [23:0] prod_10 = data_in_10 * weight_10;
    wire signed [23:0] prod_11 = data_in_11 * weight_11;
    wire signed [23:0] prod_12 = data_in_12 * weight_12;
    wire signed [23:0] prod_13 = data_in_13 * weight_13;
    wire signed [23:0] prod_14 = data_in_14 * weight_14;
    wire signed [23:0] prod_20 = data_in_20 * weight_20;
    wire signed [23:0] prod_21 = data_in_21 * weight_21;
    wire signed [23:0] prod_22 = data_in_22 * weight_22;
    wire signed [23:0] prod_23 = data_in_23 * weight_23;
    wire signed [23:0] prod_24 = data_in_24 * weight_24;
    wire signed [23:0] prod_30 = data_in_30 * weight_30;
    wire signed [23:0] prod_31 = data_in_31 * weight_31;
    wire signed [23:0] prod_32 = data_in_32 * weight_32;
    wire signed [23:0] prod_33 = data_in_33 * weight_33;
    wire signed [23:0] prod_34 = data_in_34 * weight_34;
    wire signed [23:0] prod_40 = data_in_40 * weight_40;
    wire signed [23:0] prod_41 = data_in_41 * weight_41;
    wire signed [23:0] prod_42 = data_in_42 * weight_42;
    wire signed [23:0] prod_43 = data_in_43 * weight_43;
    wire signed [23:0] prod_44 = data_in_44 * weight_44;
    
    // Bias
    wire signed [23:0] bias_scaled = $signed({{16{bias[7]}}, bias}) << FRAC_BITS;
    
    // All 25 products plus bias accumulated
    assign sum = 
        prod_00 + prod_01 + prod_02 + prod_03 + prod_04 +
        prod_10 + prod_11 + prod_12 + prod_13 + prod_14 +
        prod_20 + prod_21 + prod_22 + prod_23 + prod_24 +
        prod_30 + prod_31 + prod_32 + prod_33 + prod_34 +
        prod_40 + prod_41 + prod_42 + prod_43 + prod_44 +
        bias_scaled;
    
    // raw_sum is registered together with valid_out
    
    // Scale down and saturate
    assign result = sum >>> FRAC_BITS;
    
    wire signed [7:0] saturated_out;
    assign saturated_out = (result > 24'sd127)  ? 8'sd127 :
                           (result < -24'sd128) ? -8'sd128 :
                           result[7:0];
    
    // Register all outputs together: valid_out, data_out, and raw_sum
    always @(posedge clk) begin
        if (rst) begin
            valid_out <= 1'b0;
            data_out <= 8'sd0;
            raw_sum <= 24'sd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                data_out <= saturated_out;
                raw_sum <= sum;
            end
        end
    end
    
endmodule 
