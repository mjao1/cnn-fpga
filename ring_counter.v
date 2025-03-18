module ring_counter(
    input clk,
    input advance,
    output [3:0] R
);
    wire [3:0] D;

    assign D[0] = (R[3] & advance) | (R[0] & ~advance);
    assign D[1] = (R[0] & advance) | (R[1] & ~advance);
    assign D[2] = (R[1] & advance) | (R[2] & ~advance);
    assign D[3] = (R[2] & advance) | (R[3] & ~advance);

    FDRE #(.INIT(1'b1)) FF0 (.C(clk), .R(1'b0), .CE(1'b1), .D(D[0]), .Q(R[0]));
    FDRE #(.INIT(1'b0)) FF1 (.C(clk), .R(1'b0), .CE(1'b1), .D(D[1]), .Q(R[1]));
    FDRE #(.INIT(1'b0)) FF2 (.C(clk), .R(1'b0), .CE(1'b1), .D(D[2]), .Q(R[2]));
    FDRE #(.INIT(1'b0)) FF3 (.C(clk), .R(1'b0), .CE(1'b1), .D(D[3]), .Q(R[3]));

endmodule
