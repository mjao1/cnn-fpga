`timescale 1ns / 1ps

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
    
    // Test
    initial begin
        rst = 1;
        start = 0;
        pixel_data = 0;
        pixel_valid = 0;
        pixel_addr = 0;
        
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
        
        #(CLK_PERIOD*100);
        $finish;
    end
    
    integer j;
    
    reg [4:0] prev_state;
    
    always @(posedge clk) begin
        if (rst) begin
            prev_state <= 5'd0;
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
            
            if (dut.state == 5'd1 && pixel_valid) begin
                if (pixel_addr % (NUM_PIXELS/10) == 0) begin
                    $display("  Image loading: %0d%%", (pixel_addr * 100) / NUM_PIXELS);
                end
            end
            
            prev_state <= dut.state;
        end
    end
    
endmodule 
