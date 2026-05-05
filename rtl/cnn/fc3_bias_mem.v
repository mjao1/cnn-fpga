// Memory wrapper for FC3 (output) layer biases
`ifndef WEIGHTS_DIR
`define WEIGHTS_DIR "weights_mem/"
`endif
module fc3_bias_mem #(
    parameter DATA_WIDTH = 8,
    parameter NUM_NEURONS = 10
)(
    input wire clk,
    input wire rst,
    
    input wire [7:0] neuron_idx,
    output wire [DATA_WIDTH-1:0] bias_out
);

    localparam ADDR_WIDTH = 4;  // ceil(log2(NUM_NEURONS))
    localparam DEPTH = NUM_NEURONS;

    bram_weights #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DEPTH(DEPTH),
        .MEM_INIT_FILE({`WEIGHTS_DIR, "fc3_biases.mem"})
    ) bias_mem (
        .clk(clk),
        .rst(rst),
        
        // Port A (unused)
        .addr_a({ADDR_WIDTH{1'b0}}),
        .data_in_a({DATA_WIDTH{1'b0}}),
        .we_a(1'b0),
        .data_out_a(),
        
        // Port B (readonly)
        .addr_b(neuron_idx[ADDR_WIDTH-1:0]),
        .data_out_b(bias_out)
    );

endmodule 
