# cnn-fpga
## Project Overview
A LeNet-5 Convolutional Neural Network (CNN) accelerator implemented in synthesizable RTL Verilog/SystemVerilog for real-time handwritten digit recognition. The CNN is trained on the MNIST dataset and optimized for FPGA deployment using uniform Q1.7 fixed-point quantization.

<p align="center">
  <img src="./python/plots/lenet5-diagram.png" width="100%" alt="LeNet-5 Architecture">
</p>
<p align="center">
  <img src="./python/plots/predictions.png" width="100%" alt="MNIST Recognition">
</p>

## Architecture Overview

The implementation follows the LeNet-5 architecture:

### Input Layer
- 28×28 grayscale image input (1 channel)
- Q1.7 fixed-point format (8-bit signed, 7 fractional bits)

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


## Project Structure
```
cnn-fpga/
├── rtl/cnn/                # CNN RTL modules (Verilog/SystemVerilog)
├── sim/cnn/                # Simulation testbenches and test data
│   ├── golden_vectors/     # Expected layer outputs for verification (.mem format)
│   ├── test_images/        # Individual MNIST test images (.txt and .mem formats)
│   └── test_images_bulk/   # Bulk test images for accuracy test (1000 images, .mem format)
├── weights_mem/            # Quantized CNN weights and biases (.mem format)
└── python/                 # Model training, quantization, and test generation
```


## RTL Implementation

### CNN Components
- **cnn_top**: Top level state machine coordinating data flow through all layers (conv→relu→pool→flatten→fc), managing layer transitions and pipeline synchronization
- **conv_layer_1**: First convolutional layer implementing 6 parallel 5×5 filters, line buffering for 28×28 input, weight loading from BRAM, and ReLU activation
- **conv_layer_2**: Second convolutional layer implementing 16 parallel 5×5 filters, full-precision multi-channel accumulation across 6 input channels, weight loading from BRAM, and ReLU activation
- **conv_5x5**: Core 5×5 convolution MAC engine performing 25 parallel multiplications using optimized 8-bit multipliers, accumulation in 24-bit precision, bias addition, and Q1.7 scaling with saturation
- **mult_8x8_signed**: Optimized 8-bit signed multiplier using tree structured partial products for Q1.7 arithmetic
- **relu**: ReLU activation function implementing max(0, x) for signed 8-bit Q1.7 values
- **pool_layer_1**: First pooling layer processing 6 channels of 24×24 feature maps with line buffering, producing 6×12×12 output
- **pool_layer_2**: Second pooling layer processing 16 channels of 8×8 feature maps with line buffering, producing 16×4×4 output
- **max_pool_2x2**: 2×2 max pooling unit with signed comparison
- **flatten**: Converts multi-dimensional feature maps (16×4×4) into a 256-element 1D vector for fully connected layers
- **fc_layer_1**: First fully connected layer performing matrix-vector multiplication (256→120), weight/bias access from BRAM with proper latency handling, and ReLU activation
- **fc_layer_2**: Second fully connected layer performing matrix-vector multiplication (120→84), weight/bias access from BRAM with proper latency handling, and ReLU activation
- **fc_layer_3**: Output layer performing matrix-vector multiplication (84→10) for digit classification, weight/bias access from BRAM with proper latency handling, no activation
- **weight_loader**: Centralized module routing weight and bias requests to BRAM memory modules based on layer selection


### Weight Management
- Weights stored in BRAM via memory wrapper modules
- 8-bit signed fixed-point (Q1.7 format)
- Separate memory modules for weights and biases of each layer


## Simulation

### Full CNN pipeline test
```bash
iverilog -g2012 -o sim/cnn/tb_cnn_top.vvp sim/cnn/tb_cnn_top.sv rtl/cnn/*.v rtl/cnn/*.sv && vvp sim/cnn/tb_cnn_top.vvp
```
- Runs the complete LeNet-5 pipeline on an MNIST test image and outputs the predicted digit class

### Note: 
- To test a different image, edit line 127 in `tb_cnn_top.sv` to change the input image path:
  ```systemverilog
  $readmemh("sim/cnn/test_images/test_image_X.mem", test_image);  // Test digit X (0-9)
  ```
- Golden vector comparison is disabled by default (`ENABLE_GOLDEN_COMPARE = 0`), only enable when testing digit 4 with corresponding golden vectors

### Individual module tests
```bash
# conv_5x5
iverilog -g2012 -o sim/cnn/tb_conv_5x5.vvp sim/cnn/tb_conv_5x5.v rtl/cnn/conv_5x5.v rtl/cnn/mult_8x8_signed.v && vvp sim/cnn/tb_conv_5x5.vvp

# conv_layer_1
iverilog -g2012 -o sim/cnn/tb_conv_layer_1.vvp sim/cnn/tb_conv_layer_1.v rtl/cnn/*.v rtl/cnn/*.sv && vvp sim/cnn/tb_conv_layer_1.vvp

# conv_layer_2
iverilog -g2012 -o sim/cnn/tb_conv_layer_2.vvp sim/cnn/tb_conv_layer_2.sv rtl/cnn/*.v rtl/cnn/*.sv && vvp sim/cnn/tb_conv_layer_2.vvp

# pool_layer_1
iverilog -g2012 -o sim/cnn/tb_pool_layer_1.vvp sim/cnn/tb_pool_layer_1.sv rtl/cnn/pool_layer_1.v rtl/cnn/max_pool_2x2.v && vvp sim/cnn/tb_pool_layer_1.vvp

# pool_layer_2
iverilog -g2012 -o sim/cnn/tb_pool_layer_2.vvp sim/cnn/tb_pool_layer_2.sv rtl/cnn/pool_layer_2.v rtl/cnn/max_pool_2x2.v && vvp sim/cnn/tb_pool_layer_2.vvp

# relu
iverilog -g2012 -o sim/cnn/tb_relu.vvp sim/cnn/tb_relu.v rtl/cnn/relu.v && vvp sim/cnn/tb_relu.vvp

# flatten
iverilog -g2012 -o sim/cnn/tb_flatten.vvp sim/cnn/tb_flatten.sv rtl/cnn/flatten.v && vvp sim/cnn/tb_flatten.vvp

# fc_layer_1
iverilog -g2012 -o sim/cnn/tb_fc_layer_1.vvp sim/cnn/tb_fc_layer_1.v rtl/cnn/*.v rtl/cnn/*.sv && vvp sim/cnn/tb_fc_layer_1.vvp

# fc_layer_2
iverilog -g2012 -o sim/cnn/tb_fc_layer_2.vvp sim/cnn/tb_fc_layer_2.v rtl/cnn/*.v rtl/cnn/*.sv && vvp sim/cnn/tb_fc_layer_2.vvp

# fc_layer_3
iverilog -g2012 -o sim/cnn/tb_fc_layer_3.vvp sim/cnn/tb_fc_layer_3.v rtl/cnn/*.v rtl/cnn/*.sv && vvp sim/cnn/tb_fc_layer_3.vvp

# fc_layers
iverilog -g2012 -o sim/cnn/tb_fc_layers.vvp sim/cnn/tb_fc_layers.v rtl/cnn/*.v rtl/cnn/*.sv && vvp sim/cnn/tb_fc_layers.vvp
```

### Accuracy test
```bash
iverilog -g2012 -o sim/cnn/tb_cnn_top_bulk.vvp sim/cnn/tb_cnn_top_bulk.sv rtl/cnn/*.v rtl/cnn/*.sv && vvp sim/cnn/tb_cnn_top_bulk.vvp
```
- Tests the CNN on 1000 MNIST test set images (100 per digit) and measures correctness
- Currently, the CNN achieves ~90.1% inference accuracy across this test:
```bash
=== Accuracy Results ===

Digit 0: 83/100 correct (83%)
Digit 1: 92/100 correct (92%)
Digit 2: 98/100 correct (98%)
Digit 3: 90/100 correct (90%)
Digit 4: 99/100 correct (99%)
Digit 5: 93/100 correct (93%)
Digit 6: 74/100 correct (74%)
Digit 7: 93/100 correct (93%)
Digit 8: 94/100 correct (94%)
Digit 9: 85/100 correct (85%)

Total Accuracy: 901/1000 correct (90.10%)
```


## Synthesis

```bash
yosys synth.ys
```
Output: `synth_cnn_top.v`


## Generating Test Images

Test images can be generated from the MNIST dataset using the `generate_test_image.py` or `generate_bulk_test_images.py` script:

```bash
# Generate test image for a specific digit (0-9)
python python/generate_test_image.py --digit 7

# Generate test image for a random digit
python python/generate_test_image.py --random

# Generate a specific occurrence of a digit
python python/generate_test_image.py --digit 4 --index 5

# Generate bulk test images
python python/generate_bulk_test_images.py
```

Single test images are saved to `sim/cnn/test_images/` in both `.txt` (raw pixel values) and `.mem` (Q1.7 quantized hex) formats.
Accuracy test images are saved to `sim/cnn/test_images_bulk/` in `.mem` format.
