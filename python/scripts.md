# Python Scripts Usage

This directory contains Python scripts for training the LeNet-5 CNN model on the MNIST dataset and exporting the weights in formats compatible with FPGA implementation.

## Contents

- `train_lenet5.py`: Script to train the LeNet-5 model and export weights
- `plots/`: Directory for storing visualization plots of the training process

## Requirements

To run these scripts, you need the following dependencies:

```bash
tensorflow>=2.4.0
numpy>=1.19.2
matplotlib>=3.3.2
```

## Usage

### Training the Model and Exporting Weights

To train the LeNet-5 model on MNIST and export the weights for FPGA implementation:

```bash
cd /path/to/cnn-fpga

python python/train_lenet5.py
```

This will:
1. Train the LeNet-5 model on the MNIST dataset for 10 epochs
2. Export the quantized weights as memory initialization files (`.mem` files) in hexadecimal format
3. Generate visualization plots in the `python/plots/` directory

### Output Files

The script generates the following outputs in the `weights_mem/` directory:

#### Memory Initialization Files
- `conv1_weights.mem`: MEM file for the first convolutional layer weights
- `conv1_biases.mem`: MEM file for the first convolutional layer biases
- `conv2_weights.mem`: MEM file for the second convolutional layer weights
- `conv2_biases.mem`: MEM file for the second convolutional layer biases
- `fc1_weights.mem`: MEM file for the first fully connected layer weights
- `fc1_biases.mem`: MEM file for the first fully connected layer biases
- `fc2_weights.mem`: MEM file for the second fully connected layer weights
- `fc2_biases.mem`: MEM file for the second fully connected layer biases
- `fc3_weights.mem`: MEM file for the output layer weights
- `fc3_biases.mem`: MEM file for the output layer biases

## Integrating with FPGA Implementation

### Using MEM Files

For Xilinx FPGAs, the MEM files can be used to initialize Block RAM (BRAM) components:

1. In Vivado, create a BRAM IP
2. Configure it with the appropriate size
3. Set the initialization file to the corresponding `.mem` file

### Workflow Integration

A typical workflow for incorporating the trained weights:

1. Train the model using `train_lenet5.py`
2. Include the generated Verilog weight modules in your FPGA project
3. Create a `weights_loader.v` module that uses the weight modules to load weights into your CNN layers
4. For memory-intensive layers, implement BRAMs initialized with the MEM files

## Customization

To customize the training process or weight export:

1. Modify the model architecture in the `create_lenet5_model()` function
2. Adjust the quantization in the `quantize_weights()` function 
3. Change the export formats in the `export_weights_to_mem()` function 
