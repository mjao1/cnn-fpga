`timescale 1ns / 1ps

module tb_pool_layer_2;
    parameter IN_WIDTH = 8;
    parameter IN_HEIGHT = 8;
    parameter OUT_WIDTH = 4;
    parameter OUT_HEIGHT = 4;
    parameter NUM_CHANNELS = 16;
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;
    
    reg clk;
    reg rst;
    reg valid_in;
    reg [(DATA_WIDTH*NUM_CHANNELS)-1:0] data_in;
    reg [7:0] x_in;
    reg [7:0] y_in;
    
    wire valid_out;
    wire [(DATA_WIDTH*NUM_CHANNELS)-1:0] data_out;
    wire [7:0] x_out;
    wire [7:0] y_out;
    
    reg [DATA_WIDTH-1:0] test_feature_maps [0:NUM_CHANNELS-1][0:IN_HEIGHT-1][0:IN_WIDTH-1];
    
    reg [DATA_WIDTH-1:0] expected_outputs [0:NUM_CHANNELS-1][0:OUT_HEIGHT-1][0:OUT_WIDTH-1];
    
    reg [DATA_WIDTH-1:0] data_in_channel [0:NUM_CHANNELS-1];
    wire [DATA_WIDTH-1:0] data_out_channel [0:NUM_CHANNELS-1];
    
    // Pack input channels and unpack output channels
    genvar c;
    generate
        for (c = 0; c < NUM_CHANNELS; c = c + 1) begin : channel_connections
            always_comb begin
                data_in[((c+1)*DATA_WIDTH)-1:c*DATA_WIDTH] = data_in_channel[c];
            end
            assign data_out_channel[c] = data_out[((c+1)*DATA_WIDTH)-1:c*DATA_WIDTH];
        end
    endgenerate
    
    pool_layer_2 #(
        .IN_WIDTH(IN_WIDTH),
        .IN_HEIGHT(IN_HEIGHT),
        .OUT_WIDTH(OUT_WIDTH),
        .OUT_HEIGHT(OUT_HEIGHT),
        .NUM_CHANNELS(NUM_CHANNELS),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .data_in(data_in),
        .x_in(x_in),
        .y_row_lsb(y_in[0]),
        .valid_out(valid_out),
        .data_out(data_out),
        .x_out(x_out),
        .y_out(y_out)
    );
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    integer i, j, k, ch;
    integer errors = 0;
    reg [DATA_WIDTH-1:0] max_val;
    reg [DATA_WIDTH-1:0] val;
    
    // Test
    initial begin
        rst = 1;
        valid_in = 0;
        x_in = 0;
        y_in = 0;
        
        for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
            data_in_channel[ch] = 0;
        end
        
        // Initialize test patterns
        for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
            for (i = 0; i < IN_HEIGHT; i = i + 1) begin
                for (j = 0; j < IN_WIDTH; j = j + 1) begin
                    test_feature_maps[ch][i][j] = $signed({1'b0, ch[3:0], i[1:0], j[1:0]});
                    
                    if (ch >= 8) begin
                        if ((i + j) % 3 == 0) begin
                            test_feature_maps[ch][i][j] = $signed({1'b1, ch[3:0], i[1:0], j[1:0]});
                        end
                    end
                end
            end
        end
        
        // Compute expected outputs (max of each 2x2 block)
        for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
            for (i = 0; i < OUT_HEIGHT; i = i + 1) begin
                for (j = 0; j < OUT_WIDTH; j = j + 1) begin
                    // top left
                    max_val = test_feature_maps[ch][i*2][j*2];
                    
                    // top right
                    val = test_feature_maps[ch][i*2][j*2+1];
                    if ($signed(val) > $signed(max_val)) max_val = val;
                    
                    // bottom left
                    val = test_feature_maps[ch][i*2+1][j*2];
                    if ($signed(val) > $signed(max_val)) max_val = val;
                    
                    // bottom right
                    val = test_feature_maps[ch][i*2+1][j*2+1];
                    if ($signed(val) > $signed(max_val)) max_val = val;
                    
                    expected_outputs[ch][i][j] = max_val;
                end
            end
        end
        
        $display("=== Pool Layer 2 Testbench ===");
        $display("Testing %0d channels of size %0dx%0d", NUM_CHANNELS, IN_WIDTH, IN_HEIGHT);
        $display("Output feature maps will be %0dx%0d", OUT_WIDTH, OUT_HEIGHT);
        
        $display("\n=== Sample Test Pattern for Channel 0 ===");
        for (i = 0; i < IN_HEIGHT; i = i + 1) begin
            for (j = 0; j < IN_WIDTH; j = j + 1) begin
                $write("%3d ", $signed(test_feature_maps[0][i][j]));
            end
            $write("\n");
        end
        
        #100;
        rst = 0;
        #20;
        
        $display("\nStarting test...");
        for (i = 0; i < IN_HEIGHT; i = i + 1) begin
            for (j = 0; j < IN_WIDTH; j = j + 1) begin
                x_in = j;
                y_in = i;

                for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
                    data_in_channel[ch] = test_feature_maps[ch][i][j];
                end
                
                valid_in = 1;
                
                @(posedge clk);
                #1;
            end
        end
        
        valid_in = 0;
        
        repeat (IN_HEIGHT + 20) @(posedge clk);
        
        $display("\nTest completed with %0d errors", errors);

        $finish;
    end
    
    reg [DATA_WIDTH-1:0] outputs_received [0:NUM_CHANNELS-1][0:OUT_HEIGHT-1][0:OUT_WIDTH-1];
    reg output_valid [0:NUM_CHANNELS-1][0:OUT_HEIGHT-1][0:OUT_WIDTH-1];
    
    initial begin
        for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
            for (i = 0; i < OUT_HEIGHT; i = i + 1) begin
                for (j = 0; j < OUT_WIDTH; j = j + 1) begin
                    output_valid[ch][i][j] = 0;
                    outputs_received[ch][i][j] = 0;
                end
            end
        end
        
        while (1) begin
            @(posedge clk);
            if (valid_out) begin
                for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
                    outputs_received[ch][y_out][x_out] = data_out_channel[ch];
                    output_valid[ch][y_out][x_out] = 1;
                end
                
                $display("Output at (%0d,%0d): ", x_out, y_out);
                
                for (ch = 0; ch < 3; ch = ch + 1) begin
                    $write("Ch%0d=%0d, ", ch, $signed(data_out_channel[ch]));
                end
                
                $write("..., ");
                
                for (ch = NUM_CHANNELS-3; ch < NUM_CHANNELS; ch = ch + 1) begin
                    $write("Ch%0d=%0d, ", ch, $signed(data_out_channel[ch]));
                end
                
                $write("\n");
                
                // Compare with expected output
                for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
                    if (data_out_channel[ch] !== expected_outputs[ch][y_out][x_out]) begin
                        errors = errors + 1;
                        $display("ERROR at (%0d,%0d) Ch%0d: Expected %0d, Got %0d", 
                                x_out, y_out, ch, 
                                $signed(expected_outputs[ch][y_out][x_out]), 
                                $signed(data_out_channel[ch]));
                    end
                end
                
                // Debug: print the 2x2 input block that produced the output
                if (x_out < 2 && y_out < 2) begin 
                    $display("Input 2x2 block for Ch0 at position (%0d,%0d):", x_out*2, y_out*2);
                    $display("%3d %3d", 
                            $signed(test_feature_maps[0][y_out*2][x_out*2]), 
                            $signed(test_feature_maps[0][y_out*2][x_out*2+1]));
                    $display("%3d %3d", 
                            $signed(test_feature_maps[0][y_out*2+1][x_out*2]), 
                            $signed(test_feature_maps[0][y_out*2+1][x_out*2+1]));
                    $display("Expected max: %0d, Got: %0d", 
                            $signed(expected_outputs[0][y_out][x_out]), 
                            $signed(data_out_channel[0]));
                    $display("");
                end
            end
            
        end
    end

endmodule 
