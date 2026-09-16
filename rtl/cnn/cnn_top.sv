// CNN top module
// Takes a 28x28 MNIST image and processes it through all CNN layers

module cnn_top #(
    parameter IMG_WIDTH = 28,
    parameter IMG_HEIGHT = 28,
    parameter DATA_WIDTH = 8,
    parameter NUM_CLASSES = 10
)(
    input  logic                          clk_i,
    input  logic                          rst_i,
    input  logic                          start_i,

    input  logic [DATA_WIDTH-1:0]         pixel_data_i,
    input  logic                          pixel_valid_i,
    input  logic [$clog2(IMG_HEIGHT)-1:0] pixel_row_i,
    input  logic [$clog2(IMG_WIDTH)-1:0]  pixel_col_i,

    output logic                          done_o,
    output logic [3:0]                    pred_digit_o,
    output logic [DATA_WIDTH-1:0]         pred_confidence_o
);

    // States
    typedef enum logic [4:0] {
        IDLE          = 5'd0,
        LOAD_IMAGE    = 5'd1,
        CONV1         = 5'd2,
        CONV2         = 5'd4,
        FLATTEN       = 5'd5,
        FC_LAYERS     = 5'd6,
        FIND_MAX      = 5'd7,
        DONE    = 5'd8
    } state_t;

    state_t state;
    logic [DATA_WIDTH-1:0] image_buffer [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic [9:0] pixel_count;
    logic [4:0] conv1_rd_x, conv1_rd_y;
    logic [5:0] conv2_count;
    logic [3:0] fc_count;

    // Conv layer 1 signals
    logic conv1_valid_in;
    logic [DATA_WIDTH-1:0] conv1_data_in;
    logic [8:0] conv1_x_in, conv1_y_in;
    logic conv1_valid_out;
    logic [DATA_WIDTH-1:0] conv1_data_out_0;
    logic [DATA_WIDTH-1:0] conv1_data_out_1;
    logic [DATA_WIDTH-1:0] conv1_data_out_2;
    logic [DATA_WIDTH-1:0] conv1_data_out_3;
    logic [DATA_WIDTH-1:0] conv1_data_out_4;
    logic [DATA_WIDTH-1:0] conv1_data_out_5;
    logic [8:0] conv1_x_out, conv1_y_out;
    logic conv1_busy;
    logic [DATA_WIDTH*6-1:0] conv1_data_out;

    // Pool layer 1 signals
    logic pool1_valid_out;
    logic [DATA_WIDTH*6-1:0] pool1_data_out;
    logic [8:0] pool1_x_out, pool1_y_out;

    logic [DATA_WIDTH-1:0] pool1_buffer [0:5][0:11][0:11];
    logic [DATA_WIDTH*6-1:0] pool1_buffer_data;
    logic [7:0] pool1_buffer_count;
    logic pool1_buffer_complete;
    logic [7:0] conv2_feed_x, conv2_feed_y;
    logic conv2_feed_valid;

    // Conv layer 2 signals
    logic conv2_valid_out;
    logic [DATA_WIDTH*16-1:0] conv2_data_out;
    logic [7:0] conv2_x_out, conv2_y_out;
    logic conv2_ready;  // Indicates conv_layer_2 weight loading complete
    logic conv2_busy;

    // Pool layer 2 signals
    logic pool2_valid_out;
    logic [DATA_WIDTH*16-1:0] pool2_data_out;
    logic [1:0] pool2_x_out, pool2_y_out;
    logic pool2_valid_in;
    logic [4:0] pool2_valid_count;
    logic pool2_complete;

    // Flatten signals
    logic flatten_valid_out;
    logic [DATA_WIDTH-1:0] flatten_data_out;
    logic [7:0] flatten_addr_out;
    logic flatten_complete;
    logic flatten_reload;

    // FC layers signals
    logic fc_start;
    logic fc_valid_out;
    logic [DATA_WIDTH-1:0] fc_data_out;
    logic [3:0] fc_digit_idx;
    logic fc_done_out;

    // Classification results
    logic [DATA_WIDTH-1:0] class_scores [0:NUM_CLASSES-1];
    logic [3:0] max_class_idx;
    logic [DATA_WIDTH-1:0] max_class_score;
    logic [3:0] max_scan_idx;
    logic [3:0] max_scan_class_idx;
    logic signed [DATA_WIDTH-1:0] max_scan_val;

    // LOAD_IMAGE staged write
    logic img_wr_pending;
    (* max_fanout = 32 *)
    logic [$clog2(IMG_HEIGHT)-1:0] img_wr_row;
    (* max_fanout = 32 *)
    logic [$clog2(IMG_WIDTH)-1:0] img_wr_col;
    logic [DATA_WIDTH-1:0] img_wr_data;

    // Next state signals
    state_t state_n;
    logic [9:0] pixel_count_n;
    logic [4:0] conv1_rd_x_n, conv1_rd_y_n;
    logic [5:0] conv2_count_n;
    logic [3:0] fc_count_n;
    logic conv1_valid_in_n;
    logic [8:0] conv1_x_in_n, conv1_y_in_n;
    logic [7:0] pool1_buffer_count_n;
    logic pool1_buffer_complete_n;
    logic [7:0] conv2_feed_x_n, conv2_feed_y_n;
    logic conv2_feed_valid_n;
    logic [4:0] pool2_valid_count_n;
    logic pool2_complete_n;
    logic flatten_complete_n;
    logic fc_start_n;
    logic [3:0] max_class_idx_n;
    logic [DATA_WIDTH-1:0] max_class_score_n;
    logic [3:0] max_scan_idx_n;
    logic [3:0] max_scan_class_idx_n;
    logic signed [DATA_WIDTH-1:0] max_scan_val_n;
    logic done_o_n;
    logic [3:0] pred_digit_o_n;
    logic [DATA_WIDTH-1:0] pred_confidence_o_n;
    logic img_wr_pending_n;
    logic [$clog2(IMG_HEIGHT)-1:0] img_wr_row_n;
    logic [$clog2(IMG_WIDTH)-1:0] img_wr_col_n;
    logic [DATA_WIDTH-1:0] img_wr_data_n;

    // Pack conv1 output channels
    assign conv1_data_out = {
        conv1_data_out_5, conv1_data_out_4, conv1_data_out_3,
        conv1_data_out_2, conv1_data_out_1, conv1_data_out_0
    };

    // Data packing from pool1_buffer for conv2 input
    always_comb begin
        pool1_buffer_data[7:0]   = pool1_buffer[0][conv2_feed_y][conv2_feed_x];
        pool1_buffer_data[15:8]  = pool1_buffer[1][conv2_feed_y][conv2_feed_x];
        pool1_buffer_data[23:16] = pool1_buffer[2][conv2_feed_y][conv2_feed_x];
        pool1_buffer_data[31:24] = pool1_buffer[3][conv2_feed_y][conv2_feed_x];
        pool1_buffer_data[39:32] = pool1_buffer[4][conv2_feed_y][conv2_feed_x];
        pool1_buffer_data[47:40] = pool1_buffer[5][conv2_feed_y][conv2_feed_x];
    end

    assign pool2_valid_in = conv2_valid_out;
    assign flatten_reload = ((state == IDLE) || (state == DONE)) && start_i;

    // Conv Layer 1 (1x28x28 to 6x24x24)
    conv_layer_1 #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .OUT_WIDTH(24),
        .OUT_HEIGHT(24),
        .NUM_FILTERS(6),
        .KERNEL_SIZE(5),
        .DATA_WIDTH(DATA_WIDTH)
    ) conv1 (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .valid_i(conv1_valid_in),
        .data_i(conv1_data_in),
        .x_i(conv1_x_in),
        .y_i(conv1_y_in),
        .valid_o(conv1_valid_out),
        .data_0_o(conv1_data_out_0),
        .data_1_o(conv1_data_out_1),
        .data_2_o(conv1_data_out_2),
        .data_3_o(conv1_data_out_3),
        .data_4_o(conv1_data_out_4),
        .data_5_o(conv1_data_out_5),
        .x_o(conv1_x_out),
        .y_o(conv1_y_out),
        .busy_o(conv1_busy)
    );

    // Pool Layer 1 (6x24x24 to 6x12x12)
    pool_layer_1 #(
        .IN_WIDTH(24),
        .IN_HEIGHT(24),
        .OUT_WIDTH(12),
        .OUT_HEIGHT(12),
        .NUM_CHANNELS(6),
        .DATA_WIDTH(DATA_WIDTH)
    ) pool1 (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .valid_i(conv1_valid_out),
        .data_i(conv1_data_out),
        .x_i(conv1_x_out),
        .y_i(conv1_y_out),
        .valid_o(pool1_valid_out),
        .data_o(pool1_data_out),
        .x_o(pool1_x_out),
        .y_o(pool1_y_out)
    );

    // Conv Layer 2 (6x12x12 to 16x8x8)
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
        .clk_i(clk_i),
        .rst_i(rst_i),
        .valid_i(conv2_feed_valid),
        .data_i(pool1_buffer_data),
        .x_i(conv2_feed_x),
        .y_i(conv2_feed_y),
        .valid_o(conv2_valid_out),
        .data_o(conv2_data_out),
        .x_o(conv2_x_out),
        .y_o(conv2_y_out),
        .ready_o(conv2_ready),
        .busy_o(conv2_busy)
    );

    // Pool Layer 2 (16x8x8 to 16x4x4)
    pool_layer_2 #(
        .IN_WIDTH(8),
        .IN_HEIGHT(8),
        .OUT_WIDTH(4),
        .OUT_HEIGHT(4),
        .NUM_CHANNELS(16),
        .DATA_WIDTH(DATA_WIDTH)
    ) pool2 (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .valid_i(pool2_valid_in),
        .data_i(conv2_data_out),
        .x_i(conv2_x_out[2:0]),
        .y_i(conv2_y_out[2:0]),
        .valid_o(pool2_valid_out),
        .data_o(pool2_data_out),
        .x_o(pool2_x_out),
        .y_o(pool2_y_out)
    );

    // Flatten
    flatten #(
        .IN_CHANNELS(16),
        .IN_WIDTH(4),
        .IN_HEIGHT(4),
        .DATA_WIDTH(DATA_WIDTH),
        .OUT_FEATURES(256)
    ) flatten_inst (
        .clk(clk_i),
        .rst(rst_i),
        .reload(flatten_reload),
        .valid_in(pool2_valid_out),
        .data_in(pool2_data_out),
        .valid_out(flatten_valid_out),
        .data_out(flatten_data_out),
        .addr_out(flatten_addr_out)
    );

    // FC Layers (256 to 120 to 84 to 10)
    fc_layers #(
        .FC1_IN_FEATURES(256),
        .FC1_OUT_FEATURES(120),
        .FC2_IN_FEATURES(120),
        .FC2_OUT_FEATURES(84),
        .FC3_IN_FEATURES(84),
        .FC3_OUT_FEATURES(10),
        .DATA_WIDTH(DATA_WIDTH)
    ) fc_layers_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(fc_start),
        .valid_i(flatten_valid_out),
        .data_i(flatten_data_out),
        .addr_i(flatten_addr_out),
        .valid_o(fc_valid_out),
        .data_o(fc_data_out),
        .digit_idx_o(fc_digit_idx),
        .done_o(fc_done_out)
    );

    // Main state machine
    always_comb begin
        state_n = state;
        pixel_count_n = pixel_count;
        conv1_rd_x_n = conv1_rd_x;
        conv1_rd_y_n = conv1_rd_y;
        conv2_count_n = conv2_count;
        fc_count_n = fc_count;
        conv1_valid_in_n = 1'b0;
        conv1_x_in_n = conv1_x_in;
        conv1_y_in_n = conv1_y_in;
        pool1_buffer_count_n = pool1_buffer_count;
        pool1_buffer_complete_n = pool1_buffer_complete;
        conv2_feed_x_n = conv2_feed_x;
        conv2_feed_y_n = conv2_feed_y;
        conv2_feed_valid_n = 1'b0;
        pool2_valid_count_n = pool2_valid_count;
        pool2_complete_n = pool2_complete;
        flatten_complete_n = flatten_complete;
        fc_start_n = 1'b0;
        max_class_idx_n = max_class_idx;
        max_class_score_n = max_class_score;
        max_scan_idx_n = max_scan_idx;
        max_scan_class_idx_n = max_scan_class_idx;
        max_scan_val_n = max_scan_val;
        done_o_n = done_o;
        pred_digit_o_n = pred_digit_o;
        pred_confidence_o_n = pred_confidence_o;
        img_wr_pending_n = img_wr_pending;
        img_wr_row_n = img_wr_row;
        img_wr_col_n = img_wr_col;
        img_wr_data_n = img_wr_data;

        // Always capture pool1 outputs when valid
        if (pool1_valid_out && !pool1_buffer_complete) begin
            pool1_buffer_count_n = pool1_buffer_count + 8'd1;
            if (pool1_buffer_count == 8'd143) begin
                pool1_buffer_complete_n = 1'b1;
            end
        end

        // Always capture pool2 outputs when valid
        if (pool2_valid_out && !pool2_complete) begin
            pool2_valid_count_n = pool2_valid_count + 5'd1;
            if (pool2_valid_count == 5'd15) begin
                pool2_complete_n = 1'b1;
            end
        end

        case (state)
            IDLE: begin
                done_o_n = 1'b0;
                if (start_i) begin
                    state_n = LOAD_IMAGE;
                    pixel_count_n = 10'd0;
                    img_wr_pending_n = 1'b0;
                    pool1_buffer_complete_n = 1'b0;
                    pool1_buffer_count_n = 8'd0;
                    pool2_complete_n = 1'b0;
                    pool2_valid_count_n = 5'd0;
                    flatten_complete_n = 1'b0;
                    fc_count_n = 4'd0;
                    conv2_count_n = 6'd0;
                    conv2_feed_x_n = 8'd0;
                    conv2_feed_y_n = 8'd0;
                end
            end

            LOAD_IMAGE: begin
                if (img_wr_pending) begin
                    img_wr_pending_n = 1'b0;
                    if (pixel_count == (IMG_WIDTH * IMG_HEIGHT)) begin
                        state_n = CONV1;
                        conv1_rd_x_n = 5'd0;
                        conv1_rd_y_n = 5'd0;
                    end
                end
                if (pixel_valid_i) begin
                    img_wr_row_n = pixel_row_i;
                    img_wr_col_n = pixel_col_i;
                    img_wr_data_n = pixel_data_i;
                    img_wr_pending_n = 1'b1;
                    pixel_count_n = pixel_count + 10'd1;
                end
            end

            CONV1: begin
                // Advance read pointer when conv1 accepts, hold if busy
                if (conv1_valid_in && !conv1_busy) begin
                    if (conv1_rd_x == IMG_WIDTH - 1) begin
                        conv1_rd_x_n = 5'd0;
                        conv1_rd_y_n = conv1_rd_y + 5'd1;
                    end else begin
                        conv1_rd_x_n = conv1_rd_x + 5'd1;
                    end
                end else if (!conv1_busy && conv1_rd_y < IMG_HEIGHT && conv1_rd_x < IMG_WIDTH) begin
                    conv1_valid_in_n = 1'b1;
                    conv1_valid_in_n = 1'b1;
                    conv1_x_in_n = {4'b0000, conv1_rd_x};
                    conv1_y_in_n = {4'b0000, conv1_rd_y};
                end else begin
                    if (conv1_valid_in && conv1_busy) begin
                        conv1_valid_in_n = conv1_valid_in;
                    end
                    if (pool1_buffer_complete && conv2_ready) begin
                        conv2_count_n = 6'd0;
                        conv2_feed_x_n = 8'd0;
                        conv2_feed_y_n = 8'd0;
                        state_n = CONV2;
                    end
                end
            end

            CONV2: begin
                // Advance read pointer when conv2 accepts, hold if busy
                if (conv2_feed_valid && !conv2_busy) begin
                    if (conv2_feed_x == 8'd11) begin
                        conv2_feed_x_n = 8'd0;
                        conv2_feed_y_n = conv2_feed_y + 8'd1;
                    end else begin
                        conv2_feed_x_n = conv2_feed_x + 8'd1;
                    end
                end else if (!conv2_busy && conv2_feed_y < 8'd12 && conv2_feed_x < 8'd12) begin
                    conv2_feed_valid_n = 1'b1;
                end else begin
                    if (conv2_feed_valid && conv2_busy) begin
                        conv2_feed_valid_n = conv2_feed_valid;
                    end
                end

                if (conv2_valid_out && conv2_count < 6'd63) begin
                    conv2_count_n = conv2_count + 6'd1;
                end

                if (conv2_count >= 6'd63 && pool2_complete) begin
                    state_n = FLATTEN;
                end
            end

            FLATTEN: begin
                if (flatten_valid_out && (flatten_addr_out == 8'd255)) begin
                    flatten_complete_n = 1'b1;
                end
                if (flatten_complete) begin
                    state_n = FC_LAYERS;
                    fc_start_n = 1'b1;
                end
            end

            FC_LAYERS: begin
                if (fc_valid_out) begin
                    fc_count_n = fc_count + 4'd1;
                end
                if (fc_count == NUM_CLASSES) begin
                    max_scan_idx_n = 4'd0;
                    max_scan_class_idx_n = 4'd0;
                    max_scan_val_n = 8'sd0;
                    state_n = FIND_MAX;
                end
            end

            FIND_MAX: begin
                if (max_scan_idx == 4'd0) begin
                    max_scan_idx_n = 4'd1;
                end else if (max_scan_idx < NUM_CLASSES) begin
                    max_scan_idx_n = max_scan_idx + 4'd1;
                end else begin
                    state_n = DONE;
                end
            end

            DONE: begin
                pred_digit_o_n = max_class_idx;
                pred_confidence_o_n = max_class_score;
                if (start_i) begin
                    state_n = LOAD_IMAGE;
                    pixel_count_n = 10'd0;
                    img_wr_pending_n = 1'b0;
                    pool1_buffer_complete_n = 1'b0;
                    pool1_buffer_count_n = 8'd0;
                    pool2_complete_n = 1'b0;
                    pool2_valid_count_n = 5'd0;
                    flatten_complete_n = 1'b0;
                    fc_count_n = 4'd0;
                    conv2_count_n = 6'd0;
                    conv2_feed_x_n = 8'd0;
                    conv2_feed_y_n = 8'd0;
                    done_o_n = 1'b0;
                end else begin
                    done_o_n = 1'b1;
                end
            end

            default: state_n = IDLE;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state <= IDLE;
            done_o <= 1'b0;
            pred_digit_o <= 4'd0;
            pred_confidence_o <= 8'd0;
            pixel_count <= 10'd0;
            conv2_count <= 6'd0;
            fc_count <= 4'd0;
            flatten_complete <= 1'b0;
            pool2_valid_count <= 5'd0;
            conv1_valid_in <= 1'b0;
            conv1_data_in <= 8'd0;
            conv1_x_in <= 9'd0;
            conv1_y_in <= 9'd0;
            fc_start <= 1'b0;
            max_class_idx <= 4'd0;
            max_class_score <= 8'd0;
            max_scan_idx <= 4'd0;
            max_scan_class_idx <= 4'd0;
            max_scan_val <= '0;
            pool1_buffer_count <= 8'd0;
            pool1_buffer_complete <= 1'b0;
            conv2_feed_x <= 8'd0;
            conv2_feed_y <= 8'd0;
            conv2_feed_valid <= 1'b0;
            pool2_complete <= 1'b0;
            conv1_rd_x <= 5'd0;
            conv1_rd_y <= 5'd0;
            img_wr_pending <= 1'b0;
            img_wr_row <= '0;
            img_wr_col <= '0;
            img_wr_data <= '0;

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
            state <= state_n;
            pixel_count <= pixel_count_n;
            conv1_rd_x <= conv1_rd_x_n;
            conv1_rd_y <= conv1_rd_y_n;
            conv2_count <= conv2_count_n;
            fc_count <= fc_count_n;
            conv1_valid_in <= conv1_valid_in_n;
            conv1_x_in <= conv1_x_in_n;
            conv1_y_in <= conv1_y_in_n;
            pool1_buffer_count <= pool1_buffer_count_n;
            pool1_buffer_complete <= pool1_buffer_complete_n;
            conv2_feed_x <= conv2_feed_x_n;
            conv2_feed_y <= conv2_feed_y_n;
            conv2_feed_valid <= conv2_feed_valid_n;
            pool2_valid_count <= pool2_valid_count_n;
            pool2_complete <= pool2_complete_n;
            flatten_complete <= flatten_complete_n;
            fc_start <= fc_start_n;
            max_class_idx <= max_class_idx_n;
            max_class_score <= max_class_score_n;
            max_scan_idx <= max_scan_idx_n;
            max_scan_class_idx <= max_scan_class_idx_n;
            max_scan_val <= max_scan_val_n;
            done_o <= done_o_n;
            pred_digit_o <= pred_digit_o_n;
            pred_confidence_o <= pred_confidence_o_n;
            img_wr_pending <= img_wr_pending_n;
            img_wr_row <= img_wr_row_n;
            img_wr_col <= img_wr_col_n;
            img_wr_data <= img_wr_data_n;

            // Image buffer store (staged one cycle after pixel_valid_i)
            if (img_wr_pending) begin
                image_buffer[img_wr_row][img_wr_col] <= img_wr_data;
            end

            // Conv1 pixel fetch from image buffer
            if ((state == CONV1) && !conv1_busy && (conv1_rd_y < IMG_HEIGHT) && (conv1_rd_x < IMG_WIDTH)) begin
                conv1_data_in <= image_buffer[conv1_rd_y][conv1_rd_x];
            end

            // Pool1 output capture into buffer
            if (pool1_valid_out && !pool1_buffer_complete) begin
                pool1_buffer[0][pool1_y_out][pool1_x_out] <= pool1_data_out[7:0];
                pool1_buffer[1][pool1_y_out][pool1_x_out] <= pool1_data_out[15:8];
                pool1_buffer[2][pool1_y_out][pool1_x_out] <= pool1_data_out[23:16];
                pool1_buffer[3][pool1_y_out][pool1_x_out] <= pool1_data_out[31:24];
                pool1_buffer[4][pool1_y_out][pool1_x_out] <= pool1_data_out[39:32];
                pool1_buffer[5][pool1_y_out][pool1_x_out] <= pool1_data_out[47:40];
            end

            // Sequential argmax over class_scores
            if (state == FIND_MAX) begin
                if (max_scan_idx == 4'd0) begin
                    max_scan_val <= $signed(class_scores[0]);
                    max_scan_class_idx <= 4'd0;
                end else if (max_scan_idx < NUM_CLASSES) begin
                    if ($signed(class_scores[max_scan_idx]) > max_scan_val) begin
                        max_scan_val <= $signed(class_scores[max_scan_idx]);
                        max_scan_class_idx <= max_scan_idx;
                    end
                end else begin
                    max_class_idx <= max_scan_class_idx;
                    max_class_score <= max_scan_val;
                end
            end

            // FC score capture
            if ((state == FC_LAYERS) && fc_valid_out) begin
                class_scores[fc_digit_idx] <= fc_data_out;
            end
        end
    end

endmodule
