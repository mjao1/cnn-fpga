// CNN top module
// Takes a 28x28 MNIST image and processes it through all CNN layers
// First line of test_image.txt is the expected label (for simulation)
// Remaining 784 lines are pixel values (0-255) for 28x28 image

module cnn_top #(
    parameter IMG_WIDTH = 28,
    parameter IMG_HEIGHT = 28,
    parameter DATA_WIDTH = 8,
    parameter NUM_CLASSES = 10
)(
    input wire clk,
    input wire rst,
    input wire start,
    
    // For test_image.txt input
    input wire [DATA_WIDTH-1:0] pixel_data,
    input wire pixel_valid,
    input wire [9:0] pixel_addr,
    
    output reg done,
    output reg [3:0] pred_digit,
    output reg [DATA_WIDTH-1:0] pred_confidence
);

    // State Machine States
    localparam IDLE          = 5'd0;
    localparam LOAD_IMAGE    = 5'd1;
    localparam CONV1         = 5'd2;
    localparam POOL1         = 5'd3;
    localparam CONV2         = 5'd4;
    localparam POOL2         = 5'd5;
    localparam FLATTEN       = 5'd6;
    localparam FC_LAYERS     = 5'd7;
    localparam FIND_MAX      = 5'd8;
    localparam DONE          = 5'd9;
    
    reg [4:0] state;
    
    reg [DATA_WIDTH-1:0] image_buffer [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    reg image_loaded;
    
    reg [9:0] pixel_count;
    reg [4:0] x_pos, y_pos;
    reg [5:0] conv2_count;
    reg [3:0] fc_count;
    
    // Conv Layer 1 signals
    reg conv1_start;
    reg [DATA_WIDTH-1:0] conv1_data_in;
    reg [8:0] conv1_x_in, conv1_y_in;
    reg conv1_valid_in;
    
    wire conv1_valid_out;
    wire [DATA_WIDTH-1:0] conv1_data_out_0;
    wire [DATA_WIDTH-1:0] conv1_data_out_1;
    wire [DATA_WIDTH-1:0] conv1_data_out_2;
    wire [DATA_WIDTH-1:0] conv1_data_out_3;
    wire [DATA_WIDTH-1:0] conv1_data_out_4;
    wire [DATA_WIDTH-1:0] conv1_data_out_5;
    wire [8:0] conv1_x_out, conv1_y_out;
    
    // Pack conv1 output channels
    wire [DATA_WIDTH*6-1:0] conv1_data_out = {
        conv1_data_out_5, conv1_data_out_4, conv1_data_out_3,
        conv1_data_out_2, conv1_data_out_1, conv1_data_out_0
    };
    
    // Pool Layer 1 signals
    reg pool1_start;
    wire pool1_valid_out;
    wire [DATA_WIDTH*6-1:0] pool1_data_out;
    wire [7:0] pool1_x_out, pool1_y_out;
    
    // Conv Layer 2 signals
    reg conv2_start;
    wire conv2_valid_out;
    wire [DATA_WIDTH*16-1:0] conv2_data_out;
    wire [7:0] conv2_x_out, conv2_y_out;
    
    // Pool Layer 2 signals
    reg pool2_start;
    wire pool2_valid_out;
    wire [DATA_WIDTH*16-1:0] pool2_data_out;
    wire [7:0] pool2_x_out, pool2_y_out;
    
    // Flatten signals
    reg [3:0] flatten_channel;
    reg flatten_valid_in;
    wire flatten_valid_out;
    wire [DATA_WIDTH-1:0] flatten_data_out;
    wire [7:0] flatten_addr_out;
    
    // FC Layers signals
    reg fc_start;
    wire fc_valid_out;
    wire [DATA_WIDTH-1:0] fc_data_out;
    wire [3:0] fc_digit_idx;
    wire fc_done_out;
    
    // Classification results
    reg [DATA_WIDTH-1:0] class_scores [0:NUM_CLASSES-1];
    reg [3:0] max_class_idx;
    reg [DATA_WIDTH-1:0] max_class_score;
    
    integer i, j, k;
    
    wire pool2_valid_in = (state == POOL2) ? 1'b1 : conv2_valid_out;
    
    reg [7:0] pool2_x_reg, pool2_y_reg;
    
    reg flatten_complete;
    
    reg [4:0] pool2_valid_count;
    
    // Conv Layer 1 (1x28x28 -> 6x24x24)
    conv_layer_1 #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .OUT_WIDTH(24),
        .OUT_HEIGHT(24),
        .NUM_FILTERS(6),
        .KERNEL_SIZE(5),
        .DATA_WIDTH(DATA_WIDTH)
    ) conv1 (
        .clk(clk),
        .rst(rst),
        .valid_in(conv1_valid_in),
        .data_in(conv1_data_in),
        .x_in(conv1_x_in),
        .y_in(conv1_y_in),
        .valid_out(conv1_valid_out),
        .data_out_0(conv1_data_out_0),
        .data_out_1(conv1_data_out_1),
        .data_out_2(conv1_data_out_2),
        .data_out_3(conv1_data_out_3),
        .data_out_4(conv1_data_out_4),
        .data_out_5(conv1_data_out_5),
        .x_out(conv1_x_out),
        .y_out(conv1_y_out)
    );
    
    // Pool Layer 1 (6x24x24 -> 6x12x12)
    pool_layer_1 #(
        .IN_WIDTH(24),
        .IN_HEIGHT(24),
        .OUT_WIDTH(12),
        .OUT_HEIGHT(12),
        .NUM_CHANNELS(6),
        .DATA_WIDTH(DATA_WIDTH)
    ) pool1 (
        .clk(clk),
        .rst(rst),
        .valid_in(conv1_valid_out),
        .data_in(conv1_data_out),
        .x_in(conv1_x_out[7:0]),
        .y_in(conv1_y_out[7:0]),
        .valid_out(pool1_valid_out),
        .data_out(pool1_data_out),
        .x_out(pool1_x_out),
        .y_out(pool1_y_out)
    );
    
    // Conv Layer 2 (6x12x12 -> 16x8x8)
    conv_layer_2 #(
        .MAP_WIDTH(12),
        .MAP_HEIGHT(12),
        .OUT_WIDTH(8),
        .OUT_HEIGHT(8),
        .IN_CHANNELS(6),
        .OUT_CHANNELS(16),
        .KERNEL_SIZE(5),
        .DATA_WIDTH(DATA_WIDTH)
    ) conv2 (
        .clk(clk),
        .rst(rst),
        .valid_in(pool1_valid_out),
        .data_in(pool1_data_out),
        .x_in(pool1_x_out),
        .y_in(pool1_y_out),
        .valid_out(conv2_valid_out),
        .data_out(conv2_data_out),
        .x_out(conv2_x_out),
        .y_out(conv2_y_out)
    );
    
    // Pool Layer 2 signals
    pool_layer_2 #(
        .IN_WIDTH(8),
        .IN_HEIGHT(8),
        .OUT_WIDTH(4),
        .OUT_HEIGHT(4),
        .NUM_CHANNELS(16),
        .DATA_WIDTH(DATA_WIDTH)
    ) pool2 (
        .clk(clk),
        .rst(rst),
        .valid_in(pool2_valid_in),
        .data_in(conv2_data_out),
        .x_in((state == POOL2 || state == FLATTEN) ? pool2_x_reg : conv2_x_out),
        .y_in((state == POOL2 || state == FLATTEN) ? pool2_y_reg : conv2_y_out),
        .valid_out(pool2_valid_out),
        .data_out(pool2_data_out),
        .x_out(pool2_x_out),
        .y_out(pool2_y_out)
    );
    
    // Flatten module (16 channels of 4x4 feature maps -> 256 vector)
    flatten #(
        .IN_CHANNELS(16),
        .IN_WIDTH(4),
        .IN_HEIGHT(4),
        .DATA_WIDTH(DATA_WIDTH),
        .OUT_FEATURES(256)
    ) flatten_inst (
        .clk(clk),
        .rst(rst),
        .valid_in(flatten_valid_in),
        .data_in(pool2_data_out),
        .valid_out(flatten_valid_out),
        .data_out(flatten_data_out),
        .addr_out(flatten_addr_out)
    );
    
    // FC Layers signals
    reg fc_start;
    wire fc_valid_out;
    wire [DATA_WIDTH-1:0] fc_data_out;
    wire [3:0] fc_digit_idx;
    wire fc_done_out;
    
    // FC Layers (256 -> 120 -> 84 -> 10)
    fc_layers #(
        .FC1_IN_FEATURES(256),
        .FC1_OUT_FEATURES(120),
        .FC2_IN_FEATURES(120),
        .FC2_OUT_FEATURES(84),
        .FC3_IN_FEATURES(84),
        .FC3_OUT_FEATURES(10),
        .DATA_WIDTH(DATA_WIDTH)
    ) fc_layers_inst (
        .clk(clk),
        .rst(rst),
        .start(fc_start),
        .valid_in(flatten_valid_out),
        .data_in(flatten_data_out),
        .addr_in(flatten_addr_out),
        .valid_out(fc_valid_out),
        .data_out(fc_data_out),
        .digit_idx(fc_digit_idx),
        .done_out(fc_done_out)
    );
    
    // Main state machine
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            done <= 1'b0;
            pred_digit <= 4'd0;
            pred_confidence <= 8'd0;
            image_loaded <= 1'b0;
            pixel_count <= 10'd0;
            conv2_count <= 6'd0;
            fc_count <= 4'd0;
            flatten_complete <= 1'b0;
            pool2_valid_count <= 5'd0;
            conv1_valid_in <= 1'b0;
            flatten_valid_in <= 1'b0;
            fc_start <= 1'b0;
            flatten_channel <= 4'd0;
            max_class_idx <= 4'd0;
            max_class_score <= 8'd0;
            pool2_x_reg <= 8'd0;
            pool2_y_reg <= 8'd0;
            
            for (i = 0; i < IMG_HEIGHT; i = i + 1) begin
                for (j = 0; j < IMG_WIDTH; j = j + 1) begin
                    image_buffer[i][j] <= 8'd0;
                end
            end
            
            for (i = 0; i < NUM_CLASSES; i = i + 1) begin
                class_scores[i] <= 8'd0;
            end
        end else begin
            // Default signals
            conv1_valid_in <= 1'b0;
            flatten_valid_in <= 1'b0;
            fc_start <= 1'b0;
            
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state <= LOAD_IMAGE;
                        pixel_count <= 10'd0;
                        image_loaded <= 1'b0;
                    end
                end
                
                LOAD_IMAGE: begin
                    if (pixel_valid) begin
                        // Calculate position in 2D image (row-major order)
                        x_pos <= pixel_addr % IMG_WIDTH;
                        y_pos <= pixel_addr / IMG_WIDTH;
                        
                        // Store pixel in buffer
                        image_buffer[pixel_addr / IMG_WIDTH][pixel_addr % IMG_WIDTH] <= pixel_data;
                        
                        pixel_count <= pixel_count + 10'd1;
                        
                        if (pixel_count == (IMG_WIDTH * IMG_HEIGHT - 1)) begin
                            image_loaded <= 1'b1;
                            state <= CONV1;
                            // Reset pos for CONV1
                            x_pos <= 5'd0;
                            y_pos <= 5'd0;
                        end
                    end
                end
                
                CONV1: begin
                    // Send data through Conv1 layer
                    if (y_pos < IMG_HEIGHT && x_pos < IMG_WIDTH) begin
                        conv1_valid_in <= 1'b1;
                        conv1_data_in <= image_buffer[y_pos][x_pos];
                        conv1_x_in <= x_pos;
                        conv1_y_in <= y_pos;
                        
                        // Move to next pixel
                        if (x_pos == IMG_WIDTH - 1) begin
                            x_pos <= 0;
                            y_pos <= y_pos + 1;
                        end else begin
                            x_pos <= x_pos + 1;
                        end
                    end else begin
                        // All pixels sent, wait for POOL1 to complete
                        conv1_valid_in <= 1'b0;
                        state <= POOL1;
                    end
                end
                
                POOL1: begin
                    if (pool1_valid_out) begin
                        conv2_count <= 6'd0;
                        state <= CONV2;
                    end
                end
                
                CONV2: begin
                    if (conv2_valid_out) begin
                        conv2_count <= conv2_count + 6'd1;
                    end
                    if (conv2_count == 6'd64) begin
                        conv2_count <= 6'd0;
                        pool2_x_reg <= 8'd0;
                        pool2_y_reg <= 8'd0;
                        state <= POOL2; // transition after 64 valid outputs (8x8)
                    end
                end
                
                POOL2: begin
                    if (pool2_x_reg == 8'd7) begin
                        pool2_x_reg <= 8'd0;
                        if (pool2_y_reg == 8'd7)
                            pool2_y_reg <= 8'd0;
                        else
                            pool2_y_reg <= pool2_y_reg + 8'd1;
                    end else begin
                        pool2_x_reg <= pool2_x_reg + 8'd1;
                    end

                    if (pool2_valid_out) begin
                        pool2_valid_count <= pool2_valid_count + 5'd1;
                    end

                    if (pool2_valid_count == 5'd16) begin
                        state <= FLATTEN;
                        pool2_valid_count <= 5'd0;
                    end
                end
                
                FLATTEN: begin
                    flatten_valid_in <= 1'b1;
                    // Latch when the flatten module outputs final value (addr 255)
                    if (flatten_valid_out && (flatten_addr_out == 8'd255)) begin
                        flatten_complete <= 1'b1;
                    end
                    // Once flatten_complete goto FC_LAYERS
                    if (flatten_complete) begin
                        state <= FC_LAYERS;
                        fc_start <= 1'b1;
                    end
                end
                
                FC_LAYERS: begin
                    fc_start <= 1'b0;
                    if (fc_valid_out) begin
                        class_scores[fc_digit_idx] <= fc_data_out;
                        fc_count <= fc_count + 1;
                    end
                    // Once all 10 outputs capturedgoto FIND_MAX
                    if (fc_count == NUM_CLASSES) begin
                        state <= FIND_MAX;
                    end
                end
                
                FIND_MAX: begin
                    // Find max class score
                    max_class_score <= class_scores[0];
                    max_class_idx <= 4'd0;
                    
                    for (i = 1; i < NUM_CLASSES; i = i + 1) begin
                        if ($signed(class_scores[i]) > $signed(max_class_score)) begin
                            max_class_score <= class_scores[i];
                            max_class_idx <= i;
                        end
                    end
                    
                    state <= DONE;
                end
                
                DONE: begin
                    // Output prediction results
                    pred_digit <= max_class_idx;
                    pred_confidence <= max_class_score;
                    done <= 1'b1;
                    
                    // Stay in DONE until start
                    if (start) begin
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule 
