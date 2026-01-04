`timescale 1ns / 1ps

module tb_conv_5x5();
    localparam FRAC_BITS = 7;
    localparam PIPELINE_DEPTH = 1;
    
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
    wire signed [23:0] raw_sum;
    
    reg signed [23:0] expected_acc;
    reg signed [7:0] expected_output;
    integer test_num;
    integer pass_count;
    integer fail_count;
    
    conv_5x5 #(
        .FRAC_BITS(FRAC_BITS)
    ) dut (
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
        .data_out(data_out),
        .raw_sum(raw_sum)
    );
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    function signed [7:0] scale_and_saturate;
        input signed [23:0] acc_value;
        reg signed [23:0] scaled;
        begin
            scaled = acc_value >>> FRAC_BITS;
            if (scaled > 24'sd127)
                scale_and_saturate = 8'sd127;
            else if (scaled < -24'sd128)
                scale_and_saturate = -8'sd128;
            else
                scale_and_saturate = scaled[7:0];
        end
    endfunction
    
    task run_test;
        input integer test_id;
        input signed [7:0] exp_out;
        integer i;
        reg found_valid;
        begin
            test_num = test_id;
            expected_output = exp_out;
            found_valid = 0;
            

            @(posedge clk);
            #1;
            valid_in = 1;
            @(posedge clk);
            #1;
            if (valid_out) begin
                found_valid = 1;
                if (data_out == expected_output) begin
                    $display("Test %0d PASS: Output=%0d, Expected=%0d", test_num, data_out, expected_output);
                    pass_count = pass_count + 1;
                end else begin
                    $display("Test %0d FAIL: Output=%0d, Expected=%0d (raw_sum=%0d)", test_num, data_out, expected_output, raw_sum);
                    fail_count = fail_count + 1;
                end
            end
            valid_in = 0;
            
            // If not found yet, wait a few more cycles
            if (!found_valid) begin
                for (i = 0; i < 4; i = i + 1) begin
                    @(posedge clk);
                    #1;
                    if (valid_out && !found_valid) begin
                        found_valid = 1;
                        if (data_out == expected_output) begin
                            $display("Test %0d PASS: Output=%0d, Expected=%0d", test_num, data_out, expected_output);
                            pass_count = pass_count + 1;
                        end else begin
                            $display("Test %0d FAIL: Output=%0d, Expected=%0d (raw_sum=%0d)", test_num, data_out, expected_output, raw_sum);
                            fail_count = fail_count + 1;
                        end
                    end
                end
            end
            if (!found_valid) begin
                $display("Test %0d FAIL: valid_out never asserted!", test_num);
                fail_count = fail_count + 1;
            end
            
            @(posedge clk);
            #1;
        end
    endtask
    
    initial begin
        rst = 1;
        valid_in = 0;
        pass_count = 0;
        fail_count = 0;
        
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
        
        // Test 1: All inputs=1, weights=1, bias=0 -> acc=25, >>>7 = 0
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
        bias = 0;
        
        // Expected result: 25 (all 1's multiplied and summed)
        expected_acc = 25;
        run_test(1, scale_and_saturate(expected_acc));
        
        // Test 2: Identity kernel (center=1), center input=64 -> acc=64, >>>7 = 0
        data_in_00 = 10; data_in_01 = 20; data_in_02 = 30; data_in_03 = 40; data_in_04 = 50;
        data_in_10 = 15; data_in_11 = 25; data_in_12 = 35; data_in_13 = 45; data_in_14 = 55;
        data_in_20 = 20; data_in_21 = 30; data_in_22 = 64; data_in_23 = 50; data_in_24 = 60;
        data_in_30 = 25; data_in_31 = 35; data_in_32 = 45; data_in_33 = 55; data_in_34 = 65;
        data_in_40 = 30; data_in_41 = 40; data_in_42 = 50; data_in_43 = 60; data_in_44 = 70;
        
        weight_00 = 0; weight_01 = 0; weight_02 = 0; weight_03 = 0; weight_04 = 0;
        weight_10 = 0; weight_11 = 0; weight_12 = 0; weight_13 = 0; weight_14 = 0;
        weight_20 = 0; weight_21 = 0; weight_22 = 1; weight_23 = 0; weight_24 = 0;
        weight_30 = 0; weight_31 = 0; weight_32 = 0; weight_33 = 0; weight_34 = 0;
        weight_40 = 0; weight_41 = 0; weight_42 = 0; weight_43 = 0; weight_44 = 0;
        bias = 0;
        
        expected_acc = 64;
        run_test(2, scale_and_saturate(expected_acc));
        
        // Test 3: inputs=64, weights=4, bias=0 -> acc=6400, >>>7 = 50
        data_in_00 = 64; data_in_01 = 64; data_in_02 = 64; data_in_03 = 64; data_in_04 = 64;
        data_in_10 = 64; data_in_11 = 64; data_in_12 = 64; data_in_13 = 64; data_in_14 = 64;
        data_in_20 = 64; data_in_21 = 64; data_in_22 = 64; data_in_23 = 64; data_in_24 = 64;
        data_in_30 = 64; data_in_31 = 64; data_in_32 = 64; data_in_33 = 64; data_in_34 = 64;
        data_in_40 = 64; data_in_41 = 64; data_in_42 = 64; data_in_43 = 64; data_in_44 = 64;
        
        weight_00 = 4; weight_01 = 4; weight_02 = 4; weight_03 = 4; weight_04 = 4;
        weight_10 = 4; weight_11 = 4; weight_12 = 4; weight_13 = 4; weight_14 = 4;
        weight_20 = 4; weight_21 = 4; weight_22 = 4; weight_23 = 4; weight_24 = 4;
        weight_30 = 4; weight_31 = 4; weight_32 = 4; weight_33 = 4; weight_34 = 4;
        weight_40 = 4; weight_41 = 4; weight_42 = 4; weight_43 = 4; weight_44 = 4;
        bias = 0;
        
        expected_acc = 25 * 64 * 4;
        run_test(3, scale_and_saturate(expected_acc));
        
        // Test 4: inputs=32, weights=2, bias=64 -> acc=1600+8192=9792, >>>7 = 76
        data_in_00 = 32; data_in_01 = 32; data_in_02 = 32; data_in_03 = 32; data_in_04 = 32;
        data_in_10 = 32; data_in_11 = 32; data_in_12 = 32; data_in_13 = 32; data_in_14 = 32;
        data_in_20 = 32; data_in_21 = 32; data_in_22 = 32; data_in_23 = 32; data_in_24 = 32;
        data_in_30 = 32; data_in_31 = 32; data_in_32 = 32; data_in_33 = 32; data_in_34 = 32;
        data_in_40 = 32; data_in_41 = 32; data_in_42 = 32; data_in_43 = 32; data_in_44 = 32;
        
        weight_00 = 2; weight_01 = 2; weight_02 = 2; weight_03 = 2; weight_04 = 2;
        weight_10 = 2; weight_11 = 2; weight_12 = 2; weight_13 = 2; weight_14 = 2;
        weight_20 = 2; weight_21 = 2; weight_22 = 2; weight_23 = 2; weight_24 = 2;
        weight_30 = 2; weight_31 = 2; weight_32 = 2; weight_33 = 2; weight_34 = 2;
        weight_40 = 2; weight_41 = 2; weight_42 = 2; weight_43 = 2; weight_44 = 2;
        bias = 64;
        
        expected_acc = 25 * 32 * 2 + (64 << FRAC_BITS);
        run_test(4, scale_and_saturate(expected_acc));
        
        // Test 5: Positive saturation - inputs=127, weights=8 -> saturate to 127
        data_in_00 = 127; data_in_01 = 127; data_in_02 = 127; data_in_03 = 127; data_in_04 = 127;
        data_in_10 = 127; data_in_11 = 127; data_in_12 = 127; data_in_13 = 127; data_in_14 = 127;
        data_in_20 = 127; data_in_21 = 127; data_in_22 = 127; data_in_23 = 127; data_in_24 = 127;
        data_in_30 = 127; data_in_31 = 127; data_in_32 = 127; data_in_33 = 127; data_in_34 = 127;
        data_in_40 = 127; data_in_41 = 127; data_in_42 = 127; data_in_43 = 127; data_in_44 = 127;
        
        weight_00 = 8; weight_01 = 8; weight_02 = 8; weight_03 = 8; weight_04 = 8;
        weight_10 = 8; weight_11 = 8; weight_12 = 8; weight_13 = 8; weight_14 = 8;
        weight_20 = 8; weight_21 = 8; weight_22 = 8; weight_23 = 8; weight_24 = 8;
        weight_30 = 8; weight_31 = 8; weight_32 = 8; weight_33 = 8; weight_34 = 8;
        weight_40 = 8; weight_41 = 8; weight_42 = 8; weight_43 = 8; weight_44 = 8;
        bias = 0;
        
        expected_acc = 25 * 127 * 8;
        run_test(5, scale_and_saturate(expected_acc));
        
        // Test 6: Negative saturation - inputs=127, weights=-8 -> saturate to -128
        weight_00 = -8; weight_01 = -8; weight_02 = -8; weight_03 = -8; weight_04 = -8;
        weight_10 = -8; weight_11 = -8; weight_12 = -8; weight_13 = -8; weight_14 = -8;
        weight_20 = -8; weight_21 = -8; weight_22 = -8; weight_23 = -8; weight_24 = -8;
        weight_30 = -8; weight_31 = -8; weight_32 = -8; weight_33 = -8; weight_34 = -8;
        weight_40 = -8; weight_41 = -8; weight_42 = -8; weight_43 = -8; weight_44 = -8;
        bias = 0;
        
        expected_acc = 25 * 127 * (-8);
        run_test(6, scale_and_saturate(expected_acc));
        
        #50;
        $display("PASSED: %0d", pass_count);
        $display("FAILED: %0d", fail_count);
        $finish;
    end
    
endmodule 
