// pooling layer 1
// Input: 6 channels, 24x24 feature maps (output of first convolutional layer)
// Output: 6 channels, 12x12 feature maps
// Pooling: 2x2 max pooling with stride 2

module pool_layer_1 #(
    parameter IN_WIDTH = 24,      // Input feature map width
    parameter IN_HEIGHT = 24,     // Input feature map height
    parameter OUT_WIDTH = 12,     // Output feature map width (24/2)
    parameter OUT_HEIGHT = 12,    // Output feature map height (24/2)
    parameter NUM_CHANNELS = 6,   // Number of channels (same for input and output)
    parameter DATA_WIDTH = 8      // Data width (8-bit fixed point)
)(
    input  logic                                 clk_i,
    input  logic                                 rst_i,
    input  logic                                 valid_i,
    input  logic [(DATA_WIDTH*NUM_CHANNELS)-1:0] data_i,
    input  logic [8:0]                           x_i,
    input  logic [8:0]                           y_i,

    output logic                                 valid_o,
    output logic [(DATA_WIDTH*NUM_CHANNELS)-1:0] data_o,
    output logic [8:0]                           x_o,
    output logic [8:0]                           y_o
);

    logic [DATA_WIDTH-1:0] buffer [0:NUM_CHANNELS-1][0:1][0:IN_WIDTH-1];
    logic [DATA_WIDTH-1:0] window_00 [0:NUM_CHANNELS-1];
    logic [DATA_WIDTH-1:0] window_01 [0:NUM_CHANNELS-1];
    logic [DATA_WIDTH-1:0] window_10 [0:NUM_CHANNELS-1];
    logic [DATA_WIDTH-1:0] window_11 [0:NUM_CHANNELS-1];
    logic pool_valid;
    logic [8:0] pool_x;
    logic [8:0] pool_y;

    logic [DATA_WIDTH-1:0] data_in_channel [0:NUM_CHANNELS-1];
    logic [DATA_WIDTH-1:0] data_out_channel [0:NUM_CHANNELS-1];
    logic pool_valid_out [0:NUM_CHANNELS-1];

    integer i, j;

    assign valid_o = pool_valid_out[0];
    assign x_o = pool_x;
    assign y_o = pool_y;

    // Unpack input channels
    generate
        genvar c;
        for (c = 0; c < NUM_CHANNELS; c = c + 1) begin : unpack_inputs
            assign data_in_channel[c] = data_i[((c+1)*DATA_WIDTH)-1:c*DATA_WIDTH];
        end
    endgenerate

    // Pack output channels
    generate
        genvar cp;
        for (cp = 0; cp < NUM_CHANNELS; cp = cp + 1) begin : pack_outputs
            assign data_o[((cp+1)*DATA_WIDTH)-1:cp*DATA_WIDTH] = data_out_channel[cp];
        end
    endgenerate

    // max_pool_2x2 for each channel
    generate
        genvar cm;
        for (cm = 0; cm < NUM_CHANNELS; cm = cm + 1) begin : max_pool_units
            max_pool_2x2 pool_unit (
                .clk(clk_i),
                .rst(rst_i),
                .valid_in(pool_valid),
                .data_in_00(window_00[cm]),
                .data_in_01(window_01[cm]),
                .data_in_10(window_10[cm]),
                .data_in_11(window_11[cm]),
                .valid_out(pool_valid_out[cm]),
                .data_out(data_out_channel[cm])
            );
        end
    endgenerate

    // Buffer and window formation
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            pool_x <= 9'd0;
            pool_y <= 9'd0;
            pool_valid <= 1'b0;

            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                for (j = 0; j < IN_WIDTH; j = j + 1) begin
                    buffer[i][0][j] <= 8'd0;
                    buffer[i][1][j] <= 8'd0;
                end
            end
        end else begin
            if (valid_i) begin
                for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                    buffer[i][y_i % 2][x_i] <= data_in_channel[i];
                end

                // Form window for pooling
                if ((x_i % 2 == 1) && (y_i % 2 == 1)) begin
                    for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                        window_00[i] <= buffer[i][0][x_i-1]; // top left
                        window_01[i] <= buffer[i][0][x_i];   // top right
                        window_10[i] <= buffer[i][1][x_i-1]; // bottom left
                        window_11[i] <= data_in_channel[i];  // bottom right (current input)
                    end
                    pool_valid <= 1'b1;

                    // Divide by 2
                    pool_x <= x_i >> 1;
                    pool_y <= y_i >> 1;

                end else begin
                    pool_valid <= 1'b0;
                end
            end else begin
                pool_valid <= 1'b0;
            end
        end
    end

endmodule
