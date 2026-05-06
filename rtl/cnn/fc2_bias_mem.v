// Memory wrapper for FC2 layer biases
`ifndef WEIGHTS_DIR
`ifdef __ICARUS__
`define WEIGHTS_DIR "weights_mem/"
`else
`define WEIGHTS_DIR ""
`endif
`endif
module fc2_bias_mem #(
    parameter DATA_WIDTH = 8,
    parameter NUM_NEURONS = 84,
    parameter NEURON_IDX_W = $clog2(NUM_NEURONS)
)(
    input wire clk,
    input wire rst,
    
    input wire [NEURON_IDX_W-1:0] neuron_idx,
    output wire [DATA_WIDTH-1:0] bias_out
);

    localparam ADDR_WIDTH = 7;  // ceil(log2(NUM_NEURONS))
    localparam DEPTH = NUM_NEURONS;
    
    bram_weights #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DEPTH(DEPTH),
        .MEM_INIT_FILE({`WEIGHTS_DIR, "fc2_biases.mem"})
    ) bias_mem (
        .clk(clk),
        .rst(rst),
        
        // Port A (unused)
        .addr_a({ADDR_WIDTH{1'b0}}),
        .data_in_a({DATA_WIDTH{1'b0}}),
        .we_a(1'b0),
        .data_out_a(),
        
        // Port B (readonly)
        .addr_b(neuron_idx),
        .data_out_b(bias_out)
    );

endmodule 
