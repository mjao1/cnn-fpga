`timescale 1ns / 1ps

// Testbench for cnn_top with optional layer-by-layer golden vector verification
// Uses Q1.7 quantized input to match hardware format

module tb_cnn_top;

    parameter CLK_PERIOD = 10;
    parameter DATA_WIDTH = 8;
    parameter IMG_WIDTH = 28;
    parameter IMG_HEIGHT = 28;
    parameter NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT;
    parameter ENABLE_GOLDEN_COMPARE = 1;

    // Golden vector sizes
    parameter CONV1_SIZE = 6 * 24 * 24; // 3456
    parameter POOL1_SIZE = 6 * 12 * 12; // 864
    parameter CONV2_SIZE = 16 * 8 * 8;  // 1024
    parameter POOL2_SIZE = 16 * 4 * 4;  // 256
    parameter FLATTEN_SIZE = 256;
    parameter FC1_SIZE = 120;
    parameter FC2_SIZE = 84;
    parameter FC3_SIZE = 10;
    
    reg clk;
    reg rst;
    
    reg start;
    reg [DATA_WIDTH-1:0] pixel_data;
    reg pixel_valid;
    reg [4:0] pixel_row;
    reg [4:0] pixel_col;
    
    wire done;
    wire [3:0] pred_digit;
    wire [DATA_WIDTH-1:0] pred_confidence;
    
    // Test image (Q1.7 format)
    reg [DATA_WIDTH-1:0] test_image [0:NUM_PIXELS-1];
    reg [3:0] expected_digit;
    
    // Golden vectors
    reg [DATA_WIDTH-1:0] conv1_expected [0:CONV1_SIZE-1];
    reg [DATA_WIDTH-1:0] pool1_expected [0:POOL1_SIZE-1];
    reg [DATA_WIDTH-1:0] conv2_expected [0:CONV2_SIZE-1];
    reg [DATA_WIDTH-1:0] pool2_expected [0:POOL2_SIZE-1];
    reg [DATA_WIDTH-1:0] flatten_expected [0:FLATTEN_SIZE-1];
    reg [DATA_WIDTH-1:0] fc1_expected [0:FC1_SIZE-1];
    reg [DATA_WIDTH-1:0] fc2_expected [0:FC2_SIZE-1];
    reg [DATA_WIDTH-1:0] fc3_expected [0:FC3_SIZE-1];
    
    // Mismatch counters
    integer conv1_match, conv1_mismatch;
    integer pool1_match, pool1_mismatch;
    integer conv2_match, conv2_mismatch;
    integer pool2_match, pool2_mismatch;
    integer flatten_match, flatten_mismatch;
    integer fc1_match, fc1_mismatch;
    integer fc2_match, fc2_mismatch;
    integer fc3_match, fc3_mismatch;
    
    integer i, ch;
    
    reg [127:0] state_name;
    always_comb begin
        case (dut.state)
            5'd0: state_name = "IDLE";
            5'd1: state_name = "LOAD_IMAGE";
            5'd2: state_name = "CONV1";
            5'd4: state_name = "CONV2";
            5'd5: state_name = "FLATTEN";
            5'd6: state_name = "FC_LAYERS";
            5'd7: state_name = "FIND_MAX";
            5'd8: state_name = "DONE";
            default: state_name = "UNKNOWN";
        endcase
    end
    
    cnn_top #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .pixel_data(pixel_data),
        .pixel_valid(pixel_valid),
        .pixel_row_in(pixel_row),
        .pixel_col_in(pixel_col),
        .done(done),
        .pred_digit(pred_digit),
        .pred_confidence(pred_confidence)
    );
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Main test
    initial begin
        rst = 1;
        start = 0;
        pixel_data = 0;
        pixel_valid = 0;
        pixel_row = 0;
        pixel_col = 0;
        
        conv1_match = 0; conv1_mismatch = 0;
        pool1_match = 0; pool1_mismatch = 0;
        conv2_match = 0; conv2_mismatch = 0;
        pool2_match = 0; pool2_mismatch = 0;
        flatten_match = 0; flatten_mismatch = 0;fc1_match = 0; fc1_mismatch = 0;
        fc2_match = 0; fc2_mismatch = 0;
        fc3_match = 0; fc3_mismatch = 0;
        
        expected_digit = 4; // Change based on test image

        // Load Q1.7 quantized input image (Change to test a different input digit)
        $readmemh("sim/cnn/test_images/test_image_4.mem", test_image);
        
        // Load golden vectors for each layer
        if (ENABLE_GOLDEN_COMPARE) begin
            $readmemh("sim/cnn/golden_vectors/conv1_expected.mem", conv1_expected);
            $readmemh("sim/cnn/golden_vectors/pool1_expected.mem", pool1_expected);
            $readmemh("sim/cnn/golden_vectors/conv2_expected.mem", conv2_expected);
            $readmemh("sim/cnn/golden_vectors/pool2_expected.mem", pool2_expected);
            $readmemh("sim/cnn/golden_vectors/flatten_expected.mem", flatten_expected);
            $readmemh("sim/cnn/golden_vectors/fc1_expected.mem", fc1_expected);
            $readmemh("sim/cnn/golden_vectors/fc2_expected.mem", fc2_expected);
            $readmemh("sim/cnn/golden_vectors/fc3_expected.mem", fc3_expected);
            $display("Golden vector comparison: ENABLED");
        end else begin
            $display("Golden vector comparison: DISABLED");
        end
        
        $display("=== CNN Top Testbench ===");
        $display("Expected digit: %d", expected_digit);
        
        #(CLK_PERIOD*10);
        rst = 0;
        #(CLK_PERIOD*2);
        
        $display("Starting CNN inference...");
        start = 1;
        #(CLK_PERIOD);
        start = 0;
        
        // Feed pixel data
        for (i = 0; i < NUM_PIXELS; i = i + 1) begin
            pixel_valid = 1;
            pixel_row = i / 10'd28;
            pixel_col = i % 10'd28;
            pixel_data = test_image[i];
            @(posedge clk);
            #1;
            
            if (i % (NUM_PIXELS/10) == 0 && i > 0) begin
                $display("Image loading: %0d%%", (i * 100) / NUM_PIXELS);
            end
        end
        
        pixel_valid = 0;
        $display("Image loaded, processing through CNN...");

        fork
            begin : timeout
                #(CLK_PERIOD*1000000);
                $display("ERROR: Timeout (state=%s)", state_name);
                print_summary();
                $finish;
            end
            
            begin : wait_for_done
                wait(done);
                disable timeout;
            end
        join
        
        // Print final results
        $display("\n=== CNN Inference Complete ===");
        $display("Expected digit: %d", expected_digit);
        $display("Predicted digit: %d", pred_digit);
        $display("Confidence: %d (signed: %d)", pred_confidence, $signed(pred_confidence));
        
        if (pred_digit == expected_digit)
            $display("RESULT: CORRECT PREDICTION");
        else
            $display("RESULT: INCORRECT PREDICTION");
        
        $display("\nFinal scores:");
        for (i = 0; i < 10; i = i + 1) begin
            $display("  Digit %0d: %d", i, $signed(dut.class_scores[i]));
        end
        
        print_summary();
        
        #(CLK_PERIOD*100);
        $finish;
    end
    
    // Print layer verification summary
    task print_summary;
        begin
            if (ENABLE_GOLDEN_COMPARE) begin
                $display("\n=== Layer Verification Summary ===");
                $display("CONV1: %0d matches, %0d mismatches (%s)", 
                    conv1_match, conv1_mismatch, conv1_mismatch == 0 ? "PASS" : "FAIL");
                $display("POOL1: %0d matches, %0d mismatches (%s)", 
                    pool1_match, pool1_mismatch, pool1_mismatch == 0 ? "PASS" : "FAIL");
                $display("CONV2: %0d matches, %0d mismatches (%s)", 
                    conv2_match, conv2_mismatch, conv2_mismatch == 0 ? "PASS" : "FAIL");
                $display("POOL2: %0d matches, %0d mismatches (%s)", 
                    pool2_match, pool2_mismatch, pool2_mismatch == 0 ? "PASS" : "FAIL");
                $display("FLATTEN: %0d matches, %0d mismatches (%s)", 
                    flatten_match, flatten_mismatch, flatten_mismatch == 0 ? "PASS" : "FAIL");
                $display("FC1: %0d matches, %0d mismatches (%s)", 
                    fc1_match, fc1_mismatch, fc1_mismatch == 0 ? "PASS" : "FAIL");
                $display("FC2: %0d matches, %0d mismatches (%s)", 
                    fc2_match, fc2_mismatch, fc2_mismatch == 0 ? "PASS" : "FAIL");
                $display("FC3: %0d matches, %0d mismatches (%s)", 
                    fc3_match, fc3_mismatch, fc3_mismatch == 0 ? "PASS" : "FAIL");
            end
        end
    endtask
    
    // State change monitor
    reg [4:0] prev_state;
    always @(posedge clk) begin
        if (rst) begin
            prev_state <= 5'd0;
        end else begin
            if (dut.state != prev_state) begin
                $display("Time %0t: State -> %s", $time, state_name);
                prev_state <= dut.state;
            end
        end
    end
    
    // CONV1 output verification
    // Golden vector format: channel major (all ch0, then ch1, etc.)
    integer conv1_idx;
    reg [DATA_WIDTH-1:0] conv1_exp, conv1_act;
    wire [DATA_WIDTH-1:0] conv1_outputs [0:5];
    assign conv1_outputs[0] = dut.conv1_data_out_0;
    assign conv1_outputs[1] = dut.conv1_data_out_1;
    assign conv1_outputs[2] = dut.conv1_data_out_2;
    assign conv1_outputs[3] = dut.conv1_data_out_3;
    assign conv1_outputs[4] = dut.conv1_data_out_4;
    assign conv1_outputs[5] = dut.conv1_data_out_5;
    
    always @(posedge clk) begin
        if (!rst && dut.conv1_valid_out && ENABLE_GOLDEN_COMPARE) begin
            for (ch = 0; ch < 6; ch = ch + 1) begin
                // Index: channel * (24*24) + y * 24 + x
                conv1_idx = ch * 24 * 24 + dut.conv1_y_out * 24 + dut.conv1_x_out;
                conv1_exp = conv1_expected[conv1_idx];
                conv1_act = conv1_outputs[ch];
                
                if (conv1_act == conv1_exp) begin
                    conv1_match = conv1_match + 1;
                end else begin
                    conv1_mismatch = conv1_mismatch + 1;
                    if (conv1_mismatch <= 10) begin
                        $display("CONV1 MISMATCH @(x=%0d,y=%0d,ch=%0d): exp=%0d, got=%0d",
                            dut.conv1_x_out, dut.conv1_y_out, ch, $signed(conv1_exp), $signed(conv1_act));
                    end
                end
            end
        end
    end
            
    // POOL1 output verification
    integer pool1_idx;
    reg [DATA_WIDTH-1:0] pool1_exp, pool1_act;
    
    always @(posedge clk) begin
        if (!rst && dut.pool1_valid_out && ENABLE_GOLDEN_COMPARE) begin
            for (ch = 0; ch < 6; ch = ch + 1) begin
                // Index: channel * (12*12) + y * 12 + x
                pool1_idx = ch * 12 * 12 + dut.pool1_y_out * 12 + dut.pool1_x_out;
                pool1_exp = pool1_expected[pool1_idx];
                pool1_act = dut.pool1_data_out[(ch+1)*DATA_WIDTH-1 -: DATA_WIDTH];
                
                if (pool1_act == pool1_exp) begin
                    pool1_match = pool1_match + 1;
                end else begin
                    pool1_mismatch = pool1_mismatch + 1;
                    if (pool1_mismatch <= 10) begin
                        $display("POOL1 MISMATCH @(x=%0d,y=%0d,ch=%0d): exp=%0d, got=%0d",
                            dut.pool1_x_out, dut.pool1_y_out, ch, $signed(pool1_exp), $signed(pool1_act));
                    end
                end
            end
        end
    end
    
    // CONV2 output verification
    integer conv2_idx;
    reg [DATA_WIDTH-1:0] conv2_exp, conv2_act;
    
    always @(posedge clk) begin
        if (!rst && dut.conv2_valid_out && ENABLE_GOLDEN_COMPARE) begin
                for (ch = 0; ch < 16; ch = ch + 1) begin
                // Index: channel * (8*8) + y * 8 + x
                conv2_idx = ch * 8 * 8 + dut.conv2_y_out * 8 + dut.conv2_x_out;
                conv2_exp = conv2_expected[conv2_idx];
                conv2_act = dut.conv2_data_out[(ch+1)*DATA_WIDTH-1 -: DATA_WIDTH];
                
                if (conv2_act == conv2_exp) begin
                    conv2_match = conv2_match + 1;
                end else begin
                    conv2_mismatch = conv2_mismatch + 1;
                    if (conv2_mismatch <= 10) begin
                        $display("CONV2 MISMATCH @(x=%0d,y=%0d,ch=%0d): exp=%0d, got=%0d",
                            dut.conv2_x_out, dut.conv2_y_out, ch, $signed(conv2_exp), $signed(conv2_act));
                    end
                end
            end
        end
    end
            
    // POOL2 output verification
    integer pool2_idx;
    reg [DATA_WIDTH-1:0] pool2_exp, pool2_act;
    
    always @(posedge clk) begin
        if (!rst && dut.pool2_valid_out && ENABLE_GOLDEN_COMPARE) begin
                for (ch = 0; ch < 16; ch = ch + 1) begin
                // Index: channel * (4*4) + y * 4 + x
                pool2_idx = ch * 4 * 4 + dut.pool2_y_out * 4 + dut.pool2_x_out;
                pool2_exp = pool2_expected[pool2_idx];
                pool2_act = dut.pool2_data_out[(ch+1)*DATA_WIDTH-1 -: DATA_WIDTH];
                
                if (pool2_act == pool2_exp) begin
                    pool2_match = pool2_match + 1;
                end else begin
                    pool2_mismatch = pool2_mismatch + 1;
                    if (pool2_mismatch <= 10) begin
                        $display("POOL2 MISMATCH @(x=%0d,y=%0d,ch=%0d): exp=%0d, got=%0d",
                            dut.pool2_x_out, dut.pool2_y_out, ch, $signed(pool2_exp), $signed(pool2_act));
                    end
                end
            end
        end
    end
    
    // FLATTEN output verification
    reg [DATA_WIDTH-1:0] flatten_exp, flatten_act;
    reg [8:0] flatten_output_count;
    reg flatten_first_pass_done;
    
    always @(posedge clk) begin
        if (rst) begin
            flatten_output_count <= 0;
            flatten_first_pass_done <= 0;
        end else if (!flatten_first_pass_done && dut.flatten_valid_out) begin
            if (ENABLE_GOLDEN_COMPARE) begin
                flatten_exp = flatten_expected[dut.flatten_addr_out];
                flatten_act = dut.flatten_data_out;
                
                if (flatten_act == flatten_exp) begin
                    flatten_match = flatten_match + 1;
                end else begin
                    flatten_mismatch = flatten_mismatch + 1;
                    if (flatten_mismatch <= 10) begin
                        $display("FLATTEN MISMATCH @idx=%0d: exp=%0d, got=%0d",
                            dut.flatten_addr_out, $signed(flatten_exp), $signed(flatten_act));
                    end
                end
            end
            
            flatten_output_count <= flatten_output_count + 1;
            if (flatten_output_count == FLATTEN_SIZE - 1) begin
                flatten_first_pass_done <= 1;
            end
        end
    end
    
    // FC1 output verification
    reg [DATA_WIDTH-1:0] fc1_exp, fc1_act;
    
    always @(posedge clk) begin
        if (!rst && dut.fc_layers_inst.fc1_valid_out && ENABLE_GOLDEN_COMPARE) begin
            fc1_exp = fc1_expected[dut.fc_layers_inst.fc1_neuron_idx];
            fc1_act = dut.fc_layers_inst.fc1_data_out;
            
            if (fc1_act == fc1_exp) begin
                fc1_match = fc1_match + 1;
            end else begin
                fc1_mismatch = fc1_mismatch + 1;
                if (fc1_mismatch <= 10) begin
                    $display("FC1 MISMATCH @neuron=%0d: exp=%0d, got=%0d",
                        dut.fc_layers_inst.fc1_neuron_idx, $signed(fc1_exp), $signed(fc1_act));
                end
            end
        end
    end
    
    // FC2 output verification
    reg [DATA_WIDTH-1:0] fc2_exp, fc2_act;
    
    always @(posedge clk) begin
        if (!rst && dut.fc_layers_inst.fc2_valid_out && ENABLE_GOLDEN_COMPARE) begin
            fc2_exp = fc2_expected[dut.fc_layers_inst.fc2_neuron_idx];
            fc2_act = dut.fc_layers_inst.fc2_data_out;
            
            if (fc2_act == fc2_exp) begin
                fc2_match = fc2_match + 1;
            end else begin
                fc2_mismatch = fc2_mismatch + 1;
                if (fc2_mismatch <= 10) begin
                    $display("FC2 MISMATCH @neuron=%0d: exp=%0d, got=%0d",
                        dut.fc_layers_inst.fc2_neuron_idx, $signed(fc2_exp), $signed(fc2_act));
                end
            end
        end
    end
            
    // FC3 output verification
    reg [DATA_WIDTH-1:0] fc3_exp, fc3_act;
    
    always @(posedge clk) begin
        if (!rst && dut.fc_layers_inst.fc3_valid_out && ENABLE_GOLDEN_COMPARE) begin
            fc3_exp = fc3_expected[dut.fc_layers_inst.fc3_neuron_idx];
            fc3_act = dut.fc_layers_inst.fc3_data_out;
            
            if (fc3_act == fc3_exp) begin
                fc3_match = fc3_match + 1;
            end else begin
                fc3_mismatch = fc3_mismatch + 1;
                $display("FC3 MISMATCH @digit=%0d: exp=%0d, got=%0d",
                    dut.fc_layers_inst.fc3_neuron_idx, $signed(fc3_exp), $signed(fc3_act));
            end
        end
    end
    
endmodule 
