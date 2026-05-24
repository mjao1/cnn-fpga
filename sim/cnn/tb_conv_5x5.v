`timescale 1ns / 1ps

module tb_conv_5x5();
    localparam FRAC_BITS = 7;

    reg clk;
    reg rst;
    reg valid_in;
    reg [199:0] data_in;
    reg [199:0] weight_in;
    reg signed [7:0] bias_in;

    wire valid_out;
    wire signed [7:0] data_out;
    wire signed [23:0] raw_sum;

    reg signed [7:0] data_arr [0:24];
    reg signed [7:0] weight_arr [0:24];
    reg signed [7:0] bias_val;

    integer test_num;
    integer pass_count;
    integer fail_count;
    integer k;

    conv_5x5 #(
        .FRAC_BITS(FRAC_BITS)
    ) dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .data_in(data_in),
        .weight_in(weight_in),
        .bias_in(bias_in),
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

    task run_parallel_conv;
        begin
            for (k = 0; k < 25; k = k + 1) begin
                data_in[((k + 1) * 8) - 1 -: 8] = data_arr[k];
                weight_in[((k + 1) * 8) - 1 -: 8] = weight_arr[k];
            end
            bias_in = bias_val;
            valid_in = 0;
            @(posedge clk);
            #1;
            valid_in = 1;
            @(posedge clk);
            #1;
            valid_in = 0;
        end
    endtask

    task run_test;
        input integer test_id;
        input signed [7:0] exp_out;
        integer i;
        begin
            test_num = test_id;
            run_parallel_conv();
            #1;
            if (valid_out) begin
                if (data_out == exp_out) begin
                    $display("Test %0d PASS: Output=%0d, Expected=%0d", test_num, data_out, exp_out);
                    pass_count = pass_count + 1;
                end else begin
                    $display("Test %0d FAIL: Output=%0d, Expected=%0d (raw_sum=%0d)", test_num, data_out, exp_out, raw_sum);
                    fail_count = fail_count + 1;
                end
            end else begin
                $display("Test %0d FAIL: valid_out not asserted", test_num);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        rst = 1;
        valid_in = 0;
        pass_count = 0;
        fail_count = 0;
        for (k = 0; k < 25; k = k + 1) begin
            data_in[((k + 1) * 8) - 1 -: 8] = 8'sd0;
            weight_in[((k + 1) * 8) - 1 -: 8] = 8'sd0;
        end
        bias_in = 8'sd0;
        bias_val = 0;
        #20;
        rst = 0;
        #10;

        for (k = 0; k < 25; k = k + 1) begin
            data_arr[k] = 1;
            weight_arr[k] = 1;
        end
        bias_val = 0;
        run_test(1, scale_and_saturate(25));

        for (k = 0; k < 25; k = k + 1) begin
            data_arr[k] = 0;
            weight_arr[k] = 0;
        end
        data_arr[12] = 64;
        weight_arr[12] = 1;
        bias_val = 0;
        run_test(2, scale_and_saturate(64));

        for (k = 0; k < 25; k = k + 1) begin
            data_arr[k] = 64;
            weight_arr[k] = 4;
        end
        bias_val = 0;
        run_test(3, scale_and_saturate(25 * 64 * 4));

        for (k = 0; k < 25; k = k + 1) begin
            data_arr[k] = 32;
            weight_arr[k] = 2;
        end
        bias_val = 64;
        run_test(4, scale_and_saturate(25 * 32 * 2 + (64 << FRAC_BITS)));

        for (k = 0; k < 25; k = k + 1) begin
            data_arr[k] = 127;
            weight_arr[k] = 8;
        end
        bias_val = 0;
        run_test(5, scale_and_saturate(25 * 127 * 8));

        for (k = 0; k < 25; k = k + 1) begin
            data_arr[k] = 127;
            weight_arr[k] = -8;
        end
        bias_val = 0;
        run_test(6, scale_and_saturate(25 * 127 * (-8)));

        #50;
        $display("PASSED: %0d", pass_count);
        $display("FAILED: %0d", fail_count);
        $finish;
    end

endmodule
