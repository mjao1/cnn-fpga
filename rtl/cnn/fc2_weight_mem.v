// Memory wrapper for FC2 layer weights
module fc2_weight_mem #(
    parameter DATA_WIDTH = 8,
    parameter IN_FEATURES = 256,
    parameter OUT_FEATURES = 120
)(
    input wire clk,
    input wire rst,
    
    input wire [15:0] neuron_idx,
    input wire [15:0] input_idx,
    output wire [DATA_WIDTH-1:0] weight_out
);

    localparam ADDR_WIDTH = 15;  // ceil(log2(IN_FEATURES * OUT_FEATURES))
    localparam DEPTH = IN_FEATURES * OUT_FEATURES;
    
    // Address based on indices
    wire [ADDR_WIDTH-1:0] read_addr;
    assign read_addr = neuron_idx * IN_FEATURES + input_idx;
    
    bram_weights #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DEPTH(DEPTH),
        .MEM_INIT_FILE("fc7_weights.mif")
    ) weight_mem (
        .clk(clk),
        .rst(rst),
        
        // Port A (unused)
        .addr_a({ADDR_WIDTH{1'b0}}),
        .data_in_a({DATA_WIDTH{1'b0}}),
        .we_a(1'b0),
        .data_out_a(),
        
        // Port B (readonly)
        .addr_b(read_addr),
        .data_out_b(weight_out)
    );

endmodule 
