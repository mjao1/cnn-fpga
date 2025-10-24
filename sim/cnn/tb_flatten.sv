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
    reg [7:0] x_in;
    reg [7:0] y_in;
    reg [3:0] channel_in;

    wire valid_out;
    wire [DATA_WIDTH-1:0] data_out;
    wire [7:0] addr_out;

    reg [DATA_WIDTH-1:0] test_data [0:IN_CHANNELS-1][0:IN_HEIGHT-1][0:IN_WIDTH-1];
    reg [DATA_WIDTH-1:0] expected_flat [0:OUT_FEATURES-1];
    reg [DATA_WIDTH-1:0] received_flat [0:OUT_FEATURES-1];
    reg received_valid [0:OUT_FEATURES-1];
    integer errors;
    integer outputs_received;

    reg [DATA_WIDTH-1:0] channel_data [0:IN_CHANNELS-1];
    
    integer i;
    integer ii, iii;
    integer ch;
    
    genvar g;
    generate
        for (g = 0; g < IN_CHANNELS; g = g + 1) begin : pack_data
            always_comb begin
                data_in[((g+1)*DATA_WIDTH)-1:g*DATA_WIDTH] = channel_data[g];
            end
        end
    endgenerate

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
        .x_in(x_in),
        .y_in(y_in),
        .channel_in(channel_in),
        .valid_out(valid_out),
        .data_out(data_out),
        .addr_out(addr_out)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test
    integer flat_idx;
    initial begin
        rst = 1;
        valid_in = 0;
        x_in = 0;
        y_in = 0;
        channel_in = 0;
        errors = 0;
        outputs_received = 0;
        
        for (i = 0; i < IN_CHANNELS; i = i + 1) begin
            channel_data[i] = 0;
        end
        
        #(CLK_PERIOD*2);
        rst = 0;
        #(CLK_PERIOD);

        $display("Generating test data...");
        
        // Pattern 1: Unique values based on position
        for (i = 0; i < IN_CHANNELS; i = i + 1) begin
            for (ii = 0; ii < IN_HEIGHT; ii = ii + 1) begin
                for (iii = 0; iii < IN_WIDTH; iii = iii + 1) begin
                    // Create unique values( channel*100 + row*10 + col)
                    test_data[i][ii][iii] = i*100 + ii*10 + iii;
                    
                    // Calculate flattened address
                    flat_idx = (i * IN_HEIGHT * IN_WIDTH) + (ii * IN_WIDTH) + iii;
                    
                    // Compute expected flattened output
                    expected_flat[flat_idx] = test_data[i][ii][iii];
                    
                    // Compare
                    if (flat_idx < 32) begin
                        $display("Expected: ch=%0d, y=%0d, x=%0d -> addr=%0d, val=%0d", 
                                i, ii, iii, flat_idx, test_data[i][ii][iii]);
                    end
                end
            end
        end
        
        for (i = 0; i < OUT_FEATURES; i = i + 1) begin
            received_flat[i] = 8'hFF;
            received_valid[i] = 0;
        end
        
        $display("Feeding data into the flattener...");
        
        // Flatten feature maps
        for (i = 0; i < IN_CHANNELS; i = i + 1) begin
            for (ii = 0; ii < IN_HEIGHT; ii = ii + 1) begin
                for (iii = 0; iii < IN_WIDTH; iii = iii + 1) begin
                    for (ch = 0; ch < IN_CHANNELS; ch = ch + 1) begin
                        if (ch == i) begin
                            channel_data[ch] = test_data[ch][ii][iii];
                        end else begin
                            channel_data[ch] = 8'h00;
                        end
                    end
                    
                    x_in = iii;
                    y_in = ii;
                    channel_in = i;
                    valid_in = 1;
                    
                    @(posedge clk);
                    #1;
                end
            end
        end
        
        valid_in = 0;
        
        repeat (OUT_FEATURES + 20) @(posedge clk);
        
        if (outputs_received < OUT_FEATURES) begin
            $display("ERROR: Timeout waiting for outputs. Only received %0d out of %0d outputs.", 
                     outputs_received, OUT_FEATURES);
        end
        
        // Debug errors
        for (i = 0; i < OUT_FEATURES; i = i + 1) begin
            if (!received_valid[i]) begin
                $display("Error: Output %0d not received", i);
                errors = errors + 1;
            end else if (received_flat[i] !== expected_flat[i]) begin
                $display("Error at output %0d: Expected data = %0d, addr = %0d, Got data = %0d, addr = %0d", 
                         i, expected_flat[i], i, received_flat[i], i);
                errors = errors + 1;
            end
        end
        
        // Display results
        if (errors == 0) begin
            $display("TEST PASSED: All %0d outputs correct", OUT_FEATURES);
        end else begin
            $display("TEST FAILED: %0d errors out of %0d outputs", errors, OUT_FEATURES);
        end
        
        // Run second test with diff pattern
        $display("\nRunning second test with different pattern...");
        rst = 1;
        #(CLK_PERIOD*2);
        rst = 0;
        #(CLK_PERIOD);
        
        errors = 0;
        outputs_received = 0;
        
        // Pattern 2: Reverse counting for easier visual check
        for (i = 0; i < OUT_FEATURES; i = i + 1) begin
            expected_flat[i] = 8'd256 - i;
            received_flat[i] = 8'hFF;
            received_valid[i] = 0;
        end
        
        for (i = 0; i < IN_CHANNELS; i = i + 1) begin
            for (ii = 0; ii < IN_HEIGHT; ii = ii + 1) begin
                for (iii = 0; iii < IN_WIDTH; iii = iii + 1) begin
                    test_data[i][ii][iii] = expected_flat[(i*IN_HEIGHT*IN_WIDTH) + (ii*IN_WIDTH) + iii];
                end
            end
        end
        
        // Flatten feature maps
        for (i = 0; i < IN_CHANNELS; i = i + 1) begin
            for (ii = 0; ii < IN_HEIGHT; ii = ii + 1) begin
                for (iii = 0; iii < IN_WIDTH; iii = iii + 1) begin
                    for (ch = 0; ch < IN_CHANNELS; ch = ch + 1) begin
                        if (ch == i) begin
                            channel_data[ch] = test_data[ch][ii][iii];
                        end else begin
                            channel_data[ch] = 8'h00;
                        end
                    end
                    
                    x_in = iii;
                    y_in = ii;
                    channel_in = i;
                    valid_in = 1;
                    
                    @(posedge clk);
                    #1;
                end
            end
        end
        
        valid_in = 0;
        
        repeat (OUT_FEATURES + 20) @(posedge clk);
        
        if (outputs_received < OUT_FEATURES) begin
            $display("ERROR: Timeout waiting for outputs. Only received %0d out of %0d outputs.", 
                     outputs_received, OUT_FEATURES);
        end
        
        // Debug errors
        for (i = 0; i < OUT_FEATURES; i = i + 1) begin
            if (!received_valid[i]) begin
                $display("Error: Output %0d not received", i);
                errors = errors + 1;
            end else if (received_flat[i] !== expected_flat[i]) begin
                $display("Error at output %0d: Expected data = %0d, addr = %0d, Got data = %0d, addr = %0d", 
                         i, expected_flat[i], i, received_flat[i], i);
                errors = errors + 1;
            end
        end
        
        // Final results
        if (errors == 0) begin
            $display("\nALL TESTS PASSED");
        end else begin
            $display("\nTESTS FAILED with %0d errors", errors);
        end

        $display("\nTest completed");
        
        $finish;
    end
    
    always @(posedge clk) begin
        if (valid_out) begin
            received_flat[addr_out] = data_out;
            received_valid[addr_out] = 1;
            outputs_received = outputs_received + 1;
        end
    end

endmodule 
