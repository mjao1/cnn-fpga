# cnn-fpga
## Project Overview
This project implements a LeNet-5 Convolutional Neural Network (CNN) architecture created by RTL Verilog and designed for for a real-time handwritten digit recognition. The CNN is trained on the MNIST dataset and optimized for hardware acceleration.

## Architecture Overview

The implementation follows the LeNet-5 architecture:

### Input Layer
- 28×28 grayscale image input (1 channel)

### Convolutional Layers
- **Conv1**: 1×28×28 → 6×24×24 (6 filters, 5×5 kernel, stride 1, no padding)
- **Pool1**: 6×24×24 → 6×12×12 (2×2 max pooling, stride 2)
- **Conv2**: 6×12×12 → 16×8×8 (16 filters, 5×5 kernel, stride 1, no padding)
- **Pool2**: 16×8×8 → 16×4×4 (2×2 max pooling, stride 2)

### Fully Connected Layers
- **Flatten**: 16×4×4 = 256 neurons
- **FC1**: 256 → 120 neurons
- **FC2**: 120 → 84 neurons
- **FC3**: 84 → 10 neurons (digit classification)

## Current Implementation

### CNN Components
- **ReLU Activation**: Implements max(0,x) function with 8-bit signed precision
- **Max Pooling**: 2×2 max pooling with stride 2, handles signed values correctly
- **Convolution**: 5×5 convolution with 5-stage pipeline, saturation, and bias addition
- **Conv Layer 1**: First convolutional layer with 6 filters (28×28 → 24×24)
- **Pool Layer 1**: First pooling layer (24×24 → 12×12)
- **Conv Layer 2**: Second convolutional layer with 16 filters (12×12 → 8×8)
- **Pool Layer 2**: Second pooling layer (8×8 → 4×4)
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
└── python/           # Model training and weight generation
```

## Next Steps

1. Implement remaining components:
   - **Flatten Module**: Convert 16×4×4 feature maps to 256-element vector
   - **Fully Connected Layers**: Implement FC1, FC2, and FC3 layers
   - **Top-Level Module**: Connect all components for end-to-end inference

2. Create inference pipeline:
   - Connect all layers
   - Implement top control module
   - Optimize for parallel processing where possible

3. Interface with I/O:
   - Implement interface for touchpad input (eyeing Adafruit 2.8 touchscreen)
   - Connect logic for 7-segment display output

4. Optimize for FPGA resources:
   - Explore BRAM implementation for weight storage
   - Implement resource sharing for multipliers
   - Balance area vs. performance tradeoffs

## Performance
- Process one 28×28 digit in under 10ms
- Achieve >95% accuracy on MNIST test set
- Minimize resource utilization
- Maintain real-time operation with user input
