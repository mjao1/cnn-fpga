`timescale 1ns / 1ps

module tb_weight_loader();
    reg clk;
    reg rst;
    
    reg [7:0] layer_select;
    reg [7:0] filter_idx;
    reg [7:0] in_channel;
    reg [7:0] kernel_row;
    reg [7:0] kernel_col;
    reg [15:0] input_idx;
    reg [15:0] neuron_idx;
    
    wire [7:0] weight_out;
    wire [7:0] bias_out;
    
    weight_loader #(
        .DATA_WIDTH(8)
    ) uut (
        .clk(clk),
        .rst(rst),
        .layer_select(layer_select),
        .filter_idx(filter_idx),
        .in_channel(in_channel),
        .kernel_row(kernel_row),
        .kernel_col(kernel_col),
        .input_idx(input_idx),
        .neuron_idx(neuron_idx),
        .weight_out(weight_out),
        .bias_out(bias_out)
    );
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    initial begin
        rst = 1;
        layer_select = 0;
        filter_idx = 0;
        in_channel = 0;
        kernel_row = 0;
        kernel_col = 0;
        input_idx = 0;
        neuron_idx = 0;
        
        #20 rst = 0;
        
        #20;
        
        // Test Case 1: First conv layer, filter 0, center of kernel
        layer_select = 8'd0;
        filter_idx = 8'd0;
        in_channel = 8'd0;
        kernel_row = 8'd2;  // Center row
        kernel_col = 8'd2;  // Center col
        #10;
        $display("Conv1 - Filter 0, Center Weight: %d, Bias: %d", weight_out, bias_out);
        
        // Test Case 2: First conv layer, filter 1, top-left of kernel
        filter_idx = 8'd1;
        kernel_row = 8'd0;  // Top row
        kernel_col = 8'd0;  // Left col
        #10;
        $display("Conv1 - Filter 1, Top-Left Weight: %d, Bias: %d", weight_out, bias_out);
        
        // Test Case 3: First conv layer, filter 2, bottom-right of kernel
        filter_idx = 8'd2;
        kernel_row = 8'd4;  // Bottom row
        kernel_col = 8'd4;  // Right col
        #10;
        $display("Conv1 - Filter 2, Bottom-Right Weight: %d, Bias: %d", weight_out, bias_out);
        
        // Test Case 4: Second conv layer with multiple input channels
        layer_select = 8'd1;
        filter_idx = 8'd0;
        in_channel = 8'd2;  // Testing with input channel 2
        kernel_row = 8'd2;  // Center row
        kernel_col = 8'd2;  // Center col
        #10;
        $display("Conv2 - Filter 0, Channel 2, Center Weight: %d, Bias: %d", weight_out, bias_out);
        
        // Test Case 5: First fully connected layer (FC1)
        layer_select = 8'd2;
        input_idx = 16'd50;
        neuron_idx = 16'd10;
        #10;
        $display("FC1 - Input 50, Neuron 10 - Weight: %d, Bias: %d", weight_out, bias_out);
        
        // Test Case 6: Output layer (FC3)
        layer_select = 8'd4;
        input_idx = 16'd30;
        neuron_idx = 16'd5;  // Class 5
        #10;
        $display("FC3 (Output) - Class 5 - Weight from input 30: %d, Bias: %d", weight_out, bias_out);
        
        #50;
        $display("Testbench completed");
        $finish;
    end
    
    initial begin
        $monitor("Time=%t Layer=%d Filter=%d Channel=%d Row=%d Col=%d Input=%d Neuron=%d Weight=%d Bias=%d",
                 $time, layer_select, filter_idx, in_channel, kernel_row, kernel_col, 
                 input_idx, neuron_idx, weight_out, bias_out);
    end

endmodule
