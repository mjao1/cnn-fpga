`timescale 1ns / 1ps

module tb_conv_layer_2;
    parameter MAP_WIDTH = 12;
    parameter MAP_HEIGHT = 12;
    parameter OUT_WIDTH = 8;
    parameter OUT_HEIGHT = 8;
    parameter IN_CHANNELS = 6;
    parameter OUT_CHANNELS = 16;
    parameter KERNEL_SIZE = 5;
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;
    
    reg clk;
    reg rst;
    reg valid_in;
    reg [(DATA_WIDTH*IN_CHANNELS)-1:0] data_in;
    reg [7:0] x_in;
    reg [7:0] y_in;
    
    wire valid_out;
    wire [(DATA_WIDTH*OUT_CHANNELS)-1:0] data_out;
    wire [7:0] x_out;
    wire [7:0] y_out;
    
    reg [DATA_WIDTH-1:0] test_feature_maps [0:IN_CHANNELS-1][0:MAP_HEIGHT-1][0:MAP_WIDTH-1];
    
    reg [DATA_WIDTH-1:0] data_in_channel [0:IN_CHANNELS-1];
    wire [DATA_WIDTH-1:0] data_out_channel [0:OUT_CHANNELS-1];
    
    // Unpack output channels
    generate
        genvar p;
        for (p = 0; p < OUT_CHANNELS; p = p + 1) begin : unpack_outputs
            assign data_out_channel[p] = data_out[((p+1)*DATA_WIDTH)-1:p*DATA_WIDTH];
        end
    endgenerate
    
    // Pack input channels
    generate
        genvar ic_gen;
        for (ic_gen = 0; ic_gen < IN_CHANNELS; ic_gen = ic_gen + 1) begin : pack_inputs
            always @(*) begin
                data_in[((ic_gen+1)*DATA_WIDTH)-1:ic_gen*DATA_WIDTH] = data_in_channel[ic_gen];
            end
        end
    endgenerate
    
    integer i, j, k, ic, oc, m;
    integer sum;
    
    localparam WEIGHT_LOAD_CYCLES = (OUT_CHANNELS * (IN_CHANNELS * KERNEL_SIZE*KERNEL_SIZE + 1)) + 20;
    
    wire [1:0] state_debug;
    wire [7:0] current_filter_debug;
    wire [7:0] current_channel_debug;
    wire [7:0] current_kernel_debug;
    wire load_bias_debug;
    wire signed [DATA_WIDTH-1:0] loaded_weight_debug;
    wire signed [DATA_WIDTH-1:0] loaded_bias_debug;
    wire window_valid_debug;
    
    wire signed [DATA_WIDTH-1:0] weight_debug [0:OUT_CHANNELS-1][0:IN_CHANNELS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    wire signed [DATA_WIDTH-1:0] bias_debug [0:OUT_CHANNELS-1];
    wire signed [19:0] channel_acc_debug [0:OUT_CHANNELS-1];
    
    conv_layer_2 #(
        .MAP_WIDTH(MAP_WIDTH),
        .MAP_HEIGHT(MAP_HEIGHT),
        .OUT_WIDTH(OUT_WIDTH),
        .OUT_HEIGHT(OUT_HEIGHT),
        .IN_CHANNELS(IN_CHANNELS),
        .OUT_CHANNELS(OUT_CHANNELS),
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
        .data_out(data_out),
        .x_out(x_out),
        .y_out(y_out)
    );
    
    assign state_debug = uut.state;
    assign current_filter_debug = uut.current_filter;
    assign current_channel_debug = uut.current_channel;
    assign current_kernel_debug = uut.current_kernel;
    assign load_bias_debug = uut.load_bias;
    assign loaded_weight_debug = uut.loaded_weight;
    assign loaded_bias_debug = uut.loaded_bias;
    assign window_valid_debug = uut.window_valid;
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Test
    initial begin
        rst = 1;
        valid_in = 0;
        x_in = 0;
        y_in = 0;
        
        for (ic = 0; ic < IN_CHANNELS; ic = ic + 1) begin
            data_in_channel[ic] = 0;
        end
        
        // Initialize test feature maps with a simple pattern
        for (ic = 0; ic < IN_CHANNELS; ic = ic + 1) begin
            for (i = 0; i < MAP_HEIGHT; i = i + 1) begin
                for (j = 0; j < MAP_WIDTH; j = j + 1) begin
                    test_feature_maps[ic][i][j] = 0;
                    
                    if (i >= 5 && i < 7 && j >= 5 && j < 7) begin
                        test_feature_maps[ic][i][j] = (8'd50 * (ic + 1));
                    end
                    
                    if ((i == 1 && j == 1) || (i == 1 && j == MAP_WIDTH-2) || 
                        (i == MAP_HEIGHT-2 && j == 1) || (i == MAP_HEIGHT-2 && j == MAP_WIDTH-2)) begin
                        test_feature_maps[ic][i][j] = (8'd100 * (ic + 1));
                    end
                end
            end
        end
        
        $display("=== Convolutional Layer 2 Testbench ===");
        $display("Testing %0d filters on %0d input channels of size %0dx%0d", OUT_CHANNELS, IN_CHANNELS, MAP_WIDTH, MAP_HEIGHT);
        $display("Output feature maps will be %0dx%0d", OUT_WIDTH, OUT_HEIGHT);
        $display("Weight loading will take approximately %0d cycles", WEIGHT_LOAD_CYCLES);
        
        for (ic = 0; ic < IN_CHANNELS; ic = ic + 1) begin
            $display("\n=== Test Pattern for Input Channel %0d ===", ic);
            for (i = 0; i < MAP_HEIGHT; i = i + 1) begin
                for (j = 0; j < MAP_WIDTH; j = j + 1) begin
                    if (test_feature_maps[ic][i][j] == 0)
                        $write("  . ");
                    else
                        $write("%3d ", test_feature_maps[ic][i][j]);
                end
                $write("\n");
            end
        end
        
        #100;
        rst = 0;
        
        #(CLK_PERIOD * WEIGHT_LOAD_CYCLES);
        
        $display("\n=== Weight Loading Complete ===");
        $display("\nStarting feature map processing...");
        
        // Feed in the test feature maps
        for (i = 0; i < MAP_HEIGHT; i = i + 1) begin
            for (j = 0; j < MAP_WIDTH; j = j + 1) begin
                x_in = j;
                y_in = i;
                
                for (ic = 0; ic < IN_CHANNELS; ic = ic + 1) begin
                    data_in_channel[ic] = test_feature_maps[ic][i][j];
                end
                
                valid_in = 1;
                
                @(posedge clk);
                
                if (i >= KERNEL_SIZE-1 && j >= KERNEL_SIZE-1 && i < MAP_HEIGHT && j < MAP_WIDTH) begin
                    if ((i == KERNEL_SIZE-1 && j == KERNEL_SIZE-1) || 
                        (i == MAP_HEIGHT/2 && j == MAP_WIDTH/2) || 
                        (i == MAP_HEIGHT-KERNEL_SIZE && j == MAP_WIDTH-KERNEL_SIZE)) begin
                        
                        $display("\n=== Window at position (%0d,%0d) ===", j, i);
                        $display("Window Valid: %0d", window_valid_debug);
                        
                        for (ic = 0; ic < 2; ic = ic + 1) begin
                            $display("Channel %0d window:", ic);
                            for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
                                for (m = 0; m < KERNEL_SIZE; m = m + 1) begin
                                    $write("%3d ", uut.window[ic][k][m]);
                                end
                                $write("\n");
                            end
                        end
                    end
                end
            end
        end
        
        valid_in = 0;
        
        repeat (MAP_WIDTH + KERNEL_SIZE*2) @(posedge clk);
        
        $display("\nTest completed");
        $finish;
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
                
                if (output_count < 20 || (x_out % 4 == 0 && y_out % 4 == 0)) begin
                    $write("Output at (%0d,%0d): ", x_out, y_out);
                    
                    for (oc = 0; oc < 4; oc = oc + 1) begin
                        $write("F%0d=%0d, ", oc, $signed(data_out_channel[oc]));
                    end
                    
                    $write("... ");
                    
                    for (oc = OUT_CHANNELS-2; oc < OUT_CHANNELS; oc = oc + 1) begin
                        $write("F%0d=%0d, ", oc, $signed(data_out_channel[oc]));
                    end
                    
                    $write("\n");
                end
            end
        end
    end

endmodule 
