`timescale 1ns / 1ps

module tb_cnn_top_bulk;

    parameter CLK_PERIOD = 10;
    parameter DATA_WIDTH = 8;
    parameter IMG_WIDTH = 28;
    parameter IMG_HEIGHT = 28;
    parameter NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT;
    parameter NUM_PER_DIGIT = 100;
    parameter NUM_DIGITS = 10;
    parameter TOTAL_IMAGES = NUM_PER_DIGIT * NUM_DIGITS;
    
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
    
    reg [DATA_WIDTH-1:0] test_image [0:NUM_PIXELS-1];
    
    integer digit_idx, image_idx;
    integer correct_count [0:9];
    integer total_correct;
    integer mismatch_count;
    reg [1023:0] image_filename;
    reg [3:0] expected_digit;
    integer test_num;
    
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
    
    task run_single_test;
        input [3:0] digit;
        input integer img_idx;
        begin
            $sformat(image_filename, "sim/cnn/test_images_bulk/test_image_%0d_%0d.mem", digit, img_idx);
            $readmemh(image_filename, test_image);
            expected_digit = digit;
            
            rst = 1;
            start = 0;
            pixel_data = 0;
            pixel_valid = 0;
            pixel_row = 0;
            pixel_col = 0;
            repeat (20) @(posedge clk);
            rst = 0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            
            start = 1;
            @(posedge clk); #1;
            start = 0;
            
            for (integer i = 0; i < NUM_PIXELS; i = i + 1) begin
                pixel_valid = 1;
                pixel_row = i / 10'd28;
                pixel_col = i % 10'd28;
                pixel_data = test_image[i];
                @(posedge clk); #1;
            end
            pixel_valid = 0;
            
            wait(done);
            @(posedge clk); #1;
        end
    endtask
    
    task print_progress;
        input integer current;
        input integer total;
        begin
            integer percent;
            integer i;
            percent = (current * 100) / total;
            $write("Progress: [");
            for (i = 0; i < 50; i = i + 1) begin
                if (i < (percent / 2)) begin
                    $write("=");
                end else begin
                    $write(" ");
                end
            end
            $write("] %0d%% (%0d/%0d)", percent, current, total);
        end
    endtask
    
    initial begin
        for (integer d = 0; d < 10; d = d + 1) begin
            correct_count[d] = 0;
        end
        total_correct = 0;
        mismatch_count = 0;
        test_num = 0;
        
        $display("=== CNN Bulk Accuracy Test ===");
        $display("Testing %0d images per digit (total: %0d images)", NUM_PER_DIGIT, TOTAL_IMAGES);
        $display("");
        
        for (digit_idx = 0; digit_idx < NUM_DIGITS; digit_idx = digit_idx + 1) begin
            for (image_idx = 0; image_idx < NUM_PER_DIGIT; image_idx = image_idx + 1) begin
                run_single_test(digit_idx, image_idx);
                
                test_num = test_num + 1;
                
                if (pred_digit == expected_digit) begin
                    correct_count[digit_idx] = correct_count[digit_idx] + 1;
                    total_correct = total_correct + 1;
                end else begin
                    mismatch_count = mismatch_count + 1;
                    $display("Mismatch: Digit %0d, Image %0d -> Predicted %0d (confidence: %0d)",
                        expected_digit, image_idx, pred_digit, $signed(pred_confidence));
                end
                
                print_progress(test_num, TOTAL_IMAGES);
                $display("");
            end
        end
        
        $write("\n\n");
        $display("=== Accuracy Results ===");
        $display("");
        
        for (integer d = 0; d < 10; d = d + 1) begin
            integer digit_acc;
            digit_acc = (correct_count[d] * 100) / NUM_PER_DIGIT;
            $display("Digit %0d: %0d/%0d correct (%0d%%)", 
                d, correct_count[d], NUM_PER_DIGIT, digit_acc);
        end
        
        $display("");
        $display("Total Accuracy: %0d/%0d correct (%.2f%%)", 
            total_correct, TOTAL_IMAGES, (total_correct * 100.0) / TOTAL_IMAGES);
        $display("Total Mismatches: %0d", mismatch_count);
        $display("");
        
        $finish;
    end
    
endmodule
