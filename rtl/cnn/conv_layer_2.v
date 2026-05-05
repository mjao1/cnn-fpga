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

    reg [DATA_WIDTH-1:0] line_buffer [0:IN_CHANNELS-1][0:KERNEL_SIZE-1][0:MAP_WIDTH-1];
    reg [DATA_WIDTH-1:0] window [0:IN_CHANNELS-1][0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    
    reg signed [DATA_WIDTH-1:0] weight [0:OUT_CHANNELS-1][0:IN_CHANNELS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    reg signed [DATA_WIDTH-1:0] bias [0:OUT_CHANNELS-1];
    
    reg [7:0] x_count, y_count;
    reg window_valid;

    reg serial_busy;
    reg serial_busy_d;
    reg [5:0] ser_step;

    assign busy = serial_busy;

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
    
    assign ready = (state == RUNNING);
    
    reg [2:0] state;
    reg [7:0] current_filter;
    reg [7:0] current_channel;
    reg [7:0] current_kernel;
    reg load_bias;
    
    wire signed [DATA_WIDTH-1:0] loaded_weight;
    wire signed [DATA_WIDTH-1:0] loaded_bias;
    
    wire [DATA_WIDTH-1:0] data_in_channel [0:IN_CHANNELS-1];
    
    reg [DATA_WIDTH-1:0] filter_outputs [0:OUT_CHANNELS-1];
    
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
        .filter_idx(current_filter),
        .in_channel(current_channel),
        .kernel_row(current_kernel / KERNEL_SIZE),
        .kernel_col(current_kernel % KERNEL_SIZE),
        .weight_out(loaded_weight)
    );

    conv2_bias_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_FILTERS(OUT_CHANNELS)
    ) conv2_biases (
        .clk(clk),
        .rst(rst),
        .filter_idx(current_filter),
        .bias_out(loaded_bias)
    );
    
    // Weight loading state machine
    integer ii, jj, kk;
    always @(posedge clk) begin
        if (rst) begin
            state <= INIT;
            current_filter <= 8'd0;
            current_channel <= 8'd0;
            current_kernel <= 8'd0;
            load_bias <= 1'b0;
            
            for (ii = 0; ii < OUT_CHANNELS; ii = ii + 1) begin
                bias[ii] <= 8'd0;
                for (jj = 0; jj < IN_CHANNELS; jj = jj + 1) begin
                    for (kk = 0; kk < KERNEL_SIZE*KERNEL_SIZE; kk = kk + 1) begin
                        weight[ii][jj][kk] <= 8'd0;
                    end
                end
            end
        end else begin
            case (state)
                INIT: begin
                    state <= LOAD_WEIGHTS_ADDR;
                    current_filter <= 8'd0;
                    current_channel <= 8'd0;
                    current_kernel <= 8'd0;
                    load_bias <= 1'b0;
                end
                
                LOAD_WEIGHTS_ADDR: begin
                    state <= LOAD_WEIGHTS_DATA;
                end
                
                LOAD_WEIGHTS_DATA: begin
                    weight[current_filter][current_channel][current_kernel] <= loaded_weight;
                    
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
                    // Store bias
                    bias[current_filter] <= loaded_bias;
                    
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

    wire conv_start;
    assign conv_start = serial_busy & ~serial_busy_d;

    wire signed [DATA_WIDTH-1:0] conv_din [0:IN_CHANNELS-1];
    genvar ldci;
    generate
        for (ldci = 0; ldci < IN_CHANNELS; ldci = ldci + 1) begin : din_mux
            assign conv_din[ldci] = (serial_busy & ser_step >= 6'd1 & ser_step <= 6'd25) ? window_flat[ldci][ser_step - 6'd1] : 8'sd0;
        end
    endgenerate

    wire signed [DATA_WIDTH-1:0] conv_w_in [0:OUT_CHANNELS-1][0:IN_CHANNELS-1];
    genvar wf, wc;
    generate
        for (wf = 0; wf < OUT_CHANNELS; wf = wf + 1) begin : w_row
            for (wc = 0; wc < IN_CHANNELS; wc = wc + 1) begin : w_col
                assign conv_w_in[wf][wc] = (serial_busy & ser_step >= 6'd1 & ser_step <= 6'd25) ? weight[wf][wc][ser_step - 6'd1] : (serial_busy & (ser_step == 6'd26)) ? 8'd0 : 8'sd0;
            end
        end
    endgenerate
    
    // Instantiate conv_5x5 modules for each filter and input channel combination
    generate
        genvar f, chan;
        for (f = 0; f < OUT_CHANNELS; f = f + 1) begin: filter_units
            
            // Accumulation signals for each output channel
            wire [IN_CHANNELS-1:0] conv_valid;
            wire signed [DATA_WIDTH-1:0] conv_result [0:IN_CHANNELS-1]; // Scaled output
            wire signed [23:0] conv_raw_sum [0:IN_CHANNELS-1];          // Raw sum in Q2.14 format
            reg signed [23:0] conv_raw_sum_held [0:IN_CHANNELS-1];      // Extra register to hold values
            reg conv_valid_d1;                                          // Delayed conv_valid to sync with held values
            reg signed [26:0] accumulator;
            reg accum_valid;
            
            // Instantiate a 5x5 convolution module for each input channel of this filter
            for (chan = 0; chan < IN_CHANNELS; chan = chan + 1) begin: channel_convs
                conv_5x5 #(
                    .FRAC_BITS(FRAC_BITS)
                ) conv_inst (
                    .clk(clk),
                    .rst(rst),
                    .start(conv_start),
                    .data_in(conv_din[chan]),
                    .weight_in(conv_w_in[f][chan]),
                    .done(conv_valid[chan]),
                    .data_out(conv_result[chan]),
                    .raw_sum(conv_raw_sum[chan])
                );
            end
            
            // Accumulation logic across channels for this filter
            // Use raw sums from conv_5x5 (Q2.14) for full precision accumulation
            // Then scale once at the end
            reg signed [26:0] scaled_result;
            
            always @(posedge clk) begin
                if (rst) begin
                    accumulator <= 27'sd0;
                    scaled_result <= 27'sd0;
                    accum_valid <= 1'b0;
                    conv_valid_d1 <= 1'b0;
                    for (kk = 0; kk < IN_CHANNELS; kk = kk + 1) begin
                        conv_raw_sum_held[kk] <= 24'sd0;
                    end
                end else begin
                    conv_valid_d1 <= conv_valid[0];
                    if (conv_valid[0]) begin
                        for (kk = 0; kk < IN_CHANNELS; kk = kk + 1) begin
                            conv_raw_sum_held[kk] <= conv_raw_sum[kk];
                        end
                    end
                    
                    // Use held values one cycle later
                    if (conv_valid_d1) begin
                        // Perform full precision accumulation in one cycle
                        accumulator = 27'sd0;
                        
                        // Sum all channel raw sums
                        for (kk = 0; kk < IN_CHANNELS; kk = kk + 1) begin
                            accumulator = accumulator + {{3{conv_raw_sum_held[kk][23]}}, conv_raw_sum_held[kk]};
                        end
                        
                        // Add the bias term
                        accumulator = accumulator + ($signed({{19{bias[f][7]}}, bias[f]}) << FRAC_BITS);
                        
                        // Scale down to Q1.7
                        scaled_result = accumulator >>> FRAC_BITS;
                        
                        accum_valid = 1'b1;
                    end else begin
                        accum_valid = 1'b0;
                    end
                end
            end
            
            relu relu_inst (
                .clk(clk),
                .rst(rst),
                .valid_in(accum_valid),
                .data_in(saturation(scaled_result)),
                .valid_out(relu_valid_out[f]),
                .data_out(relu_out[f])
            );
            
            // Saturate 27-bit scaled result to 8-bit signed range
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
        end
    endgenerate
    
    // Process input data and update window
    always @(posedge clk) begin
        if (rst) begin
            serial_busy <= 1'b0;
            serial_busy_d <= 1'b0;
            ser_step <= 6'd0;
            x_count <= 8'd0;
            y_count <= 8'd0;
            window_valid <= 1'b0;
            valid_out <= 1'b0;
            
            x_out <= 8'd0;
            y_out <= 8'd0;
            
            // Initialize buffers and filter outputs
            for (ii = 0; ii < OUT_CHANNELS; ii = ii + 1) begin
                filter_outputs[ii] <= 8'd0;
            end
            
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
            serial_busy_d <= serial_busy;

            if (serial_busy) begin
                if (ser_step == 6'd28) begin
                    serial_busy <= 1'b0;
                    ser_step <= 6'd0;
                end else
                    ser_step <= ser_step + 6'd1;
            end

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
            window_valid <= 1'b0;
            valid_out <= 1'b0;
            
            // Process input data and update windows
            if (valid_in && !serial_busy) begin
                x_count <= x_in;
                y_count <= y_in;
                
                // Store incoming data in line buffer for each channel
                for (ii = 0; ii < IN_CHANNELS; ii = ii + 1) begin
                    line_buffer[ii][y_in % KERNEL_SIZE][x_in] <= data_in_channel[ii];
                end
                
                // Form window when we have enough data
                if (y_in >= KERNEL_SIZE-1 && x_in >= KERNEL_SIZE-1) begin
                    for (ii = 0; ii < IN_CHANNELS; ii = ii + 1) begin
                        for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                            for (kk = 0; kk < KERNEL_SIZE; kk = kk + 1) begin
                                if (jj == KERNEL_SIZE-1 && kk == KERNEL_SIZE-1)
                                    window[ii][jj][kk] <= data_in_channel[ii];
                                else
                                    window[ii][jj][kk] <= line_buffer[ii][(y_in - (KERNEL_SIZE-1) + jj) % KERNEL_SIZE][x_in - (KERNEL_SIZE-1) + kk];
                            end
                        end
                    end
                    window_valid <= 1'b1;
                    if (state == RUNNING) begin
                        serial_busy <= 1'b1;
                        ser_step <= 6'd0;
                    end
                end
                
                // Line buffer handling
                if (x_in == MAP_WIDTH-1) begin
                    y_count <= y_count + 8'd1;
                    
                end
            end
            
            if (relu_valid_out[0]) begin
                valid_out <= 1'b1;
                
                // Pack all filter outputs
                for (ii = 0; ii < OUT_CHANNELS; ii = ii + 1) begin
                    filter_outputs[ii] <= relu_out[ii];
                end
                
                // Pack outputs into a single bus
                for (ii = 0; ii < OUT_CHANNELS; ii = ii + 1) begin
                    data_out[((ii+1)*DATA_WIDTH)-1 -: DATA_WIDTH] <= relu_out[ii];
                end
            end
        end
    end

endmodule
