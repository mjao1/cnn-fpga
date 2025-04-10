`timescale 1ns / 1ps

module tb_fc_layer_3;
    parameter DATA_WIDTH = 8;
    parameter IN_FEATURES = 84;
    parameter OUT_FEATURES = 10;
    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst;
    reg valid_in;
    reg [DATA_WIDTH-1:0] data_in;
    reg [6:0] addr_in;
    
    wire valid_out;
    wire [DATA_WIDTH-1:0] data_out;
    wire [3:0] neuron_idx;
    wire done_out;
    
    reg [DATA_WIDTH-1:0] test_inputs [0:IN_FEATURES-1];
    reg [DATA_WIDTH-1:0] received_outputs [0:OUT_FEATURES-1];
    reg received_valid [0:OUT_FEATURES-1];
    
    integer errors;
    integer outputs_received;
    integer i;
    
    fc_layer_3 #(
        .IN_FEATURES(IN_FEATURES),
        .OUT_FEATURES(OUT_FEATURES),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .data_in(data_in),
        .addr_in(addr_in),
        .valid_out(valid_out),
        .data_out(data_out),
        .neuron_idx(neuron_idx),
        .done_out(done_out)
    );
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    always @(posedge clk) begin
        if (valid_out) begin
            received_outputs[neuron_idx] <= data_out;
            received_valid[neuron_idx] <= 1'b1;
            outputs_received <= outputs_received + 1;
            $display("Digit %d score = %4d (0x%h)", neuron_idx, $signed(data_out), data_out);
        end
    end
    
    // Test
    reg signed [DATA_WIDTH-1:0] max_val;
    reg [3:0] max_idx;
    integer j;
    initial begin
        rst = 1;
        valid_in = 0;
        data_in = 0;
        addr_in = 0;
        errors = 0;
        outputs_received = 0;
        
        // Initialize test arrays
        for (i = 0; i < OUT_FEATURES; i = i + 1) begin
            received_outputs[i] = 8'h00;
            received_valid[i] = 0;
        end
        
        // Generate test inputs
        for (i = 0; i < IN_FEATURES; i = i + 1) begin
            if (i % 10 == 5) 
                test_inputs[i] = 8'h7F; // strong positive
            else
                test_inputs[i] = 8'h10; // small positive
        end
        
        #(CLK_PERIOD*2);
        rst = 0;
        #(CLK_PERIOD);
        
        $display("Sending input data to FC3 layer...");
        
        for (i = 0; i < IN_FEATURES; i = i + 1) begin
            valid_in = 1;
            data_in = test_inputs[i];
            addr_in = i;
            
            @(posedge clk);
            #1;
        end
        
        valid_in = 0;
        
        $display("All inputs sent, waiting for processing...");
        
        // Wait for processing to complete
        wait(done_out);
        $display("FC3 layer signaled done_out=1 at time %t", $time);
        
        repeat (OUT_FEATURES + 10) @(posedge clk);
        
        $display("Checking results...");
        $display("Outputs received: %d out of %d", outputs_received, OUT_FEATURES);
        
        // Error count
        errors = 0;
        for (i = 0; i < OUT_FEATURES; i = i + 1) begin
            if (!received_valid[i]) begin
                $display("ERROR: No output received for digit %d", i);
                errors = errors + 1;
            end
        end
        
        if (errors == 0 && outputs_received == OUT_FEATURES) begin
            $display("TEST PASSED: All digit scores produced");

            max_val = $signed(received_outputs[0]);
            max_idx = 0;
            
            for (j = 1; j < OUT_FEATURES; j = j + 1) begin
                if ($signed(received_outputs[j]) > max_val) begin
                    max_val = $signed(received_outputs[j]);
                    max_idx = j;
                end
            end
            
            $display("Recognized digit: %d (score = %d)", max_idx, $signed(max_val));
        end else begin
            $display("TEST FAILED: %d errors, %d outputs received of %d expected", 
                    errors, outputs_received, OUT_FEATURES);
        end
        
        #(CLK_PERIOD*10);
        $finish;
    end

endmodule 
