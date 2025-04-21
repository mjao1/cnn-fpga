// Third fully connected layer for LeNet-5 CNN (Output Layer)
// Input: 84 neurons from FC2
// Output: 10 neurons (digit classification, no ReLU needed)

module fc_layer_3 #(
    parameter IN_FEATURES = 84,     // Input features from FC2
    parameter OUT_FEATURES = 10,    // Output neurons (digits 0-9)
    parameter DATA_WIDTH = 8,       // Data width (8-bit fixed point)
    parameter SHIFT = 10
)(
    input wire clk,
    input wire rst,
    input wire valid_in,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire [6:0] addr_in,
    
    output reg valid_out,
    output reg [DATA_WIDTH-1:0] data_out,
    output reg [3:0] neuron_idx,
    output reg done_out
);
    // States
    localparam IDLE = 3'b000;         // Waiting for input
    localparam LOAD = 3'b001;         // Loading input features
    localparam COMPUTE = 3'b010;      // Compute one neuron
    localparam NEXT_NEURON = 3'b011;  // Move to next neuron
    localparam DONE = 3'b100;         // All neurons processed
    
    reg [2:0] state;
    reg [3:0] current_neuron;
    reg [6:0] current_input;
    
    reg [DATA_WIDTH-1:0] input_buffer [0:IN_FEATURES-1];
    reg [IN_FEATURES-1:0] input_valid;
    
    reg signed [19:0] accumulator;
    
    wire [DATA_WIDTH-1:0] weight;
    wire [DATA_WIDTH-1:0] bias;
    
    reg [$clog2(IN_FEATURES):0] valid_count;
    reg process_ready;
    
    weight_loader #(
        .DATA_WIDTH(DATA_WIDTH)
    ) weight_loader_inst (
        .clk(clk),
        .rst(rst),
        .layer_select(8'd4),          // FC3 layer
        .filter_idx(8'd0),            // Not used
        .in_channel(8'd0),            // Not used
        .kernel_row(8'd0),            // Not used
        .kernel_col(8'd0),            // Not used
        .input_idx({9'd0, current_input}),  // Which input feature (0-83)
        .neuron_idx({12'd0, current_neuron}), // Which output neuron (0-9)
        .weight_out(weight),
        .bias_out(bias)
    );
    
    // Saturation function
    function signed [7:0] saturate;
        input signed [19:0] value;
        begin
            if (value > 20'sd127)
                saturate = 8'sd127;
            else if (value < -20'sd128)
                saturate = -8'sd128;    
            else
                saturate = value[7:0];
        end
    endfunction
    
    integer i;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            current_neuron <= 4'd0;
            current_input <= 7'd0;
            valid_out <= 1'b0;
            data_out <= 8'd0;
            neuron_idx <= 4'd0;
            done_out <= 1'b0;
            process_ready <= 1'b0;
            valid_count <= 0;
            
            for (i = 0; i < IN_FEATURES; i = i + 1) begin
                input_buffer[i] <= 8'd0;
                input_valid[i] <= 1'b0;
            end
        end else begin
            valid_out <= 1'b0;
            
            // Process incoming data (can happen in any state)
            if (valid_in) begin
                input_buffer[addr_in] <= data_in;
                input_valid[addr_in] <= 1'b1;
                
                if (!input_valid[addr_in]) begin
                    valid_count <= valid_count + 1;
                end
                
                // Check if all inputs received
                if (valid_count == IN_FEATURES - 1 && !input_valid[addr_in]) begin
                    process_ready <= 1'b1;
                end
            end
            
            // State machine
            case (state)
                IDLE: begin
                    done_out <= 1'b0;
                    if (process_ready) begin
                        current_neuron <= 4'd0;
                        current_input <= 7'd0;
                        state <= LOAD;
                    end
                end
                
                LOAD: begin
                    accumulator <= {{12{bias[7]}}, bias};
                    state <= COMPUTE;
                end
                
                COMPUTE: begin
                    // MAC operation (accumulator + weight * input)
                    accumulator <= accumulator + $signed(weight) * $signed(input_buffer[current_input]);
                    
                    if (current_input == IN_FEATURES - 1) begin
                        state <= NEXT_NEURON;
                    end else begin
                        current_input <= current_input + 7'd1;
                    end
                end
                
                NEXT_NEURON: begin
                    valid_out <= 1'b1;
                    data_out <= saturate(accumulator >> SHIFT);
                    neuron_idx <= current_neuron;
                    
                    // Move to next neuron or finish
                    if (current_neuron == OUT_FEATURES - 1) begin
                        state <= DONE;
                    end else begin
                        current_neuron <= current_neuron + 4'd1;
                        current_input <= 7'd0;
                        state <= LOAD; // goto LOAD state to get next
                    end
                end
                
                DONE: begin
                    done_out <= 1'b1;
                    // Stay in DONE state until reset
                    if (!process_ready) begin
                        state <= IDLE;
                        valid_count <= 0;
                        for (i = 0; i < IN_FEATURES; i = i + 1) begin
                            input_valid[i] <= 1'b0;
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule 
