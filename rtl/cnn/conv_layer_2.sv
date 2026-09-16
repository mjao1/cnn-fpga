// second convolutional layer
// Input: 6 channels, 12x12 feature maps (output of first pooling layer)
// Output: 16 channels, 8x8 feature maps
// Filter size: 5x5, stride 1

module conv_layer_2 #(
    parameter MAP_WIDTH = 12,     // Input feature map width
    parameter MAP_HEIGHT = 12,    // Input feature map height
    parameter OUT_WIDTH = 8,      // Output feature map width (12-5+1)
    parameter OUT_HEIGHT = 8,     // Output feature map height (12-5+1)
    parameter IN_CHANNELS = 6,    // Number of input channels
    parameter OUT_CHANNELS = 16,  // Number of filters in second layer of LeNet-5
    parameter KERNEL_SIZE = 5,    // Kernel size (5x5)
    parameter DATA_WIDTH = 8,     // Data width (8-bit fixed point)
    parameter FRAC_BITS = 7       // Q1.7 format
)(
    input  logic                                 clk_i,
    input  logic                                 rst_i,
    input  logic                                 valid_i,
    input  logic [(DATA_WIDTH*IN_CHANNELS)-1:0]  data_i,
    input  logic [7:0]                           x_i,
    input  logic [7:0]                           y_i,
    output logic                                 valid_o,
    output logic [(DATA_WIDTH*OUT_CHANNELS)-1:0] data_o,
    output logic [7:0]                           x_o,
    output logic [7:0]                           y_o,
    output logic                                 ready_o,
    output logic                                 busy_o
);

    localparam MEM_F_W = $clog2(OUT_CHANNELS);
    localparam MEM_C_W = $clog2(IN_CHANNELS);
    localparam MEM_K_W = $clog2(KERNEL_SIZE);

    typedef enum logic [2:0] {
        INIT              = 3'b000,
        LOAD_WEIGHTS_ADDR = 3'b001,  // Set address, wait for BRAM
        LOAD_WEIGHTS_DATA = 3'b010,  // Store data, advance to next
        LOAD_BIAS_ADDR    = 3'b011,  // Set bias address
        LOAD_BIAS_DATA    = 3'b100,  // Store bias
        RUNNING           = 3'b101
    } state_t;

    logic [DATA_WIDTH-1:0] line_buffer [0:IN_CHANNELS-1][0:KERNEL_SIZE-1][0:MAP_WIDTH-1];
    logic [DATA_WIDTH-1:0] window [0:IN_CHANNELS-1][0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    logic signed [DATA_WIDTH-1:0] weight [0:OUT_CHANNELS-1][0:IN_CHANNELS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    logic signed [DATA_WIDTH-1:0] bias [0:OUT_CHANNELS-1];
    logic [2:0] wr_row_idx;
    logic serial_busy;
    logic serial_busy_d;
    logic [5:0] ser_step;
    state_t state;
    logic [7:0] current_filter;
    logic [7:0] current_channel;
    logic [7:0] current_kernel;
    logic signed [DATA_WIDTH-1:0] loaded_weight_q;
    logic signed [DATA_WIDTH-1:0] loaded_bias_q;
    logic [7:0] write_filter_q, write_channel_q, write_kernel_q;
    logic write_we_q;
    logic write_bias_we_q;
    (* max_fanout = 48 *) logic conv_start_q;
    (* max_fanout = 48 *) logic signed [DATA_WIDTH-1:0] conv_din_q [0:IN_CHANNELS-1];
    (* max_fanout = 48 *) logic signed [DATA_WIDTH-1:0] conv_w_in_q [0:OUT_CHANNELS-1][0:IN_CHANNELS-1];
    logic conv_valid_d1 [0:OUT_CHANNELS-1];
    logic conv_valid_d2 [0:OUT_CHANNELS-1];
    logic signed [24:0] acc_pair01 [0:OUT_CHANNELS-1];
    logic signed [24:0] acc_pair23 [0:OUT_CHANNELS-1];
    logic signed [24:0] acc_pair45 [0:OUT_CHANNELS-1];
    logic signed [DATA_WIDTH-1:0] relu_din_r [0:OUT_CHANNELS-1];
    logic relu_go [0:OUT_CHANNELS-1];

    logic [2:0] wr_row_idx_n;
    logic serial_busy_n;
    logic [5:0] ser_step_n;
    state_t state_n;
    logic [7:0] current_filter_n;
    logic [7:0] current_channel_n;
    logic [7:0] current_kernel_n;
    logic valid_o_n;
    logic [(DATA_WIDTH*OUT_CHANNELS)-1:0] data_o_n;
    logic [7:0] x_o_n;
    logic [7:0] y_o_n;
    logic [2:0] row_idx_m1;
    logic [2:0] row_idx_m2;
    logic [2:0] row_idx_m3;
    logic [2:0] row_idx_m4;
    logic [7:0] weight_kernel_row;
    logic [7:0] weight_kernel_col;
    logic signed [DATA_WIDTH-1:0] loaded_weight;
    logic signed [DATA_WIDTH-1:0] loaded_bias;
    logic [DATA_WIDTH-1:0] data_in_channel [0:IN_CHANNELS-1];
    logic conv_start;
    logic signed [DATA_WIDTH-1:0] conv_din [0:IN_CHANNELS-1];
    logic signed [DATA_WIDTH-1:0] conv_w_in [0:OUT_CHANNELS-1][0:IN_CHANNELS-1];
    logic signed [DATA_WIDTH-1:0] window_flat [0:IN_CHANNELS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    logic [IN_CHANNELS-1:0] conv_valid [0:OUT_CHANNELS-1];
    logic conv_done [0:OUT_CHANNELS-1];
    logic signed [DATA_WIDTH-1:0] conv_result [0:OUT_CHANNELS-1][0:IN_CHANNELS-1];
    logic signed [23:0] conv_raw_sum [0:OUT_CHANNELS-1][0:IN_CHANNELS-1];
    logic signed [26:0] bias_ext [0:OUT_CHANNELS-1];
    logic signed [26:0] acc_sum3 [0:OUT_CHANNELS-1];
    logic signed [26:0] scaled_relu_in [0:OUT_CHANNELS-1];
    logic signed [7:0] saturated [0:OUT_CHANNELS-1];
    logic relu_valid_out [0:OUT_CHANNELS-1];
    logic [DATA_WIDTH-1:0] relu_out [0:OUT_CHANNELS-1];
    logic [(DATA_WIDTH*OUT_CHANNELS)-1:0] relu_out_packed;
    logic lb_we;
    logic window_form;
    logic window_form_initial;

    integer ii, jj, kk, pi, pj;

    assign busy_o = serial_busy;
    assign ready_o = (state == RUNNING);
    assign weight_kernel_row = current_kernel / KERNEL_SIZE;
    assign weight_kernel_col = current_kernel % KERNEL_SIZE;
    assign conv_start = serial_busy & ~serial_busy_d;
    assign lb_we = valid_i && !serial_busy;
    assign window_form = lb_we && (y_i >= KERNEL_SIZE-1) && (x_i >= KERNEL_SIZE-1);
    assign window_form_initial = window_form && (x_i == KERNEL_SIZE-1);

    // Circular 5-row line buffer mapping onto 5x5 window
    always_comb begin
        case (wr_row_idx)
            3'd0: begin
                row_idx_m1 = 3'd4;
                row_idx_m2 = 3'd3;
                row_idx_m3 = 3'd2;
                row_idx_m4 = 3'd1;
            end
            3'd1: begin
                row_idx_m1 = 3'd0;
                row_idx_m2 = 3'd4;
                row_idx_m3 = 3'd3;
                row_idx_m4 = 3'd2;
            end
            3'd2: begin
                row_idx_m1 = 3'd1;
                row_idx_m2 = 3'd0;
                row_idx_m3 = 3'd4;
                row_idx_m4 = 3'd3;
            end
            3'd3: begin
                row_idx_m1 = 3'd2;
                row_idx_m2 = 3'd1;
                row_idx_m3 = 3'd0;
                row_idx_m4 = 3'd4;
            end
            default: begin
                row_idx_m1 = 3'd3;
                row_idx_m2 = 3'd2;
                row_idx_m3 = 3'd1;
                row_idx_m4 = 3'd0;
            end
        endcase
    end

    // Unpack input channels
    generate
        genvar c;
        for (c = 0; c < IN_CHANNELS; c = c + 1) begin : unpack_inputs
            assign data_in_channel[c] = data_i[((c+1)*DATA_WIDTH)-1:c*DATA_WIDTH];
        end
    endgenerate

    conv2_weight_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FILTERS(OUT_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .IN_CHANNELS(IN_CHANNELS)
    ) conv2_weights (
        .clk(clk_i),
        .rst(rst_i),
        .filter_idx(current_filter[MEM_F_W-1:0]),
        .in_channel(current_channel[MEM_C_W-1:0]),
        .kernel_row(weight_kernel_row[MEM_K_W-1:0]),
        .kernel_col(weight_kernel_col[MEM_K_W-1:0]),
        .weight_out(loaded_weight)
    );

    conv2_bias_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FILTERS(OUT_CHANNELS)
    ) conv2_biases (
        .clk(clk_i),
        .rst(rst_i),
        .filter_idx(current_filter[MEM_F_W-1:0]),
        .bias_out(loaded_bias)
    );

    // Flatten 2D windows
    generate
        genvar ci, gi, gj;
        for (ci = 0; ci < IN_CHANNELS; ci = ci + 1) begin
            for (gi = 0; gi < KERNEL_SIZE; gi = gi + 1) begin
                for (gj = 0; gj < KERNEL_SIZE; gj = gj + 1) begin
                    assign window_flat[ci][gi*KERNEL_SIZE + gj] = window[ci][gi][gj];
                end
            end
        end
    endgenerate

    generate
        genvar ldci;
        for (ldci = 0; ldci < IN_CHANNELS; ldci = ldci + 1) begin : din_mux
            assign conv_din[ldci] = (serial_busy & ser_step >= 6'd1 & ser_step <= 6'd25) ? window_flat[ldci][ser_step - 6'd1] : 8'sd0;
        end
    endgenerate

    generate
        genvar wf, wc;
        for (wf = 0; wf < OUT_CHANNELS; wf = wf + 1) begin : w_row
            for (wc = 0; wc < IN_CHANNELS; wc = wc + 1) begin : w_col
                assign conv_w_in[wf][wc] = (serial_busy & ser_step >= 6'd1 & ser_step <= 6'd25) ? weight[wf][wc][ser_step - 6'd1] : (serial_busy & (ser_step == 6'd26)) ? 8'd0 : 8'sd0;
            end
        end
    endgenerate

    // Instantiate 6 convolution modules for each filter
    generate
        genvar f, chan;
        for (f = 0; f < OUT_CHANNELS; f = f + 1) begin: filter_units
            for (chan = 0; chan < IN_CHANNELS; chan = chan + 1) begin: channel_convs
                conv_5x5 #(
                    .FRAC_BITS(FRAC_BITS)
                ) conv_inst (
                    .clk_i(clk_i),
                    .rst_i(rst_i),
                    .start_i(conv_start_q),
                    .data_i(conv_din_q[chan]),
                    .weight_i(conv_w_in_q[f][chan]),
                    .done_o(conv_valid[f][chan]),
                    .data_o(conv_result[f][chan]),
                    .raw_sum_o(conv_raw_sum[f][chan])
                );
            end

            assign conv_done[f] = conv_valid[f][0];

            assign bias_ext[f] = $signed({{19{bias[f][7]}}, bias[f]}) << FRAC_BITS;
            assign acc_sum3[f] = $signed(acc_pair01[f]) + $signed(acc_pair23[f]) + $signed(acc_pair45[f]) + bias_ext[f];
            assign scaled_relu_in[f] = acc_sum3[f] >>> FRAC_BITS;
            assign saturated[f] = (scaled_relu_in[f] > 27'sd127) ? 8'sd127 :
                                  (scaled_relu_in[f] < -27'sd128) ? -8'sd128 :
                                  scaled_relu_in[f][7:0];

            relu relu_inst (
                .clk(clk_i),
                .rst(rst_i),
                .valid_in(relu_go[f]),
                .data_in(relu_din_r[f]),
                .valid_out(relu_valid_out[f]),
                .data_out(relu_out[f])
            );

            assign relu_out_packed[((f+1)*DATA_WIDTH)-1 -: DATA_WIDTH] = relu_out[f];
        end
    endgenerate

    // Weight loading state machine
    always_comb begin
        state_n = state;
        current_filter_n = current_filter;
        current_channel_n = current_channel;
        current_kernel_n = current_kernel;

        case (state)
            INIT: begin
                // Start loading, address is set by current_filter/current_kernel
                state_n = LOAD_WEIGHTS_ADDR;
                current_filter_n = 8'd0;
                current_channel_n = 8'd0;
                current_kernel_n = 8'd0;
            end

            LOAD_WEIGHTS_ADDR: begin
                // Address is set, wait one cycle for BRAM to output data
                state_n = LOAD_WEIGHTS_DATA;
            end

            LOAD_WEIGHTS_DATA: begin
                // BRAM output is valid, advance to next weight
                if (current_kernel == KERNEL_SIZE*KERNEL_SIZE-1) begin
                    current_kernel_n = 8'd0;

                    if (current_channel == IN_CHANNELS-1) begin
                        current_channel_n = 8'd0;
                        state_n = LOAD_BIAS_ADDR;
                    end else begin
                        current_channel_n = current_channel + 8'd1;
                        state_n = LOAD_WEIGHTS_ADDR;
                    end
                end else begin
                    current_kernel_n = current_kernel + 8'd1;
                    state_n = LOAD_WEIGHTS_ADDR;
                end
            end

            LOAD_BIAS_ADDR: begin
                // Wait for bias BRAM output
                state_n = LOAD_BIAS_DATA;
            end

            LOAD_BIAS_DATA: begin
                // Move to next filter
                if (current_filter == OUT_CHANNELS-1) begin
                    state_n = RUNNING;
                end else begin
                    current_filter_n = current_filter + 8'd1;
                    current_channel_n = 8'd0;
                    current_kernel_n = 8'd0;
                    state_n = LOAD_WEIGHTS_ADDR;
                end
            end

            RUNNING: begin

            end

            default: state_n = INIT;
        endcase
    end

    // Serial MAC control and output pixel coordinates next state
    always_comb begin
        serial_busy_n = serial_busy;
        ser_step_n = ser_step;
        wr_row_idx_n = wr_row_idx;
        valid_o_n = 1'b0;
        data_o_n = data_o;
        x_o_n = x_o;
        y_o_n = y_o;

        if (serial_busy) begin
            if (ser_step == 6'd28) begin
                serial_busy_n = 1'b0;
                ser_step_n = 6'd0;
            end else
                ser_step_n = ser_step + 6'd1;
        end

        if (valid_o) begin
            if (x_o == OUT_WIDTH-1) begin
                x_o_n = 8'd0;
                if (y_o == OUT_HEIGHT-1)
                    y_o_n = 8'd0;
                else
                    y_o_n = y_o + 8'd1;
            end else begin
                x_o_n = x_o + 8'd1;
            end
        end

        if (window_form && (state == RUNNING)) begin
            serial_busy_n = 1'b1;
            ser_step_n = 6'd0;
        end

        if (lb_we && (x_i == MAP_WIDTH-1)) begin
            if (wr_row_idx == KERNEL_SIZE-1)
                wr_row_idx_n = 3'd0;
            else
                wr_row_idx_n = wr_row_idx + 3'd1;
        end

        if (relu_valid_out[0]) begin
            valid_o_n = 1'b1;
            data_o_n = relu_out_packed;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state <= INIT;
            current_filter <= 8'd0;
            current_channel <= 8'd0;
            current_kernel <= 8'd0;
            loaded_weight_q <= 8'sd0;
            loaded_bias_q <= 8'sd0;
            write_filter_q <= 8'd0;
            write_channel_q <= 8'd0;
            write_kernel_q <= 8'd0;
            write_we_q <= 1'b0;
            write_bias_we_q <= 1'b0;
            serial_busy <= 1'b0;
            serial_busy_d <= 1'b0;
            ser_step <= 6'd0;
            wr_row_idx <= 3'd0;
            valid_o <= 1'b0;
            x_o <= 8'd0;
            y_o <= 8'd0;
            data_o <= {(DATA_WIDTH*OUT_CHANNELS){1'b0}};
            conv_start_q <= 1'b0;
            for (pi = 0; pi < IN_CHANNELS; pi = pi + 1) begin
                conv_din_q[pi] <= 8'sd0;
            end
            for (pi = 0; pi < OUT_CHANNELS; pi = pi + 1) begin
                for (pj = 0; pj < IN_CHANNELS; pj = pj + 1) begin
                    conv_w_in_q[pi][pj] <= 8'sd0;
                end
            end
            for (ii = 0; ii < OUT_CHANNELS; ii = ii + 1) begin
                bias[ii] <= 8'd0;
                conv_valid_d1[ii] <= 1'b0;
                conv_valid_d2[ii] <= 1'b0;
                relu_go[ii] <= 1'b0;
                relu_din_r[ii] <= 8'sd0;
                acc_pair01[ii] <= 25'sd0;
                acc_pair23[ii] <= 25'sd0;
                acc_pair45[ii] <= 25'sd0;
                for (jj = 0; jj < IN_CHANNELS; jj = jj + 1) begin
                    for (kk = 0; kk < KERNEL_SIZE*KERNEL_SIZE; kk = kk + 1) begin
                        weight[ii][jj][kk] <= 8'd0;
                    end
                end
            end
            // Initialize buffers and filter outputs
            for (ii = 0; ii < IN_CHANNELS; ii = ii + 1) begin
                for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                    for (kk = 0; kk < MAP_WIDTH; kk = kk + 1) begin
                        line_buffer[ii][jj][kk] <= 8'd0;
                    end
                end
            end
            for (ii = 0; ii < IN_CHANNELS; ii = ii + 1) begin
                for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                    for (kk = 0; kk < KERNEL_SIZE; kk = kk + 1) begin
                        window[ii][jj][kk] <= 8'd0;
                    end
                end
            end
        end else begin
            state <= state_n;
            current_filter <= current_filter_n;
            current_channel <= current_channel_n;
            current_kernel <= current_kernel_n;
            loaded_weight_q <= loaded_weight;
            loaded_bias_q <= loaded_bias;
            write_filter_q <= current_filter;
            write_channel_q <= current_channel;
            write_kernel_q <= current_kernel;
            write_we_q <= (state == LOAD_WEIGHTS_DATA);
            write_bias_we_q <= (state == LOAD_BIAS_DATA);
            serial_busy <= serial_busy_n;
            serial_busy_d <= serial_busy;
            ser_step <= ser_step_n;
            wr_row_idx <= wr_row_idx_n;
            valid_o <= valid_o_n;
            data_o <= data_o_n;
            x_o <= x_o_n;
            y_o <= y_o_n;
            conv_start_q <= conv_start;
            for (pi = 0; pi < IN_CHANNELS; pi = pi + 1) begin
                conv_din_q[pi] <= conv_din[pi];
            end
            for (pi = 0; pi < OUT_CHANNELS; pi = pi + 1) begin
                for (pj = 0; pj < IN_CHANNELS; pj = pj + 1) begin
                    conv_w_in_q[pi][pj] <= conv_w_in[pi][pj];
                end
            end

            // Weight/bias storage writes
            if (write_we_q) begin
                weight[write_filter_q][write_channel_q][write_kernel_q] <= loaded_weight_q;
            end
            if (write_bias_we_q) begin
                bias[write_filter_q] <= loaded_bias_q;
            end

            // Filter multichannel accumulate and ReLU input pipeline
            for (ii = 0; ii < OUT_CHANNELS; ii = ii + 1) begin
                conv_valid_d1[ii] <= conv_done[ii];
                conv_valid_d2[ii] <= conv_valid_d1[ii];
                relu_go[ii] <= conv_valid_d2[ii];
                if (conv_done[ii]) begin
                    acc_pair01[ii] <= conv_raw_sum[ii][0] + conv_raw_sum[ii][1];
                    acc_pair23[ii] <= conv_raw_sum[ii][2] + conv_raw_sum[ii][3];
                    acc_pair45[ii] <= conv_raw_sum[ii][4] + conv_raw_sum[ii][5];
                end
                if (conv_valid_d1[ii]) begin
                    relu_din_r[ii] <= saturated[ii];
                end
            end

            // Line buffer write
            if (lb_we) begin
                for (ii = 0; ii < IN_CHANNELS; ii = ii + 1) begin
                    line_buffer[ii][wr_row_idx][x_i] <= data_in_channel[ii];
                end
            end

            // Sliding window update
            if (window_form_initial) begin
                for (ii = 0; ii < IN_CHANNELS; ii = ii + 1) begin
                    for (kk = 0; kk < KERNEL_SIZE; kk = kk + 1) begin
                        window[ii][0][kk] <= line_buffer[ii][row_idx_m4][kk];
                        window[ii][1][kk] <= line_buffer[ii][row_idx_m3][kk];
                        window[ii][2][kk] <= line_buffer[ii][row_idx_m2][kk];
                        window[ii][3][kk] <= line_buffer[ii][row_idx_m1][kk];
                    end
                    window[ii][4][0] <= line_buffer[ii][wr_row_idx][0];
                    window[ii][4][1] <= line_buffer[ii][wr_row_idx][1];
                    window[ii][4][2] <= line_buffer[ii][wr_row_idx][2];
                    window[ii][4][3] <= line_buffer[ii][wr_row_idx][3];
                    window[ii][4][4] <= data_in_channel[ii];
                end
            end else if (window_form) begin
                for (ii = 0; ii < IN_CHANNELS; ii = ii + 1) begin
                    for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                        for (kk = 0; kk < KERNEL_SIZE-1; kk = kk + 1) begin
                            window[ii][jj][kk] <= window[ii][jj][kk+1];
                        end
                    end
                    window[ii][0][KERNEL_SIZE-1] <= line_buffer[ii][row_idx_m4][x_i];
                    window[ii][1][KERNEL_SIZE-1] <= line_buffer[ii][row_idx_m3][x_i];
                    window[ii][2][KERNEL_SIZE-1] <= line_buffer[ii][row_idx_m2][x_i];
                    window[ii][3][KERNEL_SIZE-1] <= line_buffer[ii][row_idx_m1][x_i];
                    window[ii][4][KERNEL_SIZE-1] <= data_in_channel[ii];
                end
            end
        end
    end

endmodule
