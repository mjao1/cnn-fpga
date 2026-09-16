// 5x5 convolution module for CNN
// Fixed-Point Format: Q1.7
// Input: (data, weights, bias) 8-bit signed, Q1.7 format
// Output: 8-bit signed, Q1.7 format
// Serial: 25 data/weight pairs, one pair per cycle, then bias on weight_in, then result

module conv_5x5 #(
    parameter integer FRAC_BITS = 7
) (
    input  logic               clk_i,
    input  logic               rst_i,
    input  logic               start_i,
    input  logic signed [7:0]  data_i,
    input  logic signed [7:0]  weight_i,
    output logic               done_o,
    output logic signed [7:0]  data_o,
    output logic signed [23:0] raw_sum_o
);

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_ACCUMULATE,
        STATE_BIAS,
        STATE_DONE
    } state_t;

    state_t state;
    logic [4:0] count;
    logic signed [23:0] acc;

    state_t state_n;
    logic [4:0] count_n;
    logic signed [23:0] acc_n;
    logic done_n;
    logic signed [7:0] data_n;
    logic signed [23:0] raw_sum_n;
    (* use_dsp = "yes" *)
    logic signed [15:0] prod_16;
    logic signed [23:0] product;
    logic signed [23:0] bias_scaled;
    logic signed [23:0] scaled_acc;
    logic signed [7:0] saturated;

    assign prod_16 = data_i * weight_i;
    assign product = {{8{prod_16[15]}}, prod_16};
    assign bias_scaled = $signed({{16{weight_i[7]}}, weight_i}) << FRAC_BITS;
    assign scaled_acc = acc >>> FRAC_BITS;
    assign saturated = (scaled_acc > 24'sd127) ? 8'sd127 :
                       (scaled_acc < -24'sd128) ? -8'sd128 :
                       scaled_acc[7:0];

    always_comb begin
        state_n   = state;
        count_n   = count;
        acc_n     = acc;
        done_n    = done_o;
        data_n    = data_o;
        raw_sum_n = raw_sum_o;

        case (state)
            STATE_IDLE: begin
                done_n = 1'b0;
                if (start_i) begin
                    acc_n   = 24'sd0;
                    count_n = 5'd0;
                    state_n = STATE_ACCUMULATE;
                end
            end

            STATE_ACCUMULATE: begin
                acc_n   = acc + product;
                count_n = count + 5'd1;
                if (count == 5'd24)
                    state_n = STATE_BIAS;
            end

            STATE_BIAS: begin
                acc_n   = acc + bias_scaled;
                state_n = STATE_DONE;
            end

            STATE_DONE: begin
                data_n    = saturated;
                raw_sum_n = acc;
                done_n    = 1'b1;
                state_n   = STATE_IDLE;
            end

            default: state_n = STATE_IDLE;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state     <= STATE_IDLE;
            count     <= 5'd0;
            acc       <= 24'sd0;
            done_o    <= 1'b0;
            data_o    <= 8'sd0;
            raw_sum_o <= 24'sd0;
        end else begin
            state     <= state_n;
            count     <= count_n;
            acc       <= acc_n;
            done_o    <= done_n;
            data_o    <= data_n;
            raw_sum_o <= raw_sum_n;
        end
    end

endmodule
