// Top for Xilinx FPGA implementation and control

module fpga_top #(
    parameter int DATA_WIDTH = 8,
    parameter int IMG_WIDTH = 28,
    parameter int IMG_HEIGHT = 28,
    parameter int NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT
)(
    input  logic clk,
    input  logic rst,
    input  logic rx,
    output logic [6:0] seg7,
    output logic [7:0] an,
    output logic [3:0] led
);

    typedef enum logic [1:0] {
        IDLE,
        LOAD,
        INFERENCE,
        DONE
    } state_t;

    logic rst_sync;
    state_t state;
    logic [DATA_WIDTH-1:0] pixel_data;
    logic pixel_valid;
    logic [$clog2(IMG_HEIGHT)-1:0] pixel_row;
    logic [$clog2(IMG_WIDTH)-1:0] pixel_col;
    logic [9:0] pixel_count;
    logic cnn_start;
    logic frame_ack;

    logic rst_sync_n;
    state_t state_n;
    logic pixel_valid_n;
    logic [$clog2(IMG_HEIGHT)-1:0] pixel_row_n;
    logic [$clog2(IMG_WIDTH)-1:0] pixel_col_n;
    logic [9:0] pixel_count_n;
    logic cnn_start_n;
    logic frame_ack_n;
    logic done;
    logic [3:0] pred_digit;
    logic [DATA_WIDTH-1:0] pred_confidence;
    logic frame_ready;
    logic [9:0] ram_raddr;
    logic [DATA_WIDTH-1:0] ram_rdata;

    uart_image_loader #(
        .IMG_BYTES(NUM_PIXELS),
        .BAUD_DIV(868)
    ) u_loader (
        .clk_i(clk),
        .rst_i(rst_sync),
        .rx_i(rx),
        .frame_ack_i(frame_ack),
        .ram_raddr_i(ram_raddr),
        .frame_ready_o(frame_ready),
        .ram_rdata_o(ram_rdata)
    );

    assign ram_raddr = (state == LOAD) ? pixel_count : 10'd0;

    // CNN top
    cnn_top #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .DATA_WIDTH(DATA_WIDTH)
    ) cnn (
        .clk_i(clk),
        .rst_i(rst_sync),
        .start_i(cnn_start),
        .pixel_data_i(pixel_data),
        .pixel_valid_i(pixel_valid),
        .pixel_row_i(pixel_row),
        .pixel_col_i(pixel_col),
        .done_o(done),
        .pred_digit_o(pred_digit),
        .pred_confidence_o(pred_confidence)
    );

    // 7 seg display
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

    assign an = 8'b11111110;

    // Main state machine
    always_comb begin
        state_n = state;
        pixel_valid_n = 1'b0;
        pixel_row_n = pixel_row;
        pixel_col_n = pixel_col;
        pixel_count_n = pixel_count;
        cnn_start_n = 1'b0;
        frame_ack_n = 1'b0;

        case (state)
            IDLE: begin
                pixel_count_n = 10'd0;
                if (frame_ready) begin
                    cnn_start_n = 1'b1;
                    state_n = LOAD;
                end
            end

            LOAD: begin
                if (pixel_count < NUM_PIXELS) begin
                    pixel_valid_n = 1'b1;
                    pixel_row_n = pixel_count / IMG_WIDTH;
                    pixel_col_n = pixel_count % IMG_WIDTH;
                    pixel_count_n = pixel_count + 10'd1;
                end else begin
                    frame_ack_n = 1'b1;
                    state_n = INFERENCE;
                end
            end

            INFERENCE: begin
                if (done)
                    state_n = DONE;
            end

            DONE: begin
                state_n = IDLE;
            end

            default: state_n = IDLE;
        endcase
    end

    // State LEDs
    always_comb begin
        led = 4'b0000;
        case (state)
            IDLE:      led = 4'b0001;
            LOAD:      led = 4'b0010;
            INFERENCE: led = 4'b0100;
            DONE:      led = 4'b1000;
            default:   led = 4'b0000;
        endcase
    end

    // Reset sync
    always_ff @(posedge clk) begin
        rst_sync_n <= rst;
        rst_sync <= rst_sync_n;
    end

    always_ff @(posedge clk) begin
        if (rst_sync) begin
            state <= IDLE;
            pixel_count <= 10'd0;
            pixel_valid <= 1'b0;
            pixel_data <= {DATA_WIDTH{1'b0}};
            pixel_row <= '0;
            pixel_col <= '0;
            cnn_start <= 1'b0;
            frame_ack <= 1'b0;
        end else begin
            state <= state_n;
            pixel_valid <= pixel_valid_n;
            pixel_row <= pixel_row_n;
            pixel_col <= pixel_col_n;
            pixel_count <= pixel_count_n;
            cnn_start <= cnn_start_n;
            frame_ack <= frame_ack_n;
            if (pixel_valid_n)
                pixel_data <= ram_rdata;
        end
    end

endmodule
