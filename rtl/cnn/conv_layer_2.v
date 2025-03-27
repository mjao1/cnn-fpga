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

    wire [DATA_WIDTH-1:0] data_in_channel [0:IN_CHANNELS-1];

    reg [DATA_WIDTH-1:0] data_out_channel [0:OUT_CHANNELS-1];
    
    // Unpack input channels
    generate
        genvar g;
        for (g = 0; g < IN_CHANNELS; g = g + 1) begin : unpack_inputs
            assign data_in_channel[g] = data_in[((g+1)*DATA_WIDTH)-1:g*DATA_WIDTH];
        end
    endgenerate
    
    // Pack output channels
    generate
        genvar o;
        for (o = 0; o < OUT_CHANNELS; o = o + 1) begin : pack_outputs
            always @(*) begin
                data_out[((o+1)*DATA_WIDTH)-1:o*DATA_WIDTH] = data_out_channel[o];
            end
        end
    endgenerate
    
    wire valid_conv [0:OUT_CHANNELS-1][0:IN_CHANNELS-1];
    wire signed [DATA_WIDTH-1:0] conv_out [0:OUT_CHANNELS-1][0:IN_CHANNELS-1];
    
    wire signed [DATA_WIDTH-1:0] window_flat [0:IN_CHANNELS-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
    
    reg signed [19:0] channel_acc [0:OUT_CHANNELS-1];
    reg [2:0] acc_phase;
    reg acc_valid;
    
    integer ii, jj, kk, ic, oc;
    
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
    
    weight_loader #(
        .DATA_WIDTH(DATA_WIDTH)
    ) weight_loader_inst (
        .clk(clk),
        .rst_n(~rst),
        .layer_select(8'd1),
        .filter_idx(current_filter),
        .kernel_idx(current_kernel),
        .input_idx({8'd0, current_channel}),
        .output_idx(8'd0),
        .weight(loaded_weight),
        .bias(loaded_bias)
    );
    
    // Weight loading state machine
    always @(posedge clk) begin
        if (rst) begin
            state <= INIT;
            current_filter <= 8'd0;
            current_channel <= 8'd0;
            current_kernel <= 8'd0;
            load_bias <= 1'b0;
            
            for (oc = 0; oc < OUT_CHANNELS; oc = oc + 1) begin
                bias[oc] <= 8'd0;
                for (ic = 0; ic < IN_CHANNELS; ic = ic + 1) begin
                    for (kk = 0; kk < KERNEL_SIZE*KERNEL_SIZE; kk = kk + 1) begin
                        weight[oc][ic][kk] <= 8'd0;
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
                            
                            // Move to next input channel
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
        genvar gic, gi, gj;
        for (gic = 0; gic < IN_CHANNELS; gic = gic + 1) begin
            for (gi = 0; gi < KERNEL_SIZE; gi = gi + 1) begin
                for (gj = 0; gj < KERNEL_SIZE; gj = gj + 1) begin
                    assign window_flat[gic][gi*KERNEL_SIZE + gj] = window[gic][gi][gj];
                end
            end
        end
    endgenerate
    
    // Instantiate conv_5x5 modules for each filter and input channel combination
    generate
        genvar goc, ginc;
        for (goc = 0; goc < OUT_CHANNELS; goc = goc + 1) begin : output_channels
            for (ginc = 0; ginc < IN_CHANNELS; ginc = ginc + 1) begin : input_channels
                conv_5x5 conv_inst (
                    .clk(clk),
                    .rst(rst),
                    .valid_in(window_valid && (state == RUNNING)),

                    .data_in_00(window_flat[ginc][0]), .data_in_01(window_flat[ginc][1]), 
                    .data_in_02(window_flat[ginc][2]), .data_in_03(window_flat[ginc][3]), 
                    .data_in_04(window_flat[ginc][4]),
                    
                    .data_in_10(window_flat[ginc][5]), .data_in_11(window_flat[ginc][6]), 
                    .data_in_12(window_flat[ginc][7]), .data_in_13(window_flat[ginc][8]), 
                    .data_in_14(window_flat[ginc][9]),
                    
                    .data_in_20(window_flat[ginc][10]), .data_in_21(window_flat[ginc][11]), 
                    .data_in_22(window_flat[ginc][12]), .data_in_23(window_flat[ginc][13]), 
                    .data_in_24(window_flat[ginc][14]),
                    
                    .data_in_30(window_flat[ginc][15]), .data_in_31(window_flat[ginc][16]), 
                    .data_in_32(window_flat[ginc][17]), .data_in_33(window_flat[ginc][18]), 
                    .data_in_34(window_flat[ginc][19]),
                    
                    .data_in_40(window_flat[ginc][20]), .data_in_41(window_flat[ginc][21]), 
                    .data_in_42(window_flat[ginc][22]), .data_in_43(window_flat[ginc][23]), 
                    .data_in_44(window_flat[ginc][24]),

                    .weight_00(weight[goc][ginc][0]), .weight_01(weight[goc][ginc][1]), 
                    .weight_02(weight[goc][ginc][2]), .weight_03(weight[goc][ginc][3]), 
                    .weight_04(weight[goc][ginc][4]),
                    
                    .weight_10(weight[goc][ginc][5]), .weight_11(weight[goc][ginc][6]), 
                    .weight_12(weight[goc][ginc][7]), .weight_13(weight[goc][ginc][8]), 
                    .weight_14(weight[goc][ginc][9]),
                    
                    .weight_20(weight[goc][ginc][10]), .weight_21(weight[goc][ginc][11]), 
                    .weight_22(weight[goc][ginc][12]), .weight_23(weight[goc][ginc][13]), 
                    .weight_24(weight[goc][ginc][14]),
                    
                    .weight_30(weight[goc][ginc][15]), .weight_31(weight[goc][ginc][16]), 
                    .weight_32(weight[goc][ginc][17]), .weight_33(weight[goc][ginc][18]), 
                    .weight_34(weight[goc][ginc][19]),
                    
                    .weight_40(weight[goc][ginc][20]), .weight_41(weight[goc][ginc][21]), 
                    .weight_42(weight[goc][ginc][22]), .weight_43(weight[goc][ginc][23]), 
                    .weight_44(weight[goc][ginc][24]),

                    .bias(8'd0),  // Will add the bias later when combining channels

                    .valid_out(valid_conv[goc][ginc]),
                    .data_out(conv_out[goc][ginc])
                );
            end
        end
    endgenerate
    
    // Saturation function to convert 20-bit result to 8-bit
    function signed [7:0] saturate;
        input signed [19:0] value;
        begin
            if (value > 20'sd127)
                saturate = 8'sd127;
            else if (value < -20'sd128)
                saturate = -8'sd128;    
            else
                saturate = value[7:0];
        end
    endfunction
    
    // Channel accumulation state machine
    always @(posedge clk) begin
        if (rst) begin
            for (oc = 0; oc < OUT_CHANNELS; oc = oc + 1) begin
                channel_acc[oc] <= 20'd0;
                data_out_channel[oc] <= 8'd0;
            end
            acc_phase <= 3'd0;
            acc_valid <= 1'b0;
            valid_out <= 1'b0;
        end else if (state == RUNNING) begin
            // Step 1 - Detect when the first channel is valid
            if (valid_conv[0][0] && acc_phase == 3'd0) begin
                for (oc = 0; oc < OUT_CHANNELS; oc = oc + 1) begin
                    channel_acc[oc] <= {{12{bias[oc][7]}}, bias[oc]};
                end
                acc_phase <= 3'd1;
                acc_valid <= 1'b0;
            end
            
            // Step 2 - Accumulate results from all input channels
            else if (acc_phase == 3'd1) begin
                for (oc = 0; oc < OUT_CHANNELS; oc = oc + 1) begin
                    for (ic = 0; ic < IN_CHANNELS; ic = ic + 1) begin
                        if (valid_conv[oc][ic]) begin
                            channel_acc[oc] <= channel_acc[oc] + {{12{conv_out[oc][ic][7]}}, conv_out[oc][ic]};
                        end
                    end
                end
                acc_phase <= 3'd2;
            end
            
            // Step 3: Saturate and output final results
            else if (acc_phase == 3'd2) begin
                for (oc = 0; oc < OUT_CHANNELS; oc = oc + 1) begin
                    data_out_channel[oc] <= saturate(channel_acc[oc]);
                end
                acc_valid <= 1'b1;
                acc_phase <= 3'd0;
            end
            
            valid_out <= acc_valid;
            
            // Update output coordinates
            if (acc_valid) begin
                if (x_out == OUT_WIDTH - 1) begin
                    x_out <= 8'd0;
                    if (y_out == OUT_HEIGHT - 1)
                        y_out <= 8'd0;
                    else
                        y_out <= y_out + 8'd1;
                end else begin
                    x_out <= x_out + 8'd1;
                end
            end
        end
    end
    
    // Process input data and update window
    always @(posedge clk) begin
        if (rst) begin
            x_count <= 8'd0;
            y_count <= 8'd0;
            window_valid <= 1'b0;
            
            x_out <= 8'd0;
            y_out <= 8'd0;
            
            for (ic = 0; ic < IN_CHANNELS; ic = ic + 1) begin
                for (ii = 0; ii < KERNEL_SIZE; ii = ii + 1) begin
                    for (jj = 0; jj < MAP_WIDTH; jj = jj + 1) begin
                        line_buffer[ic][ii][jj] <= 8'd0;
                    end
                    for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                        window[ic][ii][jj] <= 8'd0;
                    end
                end
            end
        end else if (state == RUNNING) begin
            if (valid_in) begin
                for (ic = 0; ic < IN_CHANNELS; ic = ic + 1) begin
                    line_buffer[ic][y_in % KERNEL_SIZE][x_in] <= data_in_channel[ic];
                end
                
                if (y_in >= KERNEL_SIZE - 1 && x_in >= KERNEL_SIZE - 1) begin
                    for (ic = 0; ic < IN_CHANNELS; ic = ic + 1) begin
                        for (ii = 0; ii < KERNEL_SIZE; ii = ii + 1) begin
                            for (jj = 0; jj < KERNEL_SIZE; jj = jj + 1) begin
                                window[ic][ii][jj] <= line_buffer[ic][(y_in - (KERNEL_SIZE-1-ii)) % KERNEL_SIZE][x_in - (KERNEL_SIZE-1-jj)];
                            end
                        end
                    end
                    window_valid <= 1'b1;
                end else begin
                    window_valid <= 1'b0;
                end
                
                // Line buffer handling
                if (x_in == MAP_WIDTH - 1) begin
                    y_count <= y_count + 8'd1;
                    
                    if (y_count >= KERNEL_SIZE - 1) begin
                        for (ic = 0; ic < IN_CHANNELS; ic = ic + 1) begin
                            for (ii = 0; ii < KERNEL_SIZE - 1; ii = ii + 1) begin
                                for (jj = 0; jj < MAP_WIDTH; jj = jj + 1) begin
                                    line_buffer[ic][ii][jj] <= line_buffer[ic][ii+1][jj];
                                end
                            end
                        end
                    end
                end
                
                if (x_in == MAP_WIDTH - 1)
                    x_count <= 8'd0;
                else
                    x_count <= x_count + 8'd1;
            end else begin
                window_valid <= 1'b0;
            end
        end
    end

endmodule 
