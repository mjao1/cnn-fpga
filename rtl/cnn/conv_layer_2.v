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
    input wire clk,
    input wire rst,
    input wire valid_in,                         // Input valid signal
    input wire [(DATA_WIDTH*IN_CHANNELS)-1:0] data_in, // 6 parallel input channels
    input wire [7:0] x_in,                       // X coordinate of current input pixel
    input wire [7:0] y_in,                       // Y coordinate of current input pixel
    output reg valid_out,                        // Output valid signal
    output reg [(DATA_WIDTH*OUT_CHANNELS)-1:0] data_out, // 16 parallel output channels
    output reg [7:0] x_out,                      // X coordinate of output pixel
    output reg [7:0] y_out,                      // Y coordinate of output pixel
    output wire ready,                           // Ready signal (weight loading complete)
    output wire busy
);

    localparam MEM_F_W = $clog2(OUT_CHANNELS);
    localparam MEM_C_W = $clog2(IN_CHANNELS);
    localparam MEM_K_W = $clog2(KERNEL_SIZE);

    reg [DATA_WIDTH-1:0] line_buffer [0:IN_CHANNELS-1][0:KERNEL_SIZE-1][0:MAP_WIDTH-1];
    reg [DATA_WIDTH-1:0] window [0:IN_CHANNELS-1][0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    
    reg signed [DATA_WIDTH-1:0] weight [0:OUT_CHANNELS-1][0:IN_CHANNELS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    reg signed [DATA_WIDTH-1:0] bias [0:OUT_CHANNELS-1];
    
    reg conv_window_valid;
    reg [2:0] wr_row_idx;
    reg [2:0] row_idx_m1;
    reg [2:0] row_idx_m2;
    reg [2:0] row_idx_m3;
    reg [2:0] row_idx_m4;

    always @(*) begin
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

    assign busy = conv_window_valid;

    wire valid_conv [0:OUT_CHANNELS-1];
    wire signed [DATA_WIDTH-1:0] conv_out [0:OUT_CHANNELS-1];
    
    wire relu_valid_out [0:OUT_CHANNELS-1];
    wire [DATA_WIDTH-1:0] relu_out [0:OUT_CHANNELS-1];
    
    wire signed [DATA_WIDTH-1:0] window_flat [0:IN_CHANNELS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    
    localparam INIT = 3'b000;
    localparam LOAD_WEIGHTS_ADDR = 3'b001;  // Set address, wait for BRAM
    localparam LOAD_WEIGHTS_DATA = 3'b010;  // Store data, advance to next
    localparam LOAD_BIAS_ADDR = 3'b011;     // Set bias address
    localparam LOAD_BIAS_DATA = 3'b100;     // Store bias
    localparam RUNNING = 3'b101;
    
    reg [2:0] state;
    reg [7:0] current_filter;
    reg [7:0] current_channel;
    reg [7:0] current_kernel;

    assign ready = (state == RUNNING);
    
    wire signed [DATA_WIDTH-1:0] loaded_weight;
    wire signed [DATA_WIDTH-1:0] loaded_bias;
    
    wire [DATA_WIDTH-1:0] data_in_channel [0:IN_CHANNELS-1];
    
    wire [7:0] weight_kernel_row;
    wire [7:0] weight_kernel_col;
    assign weight_kernel_row = current_kernel / KERNEL_SIZE;
    assign weight_kernel_col = current_kernel % KERNEL_SIZE;

    // Unpack input channels
    genvar c;
    generate
        for (c = 0; c < IN_CHANNELS; c = c + 1) begin : unpack_inputs
            assign data_in_channel[c] = data_in[((c+1)*DATA_WIDTH)-1:c*DATA_WIDTH];
        end
    endgenerate
    
    conv2_weight_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FILTERS(OUT_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .IN_CHANNELS(IN_CHANNELS)
    ) conv2_weights (
        .clk(clk),
        .rst(rst),
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
        .clk(clk),
        .rst(rst),
        .filter_idx(current_filter[MEM_F_W-1:0]),
        .bias_out(loaded_bias)
    );
    
    // Pipeline registers for weight/bias write path
    reg signed [DATA_WIDTH-1:0] loaded_weight_q;
    reg signed [DATA_WIDTH-1:0] loaded_bias_q;
    reg [7:0] write_filter_q, write_channel_q, write_kernel_q;
    reg write_we_q;
    reg write_bias_we_q;

    // Weight loading state machine
    integer ii, jj, kk;
    always @(posedge clk) begin
        if (rst) begin
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

            for (ii = 0; ii < OUT_CHANNELS; ii = ii + 1) begin
                bias[ii] <= 8'd0;
                for (jj = 0; jj < IN_CHANNELS; jj = jj + 1) begin
                    for (kk = 0; kk < KERNEL_SIZE*KERNEL_SIZE; kk = kk + 1) begin
                        weight[ii][jj][kk] <= 8'd0;
                    end
                end
            end
        end else begin
            // Pipeline stage 1: capture BRAM output and current write pointer
            loaded_weight_q <= loaded_weight;
            loaded_bias_q <= loaded_bias;
            write_filter_q <= current_filter;
            write_channel_q <= current_channel;
            write_kernel_q <= current_kernel;
            write_we_q <= (state == LOAD_WEIGHTS_DATA);
            write_bias_we_q <= (state == LOAD_BIAS_DATA);

            // Pipeline stage 2: array writes one cycle later
            if (write_we_q)
                weight[write_filter_q][write_channel_q][write_kernel_q] <= loaded_weight_q;
            if (write_bias_we_q)
                bias[write_filter_q] <= loaded_bias_q;

            case (state)
                INIT: begin
                    state <= LOAD_WEIGHTS_ADDR;
                    current_filter <= 8'd0;
                    current_channel <= 8'd0;
                    current_kernel <= 8'd0;
                end
                
                LOAD_WEIGHTS_ADDR: begin
                    state <= LOAD_WEIGHTS_DATA;
                end
                
                LOAD_WEIGHTS_DATA: begin
                    // Move to next weight
                    if (current_kernel == KERNEL_SIZE*KERNEL_SIZE-1) begin
                        current_kernel <= 8'd0;
                        
                        if (current_channel == IN_CHANNELS-1) begin
                            current_channel <= 8'd0;
                            state <= LOAD_BIAS_ADDR;
                        end else begin
                            current_channel <= current_channel + 8'd1;
                            state <= LOAD_WEIGHTS_ADDR;
                        end
                    end else begin
                        current_kernel <= current_kernel + 8'd1;
                        state <= LOAD_WEIGHTS_ADDR;
                    end
                end
                
                LOAD_BIAS_ADDR: begin
                    state <= LOAD_BIAS_DATA;
                end
                
                LOAD_BIAS_DATA: begin
                    // Move to next filter
                    if (current_filter == OUT_CHANNELS-1) begin
                        state <= RUNNING;
                    end else begin
                        current_filter <= current_filter + 8'd1;
                        current_channel <= 8'd0;
                        current_kernel <= 8'd0;
                        state <= LOAD_WEIGHTS_ADDR;
                    end
                end
                
                RUNNING: begin

                end
                
                default: state <= INIT;
            endcase
        end
    end
    
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

    reg conv_window_valid_q;
    always @(posedge clk) begin
        if (rst)
            conv_window_valid_q <= 1'b0;
        else
            conv_window_valid_q <= conv_window_valid;
    end

    // Instantiate convolution modules for each filter and channel
    generate
        genvar f, chan;
        for (f = 0; f < OUT_CHANNELS; f = f + 1) begin: filter_units
            
            wire [IN_CHANNELS-1:0] conv_valid;
            wire signed [DATA_WIDTH-1:0] conv_result [0:IN_CHANNELS-1];
            wire signed [23:0] conv_raw_sum [0:IN_CHANNELS-1];
            reg conv_valid_d1;
            reg conv_valid_d2;
            reg signed [24:0] acc_pair01, acc_pair23, acc_pair45;
            reg signed [DATA_WIDTH-1:0] relu_din_r;
            reg relu_go;

            function automatic signed [7:0] saturation;
                input signed [26:0] value;
                begin
                    if (value > 27'sd127)
                        saturation = 8'sd127;
                    else if (value < -27'sd128)
                        saturation = -8'sd128;
                    else
                        saturation = value[7:0];
                end
            endfunction

            for (chan = 0; chan < IN_CHANNELS; chan = chan + 1) begin: channel_convs
                wire signed [DATA_WIDTH-1:0] local_data [0:KERNEL_SIZE*KERNEL_SIZE-1];
                wire signed [DATA_WIDTH-1:0] local_weight [0:KERNEL_SIZE*KERNEL_SIZE-1];
                wire [(DATA_WIDTH*KERNEL_SIZE*KERNEL_SIZE)-1:0] local_data_packed;
                wire [(DATA_WIDTH*KERNEL_SIZE*KERNEL_SIZE)-1:0] local_weight_packed;
                genvar gw;
                for (gw = 0; gw < KERNEL_SIZE*KERNEL_SIZE; gw = gw + 1) begin : array_assign
                    assign local_data[gw] = window_flat[chan][gw];
                    assign local_weight[gw] = weight[f][chan][gw];
                end
                genvar gw_pack;
                for (gw_pack = 0; gw_pack < KERNEL_SIZE*KERNEL_SIZE; gw_pack = gw_pack + 1) begin : array_pack
                    assign local_data_packed[((gw_pack + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH] = local_data[gw_pack];
                    assign local_weight_packed[((gw_pack + 1) * DATA_WIDTH) - 1 -: DATA_WIDTH] = local_weight[gw_pack];
                end
                
                conv_5x5 #(
                    .FRAC_BITS(FRAC_BITS)
                ) conv_inst (
                    .clk(clk),
                    .rst(rst),
                    .valid_in(conv_window_valid_q),
                    .data_in(local_data_packed),
                    .weight_in(local_weight_packed),
                    .bias_in(8'd0),
                    .valid_out(conv_valid[chan]),
                    .data_out(conv_result[chan]),
                    .raw_sum(conv_raw_sum[chan])
                );
            end

            wire signed [26:0] bias_ext;
            assign bias_ext = $signed({{19{bias[f][7]}}, bias[f]}) << FRAC_BITS;

            wire signed [26:0] acc_sum3;
            assign acc_sum3 = $signed(acc_pair01) + $signed(acc_pair23) + $signed(acc_pair45) + bias_ext;

            wire signed [26:0] scaled_relu_in;
            assign scaled_relu_in = acc_sum3 >>> FRAC_BITS;
            
            always @(posedge clk) begin
                if (rst) begin
                    conv_valid_d1 <= 1'b0;
                    conv_valid_d2 <= 1'b0;
                    relu_go <= 1'b0;
                    relu_din_r <= 8'sd0;
                    acc_pair01 <= 25'sd0;
                    acc_pair23 <= 25'sd0;
                    acc_pair45 <= 25'sd0;
                end else begin
                    conv_valid_d1 <= conv_valid[0];
                    conv_valid_d2 <= conv_valid_d1;
                    relu_go <= conv_valid_d2;
                    if (conv_valid[0]) begin
                        acc_pair01 <= conv_raw_sum[0] + conv_raw_sum[1];
                        acc_pair23 <= conv_raw_sum[2] + conv_raw_sum[3];
                        acc_pair45 <= conv_raw_sum[4] + conv_raw_sum[5];
                    end
                    if (conv_valid_d1)
                        relu_din_r <= saturation(scaled_relu_in);
                end
            end
            
            relu relu_inst (
                .clk(clk),
                .rst(rst),
                .valid_in(relu_go),
                .data_in(relu_din_r),
                .valid_out(relu_valid_out[f]),
                .data_out(relu_out[f])
            );
        end
    endgenerate
    
    // Process input data and update window
    always @(posedge clk) begin
        if (rst) begin
            conv_window_valid <= 1'b0;
            wr_row_idx <= 3'd0;
            valid_out <= 1'b0;
            
            x_out <= 8'd0;
            y_out <= 8'd0;
            
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
            
            data_out <= {(DATA_WIDTH*OUT_CHANNELS){1'b0}};
            
        end else begin
            conv_window_valid <= 1'b0;

            if (valid_out) begin
                if (x_out == OUT_WIDTH-1) begin
                    x_out <= 0;
                    if (y_out == OUT_HEIGHT-1)
                        y_out <= 0;
                    else
                        y_out <= y_out + 1;
                end else begin
                    x_out <= x_out + 1;
                end
            end
            
            // Default states
            valid_out <= 1'b0;
            
            // Process input data and update windows
            if (valid_in && !conv_window_valid) begin
                // Store incoming data in line buffer for each channel
                for (ii = 0; ii < IN_CHANNELS; ii = ii + 1) begin
                    line_buffer[ii][wr_row_idx][x_in] <= data_in_channel[ii];
                end
                
                // Form window when we have enough data
                if (y_in >= KERNEL_SIZE-1 && x_in >= KERNEL_SIZE-1) begin
                    for (ii = 0; ii < IN_CHANNELS; ii = ii + 1) begin
                        if (x_in == KERNEL_SIZE-1) begin
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
                        end else begin
                            for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                                for (kk = 0; kk < KERNEL_SIZE-1; kk = kk + 1)
                                    window[ii][jj][kk] <= window[ii][jj][kk+1];
                            end

                            window[ii][0][KERNEL_SIZE-1] <= line_buffer[ii][row_idx_m4][x_in];
                            window[ii][1][KERNEL_SIZE-1] <= line_buffer[ii][row_idx_m3][x_in];
                            window[ii][2][KERNEL_SIZE-1] <= line_buffer[ii][row_idx_m2][x_in];
                            window[ii][3][KERNEL_SIZE-1] <= line_buffer[ii][row_idx_m1][x_in];
                            window[ii][4][KERNEL_SIZE-1] <= data_in_channel[ii];
                        end
                    end
                    if (state == RUNNING) begin
                        conv_window_valid <= 1'b1;
                    end
                end
                
                // Line buffer row advance when end of line reached
                if (x_in == MAP_WIDTH-1) begin
                    if (wr_row_idx == KERNEL_SIZE-1)
                        wr_row_idx <= 3'd0;
                    else
                        wr_row_idx <= wr_row_idx + 3'd1;
                end
            end
            
            if (relu_valid_out[0]) begin
                valid_out <= 1'b1;
                
                for (ii = 0; ii < OUT_CHANNELS; ii = ii + 1) begin
                    data_out[((ii+1)*DATA_WIDTH)-1 -: DATA_WIDTH] <= relu_out[ii];
                end
            end
        end
    end

endmodule
