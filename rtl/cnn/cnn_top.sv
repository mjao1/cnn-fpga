// CNN top module
// Takes a 28x28 MNIST image and processes it through all CNN layers

module cnn_top #(
    parameter IMG_WIDTH = 28,
    parameter IMG_HEIGHT = 28,
    parameter DATA_WIDTH = 8,
    parameter NUM_CLASSES = 10
)(
    input logic clk,
    input logic rst,
    input logic start,
    
    // For test_image.txt input
    input logic [DATA_WIDTH-1:0] pixel_data,
    input logic pixel_valid,
    input logic [9:0] pixel_addr,
    
    output logic done,
    output logic [3:0] pred_digit,
    output logic [DATA_WIDTH-1:0] pred_confidence
);

    // State Machine States
    typedef enum logic [4:0] {
        IDLE          = 5'd0,
        LOAD_IMAGE    = 5'd1,
        CONV1         = 5'd2,
        CONV2         = 5'd4,
        FLATTEN       = 5'd5,
        FC_LAYERS     = 5'd6,
        FIND_MAX      = 5'd7,
        DONE_STATE    = 5'd8
    } state_t;
    
    state_t state;
    
    logic [DATA_WIDTH-1:0] image_buffer [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic image_loaded;
    
    logic [9:0] pixel_count;
    logic [4:0] x_pos, y_pos;
    logic [5:0] conv2_count;
    logic [3:0] fc_count;
    logic [7:0] conv2_feed_count;
    
    // Conv Layer 1 signals
    logic conv1_start;
    logic [DATA_WIDTH-1:0] conv1_data_in;
    logic [8:0] conv1_x_in, conv1_y_in;
    logic conv1_valid_in;
    
    logic conv1_valid_out;
    logic [DATA_WIDTH-1:0] conv1_data_out_0;
    logic [DATA_WIDTH-1:0] conv1_data_out_1;
    logic [DATA_WIDTH-1:0] conv1_data_out_2;
    logic [DATA_WIDTH-1:0] conv1_data_out_3;
    logic [DATA_WIDTH-1:0] conv1_data_out_4;
    logic [DATA_WIDTH-1:0] conv1_data_out_5;
    logic [8:0] conv1_x_out, conv1_y_out;
    
    // Pack conv1 output channels
    wire [DATA_WIDTH*6-1:0] conv1_data_out = {
        conv1_data_out_5, conv1_data_out_4, conv1_data_out_3,
        conv1_data_out_2, conv1_data_out_1, conv1_data_out_0
    };
    
    // Pool Layer 1 signals
    logic pool1_start;
    logic pool1_valid_out;
    logic [DATA_WIDTH*6-1:0] pool1_data_out;
    logic [8:0] pool1_x_out, pool1_y_out;
    
    // Pool1 output buffer (6 channels x 12x12 = 864 values)
    logic [DATA_WIDTH-1:0] pool1_buffer [0:5][0:11][0:11];
    logic [DATA_WIDTH*6-1:0] pool1_buffer_data;
    logic [7:0] pool1_buffer_count;
    logic pool1_buffer_complete;
    logic [7:0] conv2_feed_x, conv2_feed_y;
    logic conv2_feed_valid;
    
    // Data packing from pool1_buffer for conv2 input
    always_comb begin
        pool1_buffer_data[7:0]   = pool1_buffer[0][conv2_feed_y][conv2_feed_x];
        pool1_buffer_data[15:8]  = pool1_buffer[1][conv2_feed_y][conv2_feed_x];
        pool1_buffer_data[23:16] = pool1_buffer[2][conv2_feed_y][conv2_feed_x];
        pool1_buffer_data[31:24] = pool1_buffer[3][conv2_feed_y][conv2_feed_x];
        pool1_buffer_data[39:32] = pool1_buffer[4][conv2_feed_y][conv2_feed_x];
        pool1_buffer_data[47:40] = pool1_buffer[5][conv2_feed_y][conv2_feed_x];
    end
    
    // Conv Layer 2 signals
    logic conv2_start;
    logic conv2_valid_out;
    logic [DATA_WIDTH*16-1:0] conv2_data_out;
    logic [7:0] conv2_x_out, conv2_y_out;
    logic conv2_ready;  // Indicates conv_layer_2 weight loading complete
    
    // Pool Layer 2 signals
    logic pool2_valid_out;
    logic [DATA_WIDTH*16-1:0] pool2_data_out;
    logic [7:0] pool2_x_out, pool2_y_out;
    
    // Flatten signals
    logic [3:0] flatten_channel;
    logic flatten_valid_in;
    logic flatten_valid_out;
    logic [DATA_WIDTH-1:0] flatten_data_out;
    logic [7:0] flatten_addr_out;
    
    // FC Layers signals
    logic fc_start;
    logic fc_valid_out;
    logic [DATA_WIDTH-1:0] fc_data_out;
    logic [3:0] fc_digit_idx;
    logic fc_done_out;
    
    // Classification results
    logic [DATA_WIDTH-1:0] class_scores [0:NUM_CLASSES-1];
    logic [3:0] max_class_idx;
    logic [DATA_WIDTH-1:0] max_class_score;
    
    logic pool2_valid_in;
    assign pool2_valid_in = conv2_valid_out;
    
    logic flatten_complete;
    
    logic [4:0] pool2_valid_count;
    logic pool2_complete;
    
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
        .x_in(conv1_x_out),
        .y_in(conv1_y_out),
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
        .valid_in(conv2_feed_valid),
        .data_in(pool1_buffer_data),
        .x_in(conv2_feed_x),
        .y_in(conv2_feed_y),
        .valid_out(conv2_valid_out),
        .data_out(conv2_data_out),
        .x_out(conv2_x_out),
        .y_out(conv2_y_out),
        .ready(conv2_ready)
    );
    
    // Pool Layer 2 (16x8x8 -> 16x4x4)
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
        .x_in(conv2_x_out),
        .y_in(conv2_y_out),
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
        .valid_in(pool2_valid_out),
        .data_in(pool2_data_out),
        .valid_out(flatten_valid_out),
        .data_out(flatten_data_out),
        .addr_out(flatten_addr_out)
    );
    
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
    
    // Argmax logic for finding max class score
    logic [3:0] argmax_idx;
    logic signed [DATA_WIDTH-1:0] argmax_val;
    
    always_comb begin
        argmax_idx = 4'd0;
        argmax_val = $signed(class_scores[0]);
        
        for (int i = 1; i < NUM_CLASSES; i++) begin
            if ($signed(class_scores[i]) > argmax_val) begin
                argmax_val = $signed(class_scores[i]);
                argmax_idx = i[3:0];
            end
        end
    end
    
    // Main state machine
    always_ff @(posedge clk) begin
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
            pool1_buffer_count <= 8'd0;
            pool1_buffer_complete <= 1'b0;
            conv2_feed_x <= 8'd0;
            conv2_feed_y <= 8'd0;
            conv2_feed_valid <= 1'b0;
            conv2_feed_count <= 8'd0;
            pool2_complete <= 1'b0;
            x_pos <= 5'd0;
            y_pos <= 5'd0;
            
            for (int i = 0; i < IMG_HEIGHT; i++) begin
                for (int j = 0; j < IMG_WIDTH; j++) begin
                    image_buffer[i][j] <= 8'd0;
                end
            end
            
            for (int i = 0; i < NUM_CLASSES; i++) begin
                class_scores[i] <= 8'd0;
            end
            
            for (int i = 0; i < 6; i++) begin
                for (int j = 0; j < 12; j++) begin
                    for (int k = 0; k < 12; k++) begin
                        pool1_buffer[i][j][k] <= 8'd0;
                    end
                end
            end
        end else begin
            // Default signals
            conv1_valid_in <= 1'b0;
            flatten_valid_in <= 1'b0;
            fc_start <= 1'b0;
            conv2_feed_valid <= 1'b0;
            
            // Always capture pool1 outputs when they're valid
            if (pool1_valid_out && !pool1_buffer_complete) begin
                // Unpack pool1 data and store in buffer
                pool1_buffer[0][pool1_y_out][pool1_x_out] <= pool1_data_out[7:0];
                pool1_buffer[1][pool1_y_out][pool1_x_out] <= pool1_data_out[15:8];
                pool1_buffer[2][pool1_y_out][pool1_x_out] <= pool1_data_out[23:16];
                pool1_buffer[3][pool1_y_out][pool1_x_out] <= pool1_data_out[31:24];
                pool1_buffer[4][pool1_y_out][pool1_x_out] <= pool1_data_out[39:32];
                pool1_buffer[5][pool1_y_out][pool1_x_out] <= pool1_data_out[47:40];
                pool1_buffer_count <= pool1_buffer_count + 8'd1;
                
                // Check if all 144 pool1 outputs (12x12) received
                if (pool1_buffer_count == 8'd143) begin
                    pool1_buffer_complete <= 1'b1;
                end
            end
            
            // Always capture pool2 outputs when they're valid
            if (pool2_valid_out && !pool2_complete) begin
                pool2_valid_count <= pool2_valid_count + 5'd1;
                
                // Check if all 16 pool2 outputs (4x4) received
                if (pool2_valid_count == 5'd15) begin
                    pool2_complete <= 1'b1;
                end
            end
            
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
                        conv1_x_in <= {4'd0, x_pos};
                        conv1_y_in <= {4'd0, y_pos};
                        
                        // Move to next pixel
                        if (x_pos == IMG_WIDTH - 1) begin
                            x_pos <= 5'd0;
                            y_pos <= y_pos + 5'd1;
                        end else begin
                            x_pos <= x_pos + 5'd1;
                        end
                    end else begin
                        conv1_valid_in <= 1'b0;
                        if (pool1_buffer_complete && conv2_ready) begin
                            conv2_count <= 6'd0;
                            conv2_feed_x <= 8'd0;
                            conv2_feed_y <= 8'd0;
                            conv2_feed_count <= 8'd1;
                            conv2_feed_valid <= 1'b1;
                            state <= CONV2;
                        end
                    end
                end
                
                CONV2: begin
                    // Feed buffered pool1 data to conv2 in order
                    if (conv2_feed_count < 8'd144) begin
                        conv2_feed_valid <= 1'b1;
                        conv2_feed_count <= conv2_feed_count + 8'd1;
                        
                        if (conv2_feed_x == 8'd11) begin
                            conv2_feed_x <= 8'd0;
                            conv2_feed_y <= conv2_feed_y + 8'd1;
                        end else begin
                            conv2_feed_x <= conv2_feed_x + 8'd1;
                        end
                    end else begin
                        conv2_feed_valid <= 1'b0;
                    end
                    
                    if (conv2_valid_out && conv2_count < 6'd63) begin
                        conv2_count <= conv2_count + 6'd1;
                    end
                    
                    if (conv2_count >= 6'd63 && pool2_complete) begin
                        state <= FLATTEN;
                    end
                end
                
                FLATTEN: begin
                    if (flatten_valid_out && (flatten_addr_out == 8'd255)) begin
                        flatten_complete <= 1'b1;
                    end
                    if (flatten_complete) begin
                        state <= FC_LAYERS;
                        fc_start <= 1'b1;
                    end
                end
                
                FC_LAYERS: begin
                    fc_start <= 1'b0;
                    if (fc_valid_out) begin
                        class_scores[fc_digit_idx] <= fc_data_out;
                        fc_count <= fc_count + 4'd1;
                    end
                    if (fc_count == NUM_CLASSES) begin
                        state <= FIND_MAX;
                    end
                end
                
                FIND_MAX: begin
                    // Use combinational argmax result
                    max_class_idx <= argmax_idx;
                    max_class_score <= argmax_val;
                    state <= DONE_STATE;
                end
                
                DONE_STATE: begin
                    pred_digit <= max_class_idx;
                    pred_confidence <= max_class_score;
                    done <= 1'b1;
                    
                    if (start) begin
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
