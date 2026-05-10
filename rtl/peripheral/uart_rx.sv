// UART RX 8N1 LSB-first: sync rx, detect start, sample mid-bit using bit-period counter.

module uart_rx #(
    parameter int unsigned BAUD_DIV = 868
)(
    input logic clk,
    input logic rst,
    input logic rx,
    output logic [7:0] data,
    output logic valid
);

    localparam int unsigned HALF_DIV = BAUD_DIV / 2;
    localparam int unsigned TIM_W = $clog2(BAUD_DIV + 1);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_START,
        ST_DATA,
        ST_STOP
    } state_t;

    state_t state;

    logic rx_meta;
    logic rx_sync;
    logic rx_prev;
    logic [TIM_W-1:0] tim;
    logic [2:0] bit_idx;

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_prev <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
            rx_prev <= rx_sync;
        end
    end

    wire start_detect = rx_prev & ~rx_sync;

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= ST_IDLE;
            tim     <= '0;
            bit_idx <= '0;
            data    <= '0;
            valid   <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    valid <= 1'b0;
                    if (start_detect) begin
                        state <= ST_START;
                        tim   <= '0;
                    end
                end

                ST_START: begin
                    valid <= 1'b0;
                    if (tim == HALF_DIV - 1) begin
                        if (~rx_sync) begin
                            state   <= ST_DATA;
                            tim     <= '0;
                            bit_idx <= '0;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end else begin
                        tim <= tim + 1'b1;
                    end
                end

                ST_DATA: begin
                    valid <= 1'b0;
                    if (tim == BAUD_DIV - 1) begin
                        data[bit_idx] <= rx_sync;
                        tim <= '0;
                        if (bit_idx == 3'd7)
                            state <= ST_STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else begin
                        tim <= tim + 1'b1;
                    end
                end

                ST_STOP: begin
                    if (tim == BAUD_DIV - 1) begin
                        valid <= rx_sync;
                        state <= ST_IDLE;
                        tim   <= '0;
                    end else begin
                        valid <= 1'b0;
                        tim <= tim + 1'b1;
                    end
                end

                default: begin
                    valid <= 1'b0;
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
