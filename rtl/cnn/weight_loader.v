// Weight loader for CNN
module weight_loader #(
    parameter DATA_WIDTH = 8
)(
    input wire clk,
    input wire rst,
    
    // Layer selection and indexing
    input wire [7:0] layer_select,      // Which layer to access
    input wire [7:0] filter_idx,        // For conv layers: which filter
    input wire [7:0] in_channel,        // For conv layers: which input channel
    input wire [7:0] kernel_row,        // For conv layers: which row in kernel
    input wire [7:0] kernel_col,        // For conv layers: which col in kernel
    input wire [15:0] input_idx,        // For FC layers: which input feature
    input wire [15:0] neuron_idx,       // For FC layers: which output neuron
    
    output reg [DATA_WIDTH-1:0] weight_out,
    output reg [DATA_WIDTH-1:0] bias_out
);

    // Conv layer 1 weights and biases
    wire [DATA_WIDTH-1:0] conv1_weight, conv1_bias;
    conv1_weight_mem conv1_weights (
        .clk(clk),
        .rst(rst),
        .filter_idx(filter_idx),
        .in_channel(in_channel),
        .kernel_row(kernel_row),
        .kernel_col(kernel_col),
        .weight_out(conv1_weight)
    );
    
    conv1_bias_mem conv1_biases (
        .clk(clk),
        .rst(rst),
        .filter_idx(filter_idx),
        .bias_out(conv1_bias)
    );
    
    // Conv layer 2 weights and biases
    wire [DATA_WIDTH-1:0] conv2_weight, conv2_bias;
    conv2_weight_mem conv2_weights (
        .clk(clk),
        .rst(rst),
        .filter_idx(filter_idx),
        .in_channel(in_channel),
        .kernel_row(kernel_row),
        .kernel_col(kernel_col),
        .weight_out(conv2_weight)
    );
    
    conv2_bias_mem conv2_biases (
        .clk(clk),
        .rst(rst),
        .filter_idx(filter_idx),
        .bias_out(conv2_bias)
    );
    
    // FC1 layer (256) weights and biases
    wire [DATA_WIDTH-1:0] fc1_weight, fc1_bias;
    fc1_weight_mem fc1_weights (
        .clk(clk),
        .rst(rst),
        .neuron_idx(neuron_idx),
        .input_idx(input_idx),
        .weight_out(fc1_weight)
    );
    
    fc1_bias_mem fc1_biases (
        .clk(clk),
        .rst(rst),
        .neuron_idx(neuron_idx),
        .bias_out(fc1_bias)
    );
    
    // FC2 layer (120) weights and biases
    wire [DATA_WIDTH-1:0] fc2_weight, fc2_bias;
    fc2_weight_mem fc2_weights (
        .clk(clk),
        .rst(rst),
        .neuron_idx(neuron_idx),
        .input_idx(input_idx),
        .weight_out(fc2_weight)
    );
    
    fc2_bias_mem fc2_biases (
        .clk(clk),
        .rst(rst),
        .neuron_idx(neuron_idx),
        .bias_out(fc2_bias)
    );
    
    // FC3 layer (output, 10) weights and biases
    wire [DATA_WIDTH-1:0] fc3_weight, fc3_bias;
    fc3_weight_mem fc3_weights (
        .clk(clk),
        .rst(rst),
        .neuron_idx(neuron_idx[7:0]),
        .input_idx(input_idx),
        .weight_out(fc3_weight)
    );
    
    fc3_bias_mem fc3_biases (
        .clk(clk),
        .rst(rst),
        .neuron_idx(neuron_idx[7:0]),
        .bias_out(fc3_bias)
    );
    
    // Mux weights and biases based on layer sel
    always @(*) begin
        case (layer_select)
            8'd0: begin // Conv1
                weight_out = conv1_weight;
                bias_out = conv1_bias;
            end
            8'd1: begin // Conv2
                weight_out = conv2_weight;
                bias_out = conv2_bias;
            end
            8'd2: begin // FC1
                weight_out = fc1_weight;
                bias_out = fc1_bias;
            end
            8'd3: begin // FC2
                weight_out = fc2_weight;
                bias_out = fc2_bias;
            end
            8'd4: begin // FC3
                weight_out = fc3_weight;
                bias_out = fc3_bias;
            end
            default: begin
                weight_out = {DATA_WIDTH{1'b0}};
                bias_out = {DATA_WIDTH{1'b0}};
            end
        endcase
    end

endmodule
