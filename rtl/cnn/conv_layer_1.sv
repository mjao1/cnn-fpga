// first convolutional layer
// Input: 1 channel, 28x28 image
// Output: 6 channels, 24x24 feature maps
// Filter size: 5x5, stride 1

module conv_layer_1 #(
    parameter IMG_WIDTH = 28,     // Input image width
    parameter IMG_HEIGHT = 28,    // Input image height
    parameter OUT_WIDTH = 24,     // Output feature map width (28-5+1)
    parameter OUT_HEIGHT = 24,    // Output feature map height (28-5+1)
    parameter NUM_FILTERS = 6,    // Number of filters in first layer of LeNet-5
    parameter KERNEL_SIZE = 5,    // Kernel size (5x5)
    parameter DATA_WIDTH = 8,     // Data width (8-bit fixed point)
    parameter FRAC_BITS = 7       // Q1.7 format
)(
    input  logic                  clk_i,
    input  logic                  rst_i,
    input  logic                  valid_i,
    input  logic [DATA_WIDTH-1:0] data_i,
    input  logic [8:0]            x_i,
    input  logic [8:0]            y_i,
    output logic                  valid_o,
    output logic [DATA_WIDTH-1:0] data_0_o,
    output logic [DATA_WIDTH-1:0] data_1_o,
    output logic [DATA_WIDTH-1:0] data_2_o,
    output logic [DATA_WIDTH-1:0] data_3_o,
    output logic [DATA_WIDTH-1:0] data_4_o,
    output logic [DATA_WIDTH-1:0] data_5_o,
    output logic [8:0]            x_o,
    output logic [8:0]            y_o,
    output logic                  busy_o
);

    localparam MEM_F_W = $clog2(NUM_FILTERS);
    localparam MEM_K_W = $clog2(KERNEL_SIZE);

    typedef enum logic [2:0] {
        INIT              = 3'b000,
        LOAD_WEIGHTS_ADDR = 3'b001,  // Set address, wait for BRAM
        LOAD_WEIGHTS_DATA = 3'b010,  // Store data, advance to next
        LOAD_BIAS_ADDR    = 3'b011,  // Set bias address
        LOAD_BIAS_DATA    = 3'b100,  // Store bias
        RUNNING           = 3'b101
    } state_t;

    logic [DATA_WIDTH-1:0] line_buffer [0:KERNEL_SIZE-1][0:IMG_WIDTH-1];
    logic [DATA_WIDTH-1:0] window [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    logic signed [DATA_WIDTH-1:0] weight [0:NUM_FILTERS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    logic signed [DATA_WIDTH-1:0] bias [0:NUM_FILTERS-1];
    logic serial_busy;
    logic serial_busy_d;
    logic [2:0] wr_row_idx;
    logic [5:0] ser_step;
    state_t state;
    logic [7:0] current_filter;
    logic [7:0] current_kernel;
    (* max_fanout = 48 *) logic conv_start_q;
    (* max_fanout = 48 *) logic signed [DATA_WIDTH-1:0] conv_data_in_q;
    (* max_fanout = 48 *) logic signed [DATA_WIDTH-1:0] conv_weight_in_q [0:NUM_FILTERS-1];

    logic serial_busy_n;
    logic [5:0] ser_step_n;
    logic [2:0] wr_row_idx_n;
    state_t state_n;
    logic [7:0] current_filter_n;
    logic [7:0] current_kernel_n;
    logic valid_o_n;
    logic [DATA_WIDTH-1:0] data_0_o_n;
    logic [DATA_WIDTH-1:0] data_1_o_n;
    logic [DATA_WIDTH-1:0] data_2_o_n;
    logic [DATA_WIDTH-1:0] data_3_o_n;
    logic [DATA_WIDTH-1:0] data_4_o_n;
    logic [DATA_WIDTH-1:0] data_5_o_n;
    logic [8:0] x_o_n;
    logic [8:0] y_o_n;
    logic [2:0] row_idx_m1;
    logic [2:0] row_idx_m2;
    logic [2:0] row_idx_m3;
    logic [2:0] row_idx_m4;
    logic [7:0] weight_kernel_row;
    logic [7:0] weight_kernel_col;
    logic signed [DATA_WIDTH-1:0] loaded_weight;
    logic signed [DATA_WIDTH-1:0] loaded_bias;
    logic valid_conv [0:NUM_FILTERS-1];
    logic signed [DATA_WIDTH-1:0] conv_out [0:NUM_FILTERS-1];
    logic signed [DATA_WIDTH-1:0] window_flat [0:KERNEL_SIZE*KERNEL_SIZE-1];
    logic conv_start;
    logic signed [DATA_WIDTH-1:0] conv_data_in;
    logic signed [DATA_WIDTH-1:0] conv_weight_in [0:NUM_FILTERS-1];
    logic [7:0] relu_out [0:NUM_FILTERS-1];
    logic relu_valid [0:NUM_FILTERS-1];
    logic window_form;
    logic window_form_initial;

    integer ii, jj, pi;

    assign busy_o = serial_busy;
    assign weight_kernel_row = current_kernel / KERNEL_SIZE;
    assign weight_kernel_col = current_kernel % KERNEL_SIZE;
    assign conv_start = serial_busy & ~serial_busy_d;
    assign conv_data_in = (serial_busy & ser_step >= 6'd1 & ser_step <= 6'd25) ? window_flat[ser_step - 6'd1] : 8'sd0;
    assign window_form = valid_i && !serial_busy && (y_i >= KERNEL_SIZE-1) && (x_i >= KERNEL_SIZE-1);
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

    conv1_weight_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FILTERS(NUM_FILTERS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .IN_CHANNELS(1)
    ) conv1_weights (
        .clk(clk_i),
        .rst(rst_i),
        .filter_idx(current_filter[MEM_F_W-1:0]),
        .in_channel(1'b0),
        .kernel_row(weight_kernel_row[MEM_K_W-1:0]),
        .kernel_col(weight_kernel_col[MEM_K_W-1:0]),
        .weight_out(loaded_weight)
    );

    conv1_bias_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FILTERS(NUM_FILTERS)
    ) conv1_biases (
        .clk(clk_i),
        .rst(rst_i),
        .filter_idx(current_filter[MEM_F_W-1:0]),
        .bias_out(loaded_bias)
    );

    // Flatten 2D window
    generate
        genvar gi, gj;
        for (gi = 0; gi < KERNEL_SIZE; gi = gi + 1) begin
            for (gj = 0; gj < KERNEL_SIZE; gj = gj + 1) begin
                assign window_flat[gi*KERNEL_SIZE + gj] = window[gi][gj];
            end
        end
    endgenerate

    generate
        genvar gwf;
        for (gwf = 0; gwf < NUM_FILTERS; gwf = gwf + 1) begin : wt_mux
            assign conv_weight_in[gwf] = (serial_busy & ser_step >= 6'd1 & ser_step <= 6'd25) ? weight[gwf][ser_step - 6'd1] : (serial_busy & (ser_step == 6'd26)) ? bias[gwf] : 8'sd0;
        end
    endgenerate

    // Instantiate 6 convolution modules for each filter
    generate
        genvar gf;
        for (gf = 0; gf < NUM_FILTERS; gf = gf + 1) begin : conv_units
            conv_5x5 #(
                .FRAC_BITS(FRAC_BITS)
            ) conv_inst (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .start_i(conv_start_q),
                .data_i(conv_data_in_q),
                .weight_i(conv_weight_in_q[gf]),

                .done_o(valid_conv[gf]),
                .data_o(conv_out[gf]),
                .raw_sum_o()
            );
        end
    endgenerate

    generate
        genvar i;
        for(i = 0; i < NUM_FILTERS; i = i + 1) begin: relu_inst_block
            relu u_relu (
                .clk(clk_i),
                .rst(rst_i),
                .valid_in(valid_conv[i]),
                .data_in(conv_out[i]),
                .valid_out(relu_valid[i]),
                .data_out(relu_out[i])
            );
        end
    endgenerate

    // Weight loading state machine
    always_comb begin
        state_n = state;
        current_filter_n = current_filter;
        current_kernel_n = current_kernel;

        case (state)
            INIT: begin
                // Start loading, address is set by current_filter/current_kernel
                state_n = LOAD_WEIGHTS_ADDR;
                current_filter_n = 8'd0;
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
                    state_n = LOAD_BIAS_ADDR;
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
                if (current_filter == NUM_FILTERS-1) begin
                    state_n = RUNNING;
                end else begin
                    current_filter_n = current_filter + 8'd1;
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
        valid_o_n = (state == RUNNING) && relu_valid[0];
        data_0_o_n = data_0_o;
        data_1_o_n = data_1_o;
        data_2_o_n = data_2_o;
        data_3_o_n = data_3_o;
        data_4_o_n = data_4_o;
        data_5_o_n = data_5_o;
        x_o_n = x_o;
        y_o_n = y_o;

        if (serial_busy) begin
            if (ser_step == 6'd28) begin
                serial_busy_n = 1'b0;
                ser_step_n = 6'd0;
            end else begin
                ser_step_n = ser_step + 6'd1;
            end
        end

        if (valid_o) begin
            if (x_o == OUT_WIDTH - 1) begin
                x_o_n = 9'd0;
                if (y_o == OUT_HEIGHT - 1) begin
                    y_o_n = 9'd0;
                end else begin
                    y_o_n = y_o + 9'd1;
                end
            end else begin
                x_o_n = x_o + 9'd1;
            end
        end

        if ((state == RUNNING) && relu_valid[0]) begin
            data_0_o_n = relu_out[0];
            data_1_o_n = relu_out[1];
            data_2_o_n = relu_out[2];
            data_3_o_n = relu_out[3];
            data_4_o_n = relu_out[4];
            data_5_o_n = relu_out[5];
        end

        if (valid_i && (x_i == IMG_WIDTH - 1)) begin
            if (wr_row_idx == KERNEL_SIZE-1) begin
                wr_row_idx_n = 3'd0;
            end else begin
                wr_row_idx_n = wr_row_idx + 3'd1;
            end
        end

        if (window_form) begin
            serial_busy_n = 1'b1;
            ser_step_n = 6'd0;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state <= INIT;
            current_filter <= 8'd0;
            current_kernel <= 8'd0;
            serial_busy <= 1'b0;
            serial_busy_d <= 1'b0;
            ser_step <= 6'd0;
            wr_row_idx <= 3'd0;
            valid_o <= 1'b0;
            x_o <= 9'd0;
            y_o <= 9'd0;
            data_0_o <= 8'd0;
            data_1_o <= 8'd0;
            data_2_o <= 8'd0;
            data_3_o <= 8'd0;
            data_4_o <= 8'd0;
            data_5_o <= 8'd0;
            conv_start_q <= 1'b0;
            conv_data_in_q <= 8'sd0;
            for (pi = 0; pi < NUM_FILTERS; pi = pi + 1) begin
                conv_weight_in_q[pi] <= 8'sd0;
            end
            for (ii = 0; ii < NUM_FILTERS; ii = ii + 1) begin
                bias[ii] <= 8'd0;
                for (jj = 0; jj < KERNEL_SIZE*KERNEL_SIZE; jj = jj + 1) begin
                    weight[ii][jj] <= 8'd0;
                end
            end
            // Initialize buffers and filter outputs
            for (ii = 0; ii < KERNEL_SIZE; ii = ii + 1) begin
                for (jj = 0; jj < IMG_WIDTH; jj = jj + 1) begin
                    line_buffer[ii][jj] <= 8'd0;
                end
            end
            for (ii = 0; ii < KERNEL_SIZE; ii = ii + 1) begin
                for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                    window[ii][jj] <= 8'd0;
                end
            end
        end else begin
            state <= state_n;
            current_filter <= current_filter_n;
            current_kernel <= current_kernel_n;
            serial_busy <= serial_busy_n;
            serial_busy_d <= serial_busy;
            ser_step <= ser_step_n;
            wr_row_idx <= wr_row_idx_n;
            valid_o <= valid_o_n;
            data_0_o <= data_0_o_n;
            data_1_o <= data_1_o_n;
            data_2_o <= data_2_o_n;
            data_3_o <= data_3_o_n;
            data_4_o <= data_4_o_n;
            data_5_o <= data_5_o_n;
            x_o <= x_o_n;
            y_o <= y_o_n;
            conv_start_q <= conv_start;
            conv_data_in_q <= conv_data_in;
            for (pi = 0; pi < NUM_FILTERS; pi = pi + 1) begin
                conv_weight_in_q[pi] <= conv_weight_in[pi];
            end

            // Weight/bias storage writes
            if (state == LOAD_WEIGHTS_DATA) begin
                weight[current_filter][current_kernel] <= loaded_weight;
            end
            if (state == LOAD_BIAS_DATA) begin
                bias[current_filter] <= loaded_bias;
            end

            // Line buffer write
            if (valid_i) begin
                line_buffer[wr_row_idx][x_i] <= data_i;
            end

            // Sliding window update
            if (window_form_initial) begin
                for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                    window[0][jj] <= line_buffer[row_idx_m4][jj];
                    window[1][jj] <= line_buffer[row_idx_m3][jj];
                    window[2][jj] <= line_buffer[row_idx_m2][jj];
                    window[3][jj] <= line_buffer[row_idx_m1][jj];
                end
                window[4][0] <= line_buffer[wr_row_idx][0];
                window[4][1] <= line_buffer[wr_row_idx][1];
                window[4][2] <= line_buffer[wr_row_idx][2];
                window[4][3] <= line_buffer[wr_row_idx][3];
                window[4][4] <= data_i;
            end else if (window_form) begin
                for (ii = 0; ii < KERNEL_SIZE; ii = ii + 1) begin
                    for (jj = 0; jj < KERNEL_SIZE-1; jj = jj + 1) begin
                        window[ii][jj] <= window[ii][jj+1];
                    end
                end
                window[0][KERNEL_SIZE-1] <= line_buffer[row_idx_m4][x_i];
                window[1][KERNEL_SIZE-1] <= line_buffer[row_idx_m3][x_i];
                window[2][KERNEL_SIZE-1] <= line_buffer[row_idx_m2][x_i];
                window[3][KERNEL_SIZE-1] <= line_buffer[row_idx_m1][x_i];
                window[4][KERNEL_SIZE-1] <= data_i;
            end
        end
    end

endmodule
