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
    input  logic                  clk_i,
    input  logic                  rst_i,
    input  logic                  valid_i,
    input  logic [DATA_WIDTH-1:0] data_i,
    input  logic [6:0]            addr_i,

    output logic                  valid_o,
    output logic [DATA_WIDTH-1:0] data_o,
    output logic [6:0]            neuron_idx_o,
    output logic                  done_o
);

    localparam NUM_BATCHES = OUT_FEATURES / NUM_PARALLEL;
    localparam MEM_NEURON_W = $clog2(OUT_FEATURES);
    localparam MEM_INPUT_W  = $clog2(IN_FEATURES);

    typedef enum logic [3:0] {
        IDLE           = 4'd0,
        LOAD           = 4'd1,
        LOAD_BASE_HOLD = 4'd7,
        WAIT_WEIGHT    = 4'd2,
        COMPUTE_MULT   = 4'd3,
        COMPUTE_ACC    = 4'd4,
        OUTPUT         = 4'd5,
        DONE           = 4'd6
    } state_t;

    state_t state;
    logic [6:0] current_batch;
    logic [6:0] current_input;
    logic [6:0] compute_input_idx;
    logic [$clog2(NUM_PARALLEL)-1:0] output_idx;
    logic [DATA_WIDTH-1:0] input_buffer [0:IN_FEATURES-1];
    logic [IN_FEATURES-1:0] input_valid;
    (* use_dsp = "yes" *)
    logic signed [23:0] accumulator [0:NUM_PARALLEL-1];
    logic signed [15:0] partial_product [0:NUM_PARALLEL-1];
    logic [DATA_WIDTH-1:0] input_data_q;
    logic [$clog2(IN_FEATURES):0] valid_count;
    logic process_ready;
    logic [MEM_NEURON_W:0] neuron_idx_base_r;

    state_t state_n;
    logic [6:0] current_batch_n;
    logic [6:0] current_input_n;
    logic [6:0] compute_input_idx_n;
    logic [$clog2(NUM_PARALLEL)-1:0] output_idx_n;
    logic [$clog2(IN_FEATURES):0] valid_count_n;
    logic process_ready_n;
    logic [MEM_NEURON_W:0] neuron_idx_base_r_n;
    logic valid_o_n;
    logic [DATA_WIDTH-1:0] data_o_n;
    logic [6:0] neuron_idx_o_n;
    logic done_o_n;
    logic input_new;
    logic done_clear;

    logic [DATA_WIDTH-1:0] weight [0:NUM_PARALLEL-1];
    logic [DATA_WIDTH-1:0] bias [0:NUM_PARALLEL-1];
    logic signed [23:0] acc_scaled;
    logic signed [7:0] acc_sat;
    logic [MEM_NEURON_W-1:0] neuron_idx_base_lo;

    integer i;

    assign input_new = valid_i && !input_valid[addr_i];
    assign done_clear = (state == DONE) && !process_ready;
    assign acc_scaled = accumulator[output_idx] >>> FRAC_BITS;
    assign acc_sat = (acc_scaled > 24'sd127) ? 8'sd127 :
                     (acc_scaled < 24'sd0)   ? 8'sd0 :
                     acc_scaled[7:0];
    assign neuron_idx_base_lo = neuron_idx_base_r[MEM_NEURON_W-1:0];

    // Weight and bias memories
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
                .clk(clk_i),
                .rst(rst_i),
                .neuron_idx(mem_neuron_idx),
                .input_idx(mem_input_idx),
                .weight_out(weight[p])
            );

            fc2_bias_mem #(
                .DATA_WIDTH(DATA_WIDTH),
                .NUM_NEURONS(OUT_FEATURES)
            ) fc2_biases (
                .clk(clk_i),
                .rst(rst_i),
                .neuron_idx(mem_neuron_idx),
                .bias_out(bias[p])
            );
        end
    endgenerate

    // Main state machine
    always_comb begin
        state_n = state;
        current_batch_n = current_batch;
        current_input_n = current_input;
        compute_input_idx_n = compute_input_idx;
        output_idx_n = output_idx;
        valid_count_n = valid_count;
        process_ready_n = process_ready;
        neuron_idx_base_r_n = neuron_idx_base_r;
        valid_o_n = 1'b0;
        data_o_n = data_o;
        neuron_idx_o_n = neuron_idx_o;
        done_o_n = done_o;

        if (input_new) begin
            valid_count_n = valid_count + 1;
            if (valid_count == IN_FEATURES - 1)
                process_ready_n = 1'b1;
        end

        case (state)
            IDLE: begin
                done_o_n = 1'b0;
                if (process_ready) begin
                    current_batch_n = 7'd0;
                    current_input_n = 7'd0;
                    state_n = LOAD;
                end
            end

            LOAD: begin
                neuron_idx_base_r_n = current_batch * NUM_PARALLEL;
                state_n = LOAD_BASE_HOLD;
            end

            LOAD_BASE_HOLD: begin
                state_n = WAIT_WEIGHT;
            end

            WAIT_WEIGHT: begin
                compute_input_idx_n = current_input;
                current_input_n = current_input + 7'd1;
                state_n = COMPUTE_MULT;
            end

            COMPUTE_MULT: begin
                state_n = COMPUTE_ACC;
            end

            COMPUTE_ACC: begin
                if (compute_input_idx == IN_FEATURES - 1) begin
                    output_idx_n = 0;
                    state_n = OUTPUT;
                end else begin
                    compute_input_idx_n = current_input;
                    current_input_n = current_input + 7'd1;
                    state_n = COMPUTE_MULT;
                end
            end

            OUTPUT: begin
                valid_o_n = 1'b1;
                data_o_n = acc_sat;
                neuron_idx_o_n = neuron_idx_base_lo + output_idx;

                if (output_idx == NUM_PARALLEL - 1) begin
                    if (current_batch == NUM_BATCHES - 1) begin
                        state_n = DONE;
                        process_ready_n = 1'b0;
                    end else begin
                        current_batch_n = current_batch + 7'd1;
                        current_input_n = 7'd0;
                        compute_input_idx_n = 7'd0;
                        state_n = LOAD;
                    end
                end else begin
                    output_idx_n = output_idx + 1;
                end
            end

            DONE: begin
                done_o_n = 1'b1;
                if (!process_ready) begin
                    state_n = IDLE;
                    valid_count_n = 0;
                end
            end

            default: state_n = IDLE;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state <= IDLE;
            current_batch <= 7'd0;
            current_input <= 7'd0;
            compute_input_idx <= 7'd0;
            output_idx <= 0;
            valid_o <= 1'b0;
            data_o <= 8'd0;
            neuron_idx_o <= 7'd0;
            done_o <= 1'b0;
            process_ready <= 1'b0;
            valid_count <= 0;
            input_data_q <= 8'd0;
            neuron_idx_base_r <= '0;
            input_valid <= '0;
            for (i = 0; i < NUM_PARALLEL; i = i + 1) begin
                partial_product[i] <= 16'sd0;
                accumulator[i] <= 24'sd0;
            end
            for (i = 0; i < IN_FEATURES; i = i + 1) begin
                input_buffer[i] <= 8'd0;
            end
        end else begin
            state <= state_n;
            current_batch <= current_batch_n;
            current_input <= current_input_n;
            compute_input_idx <= compute_input_idx_n;
            output_idx <= output_idx_n;
            valid_count <= valid_count_n;
            process_ready <= process_ready_n;
            neuron_idx_base_r <= neuron_idx_base_r_n;
            valid_o <= valid_o_n;
            data_o <= data_o_n;
            neuron_idx_o <= neuron_idx_o_n;
            done_o <= done_o_n;

            input_data_q <= input_buffer[current_input];

            // Input buffer
            if (valid_i) begin
                input_buffer[addr_i] <= data_i;
                input_valid[addr_i] <= 1'b1;
            end

            if (done_clear) begin
                input_valid <= '0;
            end

            // MAC pipeline register updates
            case (state)
                WAIT_WEIGHT: begin
                    for (i = 0; i < NUM_PARALLEL; i = i + 1)
                        accumulator[i] <= {{16{bias[i][7]}}, bias[i]} << FRAC_BITS;
                end
                COMPUTE_MULT: begin
                    for (i = 0; i < NUM_PARALLEL; i = i + 1)
                        partial_product[i] <= $signed(weight[i]) * $signed(input_data_q);
                end
                COMPUTE_ACC: begin
                    for (i = 0; i < NUM_PARALLEL; i = i + 1)
                        accumulator[i] <= accumulator[i] + {{8{partial_product[i][15]}}, partial_product[i]};
                end
                default: ;
            endcase

        end
    end

endmodule
