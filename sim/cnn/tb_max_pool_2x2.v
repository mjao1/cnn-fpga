`timescale 1ns / 1ps

module tb_max_pool_2x2();
    reg clk;
    reg rst;
    reg valid_in;
    reg signed [7:0] data_in_00;
    reg signed [7:0] data_in_01;
    reg signed [7:0] data_in_10;
    reg signed [7:0] data_in_11;
    wire valid_out;
    wire signed [7:0] data_out;
    
    reg signed [7:0] prev_in_00;
    reg signed [7:0] prev_in_01;
    reg signed [7:0] prev_in_10;
    reg signed [7:0] prev_in_11;
    
    max_pool_2x2 dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .data_in_00(data_in_00),
        .data_in_01(data_in_01),
        .data_in_10(data_in_10),
        .data_in_11(data_in_11),
        .valid_out(valid_out),
        .data_out(data_out)
    );
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    always @(posedge clk) begin
        prev_in_00 <= data_in_00;
        prev_in_01 <= data_in_01;
        prev_in_10 <= data_in_10;
        prev_in_11 <= data_in_11;
    end
    
    initial begin
        rst = 1;
        valid_in = 0;
        data_in_00 = 0;
        data_in_01 = 0;
        data_in_10 = 0;
        data_in_11 = 0;
        prev_in_00 = 0;
        prev_in_01 = 0;
        prev_in_10 = 0;
        prev_in_11 = 0;
        
        #20;
        rst = 0;
        #10;
        
        // Test case 1: Max in top-left
        valid_in = 1;
        data_in_00 = 8'sd100;  // Top-left (max)
        data_in_01 = 8'sd25;   // Top-right
        data_in_10 = 8'sd50;   // Bottom-left
        data_in_11 = 8'sd75;   // Bottom-right
        #10;
        
        // Test case 2: Max in top-right
        data_in_00 = 8'sd25;   // Top-left
        data_in_01 = 8'sd100;  // Top-right (max)
        data_in_10 = 8'sd50;   // Bottom-left
        data_in_11 = 8'sd75;   // Bottom-right
        #10;
        
        // Test case 3: Max in bottom-left
        data_in_00 = 8'sd25;   // Top-left
        data_in_01 = 8'sd50;   // Top-right
        data_in_10 = 8'sd100;  // Bottom-left (max)
        data_in_11 = 8'sd75;   // Bottom-right
        #10;
        
        // Test case 4: Max in bottom-right
        data_in_00 = 8'sd25;   // Top-left
        data_in_01 = 8'sd50;   // Top-right
        data_in_10 = 8'sd75;   // Bottom-left
        data_in_11 = 8'sd100;  // Bottom-right (max)
        #10;
        
        // Test case 5: All values equal
        data_in_00 = 8'sd50;   // Top-left
        data_in_01 = 8'sd50;   // Top-right
        data_in_10 = 8'sd50;   // Bottom-left
        data_in_11 = 8'sd50;   // Bottom-right
        #10;
        
        // Test case 6: Negative values
        data_in_00 = -8'sd50;  // Top-left
        data_in_01 = -8'sd25;  // Top-right (max)
        data_in_10 = -8'sd75;  // Bottom-left
        data_in_11 = -8'sd100; // Bottom-right
        #10;
        
        valid_in = 0;
        #10;
        
        #10;
        
        $display("Test completed");
        $finish;
    end
    
    always @(posedge clk) begin
        if (valid_out) begin
            $display("Time=%0t: Inputs=[%0d,%0d,%0d,%0d], Output=%0d", 
                    $time, prev_in_00, prev_in_01, prev_in_10, prev_in_11, data_out);
            
            case ({prev_in_00, prev_in_01, prev_in_10, prev_in_11})
                {8'sd100, 8'sd25, 8'sd50, 8'sd75}: 
                    if (data_out !== 8'sd100) $display("Error: Expected 100, got %0d", data_out);
                {8'sd25, 8'sd100, 8'sd50, 8'sd75}: 
                    if (data_out !== 8'sd100) $display("Error: Expected 100, got %0d", data_out);
                {8'sd25, 8'sd50, 8'sd100, 8'sd75}: 
                    if (data_out !== 8'sd100) $display("Error: Expected 100, got %0d", data_out);
                {8'sd25, 8'sd50, 8'sd75, 8'sd100}: 
                    if (data_out !== 8'sd100) $display("Error: Expected 100, got %0d", data_out);
                {8'sd50, 8'sd50, 8'sd50, 8'sd50}: 
                    if (data_out !== 8'sd50) $display("Error: Expected 50, got %0d", data_out);
                {-8'sd50, -8'sd25, -8'sd75, -8'sd100}: 
                    if (data_out !== -8'sd25) $display("Error: Expected -25, got %0d", data_out);
            endcase
        end
    end
    
endmodule 
