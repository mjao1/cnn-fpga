// second fully connected layer
// Input: 120 neurons from FC1
// Output: 84 neurons with ReLU activation
// Computes NUM_PARALLEL neurons simultaneously per batch

module fc_layer_2 #(
    parameter IN_FEATURES = 120,
    parameter OUT_FEATURES = 84,
    parameter DATA_WIDTH = 8,
    parameter FRAC_BITS = 7,
    parameter NUM_PARALLEL = 12
)(
    input wire clk,
    input wire rst,
    input wire valid_in,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire [6:0] addr_in,

    output reg valid_out,
    output reg [DATA_WIDTH-1:0] data_out,
    output reg [6:0] neuron_idx,
    output reg done_out
);
    localparam NUM_BATCHES = OUT_FEATURES / NUM_PARALLEL;
    localparam MEM_NEURON_W = $clog2(OUT_FEATURES);
    localparam MEM_INPUT_W  = $clog2(IN_FEATURES);

    // States
    localparam IDLE = 4'd0;
    localparam LOAD = 4'd1;
    localparam LOAD_BASE_HOLD = 4'd7;
    localparam WAIT_WEIGHT = 4'd2;
    localparam COMPUTE_MULT = 4'd3;
    localparam COMPUTE_ACC = 4'd4;
    localparam OUTPUT = 4'd5;
    localparam DONE = 4'd6;

    reg [3:0] state;
    reg [6:0] current_batch;
    reg [6:0] current_input;
    reg [6:0] compute_input_idx;  // Delayed index for pipelined MAC
    reg [$clog2(NUM_PARALLEL)-1:0] output_idx;

    reg [DATA_WIDTH-1:0] input_buffer [0:IN_FEATURES-1];
    reg [IN_FEATURES-1:0] input_valid;

    reg signed [23:0] accumulator [0:NUM_PARALLEL-1];
    reg signed [15:0] partial_product [0:NUM_PARALLEL-1];

    wire [DATA_WIDTH-1:0] weight [0:NUM_PARALLEL-1];
    wire [DATA_WIDTH-1:0] bias [0:NUM_PARALLEL-1];

    // Pipeline register (capture input_buffer mux output)
    reg [DATA_WIDTH-1:0] input_data_q;

    reg [$clog2(IN_FEATURES):0] valid_count;
    reg process_ready;

    reg [MEM_NEURON_W:0] neuron_idx_base_r;

    genvar p;
    generate
        for (p = 0; p < NUM_PARALLEL; p = p + 1) begin : par
            wire [MEM_NEURON_W-1:0] mem_neuron_idx;
            wire [MEM_INPUT_W-1:0] mem_input_idx;
            assign mem_neuron_idx = neuron_idx_base_r[MEM_NEURON_W-1:0] + p[$clog2(NUM_PARALLEL)-1:0];
            assign mem_input_idx = current_input;

            fc2_weight_mem #(
                .DATA_WIDTH(DATA_WIDTH),
                .IN_FEATURES(IN_FEATURES),
                .OUT_FEATURES(OUT_FEATURES)
            ) fc2_weights (
                .clk(clk),
                .rst(rst),
                .neuron_idx(mem_neuron_idx),
                .input_idx(mem_input_idx),
                .weight_out(weight[p])
            );

            fc2_bias_mem #(
                .DATA_WIDTH(DATA_WIDTH),
                .NUM_NEURONS(OUT_FEATURES)
            ) fc2_biases (
                .clk(clk),
                .rst(rst),
                .neuron_idx(mem_neuron_idx),
                .bias_out(bias[p])
            );
        end
    endgenerate

    // Scale and saturate function
    function automatic signed [7:0] scale_and_saturate;
        input signed [23:0] acc_value;
        reg signed [23:0] scaled;
        begin
            scaled = acc_value >>> FRAC_BITS;
            
            if (scaled > 24'sd127)
                scale_and_saturate = 8'sd127;
            else if (scaled < 24'sd0)
                scale_and_saturate = 8'sd0;
            else
                scale_and_saturate = scaled[7:0];
        end
    endfunction

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            current_batch <= 7'd0;
            current_input <= 7'd0;
            compute_input_idx <= 7'd0;
            output_idx <= 0;
            valid_out <= 1'b0;
            data_out <= 8'd0;
            neuron_idx <= 7'd0;
            done_out <= 1'b0;
            process_ready <= 1'b0;
            valid_count <= 0;
            input_data_q <= 8'd0;
            for (i = 0; i < NUM_PARALLEL; i = i + 1)
                partial_product[i] <= 16'sd0;

            for (i = 0; i < IN_FEATURES; i = i + 1) begin
                input_buffer[i] <= 8'd0;
                input_valid[i] <= 1'b0;
            end
            neuron_idx_base_r <= {(MEM_NEURON_W+1){1'b0}};
        end else begin
            valid_out <= 1'b0;
            input_data_q <= input_buffer[current_input];

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
                        current_batch <= 7'd0;
                        current_input <= 7'd0;
                        state <= LOAD;
                    end
                end

                LOAD: begin
                    neuron_idx_base_r <= current_batch * NUM_PARALLEL;
                    state <= LOAD_BASE_HOLD;
                end

                LOAD_BASE_HOLD: begin
                    state <= WAIT_WEIGHT;
                end

                WAIT_WEIGHT: begin
                    for (i = 0; i < NUM_PARALLEL; i = i + 1)
                        accumulator[i] <= {{16{bias[i][7]}}, bias[i]} << FRAC_BITS;
                    compute_input_idx <= current_input;
                    current_input <= current_input + 7'd1;
                    state <= COMPUTE_MULT;
                end

                COMPUTE_MULT: begin
                    for (i = 0; i < NUM_PARALLEL; i = i + 1)
                        partial_product[i] <= $signed(weight[i]) * $signed(input_data_q);
                    state <= COMPUTE_ACC;
                end

                COMPUTE_ACC: begin
                    for (i = 0; i < NUM_PARALLEL; i = i + 1)
                        accumulator[i] <= accumulator[i] + {{8{partial_product[i][15]}}, partial_product[i]};

                    if (compute_input_idx == IN_FEATURES - 1) begin
                        output_idx <= 0;
                        state <= OUTPUT;
                    end else begin
                        compute_input_idx <= current_input;
                        current_input <= current_input + 7'd1;
                        state <= COMPUTE_MULT;
                    end
                end

                OUTPUT: begin
                    valid_out <= 1'b1;
                    data_out <= scale_and_saturate(accumulator[output_idx]);
                    neuron_idx <= neuron_idx_base_r[MEM_NEURON_W-1:0] + output_idx;

                    if (output_idx == NUM_PARALLEL - 1) begin
                        if (current_batch == NUM_BATCHES - 1) begin
                            state <= DONE;
                            process_ready <= 1'b0;
                        end else begin
                            current_batch <= current_batch + 7'd1;
                            current_input <= 7'd0;
                            compute_input_idx <= 7'd0;
                            state <= LOAD;
                        end
                    end else begin
                        output_idx <= output_idx + 1;
                    end
                end

                DONE: begin
                    done_out <= 1'b1;
                    // Stay in DONE until reset
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
