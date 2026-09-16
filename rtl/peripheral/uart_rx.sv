// UART RX 8N1 LSB-first: sync rx, detect start, sample mid-bit using bit-period counter.

module uart_rx #(
    parameter int unsigned BAUD_DIV = 868
)(
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic       rx_i,
    output logic [7:0] data_o,
    output logic       valid_o
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

    state_t state_n;
    logic [TIM_W-1:0] tim_n;
    logic [2:0] bit_idx_n;
    logic valid_o_n;
    logic start_detect;
    logic sample_bit;

    assign start_detect = rx_prev & ~rx_sync;
    assign sample_bit = (state == ST_DATA) && (tim == BAUD_DIV - 1);

    always_comb begin
        state_n   = state;
        tim_n     = tim;
        bit_idx_n = bit_idx;
        valid_o_n = 1'b0;

        case (state)
            ST_IDLE: begin
                if (start_detect) begin
                    state_n = ST_START;
                    tim_n   = {TIM_W{1'b0}};
                end
            end

            ST_START: begin
                if (tim == HALF_DIV - 1) begin
                    if (~rx_sync) begin
                        state_n   = ST_DATA;
                        tim_n     = {TIM_W{1'b0}};
                        bit_idx_n = 3'd0;
                    end else begin
                        state_n = ST_IDLE;
                    end
                end else begin
                    tim_n = tim + 1'b1;
                end
            end

            ST_DATA: begin
                if (tim == BAUD_DIV - 1) begin
                    tim_n = {TIM_W{1'b0}};
                    if (bit_idx == 3'd7) begin
                        state_n = ST_STOP;
                    end else begin
                        bit_idx_n = bit_idx + 1'b1;
                    end
                end else begin
                    tim_n = tim + 1'b1;
                end
            end

            ST_STOP: begin
                if (tim == BAUD_DIV - 1) begin
                    valid_o_n = rx_sync;
                    state_n   = ST_IDLE;
                    tim_n     = {TIM_W{1'b0}};
                end else begin
                    tim_n = tim + 1'b1;
                end
            end

            default: state_n = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_prev <= 1'b1;
        end else begin
            rx_meta <= rx_i;
            rx_sync <= rx_meta;
            rx_prev <= rx_sync;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state   <= ST_IDLE;
            tim     <= {TIM_W{1'b0}};
            bit_idx <= 3'd0;
            data_o  <= 8'd0;
            valid_o <= 1'b0;
        end else begin
            state   <= state_n;
            tim     <= tim_n;
            bit_idx <= bit_idx_n;
            valid_o <= valid_o_n;
            if (sample_bit) begin
                data_o[bit_idx] <= rx_sync;
            end
        end
    end

endmodule
