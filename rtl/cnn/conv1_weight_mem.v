// Memory wrapper for Conv1 layer weights
`ifndef WEIGHTS_DIR
`ifdef __ICARUS__
`define WEIGHTS_DIR "weights_mem/"
`else
`define WEIGHTS_DIR ""
`endif
`endif
module conv1_weight_mem #(
    parameter DATA_WIDTH = 8,
    parameter NUM_FILTERS = 6,
    parameter KERNEL_SIZE = 5,
    parameter IN_CHANNELS = 1
)(
    input wire clk,
    input wire rst,
    
    input wire [7:0] filter_idx,
    input wire [7:0] in_channel,
    input wire [7:0] kernel_row,
    input wire [7:0] kernel_col,
    output wire [DATA_WIDTH-1:0] weight_out
);

    localparam ADDR_WIDTH = 8;  // ceil(log2(NUM_FILTERS * IN_CHANNELS * KERNEL_SIZE * KERNEL_SIZE))
    localparam DEPTH = NUM_FILTERS * IN_CHANNELS * KERNEL_SIZE * KERNEL_SIZE;
    
    // Address based on indices
    wire [ADDR_WIDTH-1:0] read_addr;
    assign read_addr = filter_idx * (IN_CHANNELS * KERNEL_SIZE * KERNEL_SIZE) +
                      in_channel * (KERNEL_SIZE * KERNEL_SIZE) +
                      kernel_row * KERNEL_SIZE +
                      kernel_col;
    
    bram_weights #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DEPTH(DEPTH),
        .MEM_INIT_FILE({`WEIGHTS_DIR, "conv1_weights.mem"})
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
