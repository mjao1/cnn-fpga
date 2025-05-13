`timescale 1ns / 1ps

// Note: This testbench uses hardcoded indices instead of loops with variable indices 
// in the monitoring logic to avoid "constant expression required" errors in simulation.
// Verilog synthesis tools require constant expressions for bit-slicing operations.

module tb_cnn_top;

    parameter CLK_PERIOD = 10;
    parameter DATA_WIDTH = 8;
    parameter IMG_WIDTH = 28;
    parameter IMG_HEIGHT = 28;
    parameter NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT;
    parameter TEST_IMAGE_FILE = "test_image.txt";
    
    reg clk;
    reg rst;
    
    reg start;
    reg [DATA_WIDTH-1:0] pixel_data;
    reg pixel_valid;
    reg [9:0] pixel_addr;
    
    wire done;
    wire [3:0] pred_digit;
    wire [DATA_WIDTH-1:0] pred_confidence;
    
    reg [DATA_WIDTH-1:0] test_image [0:NUM_PIXELS-1];
    reg [3:0] expected_digit;
    integer file_handle;
    integer scan_result;
    integer i;
    
    // Output files for debug
    integer log_file; // Single log file for all outputs
    
    reg [127:0] state_name;
    always @(*) begin
        case (dut.state)
            5'd0: state_name = "IDLE";
            5'd1: state_name = "LOAD_IMAGE";
            5'd2: state_name = "CONV1";
            5'd3: state_name = "POOL1";
            5'd4: state_name = "CONV2";
            5'd5: state_name = "POOL2";
            5'd6: state_name = "FLATTEN";
            5'd7: state_name = "FC_LAYERS";
            5'd8: state_name = "FIND_MAX";
            5'd9: state_name = "DONE";
            default: state_name = "UNKNOWN";
        endcase
    end
    
    // Track FC layers state for debugging
    reg [127:0] fc_state_name;
    always @(*) begin
        case (dut.fc_layers_inst.state)
            3'b000: fc_state_name = "IDLE";
            3'b001: fc_state_name = "FC1_PROC";
            3'b010: fc_state_name = "FC2_PROC";
            3'b011: fc_state_name = "FC3_PROC";
            3'b100: fc_state_name = "DONE";
            default: fc_state_name = "UNKNOWN";
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
        .pixel_addr(pixel_addr),
        .done(done),
        .pred_digit(pred_digit),
        .pred_confidence(pred_confidence)
    );
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Test sequence
    initial begin
        rst = 1;
        start = 0;
        pixel_data = 0;
        pixel_valid = 0;
        pixel_addr = 0;
        
        // Create a single log file for all outputs
        log_file = $fopen("cnn_results.log", "w");
        if (log_file == 0) begin
            $display("Error: Failed to open log file");
            $finish;
        end
        
        // Write header to log file
        $fwrite(log_file, "CNN inference debug log\n");
        $fwrite(log_file, "----------------------\n\n");
        
        // Load test image from file
        file_handle = $fopen(TEST_IMAGE_FILE, "r");
        if (file_handle == 0) begin
            $display("Error: Failed to open file %s", TEST_IMAGE_FILE);
            $finish;
        end
        
        // First line is the expected digit
        scan_result = $fscanf(file_handle, "%d", expected_digit);
        $display("Expected digit: %d", expected_digit);
        
        // Read remaining pixel values
        for (i = 0; i < NUM_PIXELS; i = i + 1) begin
            scan_result = $fscanf(file_handle, "%d", test_image[i]);
        end
        
        $fclose(file_handle);
        $display("Test image loaded from file");
        
        #(CLK_PERIOD*10);
        rst = 0;
        #(CLK_PERIOD*2);
        
        $display("Starting CNN inference");
        start = 1;
        #(CLK_PERIOD);
        start = 0;
        
        // Feed pixel data
        for (i = 0; i < NUM_PIXELS; i = i + 1) begin
            pixel_valid = 1;
            pixel_addr = i;
            pixel_data = test_image[i]; // Use full 8-bit pixel value (0-255)
            #(CLK_PERIOD);
            
            if (i % (NUM_PIXELS/10) == 0 && i > 0) begin
                $display("Image loading: %0d%%", (i * 100) / NUM_PIXELS);
            end
        end
        
        pixel_valid = 0;
        
        // Wait for CNN to finish processing
        $display("Image loaded, waiting for CNN to process...");

        fork
            begin : timeout
                #(CLK_PERIOD*1000000);
                $display("Timeout reached, simulation stopped");
                
                // Close log file
                $fclose(log_file);
                
                $finish;
            end
            
            begin : wait_for_done
                wait(done);
                disable timeout;
            end
        join
        
        $display("\n-------------------------------------------");
        $display("CNN Inference Complete");
        $display("Expected digit: %d", expected_digit);
        $display("Predicted digit: %d", pred_digit);
        $display("Confidence score: %d (signed value)", $signed(pred_confidence));
        
        if (pred_digit == expected_digit)
            $display("RESULT: CORRECT PREDICTION! ✓");
        else
            $display("RESULT: INCORRECT PREDICTION! ✗");
        $display("-------------------------------------------\n");
        
        $display("Final scores for all digits:");
        for (i = 0; i < 10; i = i + 1) begin
            $display("Digit %0d: %d (signed value)", i, $signed(dut.class_scores[i]));
        end
        
        // Close log file
        $fclose(log_file);
        
        #(CLK_PERIOD*100);
        $finish;
    end
    
    // Additional file handlers for individual output layers
    // These will be opened only when needed
    integer conv1_file = 0;
    integer pool1_file = 0;
    integer conv2_file = 0;
    integer pool2_file = 0;
    integer flatten_file = 0;
    integer fc1_file = 0;
    integer fc2_file = 0;
    integer fc3_file = 0;
    
    reg conv1_file_opened = 0;
    reg pool1_file_opened = 0;
    reg conv2_file_opened = 0;
    reg pool2_file_opened = 0;
    reg flatten_file_opened = 0;
    reg fc1_file_opened = 0;
    reg fc2_file_opened = 0;
    reg fc3_file_opened = 0;
    
    reg [4:0] prev_state;
    reg [2:0] prev_fc_state;
    
    // Monitor signals and log to files
    always @(posedge clk) begin
        if (rst) begin
            prev_state <= 5'd0;
            prev_fc_state <= 3'b000;
        end else begin
            if (dut.state != prev_state) begin
                case (dut.state)
                    5'd0: $display("Time: %0t, State: %s", $time, "IDLE");
                    5'd1: $display("Time: %0t, State: %s", $time, "LOAD_IMAGE");
                    5'd2: $display("Time: %0t, State: %s - Starting image processing through CNN", $time, "CONV1");
                    5'd3: $display("Time: %0t, State: %s - CONV1 complete, starting pooling", $time, "POOL1");
                    5'd4: $display("Time: %0t, State: %s - POOL1 complete, starting second convolution", $time, "CONV2");
                    5'd5: $display("Time: %0t, State: %s - CONV2 complete, starting second pooling", $time, "POOL2");
                    5'd6: $display("Time: %0t, State: %s - POOL2 complete, flattening feature maps", $time, "FLATTEN");
                    5'd7: $display("Time: %0t, State: %s - Flatten complete, processing fully connected layers", $time, "FC_LAYERS");
                    5'd8: $display("Time: %0t, State: %s - FC layers complete, finding maximum class score", $time, "FIND_MAX");
                    5'd9: $display("Time: %0t, State: %s - Classification complete", $time, "DONE");
                    default: $display("Time: %0t, State: UNKNOWN", $time);
                endcase
            end
            
            // Debug fc_layers state transitions specifically
            if (dut.fc_layers_inst.state != prev_fc_state) begin
                $display("Time: %0t, FC STATE CHANGED TO: %s", $time, fc_state_name);
                $fwrite(log_file, "FC STATE CHANGE [t=%0t]: %s\n", $time, fc_state_name);
                prev_fc_state <= dut.fc_layers_inst.state;
            end
            
            if (dut.state == 5'd1 && pixel_valid) begin
                if (pixel_addr % (NUM_PIXELS/10) == 0) begin
                    $display("  Image loading: %0d%%", (pixel_addr * 100) / NUM_PIXELS);
                end
            end
            
            // Log all layer outputs to single file instead of multiple files
            
            // Monitor CONV1 outputs
            if (dut.conv1_valid_out) begin
                // Log to main log file instead of opening separate files
                $fwrite(log_file, "CONV1 [t=%0t]: ch=0, y=%0d, x=%0d, val=%0d\n", $time, dut.conv1_y_out, dut.conv1_x_out, $signed(dut.conv1_data_out_0));
                $fwrite(log_file, "CONV1 [t=%0t]: ch=1, y=%0d, x=%0d, val=%0d\n", $time, dut.conv1_y_out, dut.conv1_x_out, $signed(dut.conv1_data_out_1));
                $fwrite(log_file, "CONV1 [t=%0t]: ch=2, y=%0d, x=%0d, val=%0d\n", $time, dut.conv1_y_out, dut.conv1_x_out, $signed(dut.conv1_data_out_2));
                $fwrite(log_file, "CONV1 [t=%0t]: ch=3, y=%0d, x=%0d, val=%0d\n", $time, dut.conv1_y_out, dut.conv1_x_out, $signed(dut.conv1_data_out_3));
                $fwrite(log_file, "CONV1 [t=%0t]: ch=4, y=%0d, x=%0d, val=%0d\n", $time, dut.conv1_y_out, dut.conv1_x_out, $signed(dut.conv1_data_out_4));
                $fwrite(log_file, "CONV1 [t=%0t]: ch=5, y=%0d, x=%0d, val=%0d\n", $time, dut.conv1_y_out, dut.conv1_x_out, $signed(dut.conv1_data_out_5));
                
                // Also log the values before ReLU activation (conv_out) for debugging
                $fwrite(log_file, "CONV1_PRE_RELU [t=%0t]: ch=0, y=%0d, x=%0d, val=%0d\n", $time, dut.conv1_y_out, dut.conv1_x_out, $signed(dut.conv1.conv_units[0].conv_inst.data_out));
                $fwrite(log_file, "CONV1_PRE_RELU [t=%0t]: ch=1, y=%0d, x=%0d, val=%0d\n", $time, dut.conv1_y_out, dut.conv1_x_out, $signed(dut.conv1.conv_units[1].conv_inst.data_out));
                $fwrite(log_file, "CONV1_PRE_RELU [t=%0t]: ch=2, y=%0d, x=%0d, val=%0d\n", $time, dut.conv1_y_out, dut.conv1_x_out, $signed(dut.conv1.conv_units[2].conv_inst.data_out));
                $fwrite(log_file, "CONV1_PRE_RELU [t=%0t]: ch=3, y=%0d, x=%0d, val=%0d\n", $time, dut.conv1_y_out, dut.conv1_x_out, $signed(dut.conv1.conv_units[3].conv_inst.data_out));
                $fwrite(log_file, "CONV1_PRE_RELU [t=%0t]: ch=4, y=%0d, x=%0d, val=%0d\n", $time, dut.conv1_y_out, dut.conv1_x_out, $signed(dut.conv1.conv_units[4].conv_inst.data_out));
                $fwrite(log_file, "CONV1_PRE_RELU [t=%0t]: ch=5, y=%0d, x=%0d, val=%0d\n", $time, dut.conv1_y_out, dut.conv1_x_out, $signed(dut.conv1.conv_units[5].conv_inst.data_out));
                
                // Debug accumulator values inside the conv module
                if (dut.conv1_x_out == 0 && dut.conv1_y_out == 0) begin
                    // For the first output pixel, log the accumulator values as well
                    $fwrite(log_file, "CONV1_ACC [t=%0t]: ch=0, acc=%0d\n", $time, $signed(dut.conv1.conv_units[0].conv_inst.acc_stage5));
                    $fwrite(log_file, "CONV1_ACC [t=%0t]: ch=1, acc=%0d\n", $time, $signed(dut.conv1.conv_units[1].conv_inst.acc_stage5));
                    $fwrite(log_file, "CONV1_ACC [t=%0t]: ch=2, acc=%0d\n", $time, $signed(dut.conv1.conv_units[2].conv_inst.acc_stage5));
                    $fwrite(log_file, "CONV1_ACC [t=%0t]: ch=3, acc=%0d\n", $time, $signed(dut.conv1.conv_units[3].conv_inst.acc_stage5));
                    $fwrite(log_file, "CONV1_ACC [t=%0t]: ch=4, acc=%0d\n", $time, $signed(dut.conv1.conv_units[4].conv_inst.acc_stage5));
                    $fwrite(log_file, "CONV1_ACC [t=%0t]: ch=5, acc=%0d\n", $time, $signed(dut.conv1.conv_units[5].conv_inst.acc_stage5));
                end
            end
            
            // Monitor POOL1 outputs
            if (dut.pool1_valid_out) begin
                $fwrite(log_file, "POOL1 [t=%0t]: ch=0, y=%0d, x=%0d, val=%0d\n", $time, dut.pool1_y_out, dut.pool1_x_out, 
                          $signed(dut.pool1_data_out[1*DATA_WIDTH-1:0*DATA_WIDTH]));
                $fwrite(log_file, "POOL1 [t=%0t]: ch=1, y=%0d, x=%0d, val=%0d\n", $time, dut.pool1_y_out, dut.pool1_x_out,
                          $signed(dut.pool1_data_out[2*DATA_WIDTH-1:1*DATA_WIDTH]));
                $fwrite(log_file, "POOL1 [t=%0t]: ch=2, y=%0d, x=%0d, val=%0d\n", $time, dut.pool1_y_out, dut.pool1_x_out,
                          $signed(dut.pool1_data_out[3*DATA_WIDTH-1:2*DATA_WIDTH]));
                $fwrite(log_file, "POOL1 [t=%0t]: ch=3, y=%0d, x=%0d, val=%0d\n", $time, dut.pool1_y_out, dut.pool1_x_out,
                          $signed(dut.pool1_data_out[4*DATA_WIDTH-1:3*DATA_WIDTH]));
                $fwrite(log_file, "POOL1 [t=%0t]: ch=4, y=%0d, x=%0d, val=%0d\n", $time, dut.pool1_y_out, dut.pool1_x_out,
                          $signed(dut.pool1_data_out[5*DATA_WIDTH-1:4*DATA_WIDTH]));
                $fwrite(log_file, "POOL1 [t=%0t]: ch=5, y=%0d, x=%0d, val=%0d\n", $time, dut.pool1_y_out, dut.pool1_x_out,
                          $signed(dut.pool1_data_out[6*DATA_WIDTH-1:5*DATA_WIDTH]));
            end
            
            // Log just the first few CONV2/POOL2 outputs since they're numerous
            
            // Monitor CONV2 outputs (only first few for brevity)
            if (dut.conv2_valid_out) begin
                $fwrite(log_file, "CONV2 [t=%0t]: ch=0, y=%0d, x=%0d, val=%0d\n", $time, dut.conv2_y_out, dut.conv2_x_out, 
                          $signed(dut.conv2_data_out[1*DATA_WIDTH-1:0*DATA_WIDTH]));
                if (dut.conv2_x_out == 0 && dut.conv2_y_out == 0) begin
                    // Only show all channels for the first pixel
                    $fwrite(log_file, "CONV2 [t=%0t]: ch=1, y=%0d, x=%0d, val=%0d\n", $time, dut.conv2_y_out, dut.conv2_x_out, 
                              $signed(dut.conv2_data_out[2*DATA_WIDTH-1:1*DATA_WIDTH]));
                    $fwrite(log_file, "CONV2 [t=%0t]: ch=2, y=%0d, x=%0d, val=%0d\n", $time, dut.conv2_y_out, dut.conv2_x_out, 
                              $signed(dut.conv2_data_out[3*DATA_WIDTH-1:2*DATA_WIDTH]));
                    // ... other channels omitted for brevity
                    $fwrite(log_file, "CONV2 [t=%0t]: ch=15, y=%0d, x=%0d, val=%0d\n", $time, dut.conv2_y_out, dut.conv2_x_out,
                              $signed(dut.conv2_data_out[16*DATA_WIDTH-1:15*DATA_WIDTH]));
                end
            end
            
            // Monitor POOL2 outputs (only first few for brevity)
            if (dut.pool2_valid_out) begin
                $fwrite(log_file, "POOL2 [t=%0t]: ch=0, y=%0d, x=%0d, val=%0d\n", $time, dut.pool2_y_out, dut.pool2_x_out, 
                          $signed(dut.pool2_data_out[1*DATA_WIDTH-1:0*DATA_WIDTH]));
                if (dut.pool2_x_out == 0 && dut.pool2_y_out == 0) begin
                    // Only show all channels for the first pixel
                    $fwrite(log_file, "POOL2 [t=%0t]: ch=1, y=%0d, x=%0d, val=%0d\n", $time, dut.pool2_y_out, dut.pool2_x_out, 
                              $signed(dut.pool2_data_out[2*DATA_WIDTH-1:1*DATA_WIDTH]));
                    $fwrite(log_file, "POOL2 [t=%0t]: ch=2, y=%0d, x=%0d, val=%0d\n", $time, dut.pool2_y_out, dut.pool2_x_out, 
                              $signed(dut.pool2_data_out[3*DATA_WIDTH-1:2*DATA_WIDTH]));
                    // ... other channels omitted for brevity
                    $fwrite(log_file, "POOL2 [t=%0t]: ch=15, y=%0d, x=%0d, val=%0d\n", $time, dut.pool2_y_out, dut.pool2_x_out,
                              $signed(dut.pool2_data_out[16*DATA_WIDTH-1:15*DATA_WIDTH]));
                end
            end
            
            // Monitor FLATTEN outputs
            if (dut.flatten_valid_out) begin
                if (dut.flatten_addr_out < 10 || dut.flatten_addr_out > 245) begin
                    // Only log first 10 and last 10 values to save space
                    $fwrite(log_file, "FLATTEN [t=%0t]: idx=%0d, val=%0d\n", 
                              $time, dut.flatten_addr_out, $signed(dut.flatten_data_out));
                end
            end
            
            // Debug FC signals directly
            if (dut.state == 5'd7) begin  // FC_LAYERS state
                // Log FC communication signals regardless of valid signal
                $fwrite(log_file, "FC_DEBUG [t=%0t]: fc_state=%s, fc_valid_out=%0d, fc_digit_idx=%0d, fc_data_out=%0d\n", 
                        $time, fc_state_name, dut.fc_valid_out, dut.fc_digit_idx, $signed(dut.fc_data_out));
                
                // Monitor internal fc1 signals
                $fwrite(log_file, "FC1_INTERNAL [t=%0t]: fc1_valid_out=%0d, fc1_neuron_idx=%0d, fc1_data_out=%0d, fc1_done_out=%0d\n", 
                        $time, dut.fc_layers_inst.fc1_valid_out, dut.fc_layers_inst.fc1_neuron_idx, 
                        $signed(dut.fc_layers_inst.fc1_data_out), dut.fc_layers_inst.fc1_done_out);
                
                // Monitor internal fc2 signals
                $fwrite(log_file, "FC2_INTERNAL [t=%0t]: fc2_valid_in=%0d, fc2_valid_out=%0d, fc2_neuron_idx=%0d, fc2_data_out=%0d, fc2_done_out=%0d\n", 
                        $time, dut.fc_layers_inst.fc2_valid_in, dut.fc_layers_inst.fc2_valid_out, 
                        dut.fc_layers_inst.fc2_neuron_idx, $signed(dut.fc_layers_inst.fc2_data_out), 
                        dut.fc_layers_inst.fc2_done_out);
                
                // Monitor internal fc3 signals
                $fwrite(log_file, "FC3_INTERNAL [t=%0t]: fc3_valid_in=%0d, fc3_valid_out=%0d, fc3_neuron_idx=%0d, fc3_data_out=%0d, fc3_done_out=%0d\n", 
                        $time, dut.fc_layers_inst.fc3_valid_in, dut.fc_layers_inst.fc3_valid_out, 
                        dut.fc_layers_inst.fc3_neuron_idx, $signed(dut.fc_layers_inst.fc3_data_out), 
                        dut.fc_layers_inst.fc3_done_out);
            end
            
            // Monitor FC1 outputs - use the internal signals for more reliable detection
            if (dut.fc_layers_inst.fc1_valid_out && dut.fc_layers_inst.state == 3'b001) begin // FC1_PROC
                $fwrite(log_file, "FC1 [t=%0t]: idx=%0d, val=%0d\n", 
                          $time, dut.fc_layers_inst.fc1_neuron_idx, $signed(dut.fc_layers_inst.fc1_data_out));
            end
            
            // Monitor FC2 outputs - use internal fc2 signals
            if (dut.fc_layers_inst.fc2_valid_out && dut.fc_layers_inst.state == 3'b010) begin // FC2_PROC
                $fwrite(log_file, "FC2 [t=%0t]: idx=%0d, val=%0d\n", 
                          $time, dut.fc_layers_inst.fc2_neuron_idx, $signed(dut.fc_layers_inst.fc2_data_out));
            end
            
            // Monitor FC3 outputs
            if (dut.fc_layers_inst.fc3_valid_out && dut.fc_layers_inst.state == 3'b011) begin // FC3_PROC
                $fwrite(log_file, "FC3 [t=%0t]: idx=%0d, val=%0d\n", 
                          $time, dut.fc_layers_inst.fc3_neuron_idx, $signed(dut.fc_layers_inst.fc3_data_out));
            end
            
            prev_state <= dut.state;
        end
    end
    
endmodule 
