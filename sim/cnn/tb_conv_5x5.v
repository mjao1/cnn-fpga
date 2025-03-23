`timescale 1ns / 1ps

module tb_conv_5x5();
    reg clk;
    reg rst;
    reg valid_in;
    
    reg signed [7:0] data_in_00, data_in_01, data_in_02, data_in_03, data_in_04;
    reg signed [7:0] data_in_10, data_in_11, data_in_12, data_in_13, data_in_14;
    reg signed [7:0] data_in_20, data_in_21, data_in_22, data_in_23, data_in_24;
    reg signed [7:0] data_in_30, data_in_31, data_in_32, data_in_33, data_in_34;
    reg signed [7:0] data_in_40, data_in_41, data_in_42, data_in_43, data_in_44;
    
    reg signed [7:0] weight_00, weight_01, weight_02, weight_03, weight_04;
    reg signed [7:0] weight_10, weight_11, weight_12, weight_13, weight_14;
    reg signed [7:0] weight_20, weight_21, weight_22, weight_23, weight_24;
    reg signed [7:0] weight_30, weight_31, weight_32, weight_33, weight_34;
    reg signed [7:0] weight_40, weight_41, weight_42, weight_43, weight_44;
    
    reg signed [7:0] bias;
    
    wire valid_out;
    wire signed [7:0] data_out;
    
    reg signed [19:0] expected_acc;
    reg signed [7:0] expected_output;
    
    conv_5x5 dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .data_in_00(data_in_00), .data_in_01(data_in_01), .data_in_02(data_in_02), .data_in_03(data_in_03), .data_in_04(data_in_04),
        .data_in_10(data_in_10), .data_in_11(data_in_11), .data_in_12(data_in_12), .data_in_13(data_in_13), .data_in_14(data_in_14),
        .data_in_20(data_in_20), .data_in_21(data_in_21), .data_in_22(data_in_22), .data_in_23(data_in_23), .data_in_24(data_in_24),
        .data_in_30(data_in_30), .data_in_31(data_in_31), .data_in_32(data_in_32), .data_in_33(data_in_33), .data_in_34(data_in_34),
        .data_in_40(data_in_40), .data_in_41(data_in_41), .data_in_42(data_in_42), .data_in_43(data_in_43), .data_in_44(data_in_44),
        .weight_00(weight_00), .weight_01(weight_01), .weight_02(weight_02), .weight_03(weight_03), .weight_04(weight_04),
        .weight_10(weight_10), .weight_11(weight_11), .weight_12(weight_12), .weight_13(weight_13), .weight_14(weight_14),
        .weight_20(weight_20), .weight_21(weight_21), .weight_22(weight_22), .weight_23(weight_23), .weight_24(weight_24),
        .weight_30(weight_30), .weight_31(weight_31), .weight_32(weight_32), .weight_33(weight_33), .weight_34(weight_34),
        .weight_40(weight_40), .weight_41(weight_41), .weight_42(weight_42), .weight_43(weight_43), .weight_44(weight_44),
        .bias(bias),
        .valid_out(valid_out),
        .data_out(data_out)
    );
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    function signed [7:0] saturate;
        input signed [19:0] value;
        begin
            if (value > 20'sd127)
                saturate = 8'sd127;
            else if (value < -20'sd128)
                saturate = -8'sd128;
            else
                saturate = value[7:0];
        end
    endfunction
    
    initial begin
        rst = 1;
        valid_in = 0;
        
        // Initialize input data to 0
        data_in_00 = 0; data_in_01 = 0; data_in_02 = 0; data_in_03 = 0; data_in_04 = 0;
        data_in_10 = 0; data_in_11 = 0; data_in_12 = 0; data_in_13 = 0; data_in_14 = 0;
        data_in_20 = 0; data_in_21 = 0; data_in_22 = 0; data_in_23 = 0; data_in_24 = 0;
        data_in_30 = 0; data_in_31 = 0; data_in_32 = 0; data_in_33 = 0; data_in_34 = 0;
        data_in_40 = 0; data_in_41 = 0; data_in_42 = 0; data_in_43 = 0; data_in_44 = 0;
        
        // Initialize weights to 0
        weight_00 = 0; weight_01 = 0; weight_02 = 0; weight_03 = 0; weight_04 = 0;
        weight_10 = 0; weight_11 = 0; weight_12 = 0; weight_13 = 0; weight_14 = 0;
        weight_20 = 0; weight_21 = 0; weight_22 = 0; weight_23 = 0; weight_24 = 0;
        weight_30 = 0; weight_31 = 0; weight_32 = 0; weight_33 = 0; weight_34 = 0;
        weight_40 = 0; weight_41 = 0; weight_42 = 0; weight_43 = 0; weight_44 = 0;
        
        bias = 0;
        
        // Apply reset
        #20;
        rst = 0;
        #10;
        
        // Test case 1: Basic test with simple values
        // Set all inputs to 1 and all weights to 1, bias to 0
        valid_in = 1;
        
        // Set all inputs to 1
        data_in_00 = 1; data_in_01 = 1; data_in_02 = 1; data_in_03 = 1; data_in_04 = 1;
        data_in_10 = 1; data_in_11 = 1; data_in_12 = 1; data_in_13 = 1; data_in_14 = 1;
        data_in_20 = 1; data_in_21 = 1; data_in_22 = 1; data_in_23 = 1; data_in_24 = 1;
        data_in_30 = 1; data_in_31 = 1; data_in_32 = 1; data_in_33 = 1; data_in_34 = 1;
        data_in_40 = 1; data_in_41 = 1; data_in_42 = 1; data_in_43 = 1; data_in_44 = 1;
        
        // Set all weights to 1
        weight_00 = 1; weight_01 = 1; weight_02 = 1; weight_03 = 1; weight_04 = 1;
        weight_10 = 1; weight_11 = 1; weight_12 = 1; weight_13 = 1; weight_14 = 1;
        weight_20 = 1; weight_21 = 1; weight_22 = 1; weight_23 = 1; weight_24 = 1;
        weight_30 = 1; weight_31 = 1; weight_32 = 1; weight_33 = 1; weight_34 = 1;
        weight_40 = 1; weight_41 = 1; weight_42 = 1; weight_43 = 1; weight_44 = 1;
        
        // Expected result: 25 (all 1's multiplied and summed)
        expected_acc = 25;
        expected_output = saturate(expected_acc);
        
        #10;
        
        // Test case 2: Identity kernel (center=1, rest=0)
        // Set all inputs to different values
        data_in_00 = 10; data_in_01 = 20; data_in_02 = 30; data_in_03 = 40; data_in_04 = 50;
        data_in_10 = 15; data_in_11 = 25; data_in_12 = 35; data_in_13 = 45; data_in_14 = 55;
        data_in_20 = 20; data_in_21 = 30; data_in_22 = 40; data_in_23 = 50; data_in_24 = 60;
        data_in_30 = 25; data_in_31 = 35; data_in_32 = 45; data_in_33 = 55; data_in_34 = 65;
        data_in_40 = 30; data_in_41 = 40; data_in_42 = 50; data_in_43 = 60; data_in_44 = 70;
        
        // Set identity kernel (center=1, rest=0)
        weight_00 = 0; weight_01 = 0; weight_02 = 0; weight_03 = 0; weight_04 = 0;
        weight_10 = 0; weight_11 = 0; weight_12 = 0; weight_13 = 0; weight_14 = 0;
        weight_20 = 0; weight_21 = 0; weight_22 = 1; weight_23 = 0; weight_24 = 0;
        weight_30 = 0; weight_31 = 0; weight_32 = 0; weight_33 = 0; weight_34 = 0;
        weight_40 = 0; weight_41 = 0; weight_42 = 0; weight_43 = 0; weight_44 = 0;
        
        // Expected result: 40 (center value)
        expected_acc = 40;
        expected_output = saturate(expected_acc);
        
        #10;
        
        // Test case 3: Edge detection kernel (common for CNN first layer)
        // Keep input the same
        
        // Set edge detection kernel
        weight_00 = -1; weight_01 = -1; weight_02 = -1; weight_03 = -1; weight_04 = -1;
        weight_10 = -1; weight_11 =  8; weight_12 =  8; weight_13 =  8; weight_14 = -1;
        weight_20 = -1; weight_21 =  8; weight_22 = 16; weight_23 =  8; weight_24 = -1;
        weight_30 = -1; weight_31 =  8; weight_32 =  8; weight_33 =  8; weight_34 = -1;
        weight_40 = -1; weight_41 = -1; weight_42 = -1; weight_43 = -1; weight_44 = -1;
        
        // Add bias
        bias = 5;
        
        // Calculate expected result
        expected_acc = 10*(-1) + 20*(-1) + 30*(-1) + 40*(-1) + 50*(-1) +
                       15*(-1) + 25*8 + 35*8 + 45*8 + 55*(-1) +
                       20*(-1) + 30*8 + 40*16 + 50*8 + 60*(-1) +
                       25*(-1) + 35*8 + 45*8 + 55*8 + 65*(-1) +
                       30*(-1) + 40*(-1) + 50*(-1) + 60*(-1) + 70*(-1) + 
                       5; // bias
                       
        expected_output = saturate(expected_acc);
        
        #10;
        
        // Test case 4: Saturation test (large positive values)
        data_in_00 = 127; data_in_01 = 127; data_in_02 = 127; data_in_03 = 127; data_in_04 = 127;
        data_in_10 = 127; data_in_11 = 127; data_in_12 = 127; data_in_13 = 127; data_in_14 = 127;
        data_in_20 = 127; data_in_21 = 127; data_in_22 = 127; data_in_23 = 127; data_in_24 = 127;
        data_in_30 = 127; data_in_31 = 127; data_in_32 = 127; data_in_33 = 127; data_in_34 = 127;
        data_in_40 = 127; data_in_41 = 127; data_in_42 = 127; data_in_43 = 127; data_in_44 = 127;
        
        weight_00 = 4; weight_01 = 4; weight_02 = 4; weight_03 = 4; weight_04 = 4;
        weight_10 = 4; weight_11 = 4; weight_12 = 4; weight_13 = 4; weight_14 = 4;
        weight_20 = 4; weight_21 = 4; weight_22 = 4; weight_23 = 4; weight_24 = 4;
        weight_30 = 4; weight_31 = 4; weight_32 = 4; weight_33 = 4; weight_34 = 4;
        weight_40 = 4; weight_41 = 4; weight_42 = 4; weight_43 = 4; weight_44 = 4;
        
        bias = 10;
        
        // Result should be saturated to 127
        expected_acc = 25 * 4 * 127 + 10;  // will exceed 127
        expected_output = saturate(expected_acc);
        
        #10;
        
        valid_in = 0;
        #60;
        
        $display("Test completed");
        $finish;
    end
    
    always @(posedge clk) begin
        if (valid_out) begin
            $display("Time=%0t: Output=%0d", $time, data_out);
        end
    end
    
endmodule 
