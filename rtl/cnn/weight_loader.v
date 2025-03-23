// weight loader for CNN

module weight_loader #(
    parameter DATA_WIDTH = 8
)(
    input wire clk,
    input wire rst_n,
    
    input wire [7:0] layer_select,
    input wire [7:0] filter_idx,
    input wire [7:0] kernel_idx,
    
    input wire [15:0] input_idx,
    input wire [7:0] output_idx,
    
    output reg signed [DATA_WIDTH-1:0] weight,
    output reg signed [DATA_WIDTH-1:0] bias
);

    wire signed [DATA_WIDTH-1:0] conv1_weight, conv1_bias;
    wire signed [DATA_WIDTH-1:0] conv2_weight, conv2_bias;
    wire signed [DATA_WIDTH-1:0] fc3_weight, fc120_bias;
    wire signed [DATA_WIDTH-1:0] fc4_weight, fc84_bias;
    wire signed [DATA_WIDTH-1:0] fc5_weight, fc256_bias;

    // First convolutional layer
    conv1_weights conv1_weights_inst (
        .filter_idx(filter_idx),
        .kernel_idx(kernel_idx),
        .weight(conv1_weight)
    );
    
    conv1_biases conv1_biases_inst (
        .filter_idx(filter_idx),
        .bias(conv1_bias)
    );
    
    // Second convolutional layer
    conv2_weights conv2_weights_inst (
        .filter_idx(filter_idx),
        .kernel_idx(kernel_idx),
        .weight(conv2_weight)
    );
    
    conv2_biases conv2_biases_inst (
        .filter_idx(filter_idx),
        .bias(conv2_bias)
    );
    
    // First fully connected layer (120 neurons)
    fc3_weights fc3_weights_inst (
        .input_idx(input_idx),
        .output_idx(output_idx),
        .weight(fc3_weight)
    );
    
    fc120_biases fc120_biases_inst (
        .output_idx(output_idx),
        .bias(fc120_bias)
    );
    
    // Second fully connected layer (84 neurons)
    fc4_weights fc4_weights_inst (
        .input_idx(input_idx),
        .output_idx(output_idx),
        .weight(fc4_weight)
    );
    
    fc84_biases fc84_biases_inst (
        .output_idx(output_idx),
        .bias(fc84_bias)
    );
    
    // Output layer (10 classes)
    fc5_weights fc5_weights_inst (
        .input_idx(input_idx),
        .output_idx(output_idx),
        .weight(fc5_weight)
    );
    
    fc256_biases fc256_biases_inst (
        .output_idx(output_idx),
        .bias(fc256_bias)
    );
    
    // Mux the weights and biases based on the layer select
    always @* begin
        case (layer_select)
            8'd0: begin // First convolution layer
                weight = conv1_weight;
                bias = conv1_bias;
            end
            8'd1: begin // Second convolution layer
                weight = conv2_weight;
                bias = conv2_bias;
            end
            8'd2: begin // First fully connected layer
                weight = fc3_weight;
                bias = fc120_bias;
            end
            8'd3: begin // Second fully connected layer
                weight = fc4_weight;
                bias = fc84_bias;
            end
            8'd4: begin // Output layer
                weight = fc5_weight;
                bias = fc256_bias;
            end
            default: begin
                weight = 0;
                bias = 0;
            end
        endcase
    end
    
    // Note: In real implementation, might want to register these output and add additional control signals

endmodule
