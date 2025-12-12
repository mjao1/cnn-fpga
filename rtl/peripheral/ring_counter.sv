module ring_counter(
    input clk,
    input advance,
    output [3:0] R
);
    logic [3:0] D;
    logic [3:0] R_reg;

    assign D[0] = (R_reg[3] & advance) | (R_reg[0] & ~advance);
    assign D[1] = (R_reg[0] & advance) | (R_reg[1] & ~advance);
    assign D[2] = (R_reg[1] & advance) | (R_reg[2] & ~advance);
    assign D[3] = (R_reg[2] & advance) | (R_reg[3] & ~advance);

    assign R = R_reg;

    always_ff @(posedge clk) begin
        R_reg[0] <= D[0];
        R_reg[1] <= D[1];
        R_reg[2] <= D[2];
        R_reg[3] <= D[3];
    end

    initial begin
        R_reg[0] = 1'b1;
        R_reg[1] = 1'b0;
        R_reg[2] = 1'b0;
        R_reg[3] = 1'b0;
    end

endmodule
