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
2. Export the quantized weights in two formats:
   - Verilog modules (`.v` files)
   - Memory initialization files (`.mif` files)
3. Generate visualization plots in the `python/plots/` directory

### Output Files

The script generates the following outputs in the `weights/` directory:

#### Verilog Weight Modules
- `conv1_weights.v`: Weights for the first convolutional layer
- `conv1_biases.v`: Biases for the first convolutional layer
- `conv3_weights.v`: Weights for the second convolutional layer
- `conv3_biases.v`: Biases for the second convolutional layer
- `fc5_weights.v`: Weights for the first fully connected layer
- `fc5_biases.v`: Biases for the first fully connected layer
- `fc6_weights.v`: Weights for the second fully connected layer
- `fc6_biases.v`: Biases for the second fully connected layer
- `fc7_weights.v`: Weights for the output layer
- `fc7_biases.v`: Biases for the output layer

#### Memory Initialization Files
- `conv1_weights.mif`: MIF file for the first convolutional layer weights
- `conv1_biases.mif`: MIF file for the first convolutional layer biases
- ... (similar files for other layers)

## Integrating with FPGA Implementation

### Using Verilog Modules

The generated Verilog modules can be directly included in your FPGA project. Each module is parameterized to allow fetching specific weights or biases using indices:

```verilog
// Example: Instantiating the first convolution layer weights module
conv1_weights conv1_weights_inst (
    .filter_idx(filter_idx),    // Which filter (0-5)
    .kernel_idx(kernel_idx),    // Which kernel position (0-24 for 5x5)
    .weight(weight_value)       // Output: 8-bit signed weight
);
```

### Using MIF Files

For Xilinx FPGAs, the MIF files can be used to initialize Block RAM (BRAM) components:

1. In Vivado, create a BRAM IP
2. Configure it with the appropriate size
3. Set the initialization file to the corresponding `.mif` file

### Workflow Integration

A typical workflow for incorporating the trained weights:

1. Train the model using `train_lenet5.py`
2. Include the generated Verilog weight modules in your FPGA project
3. Create a `weights_loader.v` module that uses the weight modules to load weights into your CNN layers
4. For memory-intensive layers, implement BRAMs initialized with the MIF files

## Customization

To customize the training process or weight export:

1. Modify the model architecture in the `create_lenet5_model()` function
2. Adjust the quantization in the `quantize_weights()` function 
3. Change the export formats in the `export_weights_to_verilog()` and `export_mif_files()` functions 
