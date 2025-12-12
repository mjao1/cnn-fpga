`timescale 1ns / 1ps

module hex7seg(
    input d3, d2, d1, d0,
    output CA, CB, CC, CD, CE, CF, CG
    );  

    assign CA = ~((~d3&~d2&~d1&~d0)|(~d3&~d2&d1&~d0)|(~d3&~d2&d1&d0)|(~d3&d2&~d1&d0)|(~d3&d2&d1&~d0)|(~d3&d2&d1&d0)|(d3&~d2&~d1&~d0)|(d3&~d2&~d1&d0)|(d3&~d2&d1&~d0)|(d3&d2&~d1&~d0)|(d3&d2&d1&~d0)|(d3&d2&d1&d0));
    assign CB = ~((~d3&~d2&~d1&~d0)|(~d3&~d2&~d1&d0)|(~d3&~d2&d1&~d0)|(~d3&~d2&d1&d0)|(~d3&d2&~d1&~d0)|(~d3&d2&d1&d0)|(d3&~d2&~d1&~d0)|(d3&~d2&~d1&d0)|(d3&~d2&d1&~d0)|(d3&d2&~d1&d0));
    assign CC = ~((~d3&~d2&~d1&~d0)|(~d3&~d2&~d1&d0)|(~d3&~d2&d1&d0)|(~d3&d2&~d1&~d0)|(~d3&d2&~d1&d0)|(~d3&d2&d1&~d0)|(~d3&d2&d1&d0)|(d3&~d2&~d1&~d0)|(d3&~d2&~d1&d0)|(d3&~d2&d1&~d0)|(d3&~d2&d1&d0)|(d3&d2&~d1&d0));
    assign CD = ~((~d3&~d2&~d1&~d0)|(~d3&~d2&d1&~d0)|(~d3&~d2&d1&d0)|(~d3&d2&~d1&d0)|(~d3&d2&d1&~d0)|(d3&~d2&~d1&~d0)|(d3&~d2&~d1&d0)|(d3&~d2&d1&d0)|(d3&d2&~d1&~d0)|(d3&d2&~d1&d0)|(d3&d2&d1&~d0));
    assign CE = ~((~d3&~d2&~d1&~d0)|(~d3&~d2&d1&~d0)|(~d3&d2&d1&~d0)|(d3&~d2&~d1&~d0)|(d3&~d2&d1&~d0)|(d3&~d2&d1&d0)|(d3&d2&~d1&~d0)|(d3&d2&~d1&d0)|(d3&d2&d1&~d0)|(d3&d2&d1&d0));
    assign CF = ~((~d3&~d2&~d1&~d0)|(~d3&d2&~d1&~d0)|(~d3&d2&~d1&d0)|(~d3&d2&d1&~d0)|(d3&~d2&~d1&~d0)|(d3&~d2&~d1&d0)|(d3&~d2&d1&~d0)|(d3&~d2&d1&d0)|(d3&d2&~d1&~d0)|(d3&d2&d1&~d0)|(d3&d2&d1&d0));
    assign CG = ~((~d3&~d2&d1&~d0)|(~d3&~d2&d1&d0)|(~d3&d2&~d1&~d0)|(~d3&d2&~d1&d0)|(~d3&d2&d1&~d0)|(d3&~d2&~d1&~d0)|(d3&~d2&~d1&d0)|(d3&~d2&d1&~d0)|(d3&~d2&d1&d0)|(d3&d2&~d1&d0)|(d3&d2&d1&~d0)|(d3&d2&d1&d0));
    
endmodule
