// Top for Xilinx FPGA implementation and control

module fpga_top #(
    parameter DATA_WIDTH = 8,
    parameter IMG_WIDTH = 28,
    parameter IMG_HEIGHT = 28,
    parameter NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT
)(
    input logic clk,
    input logic rst,
    input logic start,
    input logic [9:0] sw,

    output logic [6:0] seg7,
    output logic [7:0] an,
    output logic [3:0] led
);
    wire clk_sys;
    logic rst_sync_1;
    logic rst_sync;
    IBUF clk_ibuf (
        .I (clk),
        .O (clk_sys)
    );

    typedef enum logic [1:0] {
        IDLE         = 2'd0,
        LOAD         = 2'd1,
        INFERENCE    = 2'd2,
        DONE         = 2'd3
    } state_t;
    state_t state;

    logic [DATA_WIDTH-1:0] pixel_data;
    logic pixel_valid;
    logic [$clog2(IMG_HEIGHT)-1:0] pixel_row;
    logic [$clog2(IMG_WIDTH)-1:0] pixel_col;
    logic [9:0] pixel_count;
    logic cnn_start;

    logic done;
    logic [3:0] pred_digit;
    logic [DATA_WIDTH-1:0] pred_confidence;

    logic [DATA_WIDTH-1:0] image_rom [0:NUM_PIXELS*10-1];
    logic [3:0] digit_reg;

    // Start button edge detector
    logic start_prev = 1'b0;
    wire start_pulse = start & ~start_prev;
    always_ff @(posedge clk_sys) begin
        rst_sync_1 <= rst;
        rst_sync <= rst_sync_1;
    end

    always_ff @(posedge clk_sys) begin
        if (rst_sync) 
            start_prev <= 1'b0;
        else     
            start_prev <= start;
    end

    // Switch decode
    logic [3:0] sw_digit;
    always_comb begin
        sw_digit = 4'd0;
        case (1'b1)
            sw[0]: sw_digit = 4'd0;
            sw[1]: sw_digit = 4'd1;
            sw[2]: sw_digit = 4'd2;
            sw[3]: sw_digit = 4'd3;
            sw[4]: sw_digit = 4'd4;
            sw[5]: sw_digit = 4'd5;
            sw[6]: sw_digit = 4'd6;
            sw[7]: sw_digit = 4'd7;
            sw[8]: sw_digit = 4'd8;
            sw[9]: sw_digit = 4'd9;
            default: sw_digit = 4'd0;
        endcase
    end

    // Load test images into ROM
    initial begin
        $readmemh("test_image_0.mem", image_rom, 0, 783);
        $readmemh("test_image_1.mem", image_rom, 784, 1567);
        $readmemh("test_image_2.mem", image_rom, 1568, 2351);
        $readmemh("test_image_3.mem", image_rom, 2352, 3135);
        $readmemh("test_image_4.mem", image_rom, 3136, 3919);
        $readmemh("test_image_5.mem", image_rom, 3920, 4703);
        $readmemh("test_image_6.mem", image_rom, 4704, 5487);
        $readmemh("test_image_7.mem", image_rom, 5488, 6271);
        $readmemh("test_image_8.mem", image_rom, 6272, 7055);
        $readmemh("test_image_9.mem", image_rom, 7056, 7839);
    end

    // Status LEDs
    always_comb begin
        led = 4'b0;
        unique case (state)
            IDLE:      led = 4'b0001;
            LOAD:      led = 4'b0010;
            INFERENCE: led = 4'b0100;
            DONE:      led = 4'b1000;
            default:   led = 4'b0;
        endcase
    end

    // CNN top
    cnn_top #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .DATA_WIDTH(DATA_WIDTH)
    ) cnn (
        .clk(clk_sys),
        .rst(rst_sync),
        .start(cnn_start),
        .pixel_data(pixel_data),
        .pixel_valid(pixel_valid),
        .pixel_row_in(pixel_row),
        .pixel_col_in(pixel_col),
        .done(done),
        .pred_digit(pred_digit),
        .pred_confidence(pred_confidence)
    );

    // 7 seg display
    assign an = 8'b11111110;

    hex7seg seg_display (
        .d3(pred_digit[3]), .d2(pred_digit[2]), .d1(pred_digit[1]), .d0(pred_digit[0]),
        .CA(seg7[6]),
        .CB(seg7[5]),
        .CC(seg7[4]),
        .CD(seg7[3]),
        .CE(seg7[2]),
        .CF(seg7[1]),
        .CG(seg7[0])
    );

    // Main state machine
    always_ff @(posedge clk_sys) begin
        if (rst_sync) begin
            state <= IDLE;
            pixel_count <= 10'd0;
            pixel_valid <= 1'b0;
            pixel_data <= '0;
            pixel_row <= '0;
            pixel_col <= '0;
            cnn_start <= 1'b0;
            digit_reg <= 4'd0;
        end else begin
            cnn_start <= 1'b0;
            pixel_valid <= 1'b0;

            case (state)
                // Wait for image selection and start
                IDLE: begin
                    pixel_count <= 10'd0;
                    if (|sw && (sw & (sw - 10'd1)) == 10'd0 && start_pulse) begin
                        digit_reg <= sw_digit;
                        cnn_start <= 1'b1;
                        state <= LOAD;
                    end
                end

                // Feed image pixels from ROM
                LOAD: begin
                    if (pixel_count < NUM_PIXELS) begin
                        pixel_valid <= 1'b1;
                        pixel_row <= pixel_count / 10'(IMG_WIDTH);
                        pixel_col <= pixel_count % 10'(IMG_WIDTH);
                        pixel_data <= image_rom[digit_reg * NUM_PIXELS + pixel_count];
                        pixel_count <= pixel_count + 10'd1;
                    end else begin
                        state <= INFERENCE;
                    end
                end

                // Wait for CNN process
                INFERENCE: begin
                    if (done) begin
                        state <= DONE;
                    end
                end

                // Display result, return path
                DONE: begin
                    state <= DONE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
