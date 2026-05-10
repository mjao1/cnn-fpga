// Top for Xilinx FPGA implementation and control

module fpga_top #(
    parameter int DATA_WIDTH = 8,
    parameter int IMG_WIDTH = 28,
    parameter int IMG_HEIGHT = 28,
    parameter int NUM_PIXELS = IMG_WIDTH * IMG_HEIGHT
)(
    input logic clk,
    input logic rst,
    input logic rx,
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
        IDLE,
        LOAD,
        INFERENCE,
        DONE
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

    logic frame_ready;
    logic frame_ack;
    logic [9:0] ram_raddr;
    logic [DATA_WIDTH-1:0] ram_rdata;

    uart_image_loader #(
        .IMG_BYTES(NUM_PIXELS),
        .BAUD_DIV(868)
    ) u_loader (
        .clk(clk_sys),
        .rst(rst_sync),
        .rx(rx),
        .frame_ready(frame_ready),
        .frame_ack(frame_ack),
        .ram_rdata(ram_rdata),
        .ram_raddr(ram_raddr)
    );

    assign ram_raddr = (state == LOAD) ? pixel_count[9:0] : 10'd0;

    always_ff @(posedge clk_sys) begin
        rst_sync_1 <= rst;
        rst_sync <= rst_sync_1;
    end

    always_comb begin
        led = 4'b0;
        case (state)
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
            frame_ack <= 1'b0;
        end else begin
            cnn_start <= 1'b0;
            pixel_valid <= 1'b0;
            frame_ack <= 1'b0;

            case (state)
                IDLE: begin
                    pixel_count <= 10'd0;
                    if (frame_ready) begin
                        cnn_start <= 1'b1;
                        state <= LOAD;
                    end
                end

                LOAD: begin
                    if (pixel_count < NUM_PIXELS) begin
                        pixel_valid <= 1'b1;
                        pixel_row <= pixel_count / 10'(IMG_WIDTH);
                        pixel_col <= pixel_count % 10'(IMG_WIDTH);
                        pixel_data <= ram_rdata;
                        pixel_count <= pixel_count + 10'd1;
                    end else begin
                        frame_ack <= 1'b1;
                        state <= INFERENCE;
                    end
                end

                // Wait for CNN process
                INFERENCE: begin
                    if (done)
                        state <= DONE;
                end

                DONE: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
