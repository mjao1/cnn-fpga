// 5x5 convolution module for CNN
// Fixed-Point Format: Q1.7
// Input: (data, weights, bias) 8-bit signed, Q1.7 format
// Output: 8-bit signed, Q1.7 format
// Serial: 25 data/weight pairs, one pair per cycle, then bias on weight_in, then result

module conv_5x5 #(
    parameter integer FRAC_BITS = 7
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [7:0] data_in,
    input wire signed [7:0] weight_in,
    output reg done,
    output reg signed [7:0] data_out,
    output reg signed [23:0] raw_sum
);

    localparam STATE_IDLE       = 2'd0;
    localparam STATE_ACCUMULATE = 2'd1;
    localparam STATE_BIAS       = 2'd2;
    localparam STATE_DONE       = 2'd3;

    reg [1:0] state;
    reg [4:0] count;
    reg signed [23:0] acc;

    (* use_dsp = "yes" *)
    wire signed [15:0] prod_16 = data_in * weight_in;
    wire signed [23:0] product = {{8{prod_16[15]}}, prod_16};

    wire signed [23:0] bias_scaled = $signed({{16{weight_in[7]}}, weight_in}) << FRAC_BITS;
    wire signed [23:0] scaled_acc = acc >>> FRAC_BITS;

    wire signed [7:0] saturated;
    assign saturated = (scaled_acc > 24'sd127) ? 8'sd127 : (scaled_acc < -24'sd128) ? -8'sd128 : scaled_acc[7:0];

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            count <= 5'd0;
            acc <= 24'sd0;
            done <= 1'b0;
            data_out <= 8'sd0;
            raw_sum <= 24'sd0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        acc   <= 24'sd0;
                        count <= 5'd0;
                        state <= STATE_ACCUMULATE;
                    end
                end

                STATE_ACCUMULATE: begin
                    acc   <= acc + product;
                    count <= count + 5'd1;
                    if (count == 5'd24)
                        state <= STATE_BIAS;
                end

                STATE_BIAS: begin
                    acc   <= acc + bias_scaled;
                    state <= STATE_DONE;
                end

                STATE_DONE: begin
                    data_out <= saturated;
                    raw_sum  <= acc;
                    done     <= 1'b1;
                    state    <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
