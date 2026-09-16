// Top module for the fully connected layers of LeNet-5 CNN
// Integrates FC1, FC2, and FC3 layers sequentially

module fc_layers #(
    parameter FC1_IN_FEATURES = 256,
    parameter FC1_OUT_FEATURES = 120,
    parameter FC2_IN_FEATURES = 120,
    parameter FC2_OUT_FEATURES = 84,
    parameter FC3_IN_FEATURES = 84,
    parameter FC3_OUT_FEATURES = 10,
    parameter DATA_WIDTH = 8,
    parameter FC1_NUM_PARALLEL = 10,
    parameter FC2_NUM_PARALLEL = 12,
    parameter FC3_NUM_PARALLEL = 10
)(
    input  logic                  clk_i,
    input  logic                  rst_i,
    input  logic                  start_i,
    input  logic                  valid_i,
    input  logic [DATA_WIDTH-1:0] data_i,
    input  logic [7:0]            addr_i,

    output logic                  valid_o,
    output logic [DATA_WIDTH-1:0] data_o,
    output logic [3:0]            digit_idx_o,
    output logic                  done_o
);

    typedef enum logic [2:0] {
        IDLE     = 3'b000,
        FC1_PROC = 3'b001,
        FC2_PROC = 3'b010,
        FC3_PROC = 3'b011,
        DONE     = 3'b100
    } state_t;

    state_t state;

    // FC1 signals
    logic fc1_valid_out;
    logic [DATA_WIDTH-1:0] fc1_data_out;
    logic [7:0] fc1_neuron_idx;
    logic fc1_done_out;

    // FC2 signals
    logic fc2_valid_in;
    logic [DATA_WIDTH-1:0] fc2_data_in;
    logic [6:0] fc2_addr_in;
    logic fc2_valid_out;
    logic [DATA_WIDTH-1:0] fc2_data_out;
    logic [6:0] fc2_neuron_idx;
    logic fc2_done_out;

    // FC3 signals
    logic fc3_valid_in;
    logic [DATA_WIDTH-1:0] fc3_data_in;
    logic [6:0] fc3_addr_in;
    logic fc3_valid_out;
    logic [DATA_WIDTH-1:0] fc3_data_out;
    logic [3:0] fc3_neuron_idx;
    logic fc3_done_out;

    state_t state_n;
    logic fc2_valid_in_n;
    logic [DATA_WIDTH-1:0] fc2_data_in_n;
    logic [6:0] fc2_addr_in_n;
    logic fc3_valid_in_n;
    logic [DATA_WIDTH-1:0] fc3_data_in_n;
    logic [6:0] fc3_addr_in_n;
    logic valid_o_n;
    logic [DATA_WIDTH-1:0] data_o_n;
    logic [3:0] digit_idx_o_n;
    logic done_o_n;
    logic [6:0] fc1_neuron_idx_lo;

    assign fc1_neuron_idx_lo = fc1_neuron_idx[6:0];

    // FC1 layer (256 to 120)
    fc_layer_1 #(
        .IN_FEATURES(FC1_IN_FEATURES),
        .OUT_FEATURES(FC1_OUT_FEATURES),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_PARALLEL(FC1_NUM_PARALLEL)
    ) fc1 (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .valid_i(valid_i),
        .data_i(data_i),
        .addr_i(addr_i),
        .valid_o(fc1_valid_out),
        .data_o(fc1_data_out),
        .neuron_idx_o(fc1_neuron_idx),
        .done_o(fc1_done_out)
    );

    // FC2 layer (120 to 84)
    fc_layer_2 #(
        .IN_FEATURES(FC2_IN_FEATURES),
        .OUT_FEATURES(FC2_OUT_FEATURES),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_PARALLEL(FC2_NUM_PARALLEL)
    ) fc2 (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .valid_i(fc2_valid_in),
        .data_i(fc2_data_in),
        .addr_i(fc2_addr_in),
        .valid_o(fc2_valid_out),
        .data_o(fc2_data_out),
        .neuron_idx_o(fc2_neuron_idx),
        .done_o(fc2_done_out)
    );

    // FC3 layer (84 to 10)
    fc_layer_3 #(
        .IN_FEATURES(FC3_IN_FEATURES),
        .OUT_FEATURES(FC3_OUT_FEATURES),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_PARALLEL(FC3_NUM_PARALLEL)
    ) fc3 (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .valid_i(fc3_valid_in),
        .data_i(fc3_data_in),
        .addr_i(fc3_addr_in),
        .valid_o(fc3_valid_out),
        .data_o(fc3_data_out),
        .neuron_idx_o(fc3_neuron_idx),
        .done_o(fc3_done_out)
    );

    // Main state machine
    always_comb begin
        state_n = state;
        fc2_valid_in_n = 1'b0;
        fc2_data_in_n = fc2_data_in;
        fc2_addr_in_n = fc2_addr_in;
        fc3_valid_in_n = 1'b0;
        fc3_data_in_n = fc3_data_in;
        fc3_addr_in_n = fc3_addr_in;
        valid_o_n = 1'b0;
        data_o_n = data_o;
        digit_idx_o_n = digit_idx_o;
        done_o_n = done_o;

        case (state)
            IDLE: begin
                done_o_n = 1'b0;
                if (start_i) begin
                    state_n = FC1_PROC;
                end
            end

            FC1_PROC: begin
                // Pass data from FC1 to FC2
                if (fc1_valid_out) begin
                    fc2_valid_in_n = 1'b1;
                    fc2_data_in_n = fc1_data_out;
                    fc2_addr_in_n = fc1_neuron_idx_lo;
                end

                if (fc1_done_out) begin
                    state_n = FC2_PROC;
                end
            end

            FC2_PROC: begin
                // Pass data from FC2 to FC3
                if (fc2_valid_out) begin
                    fc3_valid_in_n = 1'b1;
                    fc3_data_in_n = fc2_data_out;
                    fc3_addr_in_n = fc2_neuron_idx;
                end

                if (fc2_done_out) begin
                    state_n = FC3_PROC;
                end
            end

            FC3_PROC: begin
                // Pass final results to output
                if (fc3_valid_out) begin
                    valid_o_n = 1'b1;
                    data_o_n = fc3_data_out;
                    digit_idx_o_n = fc3_neuron_idx;
                end

                if (fc3_done_out) begin
                    state_n = DONE;
                    done_o_n = 1'b1;
                end
            end

            DONE: begin
                done_o_n = 1'b1;
                if (start_i) begin
                    state_n = FC1_PROC;
                    done_o_n = 1'b0;
                end
            end

            default: state_n = IDLE;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state <= IDLE;
            fc2_valid_in <= 1'b0;
            fc2_data_in <= 8'd0;
            fc2_addr_in <= 7'd0;
            fc3_valid_in <= 1'b0;
            fc3_data_in <= 8'd0;
            fc3_addr_in <= 7'd0;
            valid_o <= 1'b0;
            data_o <= 8'd0;
            digit_idx_o <= 4'd0;
            done_o <= 1'b0;
        end else begin
            state <= state_n;
            fc2_valid_in <= fc2_valid_in_n;
            fc2_data_in <= fc2_data_in_n;
            fc2_addr_in <= fc2_addr_in_n;
            fc3_valid_in <= fc3_valid_in_n;
            fc3_data_in <= fc3_data_in_n;
            fc3_addr_in <= fc3_addr_in_n;
            valid_o <= valid_o_n;
            data_o <= data_o_n;
            digit_idx_o <= digit_idx_o_n;
            done_o <= done_o_n;
        end
    end

endmodule
