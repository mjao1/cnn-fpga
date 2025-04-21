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
    parameter DATA_WIDTH = 8      // Data width (8-bit fixed point)
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
    output reg [7:0] y_out                       // Y coordinate of output pixel
);

    reg [DATA_WIDTH-1:0] line_buffer [0:IN_CHANNELS-1][0:KERNEL_SIZE-1][0:MAP_WIDTH-1];
    reg [DATA_WIDTH-1:0] window [0:IN_CHANNELS-1][0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    
    reg signed [DATA_WIDTH-1:0] weight [0:OUT_CHANNELS-1][0:IN_CHANNELS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    reg signed [DATA_WIDTH-1:0] bias [0:OUT_CHANNELS-1];
    
    reg [7:0] x_count, y_count;
    reg window_valid;

    wire valid_conv [0:OUT_CHANNELS-1];
    wire signed [DATA_WIDTH-1:0] conv_out [0:OUT_CHANNELS-1];
    
    wire relu_valid_out [0:OUT_CHANNELS-1];
    wire [DATA_WIDTH-1:0] relu_out [0:OUT_CHANNELS-1];
    
    wire signed [DATA_WIDTH-1:0] window_flat [0:IN_CHANNELS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    
    localparam INIT = 2'b00;
    localparam LOAD_WEIGHTS = 2'b01;
    localparam RUNNING = 2'b10;
    
    reg [1:0] state;
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
    
    weight_loader #(
        .DATA_WIDTH(DATA_WIDTH)
    ) weight_loader_inst (
        .clk(clk),
        .rst(rst),
        .layer_select(8'd1),
        .filter_idx(current_filter),
        .in_channel(current_channel),
        .kernel_row(current_kernel / KERNEL_SIZE),
        .kernel_col(current_kernel % KERNEL_SIZE),
        .input_idx(16'd0),
        .neuron_idx(16'd0),
        .weight_out(loaded_weight),
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
                    state <= LOAD_WEIGHTS;
                    current_filter <= 8'd0;
                    current_channel <= 8'd0;
                    current_kernel <= 8'd0;
                    load_bias <= 1'b0;
                end
                
                LOAD_WEIGHTS: begin
                    if (!load_bias) begin
                        // Store weight
                        weight[current_filter][current_channel][current_kernel] <= loaded_weight;
                        
                        // Move to next weight
                        if (current_kernel == KERNEL_SIZE*KERNEL_SIZE-1) begin
                            current_kernel <= 8'd0;
                            
                            if (current_channel == IN_CHANNELS-1) begin
                                current_channel <= 8'd0;
                                load_bias <= 1'b1;
                            end else begin
                                current_channel <= current_channel + 8'd1;
                            end
                        end else begin
                            current_kernel <= current_kernel + 8'd1;
                        end
                    end else begin
                        // Store bias
                        bias[current_filter] <= loaded_bias;
                        
                        // Move to next filter
                        if (current_filter == OUT_CHANNELS-1) begin
                            state <= RUNNING;
                        end else begin
                            current_filter <= current_filter + 8'd1;
                            load_bias <= 1'b0;
                        end
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
    
    // Instantiate conv_5x5 modules for each filter and input channel combination
    generate
        genvar f, chan;
        for (f = 0; f < OUT_CHANNELS; f = f + 1) begin: filter_units
            
            // Accumulation signals for each output channel
            wire [IN_CHANNELS-1:0] conv_valid;
            wire signed [DATA_WIDTH-1:0] conv_result [0:IN_CHANNELS-1];
            reg signed [19:0] accumulator;
            reg accum_valid;
            
            // Instantiate a 5x5 convolution module for each input channel of this filter
            for (chan = 0; chan < IN_CHANNELS; chan = chan + 1) begin: channel_convs
                conv_5x5 conv_inst (
                    .clk(clk),
                    .rst(rst),
                    .valid_in(window_valid && (state == RUNNING)),
                    
                    // Pass window data for this channel
                    .data_in_00(window_flat[chan][0]), .data_in_01(window_flat[chan][1]), 
                    .data_in_02(window_flat[chan][2]), .data_in_03(window_flat[chan][3]), 
                    .data_in_04(window_flat[chan][4]),
                    .data_in_10(window_flat[chan][5]), .data_in_11(window_flat[chan][6]), 
                    .data_in_12(window_flat[chan][7]), .data_in_13(window_flat[chan][8]), 
                    .data_in_14(window_flat[chan][9]),
                    .data_in_20(window_flat[chan][10]), .data_in_21(window_flat[chan][11]), 
                    .data_in_22(window_flat[chan][12]), .data_in_23(window_flat[chan][13]), 
                    .data_in_24(window_flat[chan][14]),
                    .data_in_30(window_flat[chan][15]), .data_in_31(window_flat[chan][16]), 
                    .data_in_32(window_flat[chan][17]), .data_in_33(window_flat[chan][18]), 
                    .data_in_34(window_flat[chan][19]),
                    .data_in_40(window_flat[chan][20]), .data_in_41(window_flat[chan][21]), 
                    .data_in_42(window_flat[chan][22]), .data_in_43(window_flat[chan][23]), 
                    .data_in_44(window_flat[chan][24]),
                    
                    // Pass weights for this filter/channel combination
                    .weight_00(weight[f][chan][0]), .weight_01(weight[f][chan][1]), 
                    .weight_02(weight[f][chan][2]), .weight_03(weight[f][chan][3]), 
                    .weight_04(weight[f][chan][4]),
                    .weight_10(weight[f][chan][5]), .weight_11(weight[f][chan][6]), 
                    .weight_12(weight[f][chan][7]), .weight_13(weight[f][chan][8]), 
                    .weight_14(weight[f][chan][9]),
                    .weight_20(weight[f][chan][10]), .weight_21(weight[f][chan][11]), 
                    .weight_22(weight[f][chan][12]), .weight_23(weight[f][chan][13]), 
                    .weight_24(weight[f][chan][14]),
                    .weight_30(weight[f][chan][15]), .weight_31(weight[f][chan][16]), 
                    .weight_32(weight[f][chan][17]), .weight_33(weight[f][chan][18]), 
                    .weight_34(weight[f][chan][19]),
                    .weight_40(weight[f][chan][20]), .weight_41(weight[f][chan][21]), 
                    .weight_42(weight[f][chan][22]), .weight_43(weight[f][chan][23]), 
                    .weight_44(weight[f][chan][24]),
                    
                    .bias(8'd0), // Use 0 for individual channel biases, add real bias later
                    
                    .valid_out(conv_valid[chan]),
                    .data_out(conv_result[chan])
                );
            end
            
            // Accumulation logic across channels for this filter
            always @(posedge clk) begin
                if (rst) begin
                    accumulator <= 20'd0;
                    accum_valid <= 1'b0;
                end else begin
                    // When the first channel's convolution is ready
                    if (conv_valid[0]) begin
                        accumulator <= 20'd0;
                        // Sum all channel convolutions
                        for (kk = 0; kk < IN_CHANNELS; kk = kk + 1) begin
                            accumulator <= accumulator + {{12{conv_result[kk][7]}}, conv_result[kk]};
                        end
                        // Add the bias term
                        accumulator <= accumulator + {{12{bias[f][7]}}, bias[f]};
                        accum_valid <= 1'b1;
                    end else begin
                        accum_valid <= 1'b0;
                    end
                end
            end
            
            relu relu_inst (
                .clk(clk),
                .rst(rst),
                .valid_in(accum_valid),
                .data_in(saturation(accumulator)),
                .valid_out(relu_valid_out[f]),
                .data_out(relu_out[f])
            );
            
            function signed [7:0] saturation;
                input signed [19:0] value;
                begin
                    if (value > 20'sd127)
                        saturation = 8'sd127;
                    else if (value < -20'sd128)
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
            // Default states
            window_valid <= 1'b0;
            valid_out <= 1'b0;
            
            // Process input data and update windows
            if (valid_in) begin
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
                                window[ii][jj][kk] <= line_buffer[ii][(y_in - (KERNEL_SIZE-1) + jj) % KERNEL_SIZE][x_in - (KERNEL_SIZE-1) + kk];
                            end
                        end
                    end
                    window_valid <= 1'b1;
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
                
                // Update output coordinates (offset by KERNEL_SIZE-1 from input)
                x_out <= x_count - (KERNEL_SIZE-1);
                y_out <= y_count - (KERNEL_SIZE-1);
            end
        end
    end

endmodule
