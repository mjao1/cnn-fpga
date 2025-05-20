// simple 5x5 convolution module for CNN

module conv_5x5 #(
    parameter integer PIXEL_SHIFT = 12
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
    output reg signed [7:0] data_out
);

    reg valid_stage1, valid_stage2, valid_stage3, valid_stage4, valid_stage5;
    reg signed [19:0] acc_stage1, acc_stage2, acc_stage3, acc_stage4, acc_stage5;
    
    // Saturation thresholds in scaled domain
    localparam signed [19:0] SAT_MAX = 20'sd127 <<< PIXEL_SHIFT;
    localparam signed [19:0] SAT_MIN = -20'sd128 <<< PIXEL_SHIFT;
    
    // Multiply function for 8-bit fixed-point with scaling
    function signed [15:0] mult;
        input signed [7:0] a;
        input signed [7:0] b;
        begin
            mult = a * b >>> PIXEL_SHIFT;
        end
    endfunction
    
    // Saturation function to convert 20-bit result to 8-bit
    function signed [7:0] saturate;
        input signed [19:0] value;
        begin
            if (value > SAT_MAX)
                saturate = 8'sd127;
            else if (value < SAT_MIN)
                saturate = -8'sd128;
            else
                saturate = value[PIXEL_SHIFT+7:PIXEL_SHIFT];
        end
    endfunction
    
    // Pipeline convolution
    always @(posedge clk) begin
        if (rst) begin
            valid_stage1 <= 1'b0;
            valid_stage2 <= 1'b0;
            valid_stage3 <= 1'b0;
            valid_stage4 <= 1'b0;
            valid_stage5 <= 1'b0;
            valid_out <= 1'b0;
            
            acc_stage1 <= 20'd0;
            acc_stage2 <= 20'd0;
            acc_stage3 <= 20'd0;
            acc_stage4 <= 20'd0;
            acc_stage5 <= 20'd0;
            
            data_out <= 8'd0;
        end else begin
            // stage 1: first row multiplications
            valid_stage1 <= valid_in;
            if (valid_in) begin
                acc_stage1 <= mult(data_in_00, weight_00) + 
                             mult(data_in_01, weight_01) + 
                             mult(data_in_02, weight_02) + 
                             mult(data_in_03, weight_03) + 
                             mult(data_in_04, weight_04);
            end
            
            // stage 2: second row multiplications + first row acc
            valid_stage2 <= valid_stage1;
            if (valid_stage1) begin
                acc_stage2 <= acc_stage1 +
                             mult(data_in_10, weight_10) + 
                             mult(data_in_11, weight_11) + 
                             mult(data_in_12, weight_12) + 
                             mult(data_in_13, weight_13) + 
                             mult(data_in_14, weight_14);
            end
            
            // stage 3: third row multiplications + accumulation
            valid_stage3 <= valid_stage2;
            if (valid_stage2) begin
                acc_stage3 <= acc_stage2 +
                             mult(data_in_20, weight_20) + 
                             mult(data_in_21, weight_21) + 
                             mult(data_in_22, weight_22) + 
                             mult(data_in_23, weight_23) + 
                             mult(data_in_24, weight_24);
            end
            
            // stage 4: fourth row multiplications + accumulation
            valid_stage4 <= valid_stage3;
            if (valid_stage3) begin
                acc_stage4 <= acc_stage3 +
                             mult(data_in_30, weight_30) + 
                             mult(data_in_31, weight_31) + 
                             mult(data_in_32, weight_32) + 
                             mult(data_in_33, weight_33) + 
                             mult(data_in_34, weight_34);
            end
            
            // stage 5: fifth row multiplications + accumulation + bias
            valid_stage5 <= valid_stage4;
            if (valid_stage4) begin
                acc_stage5 <= acc_stage4 +
                             mult(data_in_40, weight_40) + 
                             mult(data_in_41, weight_41) + 
                             mult(data_in_42, weight_42) + 
                             mult(data_in_43, weight_43) + 
                             mult(data_in_44, weight_44) +
                             {{12{bias[7]}}, bias};
            end
            
            valid_out <= valid_stage5;
            if (valid_stage5) begin
                // DEBUG: log raw accumulator and saturated output
                $display("%m raw_acc_stage5=%0d sat_out=%0d", acc_stage5, saturate(acc_stage5));
                data_out <= saturate(acc_stage5);
            end
        end
    end

endmodule 
