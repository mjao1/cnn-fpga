`timescale 1ns / 1ps

module tb_fc_layers;
    parameter DATA_WIDTH = 8;
    parameter FC1_IN_FEATURES = 256;
    parameter FC1_OUT_FEATURES = 120;
    parameter FC2_IN_FEATURES = 120;
    parameter FC2_OUT_FEATURES = 84;
    parameter FC3_IN_FEATURES = 84;
    parameter FC3_OUT_FEATURES = 10;
    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst;
    reg start;
    reg valid_in;
    reg [DATA_WIDTH-1:0] data_in;
    reg [7:0] addr_in;
    
    wire valid_out;
    wire [DATA_WIDTH-1:0] data_out;
    wire [3:0] digit_idx;
    wire done_out;
    
    reg [DATA_WIDTH-1:0] test_inputs [0:FC1_IN_FEATURES-1];
    reg [DATA_WIDTH-1:0] received_outputs [0:FC3_OUT_FEATURES-1];
    reg received_valid [0:FC3_OUT_FEATURES-1];
    
    integer errors;
    integer outputs_received;
    integer i;
    
    reg signed [DATA_WIDTH-1:0] max_val;
    reg [3:0] max_idx;
    integer j;
    
    fc_layers #(
        .FC1_IN_FEATURES(FC1_IN_FEATURES),
        .FC1_OUT_FEATURES(FC1_OUT_FEATURES),
        .FC2_IN_FEATURES(FC2_IN_FEATURES),
        .FC2_OUT_FEATURES(FC2_OUT_FEATURES),
        .FC3_IN_FEATURES(FC3_IN_FEATURES),
        .FC3_OUT_FEATURES(FC3_OUT_FEATURES),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .valid_in(valid_in),
        .data_in(data_in),
        .addr_in(addr_in),
        .valid_out(valid_out),
        .data_out(data_out),
        .digit_idx(digit_idx),
        .done_out(done_out)
    );
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    always @(posedge clk) begin
        if (valid_out) begin
            received_outputs[digit_idx] <= data_out;
            received_valid[digit_idx] <= 1'b1;
            outputs_received <= outputs_received + 1;
            $display("Digit %d score = %4d (0x%h)", digit_idx, $signed(data_out), data_out);
        end
    end
    
    // Test
    initial begin
        rst = 1;
        start = 0;
        valid_in = 0;
        data_in = 0;
        addr_in = 0;
        errors = 0;
        outputs_received = 0;
        
        // Initialize test arrays
        for (i = 0; i < FC3_OUT_FEATURES; i = i + 1) begin
            received_outputs[i] = 8'h00;
            received_valid[i] = 0;
        end
        
        // Generate test inputs - recognizable pattern with digit 3 emphasized
        for (i = 0; i < FC1_IN_FEATURES; i = i + 1) begin
            if (i % 10 == 3) 
                test_inputs[i] = 8'h7F; // Strong positive for pattern matching digit 3
            else
                test_inputs[i] = (i % 2 == 0) ? 8'h20 : 8'hE0; // Alternating pattern for other positions
        end
        
        #(CLK_PERIOD*2);
        rst = 0;
        #(CLK_PERIOD);
        
        $display("Starting fc_layers processing...");
        
        start = 1;
        #(CLK_PERIOD);
        start = 0;
        
        for (i = 0; i < FC1_IN_FEATURES; i = i + 1) begin
            valid_in = 1;
            data_in = test_inputs[i];
            addr_in = i;
            
            @(posedge clk);
            #1;
        end
        
        valid_in = 0;
        
        $display("All inputs sent, waiting for processing...");
        
        wait(done_out);
        $display("FC layers processing complete at time %t", $time);
        
        repeat (FC3_OUT_FEATURES + 20) @(posedge clk);
        
        $display("Checking results...");
        $display("Outputs received: %d out of %d", outputs_received, FC3_OUT_FEATURES);
        
        // Error count
        errors = 0;
        for (i = 0; i < FC3_OUT_FEATURES; i = i + 1) begin
            if (!received_valid[i]) begin
                $display("ERROR: No output received for digit %d", i);
                errors = errors + 1;
            end
        end
        
        if (errors == 0 && outputs_received == FC3_OUT_FEATURES) begin
            $display("TEST PASSED: All digit scores produced");
            
            max_val = $signed(received_outputs[0]);
            max_idx = 0;
            
            for (j = 1; j < FC3_OUT_FEATURES; j = j + 1) begin
                if ($signed(received_outputs[j]) > max_val) begin
                    max_val = $signed(received_outputs[j]);
                    max_idx = j;
                end
            end
            
            $display("CLASSIFICATION RESULT: Digit %d (score = %d)", max_idx, $signed(max_val));
            
            $display("\nAll digit scores:");
            for (i = 0; i < FC3_OUT_FEATURES; i = i + 1) begin
                $display("Digit %d: %4d", i, $signed(received_outputs[i]));
            end
        end else begin
            $display("TEST FAILED: %d errors, %d outputs received of %d expected", 
                    errors, outputs_received, FC3_OUT_FEATURES);
        end
        
        #(CLK_PERIOD*10);
        $finish;
    end

endmodule 
