// 5x5 convolution module for CNN
// Fixed-Point Format: Q1.7
// Input: (data, weights, bias) 8-bit signed, Q1.7 format
// Output: 8-bit signed, Q1.7 format
// Parallel: 25 data/weight pairs in one cycle using tree adder

module conv_5x5 #(
    parameter integer FRAC_BITS = 7
) (
    input wire clk,
    input wire rst,
    input wire valid_in,
    input wire signed [7:0] data_in [0:24],
    input wire signed [7:0] weight_in [0:24],
    input wire signed [7:0] bias_in,
    output reg valid_out,
    output reg signed [7:0] data_out,
    output reg signed [23:0] raw_sum
);


    (* use_dsp = "yes" *)
    wire signed [15:0] products [0:24];
    
    genvar i;
    generate
        for (i = 0; i < 25; i = i + 1) begin : mult_array
            assign products[i] = data_in[i] * weight_in[i];
        end
    endgenerate

    // Tree adder
    wire signed [16:0] sum_l1 [0:12];
    assign sum_l1[0]  = $signed(products[0])  + $signed(products[1]);
    assign sum_l1[1]  = $signed(products[2])  + $signed(products[3]);
    assign sum_l1[2]  = $signed(products[4])  + $signed(products[5]);
    assign sum_l1[3]  = $signed(products[6])  + $signed(products[7]);
    assign sum_l1[4]  = $signed(products[8])  + $signed(products[9]);
    assign sum_l1[5]  = $signed(products[10]) + $signed(products[11]);
    assign sum_l1[6]  = $signed(products[12]) + $signed(products[13]);
    assign sum_l1[7]  = $signed(products[14]) + $signed(products[15]);
    assign sum_l1[8]  = $signed(products[16]) + $signed(products[17]);
    assign sum_l1[9]  = $signed(products[18]) + $signed(products[19]);
    assign sum_l1[10] = $signed(products[20]) + $signed(products[21]);
    assign sum_l1[11] = $signed(products[22]) + $signed(products[23]);
    assign sum_l1[12] = $signed(products[24]);

    wire signed [17:0] sum_l2 [0:6];
    assign sum_l2[0] = $signed(sum_l1[0])  + $signed(sum_l1[1]);
    assign sum_l2[1] = $signed(sum_l1[2])  + $signed(sum_l1[3]);
    assign sum_l2[2] = $signed(sum_l1[4])  + $signed(sum_l1[5]);
    assign sum_l2[3] = $signed(sum_l1[6])  + $signed(sum_l1[7]);
    assign sum_l2[4] = $signed(sum_l1[8])  + $signed(sum_l1[9]);
    assign sum_l2[5] = $signed(sum_l1[10]) + $signed(sum_l1[11]);
    assign sum_l2[6] = $signed(sum_l1[12]);

    wire signed [18:0] sum_l3 [0:3];
    assign sum_l3[0] = $signed(sum_l2[0]) + $signed(sum_l2[1]);
    assign sum_l3[1] = $signed(sum_l2[2]) + $signed(sum_l2[3]);
    assign sum_l3[2] = $signed(sum_l2[4]) + $signed(sum_l2[5]);
    assign sum_l3[3] = $signed(sum_l2[6]);

    wire signed [19:0] sum_l4 [0:1];
    assign sum_l4[0] = $signed(sum_l3[0]) + $signed(sum_l3[1]);
    assign sum_l4[1] = $signed(sum_l3[2]) + $signed(sum_l3[3]);

    wire signed [20:0] sum_l5;
    assign sum_l5 = $signed(sum_l4[0]) + $signed(sum_l4[1]);

    // Add bias
    wire signed [23:0] bias_scaled = $signed({{16{bias_in[7]}}, bias_in}) << FRAC_BITS;
    wire signed [23:0] acc = $signed({{3{sum_l5[20]}}, sum_l5}) + bias_scaled;

    // Scale and saturate
    wire signed [23:0] scaled_acc = acc >>> FRAC_BITS;

    wire signed [7:0] saturated;
    assign saturated = (scaled_acc > 24'sd127) ? 8'sd127 : (scaled_acc < -24'sd128) ? -8'sd128 : scaled_acc[7:0];

    always @(posedge clk) begin
        if (rst) begin
            valid_out <= 1'b0;
            data_out <= 8'sd0;
            raw_sum <= 24'sd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                data_out <= saturated;
                raw_sum <= acc;
            end
        end
    end

endmodule
