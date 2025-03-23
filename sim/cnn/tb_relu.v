`timescale 1ns / 1ps

module tb_relu();
    reg clk;
    reg rst;
    reg valid_in;
    reg signed [7:0] data_in;
    wire valid_out;
    wire signed [7:0] data_out;
    
    reg signed [7:0] prev_data_in;
    
    relu dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .data_in(data_in),
        .valid_out(valid_out),
        .data_out(data_out)
    );
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    always @(posedge clk) begin
        prev_data_in <= data_in;
    end
    
    initial begin
        rst = 1;
        valid_in = 0;
        data_in = 0;
        prev_data_in = 0;
        
        #20;
        rst = 0;
        #10;
        
        // Test case 1: Positive value (should remain unchanged)
        valid_in = 1;
        data_in = 8'sd42;
        #10;
        
        // Test case 2: Zero (should remain unchanged)
        data_in = 8'sd0;
        #10;
        
        // Test case 3: Negative value (should become zero)
        data_in = -8'sd30;
        #10;
        
        // Test case 4: Maximum positive value
        data_in = 8'sd127;
        #10;
        
        // Test case 5: Minimum negative value
        data_in = -8'sd128;
        #10;
        
        // One more cycle to see result of last test
        valid_in = 0;
        #10;
        
        #10;
        
        $display("Test completed");
        $finish;
    end
    
    always @(posedge clk) begin
        if (valid_out) begin
            $display("Time=%0t: Input=%0d, Output=%0d", $time, prev_data_in, data_out);
            
            if (prev_data_in[7]) begin
                if (data_out != 0)
                    $display("Error: Expected 0, got %0d", data_out);
            end else begin
                if (data_out != prev_data_in)
                    $display("Error: Expected %0d, got %0d", prev_data_in, data_out);
            end
        end
    end
    
endmodule 
