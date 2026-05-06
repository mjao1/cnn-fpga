// Memory wrapper for FC1 layer weights
`ifndef WEIGHTS_DIR
`ifdef __ICARUS__
`define WEIGHTS_DIR "weights_mem/"
`else
`define WEIGHTS_DIR ""
`endif
`endif
module fc1_weight_mem #(
    parameter DATA_WIDTH = 8,
    parameter IN_FEATURES = 256,
    parameter OUT_FEATURES = 120,
    parameter NEURON_IDX_W = $clog2(OUT_FEATURES),
    parameter INPUT_IDX_W = $clog2(IN_FEATURES)
)(
    input wire clk,
    input wire rst,
    
    input wire [NEURON_IDX_W-1:0] neuron_idx,
    input wire [INPUT_IDX_W-1:0] input_idx,
    output wire [DATA_WIDTH-1:0] weight_out
);

    localparam DEPTH = IN_FEATURES * OUT_FEATURES;
    localparam ADDR_WIDTH = $clog2(DEPTH);
    
    // Address based on indices
    wire [ADDR_WIDTH-1:0] read_addr;
    assign read_addr = neuron_idx * IN_FEATURES + input_idx;
    
    bram_weights #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DEPTH(DEPTH),
        .MEM_INIT_FILE({`WEIGHTS_DIR, "fc1_weights.mem"})
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
