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
    parameter FRAC_BITS = 7;
    parameter CLK_PERIOD = 10;
    
    localparam INPUT_SIZE = MAP_WIDTH * MAP_HEIGHT * IN_CHANNELS;   // 864
    localparam OUTPUT_SIZE = OUT_WIDTH * OUT_HEIGHT * OUT_CHANNELS; // 1024
    
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
    
    // Input data storage
    reg [DATA_WIDTH-1:0] input_flat [0:INPUT_SIZE-1];
    
    // Expected output storage
    reg [DATA_WIDTH-1:0] expected_flat [0:OUTPUT_SIZE-1];
    
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
            always_comb begin
                data_in[((ic_gen+1)*DATA_WIDTH)-1:ic_gen*DATA_WIDTH] = data_in_channel[ic_gen];
            end
        end
    endgenerate
    
    integer i, j, ic, oc;
    integer match_count, mismatch_count;
    
    // 2 phase loading: each weight/bias takes 2 cycles (ADDR, DATA)
    // Weights per filter: 6 * 25 = 150 weights, 300 cycles
    // Bias: 2 cycles (ADDR + DATA)
    // Total per filter: 302 cycles, 16 filters = 4832 cycles
    localparam WEIGHT_LOAD_CYCLES = (OUT_CHANNELS * (IN_CHANNELS * KERNEL_SIZE*KERNEL_SIZE * 2 + 2)) + 50;
    
    conv_layer_2 #(
        .MAP_WIDTH(MAP_WIDTH),
        .MAP_HEIGHT(MAP_HEIGHT),
        .OUT_WIDTH(OUT_WIDTH),
        .OUT_HEIGHT(OUT_HEIGHT),
        .IN_CHANNELS(IN_CHANNELS),
        .OUT_CHANNELS(OUT_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_BITS(FRAC_BITS)
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
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Main test
    initial begin
        rst = 1;
        valid_in = 0;
        x_in = 0;
        y_in = 0;
        match_count = 0;
        mismatch_count = 0;
        
        for (ic = 0; ic < IN_CHANNELS; ic = ic + 1) begin
            data_in_channel[ic] = 0;
        end
        
        // Load input image and expected outputs
        $readmemh("sim/cnn/golden_vectors/pool1_expected.mem", input_flat);
        $readmemh("sim/cnn/golden_vectors/conv2_expected.mem", expected_flat);
        
        $display("=== Convolutional Layer 2 Testbench ===");
        $display("Input: %0dx%0dx%0d from pool1, Output: %0dx%0dx%0d", 
                 MAP_WIDTH, MAP_HEIGHT, IN_CHANNELS, OUT_WIDTH, OUT_HEIGHT, OUT_CHANNELS);
        
        #100;
        rst = 0;
        
        #(CLK_PERIOD * WEIGHT_LOAD_CYCLES);
        
        $display("Weight loading complete, starting inference...");
        
        // Feed in the input image
        for (i = 0; i < MAP_HEIGHT; i = i + 1) begin
            for (j = 0; j < MAP_WIDTH; j = j + 1) begin
                x_in = j;
                y_in = i;
                
                for (ic = 0; ic < IN_CHANNELS; ic = ic + 1) begin
                    data_in_channel[ic] = input_flat[ic * (MAP_WIDTH * MAP_HEIGHT) + i * MAP_WIDTH + j];
                end
                
                valid_in = 1;
                @(posedge clk);
                #1;
            end
        end
        
        valid_in = 0;
        
        // Wait for pipeline to flush
        repeat (100) @(posedge clk);
        
        $display("\n=== Test Summary ===");
        $display("Total outputs: %0d", match_count + mismatch_count);
        $display("Matches: %0d, Mismatches: %0d", match_count, mismatch_count);
        $finish;
    end
    
    // Output checker
    integer output_count;
    reg [DATA_WIDTH-1:0] expected_val;
    reg [DATA_WIDTH-1:0] actual_val;
    integer exp_idx;
    
    initial begin
        output_count = 0;
        @(negedge rst);
        
        forever begin
            @(posedge clk);
            if (valid_out) begin
                for (oc = 0; oc < OUT_CHANNELS; oc = oc + 1) begin
                    exp_idx = oc * (OUT_WIDTH * OUT_HEIGHT) + y_out * OUT_WIDTH + x_out;
                    expected_val = expected_flat[exp_idx];
                    actual_val = data_out_channel[oc];
                    
                    if (actual_val == expected_val) begin
                        match_count = match_count + 1;
                    end else begin
                        mismatch_count = mismatch_count + 1;
                        $display("MISMATCH @(%0d,%0d) ch%0d: expected=%0d, actual=%0d", 
                                 x_out, y_out, oc, $signed(expected_val), $signed(actual_val));
                    end
                end
                
                output_count = output_count + 1;
            end
        end
    end

endmodule 
