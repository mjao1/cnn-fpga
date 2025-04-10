# cnn-fpga
## Project Overview
This project implements a LeNet-5 Convolutional Neural Network (CNN) architecture created by RTL Verilog and designed for for a real-time handwritten digit recognition. The CNN is trained on the MNIST dataset and optimized for hardware acceleration.

<img src="./python/plots/predictions.png" width="70%" alt="MNIST Recognition">

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
- **Flatten Module**: Converts 16×4×4 feature maps to 256-element vector
- **FC Layer 1**: First fully connected layer (256 → 120) with ReLU activation
- **FC Layer 2**: Second fully connected layer (120 → 84) with ReLU activation
- **FC Layer 3**: Output layer (84 → 10) for digit classification
- **FC Layers**: Top module integrating all three fully connected layers
- **Weight Loader**: Module to access pre-trained weights and biases across all layers

### Weight Management
- Weights stored in BRAM via memory wrapper modules
- 8-bit fixed-point quantization
- Separate memory modules for weights and biases of each layer

## Project Structure
```
cnn-fpga/
├── rtl/cnn/          # CNN modules implementation
├── sim/cnn/          # Component testbenches
├── weights_mem/          # Quantized CNN weights (mem. format)
└── python/           # Model training and weight generation
```

## Next Steps

3. Interface with I/O:
   - Implement interface for touchpad input (eyeing Adafruit 2.8 touchscreen)
   - Connect logic for 7-segment display output

4. Optimize for FPGA resources:
   - Fine-tune weight memory implementation

## Performance
- Process one 28×28 digit in under 10ms
- Achieve >95% accuracy on MNIST test set
- Minimize resource utilization
- Maintain real-time operation with user input
