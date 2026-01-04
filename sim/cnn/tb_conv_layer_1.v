`timescale 1ns / 1ps

module tb_conv_layer_1;
    parameter IMG_WIDTH = 28;
    parameter IMG_HEIGHT = 28;
    parameter OUT_WIDTH = 24;
    parameter OUT_HEIGHT = 24;
    parameter NUM_FILTERS = 6;
    parameter KERNEL_SIZE = 5;
    parameter DATA_WIDTH = 8;
    parameter FRAC_BITS = 7;
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
    reg [DATA_WIDTH-1:0] image_flat [0:IMG_HEIGHT*IMG_WIDTH-1];
    reg [DATA_WIDTH-1:0] expected_flat [0:NUM_FILTERS*OUT_HEIGHT*OUT_WIDTH-1];
    
    integer i, j, k;
    integer output_count;
    integer match_count;
    integer mismatch_count;
    reg [DATA_WIDTH-1:0] exp_val;
    reg [DATA_WIDTH-1:0] got_val;
    
    wire [2:0] state_debug;  // 3 bits for new state encoding
    
    conv_layer_1 #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .OUT_WIDTH(OUT_WIDTH),
        .OUT_HEIGHT(OUT_HEIGHT),
        .NUM_FILTERS(NUM_FILTERS),
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
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Main test
    initial begin
        rst = 1;
        valid_in = 0;
        data_in = 0;
        x_in = 0;
        y_in = 0;
        output_count = 0;
        match_count = 0;
        mismatch_count = 0;
        
        // Load input image and expected outputs
        $readmemh("sim/cnn/input_image.mem", image_flat);
        $readmemh("sim/cnn/conv1_expected.mem", expected_flat);
        
        // Reshape to 2D arrays
        for (i = 0; i < IMG_HEIGHT; i = i + 1) begin
            for (j = 0; j < IMG_WIDTH; j = j + 1) begin
                test_image[i][j] = image_flat[i * IMG_WIDTH + j];
            end
        end
        
        for (k = 0; k < NUM_FILTERS; k = k + 1) begin
            for (i = 0; i < OUT_HEIGHT; i = i + 1) begin
                for (j = 0; j < OUT_WIDTH; j = j + 1) begin
                    expected_output[k][i][j] = expected_flat[k * OUT_HEIGHT * OUT_WIDTH + i * OUT_WIDTH + j];
                end
        end
    end
    
        $display("=== Convolutional Layer 1 Testbench ===");
        $display("Input: %0dx%0d image, Output: %0dx%0dx%0d", IMG_WIDTH, IMG_HEIGHT, OUT_WIDTH, OUT_HEIGHT, NUM_FILTERS);
        
        repeat (5) @(posedge clk);
        rst = 0;
        
        // Wait for weight loading to complete (RUNNING = 3'b101)
        wait(state_debug == 3'b101);
        $display("Weight loading complete, starting inference...");
        
        // Feed image data
        for (i = 0; i < IMG_HEIGHT; i = i + 1) begin
            for (j = 0; j < IMG_WIDTH; j = j + 1) begin
                valid_in = 1;
                data_in = test_image[i][j];
                x_in = j;
                y_in = i;
                @(posedge clk);
                #1;
            end
        end
        
        valid_in = 0;
        
        // Wait for pipeline to flush
        repeat (100) @(posedge clk);
        
        $display("\n=== Test Summary ===");
        $display("Total outputs: %0d", output_count);
        $display("Matches: %0d, Mismatches: %0d", match_count, mismatch_count);
        $finish;
    end
    
    // Output checker
    always @(posedge clk) begin
            if (valid_out) begin
                output_count = output_count + 1;
                
                // Trace first outputs of row 1
                if (y_out == 1 && x_out >= 4 && x_out <= 9) begin
                    $display("OUTPUT #%0d at (%0d,%0d): ch4=%0d (expected=%0d)",
                        output_count, x_out, y_out, $signed(data_out_4),
                        $signed(expected_output[4][y_out][x_out]));
                end
                
            // Compare each filter output against expected
            for (k = 0; k < NUM_FILTERS; k = k + 1) begin
                exp_val = expected_output[k][y_out][x_out];
                got_val = data_out_array[k];
                
                if (got_val == exp_val) begin
                    match_count = match_count + 1;
                end else begin
                    mismatch_count = mismatch_count + 1;
                    $display("MISMATCH @(%0d,%0d) ch%0d: expected=%0d, actual=%0d",
                        x_out, y_out, k, $signed(exp_val), $signed(got_val));
                end
            end
        end
    end

endmodule 
