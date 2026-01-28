// Optimized 8-bit signed multiplier for Q1.7 arithmetic
// Input: Two 8-bit signed operands
// Output: 24-bit sign extended product for accumulation

module mult_8x8_signed (
    input wire signed [7:0] a,
    input wire signed [7:0] b,
    output wire signed [23:0] product
);
    // Internal 16-bit product
    wire signed [15:0] prod_16;
    
    // Sign extend inputs to 16 bits
    wire signed [15:0] a_ext = {{8{a[7]}}, a};
    
    wire signed [15:0] pp [0:7];
    
    // Partial products
    assign pp[0] = b[0] ? a_ext : 16'sd0;
    assign pp[1] = b[1] ? (a_ext << 1) : 16'sd0;
    assign pp[2] = b[2] ? (a_ext << 2) : 16'sd0;
    assign pp[3] = b[3] ? (a_ext << 3) : 16'sd0;
    assign pp[4] = b[4] ? (a_ext << 4) : 16'sd0;
    assign pp[5] = b[5] ? (a_ext << 5) : 16'sd0;
    assign pp[6] = b[6] ? (a_ext << 6) : 16'sd0;
    // Subtract for bit 7 in 2's complement when b[7] is set
    assign pp[7] = b[7] ? (~(a_ext << 7) + 1'b1) : 16'sd0;
    
    // Sum partial products in balanced tree
    wire signed [15:0] sum01 = pp[0] + pp[1];
    wire signed [15:0] sum23 = pp[2] + pp[3];
    wire signed [15:0] sum45 = pp[4] + pp[5];
    wire signed [15:0] sum67 = pp[6] + pp[7];
    
    wire signed [15:0] sum0123 = sum01 + sum23;
    wire signed [15:0] sum4567 = sum45 + sum67;
    
    assign prod_16 = sum0123 + sum4567;
    
    // Sign extend to 24 bits
    assign product = {{8{prod_16[15]}}, prod_16};

endmodule
