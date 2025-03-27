`timescale 1ns / 1ps

module tb_conv_layer_1;
    parameter IMG_WIDTH = 28;
    parameter IMG_HEIGHT = 28;
    parameter OUT_WIDTH = 24;
    parameter OUT_HEIGHT = 24;
    parameter NUM_FILTERS = 6;
    parameter KERNEL_SIZE = 5;
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;
    
    reg clk;
    reg rst;
    reg valid_in;
    reg [DATA_WIDTH-1:0] data_in;
    reg [8:0] x_in;
    reg [8:0] y_in;
    
    wire valid_out;
    wire [DATA_WIDTH-1:0] data_out_0;
    wire [DATA_WIDTH-1:0] data_out_1;
    wire [DATA_WIDTH-1:0] data_out_2;
    wire [DATA_WIDTH-1:0] data_out_3;
    wire [DATA_WIDTH-1:0] data_out_4;
    wire [DATA_WIDTH-1:0] data_out_5;
    wire [8:0] x_out;
    wire [8:0] y_out;
    
    wire [DATA_WIDTH-1:0] data_out_array [0:NUM_FILTERS-1];
    assign data_out_array[0] = data_out_0;
    assign data_out_array[1] = data_out_1;
    assign data_out_array[2] = data_out_2;
    assign data_out_array[3] = data_out_3;
    assign data_out_array[4] = data_out_4;
    assign data_out_array[5] = data_out_5;
    
    reg [DATA_WIDTH-1:0] test_image [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    reg [DATA_WIDTH-1:0] expected_output [0:NUM_FILTERS-1][0:OUT_HEIGHT-1][0:OUT_WIDTH-1];
    
    integer i, j, k, m;
    integer ii, mm, sum;
    integer error_count = 0;
    integer total_tests = 0;
    
    localparam WEIGHT_LOAD_CYCLES = (NUM_FILTERS * (KERNEL_SIZE*KERNEL_SIZE + 1)) + 10; // Extra cycles for safety
    
    wire [1:0] state_debug;
    wire [7:0] current_filter_debug;
    wire [7:0] current_kernel_debug;
    wire load_bias_debug;
    wire signed [DATA_WIDTH-1:0] loaded_weight_debug;
    wire signed [DATA_WIDTH-1:0] loaded_bias_debug;
    
    wire window_valid_debug;
    wire [DATA_WIDTH-1:0] window_data_debug [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    
    wire signed [DATA_WIDTH-1:0] weight_debug [0:NUM_FILTERS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    wire signed [DATA_WIDTH-1:0] bias_debug [0:NUM_FILTERS-1];
    wire signed [19:0] acc_stage5_debug [0:NUM_FILTERS-1];
    
    conv_layer_1 #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .OUT_WIDTH(OUT_WIDTH),
        .OUT_HEIGHT(OUT_HEIGHT),
        .NUM_FILTERS(NUM_FILTERS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .data_in(data_in),
        .x_in(x_in),
        .y_in(y_in),
        .valid_out(valid_out),
        .data_out_0(data_out_0),
        .data_out_1(data_out_1),
        .data_out_2(data_out_2),
        .data_out_3(data_out_3),
        .data_out_4(data_out_4),
        .data_out_5(data_out_5),
        .x_out(x_out),
        .y_out(y_out)
    );
    
    assign state_debug = uut.state;
    assign current_filter_debug = uut.current_filter;
    assign current_kernel_debug = uut.current_kernel;
    assign load_bias_debug = uut.load_bias;
    assign loaded_weight_debug = uut.loaded_weight;
    assign loaded_bias_debug = uut.loaded_bias;
    assign window_valid_debug = uut.window_valid;
    
    genvar gi, gj, gf, gk;
    generate
        for (gi = 0; gi < KERNEL_SIZE; gi = gi + 1) begin
            for (gj = 0; gj < KERNEL_SIZE; gj = gj + 1) begin
                assign window_data_debug[gi][gj] = uut.window[gi][gj];
            end
        end
        
        for (gf = 0; gf < NUM_FILTERS; gf = gf + 1) begin
            assign bias_debug[gf] = uut.bias[gf];
            assign acc_stage5_debug[gf] = uut.conv_units[gf].conv_inst.acc_stage5;
            for (gk = 0; gk < KERNEL_SIZE*KERNEL_SIZE; gk = gk + 1) begin
                assign weight_debug[gf][gk] = uut.weight[gf][gk];
            end
        end
    endgenerate
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    initial begin
        $dumpfile("tb_conv_layer_1.vcd");
        $dumpvars(0, tb_conv_layer_1);
    end
    
    initial begin
        $display("\n=== Convolutional Layer 1 Testbench ===");
        $display("Testing 6 filters on a %0dx%0d input image", IMG_WIDTH, IMG_HEIGHT);
        $display("Output feature maps will be %0dx%0d", OUT_WIDTH, OUT_HEIGHT);
        $display("Weight loading will take approximately %0d cycles", WEIGHT_LOAD_CYCLES);
    end
    
    // Define test patterns
    initial begin
        for (i = 0; i < IMG_HEIGHT; i = i + 1) begin
            for (j = 0; j < IMG_WIDTH; j = j + 1) begin
                test_image[i][j] = 8'd0;
            end
        end
        
        // Create simple MNIST-like digit (7)
        for (j = 8; j < 20; j = j + 1) begin
            test_image[8][j] = 8'd200;
        end
        
        for (i = 9; i < 20; i = i + 1) begin
            test_image[i][20 - (i - 9) / 2] = 8'd200;
        end

        // Add noise
        test_image[10][15] = 8'd50;
        test_image[15][10] = 8'd50;
        test_image[18][18] = 8'd50;
        
        // Print test image pattern
        $display("\n=== Test Image Pattern ===");
        for (i = 0; i < IMG_HEIGHT; i = i + 1) begin
            for (j = 0; j < IMG_WIDTH; j = j + 1) begin
                if (test_image[i][j] > 0) begin
                    $write("%3d ", test_image[i][j]);
                end else begin
                    $write("  . ");
                end
            end
            $write("\n");
        end
    end
    
    // Test
    initial begin
        rst = 1;
        valid_in = 0;
        data_in = 0;
        x_in = 0;
        y_in = 0;
        
        repeat (5) @(posedge clk);
        rst = 0;
        
        $display("\n=== Weight Loading Process ===");
        fork
            begin
                repeat (WEIGHT_LOAD_CYCLES) begin
                    @(posedge clk);
                    if (state_debug != 2'b10) begin
                        $display("Weight loading state: %0d, Filter: %0d, Kernel: %0d, Load bias: %0d, Weight: %0d, Bias: %0d",
                                 state_debug, current_filter_debug, current_kernel_debug, 
                                 load_bias_debug, $signed(loaded_weight_debug), $signed(loaded_bias_debug));
                    end
                end
            end
            
            begin
                // Wait for state machine to enter RUNNING state
                wait(state_debug == 2'b10);
                $display("\n=== Weight Loading Complete ===");
                
                // Dump all loaded weights for verification
                $display("\n=== Loaded Filter Weights ===");
                for (i = 0; i < NUM_FILTERS; i = i + 1) begin
                    $display("Filter %0d bias: %0d", i, $signed(bias_debug[i]));
                    $display("Filter %0d weights:", i);
                    for (j = 0; j < KERNEL_SIZE; j = j + 1) begin
                        $write("  ");
                        for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
                            $write("%4d ", $signed(weight_debug[i][j*KERNEL_SIZE+k]));
                        end
                        $write("\n");
                    end
                end
            end
        join
        
        $display("\nStarting image processing...");
        
        // Feed image data
        for (i = 0; i < IMG_HEIGHT; i = i + 1) begin
            for (j = 0; j < IMG_WIDTH; j = j + 1) begin
                valid_in = 1;
                data_in = test_image[i][j];
                x_in = j;
                y_in = i;
                
                // Debug window content at specific positions
                if ((i >= 8 && i <= 10) && (j >= 8 && j <= 10)) begin
                    @(posedge clk);
                    #1;
                    $display("\n=== Window at position (%0d,%0d) ===", j, i);
                    $display("Window Valid: %0d", window_valid_debug);
                    
                    // Print window contents
                    for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
                        $write("  ");
                        for (m = 0; m < KERNEL_SIZE; m = m + 1) begin
                            $write("%3d ", window_data_debug[k][m]);
                        end
                        $write("\n");
                    end
                    
                    // Add a print of expected convolution results for this window
                    if (window_valid_debug) begin
                        $display("Expected convolution results for this window position:");
                        for (k = 0; k < NUM_FILTERS; k = k + 1) begin
                            sum = 0;
                            // Manual convolution calculation for filter k
                            for (ii = 0; ii < KERNEL_SIZE; ii = ii + 1) begin
                                for (mm = 0; mm < KERNEL_SIZE; mm = mm + 1) begin
                                    sum = sum + $signed(window_data_debug[ii][mm]) * $signed(weight_debug[k][ii*KERNEL_SIZE+mm]);
                                end
                            end
                            sum = sum + $signed(bias_debug[k]);
                            // Saturation
                            if (sum > 127) sum = 127;
                            if (sum < -128) sum = -128;
                            $display("  Filter %0d: Manual calc result = %0d", k, sum);
                        end
                    end
                end else begin
                    @(posedge clk);
                end
            end
        end
        
        valid_in = 0;
        
        repeat (IMG_WIDTH + KERNEL_SIZE*2) @(posedge clk);
        
        $display("\nTest completed");
    end
    
    integer output_count;
    initial begin
        output_count = 0;
        @(posedge valid_out);
        $display("First output detected at time %0t", $time);
        
        forever begin
            @(posedge clk);
            if (valid_out) begin
                output_count = output_count + 1;
                
                if (output_count < 20 || (x_out % 8 == 0 && y_out % 8 == 0)) begin
                    $display("Output at (%0d,%0d): Filter0=%0d, Filter1=%0d, Filter2=%0d, Filter3=%0d, Filter4=%0d, Filter5=%0d",
                        x_out, y_out, 
                        $signed(data_out_0), $signed(data_out_1), $signed(data_out_2),
                        $signed(data_out_3), $signed(data_out_4), $signed(data_out_5)
                    );
                    
                    $display("  Accumulators: F0=%0d, F1=%0d, F2=%0d, F3=%0d, F4=%0d, F5=%0d",
                        $signed(acc_stage5_debug[0]), $signed(acc_stage5_debug[1]), 
                        $signed(acc_stage5_debug[2]), $signed(acc_stage5_debug[3]),
                        $signed(acc_stage5_debug[4]), $signed(acc_stage5_debug[5])
                    );
                    
                    if (($signed(data_out_0) == $signed(bias_debug[0])) && 
                        ($signed(data_out_1) == $signed(bias_debug[1])) &&
                        ($signed(data_out_2) == $signed(bias_debug[2])) &&
                        ($signed(data_out_3) == $signed(bias_debug[3])) &&
                        ($signed(data_out_4) == $signed(bias_debug[4])) &&
                        ($signed(data_out_5) == $signed(bias_debug[5]))) begin
                        $display("  WARNING: Outputs exactly match bias values!");
                    end
                end
            end
        end
    end

endmodule 
