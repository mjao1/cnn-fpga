`timescale 1ns / 1ps

module tb_flatten;
    parameter IN_CHANNELS = 16;
    parameter IN_WIDTH = 4;
    parameter IN_HEIGHT = 4;
    parameter DATA_WIDTH = 8;
    parameter OUT_FEATURES = 256;
    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst;
    reg valid_in;
    reg [(DATA_WIDTH*IN_CHANNELS)-1:0] data_in;

    wire valid_out;
    wire [DATA_WIDTH-1:0] data_out;
    wire [7:0] addr_out;

    reg [DATA_WIDTH-1:0] expected_flat [0:OUT_FEATURES-1];
    reg [DATA_WIDTH-1:0] received_flat [0:OUT_FEATURES-1];
    integer errors;
    integer outputs_received;
    
    integer i, j, ch;
    
    flatten #(
        .IN_CHANNELS(IN_CHANNELS),
        .IN_WIDTH(IN_WIDTH),
        .IN_HEIGHT(IN_HEIGHT),
        .DATA_WIDTH(DATA_WIDTH),
        .OUT_FEATURES(OUT_FEATURES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .data_in(data_in),
        .valid_out(valid_out),
        .data_out(data_out),
        .addr_out(addr_out)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    always @(posedge clk) begin
        if (valid_out && outputs_received < OUT_FEATURES) begin
            received_flat[addr_out] = data_out;
            outputs_received = outputs_received + 1;
        end
    end

    initial begin
        rst = 1;
        valid_in = 0;
        data_in = 0;
        errors = 0;
        outputs_received = 0;
        
        for (i = 0; i < IN_CHANNELS; i = i + 1) begin
            for (j = 0; j < OUT_FEATURES; j = j + 1) begin
                received_flat[j] = 8'hFF;
            end
        end
        
        #(CLK_PERIOD*3);
        rst = 0;
        #(CLK_PERIOD);
        
        $display("Test: Flatten 16 channels of 4x4 data into 256 elements");
        
        for (i = 0; i < IN_HEIGHT * IN_WIDTH; i = i + 1) begin
            data_in = 0;
            for (ch = 0; ch < IN_CHANNELS; ch = ch + 1) begin
                data_in[((ch+1)*DATA_WIDTH)-1 -: DATA_WIDTH] = i * 16 + ch;
                expected_flat[i * 16 + ch] = i * 16 + ch;
            end
            
            @(posedge clk);
            #1;
            valid_in = 1;
            @(posedge clk);
            #1;
            valid_in = 0;
        end
        
        // Wait for all outputs
        repeat (OUT_FEATURES + 50) @(posedge clk);
        
        $display("Received %0d outputs", outputs_received);
        
        // Check outputs
        for (i = 0; i < OUT_FEATURES; i = i + 1) begin
            if (received_flat[i] !== expected_flat[i]) begin
                if (errors < 20) begin  // Limit error messages
                    $display("Error at addr %0d: Expected=%0d, Got=%0d", 
                             i, expected_flat[i], received_flat[i]);
                end
                errors = errors + 1;
            end
        end
        
        if (errors == 0 && outputs_received == OUT_FEATURES) begin
            $display("TEST PASSED: All %0d outputs correct", OUT_FEATURES);
        end else begin
            $display("TEST FAILED: %0d errors, %0d outputs received", errors, outputs_received);
        end
        
        $finish;
    end

endmodule
