// Top module for the fully connected layers of LeNet-5 CNN
// Integrates FC1, FC2, and FC3 layers sequentially

module fc_layers #(
    parameter FC1_IN_FEATURES = 256,
    parameter FC1_OUT_FEATURES = 120,
    parameter FC2_IN_FEATURES = 120,
    parameter FC2_OUT_FEATURES = 84,
    parameter FC3_IN_FEATURES = 84,
    parameter FC3_OUT_FEATURES = 10,
    parameter DATA_WIDTH = 8
)(
    input wire clk,
    input wire rst,
    input wire start,                      // Start processing signal
    input wire valid_in,                   // Input data valid
    input wire [DATA_WIDTH-1:0] data_in,   // Input data from flatten layer
    input wire [7:0] addr_in,              // Address of input data (0-255)
    
    output reg valid_out,                  // Output valid signal
    output reg [DATA_WIDTH-1:0] data_out,  // Output class scores
    output reg [3:0] digit_idx,            // Digit index (0-9)
    output reg done_out                    // Processing complete
);

    // State machine states
    localparam IDLE = 3'b000;
    localparam FC1_PROC = 3'b001;
    localparam FC2_PROC = 3'b010;
    localparam FC3_PROC = 3'b011;
    localparam DONE = 3'b100;
    
    reg [2:0] state;
    
    // FC1 signals
    wire fc1_valid_out;
    wire [DATA_WIDTH-1:0] fc1_data_out;
    wire [7:0] fc1_neuron_idx;
    wire fc1_done_out;
    
    // FC2 signals
    reg fc2_valid_in;
    reg [DATA_WIDTH-1:0] fc2_data_in;
    reg [6:0] fc2_addr_in;
    wire fc2_valid_out;
    wire [DATA_WIDTH-1:0] fc2_data_out;
    wire [6:0] fc2_neuron_idx;
    wire fc2_done_out;
    
    // FC3 signals
    reg fc3_valid_in;
    reg [DATA_WIDTH-1:0] fc3_data_in;
    reg [6:0] fc3_addr_in;
    wire fc3_valid_out;
    wire [DATA_WIDTH-1:0] fc3_data_out;
    wire [3:0] fc3_neuron_idx;
    wire fc3_done_out;
    
    // Instantiate FC1 layer (256 -> 120)
    fc_layer_1 #(
        .IN_FEATURES(FC1_IN_FEATURES),
        .OUT_FEATURES(FC1_OUT_FEATURES),
        .DATA_WIDTH(DATA_WIDTH)
    ) fc1 (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .data_in(data_in),
        .addr_in(addr_in),
        .valid_out(fc1_valid_out),
        .data_out(fc1_data_out),
        .neuron_idx(fc1_neuron_idx),
        .done_out(fc1_done_out)
    );
    
    // Instantiate FC2 layer (120 -> 84)
    fc_layer_2 #(
        .IN_FEATURES(FC2_IN_FEATURES),
        .OUT_FEATURES(FC2_OUT_FEATURES),
        .DATA_WIDTH(DATA_WIDTH)
    ) fc2 (
        .clk(clk),
        .rst(rst),
        .valid_in(fc2_valid_in),
        .data_in(fc2_data_in),
        .addr_in(fc2_addr_in),
        .valid_out(fc2_valid_out),
        .data_out(fc2_data_out),
        .neuron_idx(fc2_neuron_idx),
        .done_out(fc2_done_out)
    );
    
    // Instantiate FC3 layer (84 -> 10)
    fc_layer_3 #(
        .IN_FEATURES(FC3_IN_FEATURES),
        .OUT_FEATURES(FC3_OUT_FEATURES),
        .DATA_WIDTH(DATA_WIDTH)
    ) fc3 (
        .clk(clk),
        .rst(rst),
        .valid_in(fc3_valid_in),
        .data_in(fc3_data_in),
        .addr_in(fc3_addr_in),
        .valid_out(fc3_valid_out),
        .data_out(fc3_data_out),
        .neuron_idx(fc3_neuron_idx),
        .done_out(fc3_done_out)
    );
    
    // Main state machine
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            fc2_valid_in <= 1'b0;
            fc2_data_in <= 8'd0;
            fc2_addr_in <= 7'd0;
            fc3_valid_in <= 1'b0;
            fc3_data_in <= 8'd0;
            fc3_addr_in <= 7'd0;
            valid_out <= 1'b0;
            data_out <= 8'd0;
            digit_idx <= 4'd0;
            done_out <= 1'b0;
        end else begin
            // Default signal values
            fc2_valid_in <= 1'b0;
            fc3_valid_in <= 1'b0;
            valid_out <= 1'b0;
            
            case (state)
                IDLE: begin
                    done_out <= 1'b0;
                    if (start) begin
                        state <= FC1_PROC;
                    end
                end
                
                FC1_PROC: begin
                    // Pass data from FC1 to FC2
                    if (fc1_valid_out) begin
                        fc2_valid_in <= 1'b1;
                        fc2_data_in <= fc1_data_out;
                        fc2_addr_in <= fc1_neuron_idx[6:0];
                    end
                    
                    // Transition to FC2 when FC1 is done
                    if (fc1_done_out) begin
                        state <= FC2_PROC;
                    end
                end
                
                FC2_PROC: begin
                    // Pass data from FC2 to FC3
                    if (fc2_valid_out) begin
                        fc3_valid_in <= 1'b1;
                        fc3_data_in <= fc2_data_out;
                        fc3_addr_in <= fc2_neuron_idx;
                    end
                    
                    // Transition to FC3 when FC2 is done
                    if (fc2_done_out) begin
                        state <= FC3_PROC;
                    end
                end
                
                FC3_PROC: begin
                    // Pass final results to output
                    if (fc3_valid_out) begin
                        valid_out <= 1'b1;
                        data_out <= fc3_data_out;
                        digit_idx <= fc3_neuron_idx;
                    end
                    
                    // Transition to DONE when FC3 is done
                    if (fc3_done_out) begin
                        state <= DONE;
                        done_out <= 1'b1;
                    end
                end
                
                DONE: begin
                    done_out <= 1'b1;
                    // Stay in DONE until reset or new start signal
                    if (start) begin
                        state <= IDLE;
                        done_out <= 1'b0;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule 
