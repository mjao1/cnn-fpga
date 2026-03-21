// Third fully connected layer for LeNet-5 CNN (Output Layer)
// Input: 84 neurons from FC2
// Output: 10 neurons (digit classification, no ReLU needed)

module fc_layer_3 #(
    parameter IN_FEATURES = 84,     // Input features from FC2
    parameter OUT_FEATURES = 10,    // Output neurons (digits 0-9)
    parameter DATA_WIDTH = 8,       // Data width (8-bit fixed point)
    parameter FRAC_BITS = 7
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
    localparam WAIT_WEIGHT = 3'b101;  // Wait for first weight from BRAM
    localparam COMPUTE = 3'b010;      // Compute one neuron
    localparam NEXT_NEURON = 3'b011;  // Move to next neuron
    localparam DONE = 3'b100;         // All neurons processed
    
    reg [2:0] state;
    reg [3:0] current_neuron;
    reg [6:0] current_input;
    reg [6:0] compute_input_idx;  // Delayed index for pipelined MAC
    
    reg [DATA_WIDTH-1:0] input_buffer [0:IN_FEATURES-1];
    reg [IN_FEATURES-1:0] input_valid;
    
    reg signed [23:0] accumulator;
    
    wire [DATA_WIDTH-1:0] weight;
    wire [DATA_WIDTH-1:0] bias;
    
    reg [$clog2(IN_FEATURES):0] valid_count;
    reg process_ready;
    
    fc3_weight_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_FEATURES(IN_FEATURES),
        .OUT_FEATURES(OUT_FEATURES)
    ) fc3_weights (
        .clk(clk),
        .rst(rst),
        .neuron_idx({4'd0, current_neuron}),
        .input_idx({9'd0, current_input}),
        .weight_out(weight)
    );

    fc3_bias_mem #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_NEURONS(OUT_FEATURES)
    ) fc3_biases (
        .clk(clk),
        .rst(rst),
        .neuron_idx({4'd0, current_neuron}),
        .bias_out(bias)
    );
    
    // Scale and saturate function
    function automatic signed [7:0] scale_and_saturate;
        input signed [23:0] acc_value;
        reg signed [23:0] scaled;
        begin
            scaled = acc_value >>> FRAC_BITS;
            
            if (scaled > 24'sd127)
                scale_and_saturate = 8'sd127;
            else if (scaled < -24'sd128)
                scale_and_saturate = -8'sd128;
            else
                scale_and_saturate = scaled[7:0];
        end
    endfunction
    
    integer i;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            current_neuron <= 4'd0;
            current_input <= 7'd0;
            compute_input_idx <= 7'd0;
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
                    state <= WAIT_WEIGHT;
                end
                
                WAIT_WEIGHT: begin
                    accumulator <= {{16{bias[7]}}, bias} << FRAC_BITS;
                    compute_input_idx <= current_input;
                    current_input <= current_input + 7'd1;
                    state <= COMPUTE;
                end
                
                COMPUTE: begin
                    accumulator <= accumulator + $signed(weight) * $signed(input_buffer[compute_input_idx]);
                    
                    if (compute_input_idx == IN_FEATURES - 1) begin
                        state <= NEXT_NEURON;
                    end else begin
                        compute_input_idx <= current_input;
                        current_input <= current_input + 7'd1;
                    end
                end
                
                NEXT_NEURON: begin
                    valid_out <= 1'b1;
                    data_out <= scale_and_saturate(accumulator);
                    neuron_idx <= current_neuron;
                    // Move to next neuron or finish
                    if (current_neuron == OUT_FEATURES - 1) begin
                        state <= DONE;
                    end else begin
                        current_neuron <= current_neuron + 4'd1;
                        current_input <= 7'd0;
                        compute_input_idx <= 7'd0;
                        state <= LOAD;
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
