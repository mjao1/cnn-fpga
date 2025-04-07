// Dual-port BRAM for CNN weights/biases with MIF initialization
module bram_weights #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 10,  // adjust based on layer size
    parameter DEPTH = 1024,     // 2^ADDR_WIDTH
    parameter MEM_INIT_FILE = "none"
)(
    input wire clk,
    input wire rst,
    
    input wire [ADDR_WIDTH-1:0] addr_a,
    input wire signed [DATA_WIDTH-1:0] data_in_a,
    input wire we_a,
    output reg signed [DATA_WIDTH-1:0] data_out_a,
    
    input wire [ADDR_WIDTH-1:0] addr_b,
    output reg signed [DATA_WIDTH-1:0] data_out_b
);

    reg signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};
        end
        
        // Load from MIF
        if (MEM_INIT_FILE != "none") begin
            $readmemh(MEM_INIT_FILE, mem);
        end
    end
    
    // Port A (Read/Write port for runtime updates maybe)
    always @(posedge clk) begin
        if (we_a) begin
            mem[addr_a] <= data_in_a;
        end
        data_out_a <= mem[addr_a];
    end
    
    // Port B (Read only port for inference)
    always @(posedge clk) begin
        data_out_b <= mem[addr_b];
    end

endmodule 
