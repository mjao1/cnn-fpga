#!/usr/bin/env python3
"""
LeNet-5 Inference and Debug Script for FPGA CNN Implementation:
Loads the trained LeNet-5 model, runs inference on a test digit,
and dumps intermediate layer outputs for RTL verification.

FPGA Quantization:
- Uses uniform Q1.7 fixed-point format (FRAC_BITS=7, scale=128)
- Golden vectors are quantized using the same format as RTL weights
"""

import os
import numpy as np
import tensorflow as tf
from tensorflow.keras import models
from train_lenet5 import (
    create_lenet5_model, 
    quantize_weights, 
    quantize_weights_fpga,
    FRAC_BITS, 
    FIXED_SCALE,
    USE_UNIFORM_SCALE,
    FC_SCALE_FACTOR
)

def load_test_image(image_path=None):
    """Load a single test image, either from a specific file or from MNIST dataset."""
    if image_path and os.path.exists(image_path):
        # Load from text file (first line is label, rest are pixel values)
        with open(image_path, 'r') as f:
            lines = f.readlines()
            expected_label = int(lines[0].strip())
            pixel_values = [int(line.strip()) for line in lines[1:785]]  # 28x28 = 784 pixels
            image = np.array(pixel_values).reshape(28, 28).astype('float32')
    else:
        # Use a sample from MNIST dataset (a "4" digit)
        (_, _), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
        # Find indices of all "4" digits
        indices_of_4 = np.where(y_test == 4)[0]
        # Use the first "4" digit
        image = x_test[indices_of_4[0]]
        expected_label = 4
    
    # Normalize pixel values to [0, 1]
    image = image.astype('float32') / 255.0
    
    return image, expected_label

def export_quantized_image(image):
    """
    Export image quantized to Q1.7 format for RTL simulation.
    
    Q1.7 format: 1 sign bit, 7 fractional bits
    - Normalized input [0, 1] maps to Q1.7 values [0, 127]
    - This matches the format used for weights in hardware
    """
    # Quantize normalized [0, 1] to Q1.7 [0, 127]
    quantized = np.clip(np.round(image * 127), 0, 127).astype(np.int8)
    
    # Export as .mem file for Verilog $readmemh
    mem_filename = 'sim/cnn/test_images/input_image.mem'
    with open(mem_filename, 'w') as f:
        for row in quantized:
            for pixel in row:
                val = int(pixel)
                if val < 0:
                    val = 256 + val
                f.write(f"{val:02X}\n")
    
    print(f"  Q1.7 quantized image: range [{quantized.min()}, {quantized.max()}]")
    print(f"  Saved to {mem_filename}")
    
    return quantized

def quantized_conv2d(inputs, weights, biases, frac_bits=FRAC_BITS):
    """
    Simulate Q1.7 fixed-point convolution matching hardware behavior.
    - Input: Q1.7 format (already quantized)
    - Weights: Q1.7 format (loaded from quantized weights)
    - Products: Q2.14 format (no intermediate shift)
    - Output: Q1.7 format (shift by FRAC_BITS at end)
    """
    import scipy.signal
    
    batch, height, width, in_channels = inputs.shape
    kernel_h, kernel_w, _, out_channels = weights.shape
    out_height = height - kernel_h + 1
    out_width = width - kernel_w + 1
    
    # Output array
    outputs = np.zeros((batch, out_height, out_width, out_channels), dtype=np.int8)
    
    for b in range(batch):
        for oc in range(out_channels):
            # Accumulator in wide precision (simulates 24-bit accumulator)
            acc = np.zeros((out_height, out_width), dtype=np.int32)
            
            for ic in range(in_channels):
                # Get kernel for this input/output channel
                kernel = weights[:, :, ic, oc].astype(np.int32)
                input_slice = inputs[b, :, :, ic].astype(np.int32)
                
                # Full precision convolution (no padding, stride=1)
                for oy in range(out_height):
                    for ox in range(out_width):
                        window = input_slice[oy:oy+kernel_h, ox:ox+kernel_w]
                        # Elementwise multiply and sum (Q1.7 * Q1.7 = Q2.14)
                        acc[oy, ox] += np.sum(window * kernel)
            
            # Add bias
            bias_scaled = int(biases[oc]) << frac_bits
            acc += bias_scaled
            
            # Shift back to Q1.7
            result = acc >> frac_bits
            
            # Saturate to 8-bit signed range
            result = np.clip(result, -128, 127)
            
            # Store
            outputs[b, :, :, oc] = result.astype(np.int8)
    
    return outputs

def quantized_relu(inputs):
    """Simulate ReLU on Q1.7 inputs."""
    return np.maximum(inputs, 0)

def quantized_maxpool2x2(inputs):
    """Simulate 2x2 max pooling with stride 2."""
    batch, height, width, channels = inputs.shape
    out_height = height // 2
    out_width = width // 2
    
    outputs = np.zeros((batch, out_height, out_width, channels), dtype=inputs.dtype)
    
    for b in range(batch):
        for c in range(channels):
            for oy in range(out_height):
                for ox in range(out_width):
                    window = inputs[b, oy*2:oy*2+2, ox*2:ox*2+2, c]
                    outputs[b, oy, ox, c] = np.max(window)
    
    return outputs

def run_quantized_inference(image_q17, model):
    """
    Run inference using quantized arithmetic to match hardware behavior.
    
    Args:
        image_q17: Input image in Q1.7
        model: Trained Keras model (to extract weights)
    
    Returns:
        Dictionary of layer outputs in Q1.7
    """
    from train_lenet5 import quantize_weights_fpga
    
    # Get quantized weights from model
    conv1_weights = model.layers[0].get_weights()
    conv1_w, conv1_b = quantize_weights_fpga(conv1_weights[0])[0], np.round(conv1_weights[1] * FIXED_SCALE).astype(np.int8)
    
    conv2_weights = model.layers[2].get_weights()
    conv2_w, conv2_b = quantize_weights_fpga(conv2_weights[0])[0], np.round(conv2_weights[1] * FIXED_SCALE).astype(np.int8)
    
    # Apply FC_SCALE_FACTOR to FC layers to prevent output saturation
    fc1_weights = model.layers[5].get_weights()
    fc1_w = quantize_weights_fpga(fc1_weights[0] / FC_SCALE_FACTOR)[0]
    fc1_b = np.round(fc1_weights[1] / FC_SCALE_FACTOR * FIXED_SCALE).astype(np.int8)
    
    fc2_weights = model.layers[6].get_weights()
    fc2_w = quantize_weights_fpga(fc2_weights[0] / FC_SCALE_FACTOR)[0]
    fc2_b = np.round(fc2_weights[1] / FC_SCALE_FACTOR * FIXED_SCALE).astype(np.int8)
    
    fc3_weights = model.layers[7].get_weights()
    fc3_w = quantize_weights_fpga(fc3_weights[0] / FC_SCALE_FACTOR)[0]
    fc3_b = np.round(fc3_weights[1] / FC_SCALE_FACTOR * FIXED_SCALE).astype(np.int8)
    
    outputs = {}
    
    # Input is already in Q1.7
    x = image_q17.reshape(1, 28, 28, 1)
    
    # Conv1: 5x5 conv with 6 filters
    x = quantized_conv2d(x, conv1_w, conv1_b)
    x = quantized_relu(x)
    outputs['conv1'] = x.copy()
    print(f"  Quantized Conv1 output: shape={x.shape}, range=[{x.min()}, {x.max()}]")
    
    # Pool1: 2x2 max pooling
    x = quantized_maxpool2x2(x)
    outputs['pool1'] = x.copy()
    print(f"  Quantized Pool1 output: shape={x.shape}, range=[{x.min()}, {x.max()}]")
    
    # Conv2: 5x5 conv with 16 filters
    x = quantized_conv2d(x, conv2_w, conv2_b)
    x = quantized_relu(x)
    outputs['conv2'] = x.copy()
    print(f"  Quantized Conv2 output: shape={x.shape}, range=[{x.min()}, {x.max()}]")
    
    # Pool2: 2x2 max pooling
    x = quantized_maxpool2x2(x)
    outputs['pool2'] = x.copy()
    print(f"  Quantized Pool2 output: shape={x.shape}, range=[{x.min()}, {x.max()}]")
    
    # Flatten
    x_flat = x.flatten().reshape(1, -1)
    outputs['flatten'] = x_flat.copy()
    print(f"  Quantized Flatten output: shape={x_flat.shape}, range=[{x_flat.min()}, {x_flat.max()}]")
    
    # FC layers use matrix multiplication with Q1.7 arithmetic
    # FC1
    acc = np.zeros((1, 120), dtype=np.int32)
    for n in range(120):
        for i in range(256):
            acc[0, n] += int(x_flat[0, i]) * int(fc1_w[i, n])
        acc[0, n] += int(fc1_b[n]) << FRAC_BITS
    x_fc1 = np.clip(acc >> FRAC_BITS, -128, 127).astype(np.int8)
    x_fc1 = np.maximum(x_fc1, 0)  # ReLU
    outputs['fc1'] = x_fc1.copy()
    print(f"  Quantized FC1 output: shape={x_fc1.shape}, range=[{x_fc1.min()}, {x_fc1.max()}]")
    
    # FC2
    acc = np.zeros((1, 84), dtype=np.int32)
    for n in range(84):
        for i in range(120):
            acc[0, n] += int(x_fc1[0, i]) * int(fc2_w[i, n])
        acc[0, n] += int(fc2_b[n]) << FRAC_BITS
    x_fc2 = np.clip(acc >> FRAC_BITS, -128, 127).astype(np.int8)
    x_fc2 = np.maximum(x_fc2, 0)  # ReLU
    outputs['fc2'] = x_fc2.copy()
    print(f"  Quantized FC2 output: shape={x_fc2.shape}, range=[{x_fc2.min()}, {x_fc2.max()}]")
    
    # FC3 (output layer, no ReLU)
    acc = np.zeros((1, 10), dtype=np.int32)
    for n in range(10):
        for i in range(84):
            acc[0, n] += int(x_fc2[0, i]) * int(fc3_w[i, n])
        acc[0, n] += int(fc3_b[n]) << FRAC_BITS
    x_fc3 = np.clip(acc >> FRAC_BITS, -128, 127).astype(np.int8)
    outputs['fc3'] = x_fc3.copy()
    print(f"  Quantized FC3 output: shape={x_fc3.shape}, range=[{x_fc3.min()}, {x_fc3.max()}]")
    
    return outputs


def create_lenet5_model_with_outputs():
    """Create the LeNet-5 model with separate outputs for each layer."""
    input_img = tf.keras.layers.Input(shape=(28, 28, 1))
    
    # Conv1: 6 filters of 5x5, stride 1, valid padding
    conv1 = tf.keras.layers.Conv2D(6, kernel_size=(5, 5), activation='relu', padding='valid')(input_img)
    
    # Pool1: 2x2 max pooling, stride 2
    pool1 = tf.keras.layers.MaxPooling2D(pool_size=(2, 2), strides=(2, 2))(conv1)
    
    # Conv2: 16 filters of 5x5, stride 1, valid padding
    conv2 = tf.keras.layers.Conv2D(16, kernel_size=(5, 5), activation='relu', padding='valid')(pool1)
    
    # Pool2: 2x2 max pooling, stride 2
    pool2 = tf.keras.layers.MaxPooling2D(pool_size=(2, 2), strides=(2, 2))(conv2)
    
    # Flatten
    flatten = tf.keras.layers.Flatten()(pool2)
    
    # FC1: 120 neurons
    fc1 = tf.keras.layers.Dense(120, activation='relu')(flatten)
    
    # FC2: 84 neurons
    fc2 = tf.keras.layers.Dense(84, activation='relu')(fc1)
    
    # Output: 10 neurons (digits 0-9)
    fc3 = tf.keras.layers.Dense(10, activation='softmax')(fc2)
    
    # Create model with multiple outputs
    model = tf.keras.models.Model(inputs=input_img, outputs=[
        conv1, pool1, conv2, pool2, flatten, fc1, fc2, fc3
    ])
    
    model.compile(
        optimizer='adam',
        loss='categorical_crossentropy',
        metrics=['accuracy']
    )
    
    return model

def save_quantized_golden_vectors(outputs):
    """
    Save quantized inference outputs as golden vectors for RTL verification.
    
    Args:
        outputs: Dictionary of layer outputs from run_quantized_inference()
    """
    os.makedirs('sim/cnn/golden_vectors', exist_ok=True)
    print("\nSaving golden vector .mem files:")
    
    for layer_name, output in outputs.items():
        if layer_name.startswith('conv') or layer_name.startswith('pool'):
            # Reshape if needed
            if len(output.shape) == 4:
                batch, height, width, channels = output.shape
            else:
                continue
            
            mem_filename = f"sim/cnn/golden_vectors/{layer_name}_expected.mem"
            with open(mem_filename, 'w') as f:
                for c in range(channels):
                    for y in range(height):
                        for x in range(width):
                            value = int(output[0, y, x, c])
                            if value < 0:
                                value = 256 + value
                            f.write(f"{value:02X}\n")
            
            print(f"  Saved {layer_name}_expected.mem ({channels} channels, {height}x{width})")
            
        elif layer_name.startswith('flatten'):
            size = output.shape[1]
            mem_filename = f"sim/cnn/golden_vectors/flatten_expected.mem"
            with open(mem_filename, 'w') as f:
                for i in range(size):
                    value = int(output[0, i])
                    if value < 0:
                        value = 256 + value
                    f.write(f"{value:02X}\n")
            
            print(f"  Saved flatten_expected.mem ({size} elements)")
            
        elif layer_name.startswith('fc'):
            size = output.shape[1]
            mem_filename = f"sim/cnn/golden_vectors/{layer_name}_expected.mem"
            with open(mem_filename, 'w') as f:
                for i in range(size):
                    value = int(output[0, i])
                    if value < 0:
                        value = 256 + value
                    f.write(f"{value:02X}\n")
            
            print(f"  Saved {layer_name}_expected.mem ({size} neurons)")

def main():
    """Main function to run inference and dump intermediate outputs."""
    print("=" * 60)
    print("LeNet-5 FPGA Golden Vector Generation")
    print("=" * 60)
    print(f"Quantization: Q{8-FRAC_BITS-1}.{FRAC_BITS} format")
    print(f"FRAC_BITS: {FRAC_BITS}")
    print(f"SCALE: {FIXED_SCALE}")
    print(f"Mode: {'Uniform scaling' if USE_UNIFORM_SCALE else 'Per-layer power-of-two'}")
    print("=" * 60)
    
    print("\nLoading test image...")
    test_image, expected_label = load_test_image("python/test_image.txt")
    
    print(f"Test image loaded with expected label: {expected_label}")
    
    # Export quantized image for RTL simulation (Q1.7)
    print("\nQuantizing input image to Q1.7 format:")
    image_q17 = export_quantized_image(test_image)
    
    print("\nLoading LeNet-5 model...")
    model = create_lenet5_model()
    
    # Load weights from file if exists, otherwise train a new model
    model_weights_path = 'python/lenet5.weights.h5'
    if os.path.exists(model_weights_path):
        model.load_weights(model_weights_path)
    else:
        # Load data
        (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
        x_train = x_train.reshape(-1, 28, 28, 1).astype('float32') / 255.0
        x_test = x_test.reshape(-1, 28, 28, 1).astype('float32') / 255.0
        y_train = tf.keras.utils.to_categorical(y_train, 10)
        y_test = tf.keras.utils.to_categorical(y_test, 10)
        
        # Train model
        model.fit(
            x_train, y_train,
            batch_size=128,
            epochs=10,
            validation_data=(x_test, y_test),
            verbose=1
        )
        
        # Save weights
        model.save_weights(model_weights_path)
    
    # Run quantized inference (matches hardware behavior)
    print("\n" + "=" * 60)
    print("Running QUANTIZED inference (matches hardware)")
    print("=" * 60)
    quantized_outputs = run_quantized_inference(image_q17, model)
    
    # Save quantized golden vectors
    save_quantized_golden_vectors(quantized_outputs)
    
    # Get quantized prediction
    fc3_output = quantized_outputs['fc3']
    predicted_label_q = np.argmax(fc3_output)
    print(f"\nQuantized prediction: {predicted_label_q}")
    print(f"FC3 outputs (Q1.7):")
    for i in range(10):
        print(f"  Digit {i}: {fc3_output[0, i]}")
    
    # Also run float32 inference for comparison (but dont save)
    print("\n" + "=" * 60)
    print("Running FLOAT32 inference (reference)")
    print("=" * 60)
    input_image = test_image.reshape(1, 28, 28, 1)
    prediction = model.predict(input_image, verbose=0)
    
    # Get final prediction
    predicted_label = np.argmax(prediction)
    
    print(f"\nFloat32 prediction results:")
    print(f"Expected: {expected_label}, Predicted: {predicted_label}")
    print(f"Confidence scores:")
    for i, score in enumerate(prediction[0]):
        print(f"  Digit {i}: {score:.4f}")
    
    
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Expected label: {expected_label}")
    print(f"Float32 prediction: {predicted_label}")
    print(f"Quantized prediction: {predicted_label_q}")
    print(f"\nGolden vector .mem files saved to 'sim/cnn/golden_vectors/' directory")
    print("Done!")

if __name__ == '__main__':
    main() 
