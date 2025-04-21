`timescale 1ns / 1ps

module tb_weight_loader();

    parameter DATA_WIDTH = 8;
    
    reg clk;
    reg rst;
    
    reg [7:0] layer_select;      // 0: Conv1, 1: Conv2, 2: FC1, etc.
    reg [7:0] filter_idx;        // For conv layers
    reg [7:0] in_channel;        // For conv layers (conv1 has 1 channel)
    reg [7:0] kernel_row;        // For conv layers
    reg [7:0] kernel_col;        // For conv layers
    reg [15:0] input_idx;        // For FC layers
    reg [15:0] neuron_idx;       // For FC layers
    
    wire [DATA_WIDTH-1:0] weight_out;
    wire [DATA_WIDTH-1:0] bias_out;
    
    weight_loader uut (
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
        // Start with reset
        rst         = 1;
        layer_select = 8'd0;
        filter_idx   = 8'd0;
        in_channel   = 8'd0;
        kernel_row   = 8'd0;
        kernel_col   = 8'd0;
        input_idx    = 16'd0;
        neuron_idx   = 16'd0;

        #20;
        rst = 0;

        #20;

        // Test Conv1 weights & biases
        layer_select = 8'd0;  // Conv1
        // Loop through a few indices for conv1 (conv1 has NUM_FILTERS=6, KERNEL_SIZE=5, IN_CHANNELS=1)
        $display("=== Testing Conv1 Weights from mem file ===");
        for (filter_idx = 0; filter_idx < 6; filter_idx = filter_idx + 1) begin
            for (kernel_row = 0; kernel_row < 5; kernel_row = kernel_row + 1) begin
                for (kernel_col = 0; kernel_col < 5; kernel_col = kernel_col + 1) begin
                    in_channel = 0;  // Only channel 0 for conv1
                    #10;
                    $display("Conv1: filter=%0d, row=%0d, col=%0d -> weight = %h, bias = %h", filter_idx, kernel_row, kernel_col, weight_out, bias_out);
                end
            end
        end
        
        // Test Conv2 weights & biases
        layer_select = 8'd1;  // Conv2

        input_idx  = 0;
        neuron_idx = 0;

        $display("\n=== Testing Conv2 Weights from mem file (channel 0) ===");
        for (filter_idx = 0; filter_idx < 16; filter_idx = filter_idx + 1) begin
            in_channel = 0; // examine channel 0 for brevity; can loop 0..5 if desired
            for (kernel_row = 0; kernel_row < 5; kernel_row = kernel_row + 1) begin
                for (kernel_col = 0; kernel_col < 5; kernel_col = kernel_col + 1) begin
                    #10;
                    $display("Conv2: filt=%0d, ch=%0d, r=%0d, c=%0d -> w=%h b=%h", filter_idx, in_channel, kernel_row, kernel_col, weight_out, bias_out);
                end
            end
        end

        // Test FC1 weights & biases
        layer_select = 8'd2;  // FC1
 
        filter_idx  = 0;
        in_channel  = 0;
        kernel_row  = 0;
        kernel_col  = 0;

        #10;

        $display("\n=== Testing FC1 Weights from mem file ===");
        neuron_idx = 16'd0; input_idx = 16'd0;
        #10;
        $display("FC1: neuron=%0d, input=%0d -> weight=%h bias=%h", neuron_idx, input_idx, weight_out, bias_out);

        neuron_idx = 16'd0; input_idx = 16'd1;
        #10;
        $display("FC1: neuron=%0d, input=%0d -> weight=%h bias=%h", neuron_idx, input_idx, weight_out, bias_out);

        neuron_idx = 16'd1; input_idx = 16'd0;
        #10;
        $display("FC1: neuron=%0d, input=%0d -> weight=%h bias=%h", neuron_idx, input_idx, weight_out, bias_out);

        // Test FC2 weights & biases
        layer_select = 8'd3;  // FC2

        filter_idx  = 0;
        in_channel  = 0;
        kernel_row  = 0;
        kernel_col  = 0;

        $display("\n=== Testing FC2 Weights from mem file ===");
        neuron_idx = 16'd0; input_idx = 16'd0; #10;
        $display("FC2: neuron=%0d, input=%0d -> w=%h b=%h", neuron_idx, input_idx, weight_out, bias_out);
        neuron_idx = 16'd0; input_idx = 16'd5; #10;
        $display("FC2: neuron=%0d, input=%0d -> w=%h b=%h", neuron_idx, input_idx, weight_out, bias_out);
        neuron_idx = 16'd10; input_idx = 16'd0; #10;
        $display("FC2: neuron=%0d, input=%0d -> w=%h b=%h", neuron_idx, input_idx, weight_out, bias_out);

        // Test FC3 weights & biases
        layer_select = 8'd4;  // FC3 (output layer)

        $display("\n=== Testing FC3 Weights from mem file ===");
        neuron_idx = 16'd0; input_idx = 16'd0; #10;
        $display("FC3: neuron=%0d, input=%0d -> w=%h b=%h", neuron_idx, input_idx, weight_out, bias_out);
        neuron_idx = 16'd5; input_idx = 16'd30; #10;
        $display("FC3: neuron=%0d, input=%0d -> w=%h b=%h", neuron_idx, input_idx, weight_out, bias_out);

        $display("Testbench completed");
        $finish;
    end

endmodule
