// Memory wrapper for Conv2 layer biases
module conv2_bias_mem #(
    parameter DATA_WIDTH = 8,
    parameter NUM_FILTERS = 16
)(
    input wire clk,
    input wire rst,
    
    input wire [7:0] filter_idx,
    output wire [DATA_WIDTH-1:0] bias_out
);

    localparam ADDR_WIDTH = 4;  // ceil(log2(NUM_FILTERS))
    localparam DEPTH = NUM_FILTERS;
    
    bram_weights #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DEPTH(DEPTH),
        .MEM_INIT_FILE("conv2_biases.mif")
    ) bias_mem (
        .clk(clk),
        .rst(rst),
        
        // Port A (unused)
        .addr_a({ADDR_WIDTH{1'b0}}),
        .data_in_a({DATA_WIDTH{1'b0}}),
        .we_a(1'b0),
        .data_out_a(),
        
        // Port B (readonly)
        .addr_b(filter_idx[ADDR_WIDTH-1:0]),
        .data_out_b(bias_out)
    );

endmodule 
