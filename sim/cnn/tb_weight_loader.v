`timescale 1ns / 1ps

module tb_weight_loader();
    reg clk;
    reg rst_n;
    
    reg [7:0] layer_select;
    reg [7:0] filter_idx;
    reg [7:0] kernel_idx;
    reg [15:0] input_idx;
    reg [7:0] output_idx;
    
    wire signed [7:0] weight;
    wire signed [7:0] bias;
    
    weight_loader #(
        .DATA_WIDTH(8)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .layer_select(layer_select),
        .filter_idx(filter_idx),
        .kernel_idx(kernel_idx),
        .input_idx(input_idx),
        .output_idx(output_idx),
        .weight(weight),
        .bias(bias)
    );
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    initial begin
        rst_n = 0;
        layer_select = 0;
        filter_idx = 0;
        kernel_idx = 0;
        input_idx = 0;
        output_idx = 0;
        
        #20 rst_n = 1;
        
        #20;
        
        // Test Case 1: First conv layer, filter 0, center of kernel
        layer_select = 8'd0;
        filter_idx = 8'd0;
        kernel_idx = 8'd12;
        #10;
        $display("Conv1 - Filter 0, Center Weight: %d, Bias: %d", weight, bias);
        
        // Test Case 2: First conv layer, filter 1, top-left of kernel
        filter_idx = 8'd1;
        kernel_idx = 8'd0;
        #10;
        $display("Conv1 - Filter 1, Top-Left Weight: %d, Bias: %d", weight, bias);
        
        // Test Case 3: First conv layer, filter 2, bottom-right of kernel
        filter_idx = 8'd2;
        kernel_idx = 8'd24;
        #10;
        $display("Conv1 - Filter 2, Bottom-Right Weight: %d, Bias: %d", weight, bias);
        
        // Test Case 4: Second conv layer
        layer_select = 8'd1;
        filter_idx = 8'd0;
        kernel_idx = 8'd12;
        #10;
        $display("Conv2 - Filter 0, Center Weight: %d, Bias: %d", weight, bias);
        
        // Test Case 5: First fully connected layer
        layer_select = 8'd2;
        input_idx = 16'd50;
        output_idx = 8'd10;
        #10;
        $display("FC1 - Input 50, Output 10 - Weight: %d, Bias: %d", weight, bias);
        
        // Test Case 6: Output layer
        layer_select = 8'd4;
        input_idx = 16'd30;
        output_idx = 8'd5;
        #10;
        $display("Output Layer - Class 5 - Weight from input 30: %d, Bias: %d", weight, bias);
        
        #50;
        $display("Testbench completed");
        $finish;
    end
    
    initial begin
        $monitor("Time=%t, Layer=%d, Filter/Output=%d, Kernel/Input=%d, Weight=%d, Bias=%d",
                 $time, layer_select, filter_idx, kernel_idx, weight, bias);
    end

endmodule
