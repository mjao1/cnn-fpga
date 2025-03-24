# cnn-fpga
Convolutional Neural Network on Artix-7 FPGA trained on MNIST dataset (WIP)

## Current Implementation

### CNN Components
- **ReLU Activation**: Implements max(0,x) function with 8-bit signed precision
- **Max Pooling**: 2x2 max pooling with stride 2, handles signed values correctly
- **Convolution**: 5x5 convolution with 5-stage pipeline, saturation, and bias addition
- **Convolutional Layer**: First layer with 6 filters, line buffer sliding window implementation
- **Weight Loader**: Module to access pre-trained weights and biases across all layers

### Weight Management (for now)
- Weights stored in Verilog modules as case statements
- 8-bit fixed-point quantization

## Project Structure
```
cnn-fpga/
├── rtl/cnn/          # CNN modules implementation
├── sim/cnn/          # Component testbenches
├── weights/          # Quantized CNN weights (both .v and .mif formats)
```

## Next Steps

1. Implement remaining CNN layers:
   - First pooling layer
   - Second convolutional layer (16 filters)
   - Second pooling layer
   - Fully connected layers (256 → 120 → 84 → 10 neurons)

2. Create inference pipeline:
   - Connect all layers
   - Implement top control module
   - Add interface for input/output

3. Optimize for FPGA resources:
   - Consider BRAM implementation for larger weight matrices
   - Implement parallelism for higher throughput
