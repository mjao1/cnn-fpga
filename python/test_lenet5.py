#!/usr/bin/env python3
"""
LeNet-5 Inference and Debug Script for FPGA CNN Implementation:
Loads the trained LeNet-5 model, runs inference on a test digit,
and dumps intermediate layer outputs for RTL verification.
"""

import os
import numpy as np
import tensorflow as tf
from tensorflow.keras import models
import matplotlib.pyplot as plt
from train_lenet5 import create_lenet5_model, quantize_weights

os.makedirs('golden_vectors', exist_ok=True)

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

def export_raw_image(image, filename='golden_vectors/input_image.txt'):
    """Export raw image pixel values for RTL simulation."""
    # Scale back to 0-255 range and convert to int
    pixels = (image * 255).astype(np.uint8)
    with open(filename, 'w') as f:
        for row in pixels:
            for pixel in row:
                f.write(f"{pixel}\n")

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

def save_intermediate_outputs(model, image):
    """Extract and save intermediate outputs from each layer."""
    # Reshape to model input shape
    input_image = image.reshape(1, 28, 28, 1)
    
    # Create the multi-output model
    multi_output_model = create_lenet5_model_with_outputs()
    
    # Copy weights from the trained model to our multi-output model
    # We copy layer by layer to ensure the correct weight mapping
    for i in range(len(model.layers)):
        if hasattr(model.layers[i], 'get_weights') and hasattr(multi_output_model.layers[i+1], 'set_weights'):
            weights = model.layers[i].get_weights()
            if weights:  # Check if the layer has weights
                multi_output_model.layers[i+1].set_weights(weights)
    
    # Get outputs from all layers
    layer_outputs = multi_output_model.predict(input_image)
    
    # Names for each layer output
    layer_names = ['conv1', 'pool1', 'conv2', 'pool2', 'flatten1', 'fc1', 'fc2', 'fc3']
    
    # Create dictionary to store outputs
    outputs = {}
    
    # Process each output
    print("Extracting layer outputs:")
    for i, (name, output) in enumerate(zip(layer_names, layer_outputs)):
        outputs[name] = output
        print(f"  - {name}: {output.shape}")
        
        # Save quantized outputs (scale to int8 range: -128 to 127)
        quantized_output, scale = quantize_weights(output, bits=8)
        
        if name.startswith('conv'):
            save_conv_output(name, quantized_output)
        elif name.startswith('pool'):
            save_pool_output(name, quantized_output)
        elif name.startswith('flatten'):
            save_flatten_output(quantized_output)
        elif name.startswith('fc'):
            save_fc_output(name, quantized_output)
    
    return outputs, layer_outputs[-1]  # Return outputs dict and final prediction

def save_conv_output(layer_name, output):
    """Save convolutional layer output to file."""
    # Get dimensions
    batch, height, width, channels = output.shape
    
    filename = f"golden_vectors/{layer_name}_output.txt"
    with open(filename, 'w') as f:
        f.write(f"# {layer_name} output: {height}x{width}x{channels}\n")
        f.write(f"# Format: channel, y, x, value\n")
        
        for c in range(channels):
            for y in range(height):
                for x in range(width):
                    value = int(output[0, y, x, c])
                    # Convert to unsigned byte representation (0-255) if negative
                    if value < 0:
                        value = 256 + value  # 2's complement
                    f.write(f"{c}, {y}, {x}, {value}\n")

def save_pool_output(layer_name, output):
    """Save pooling layer output to file."""
    # Get dimensions
    batch, height, width, channels = output.shape
    
    filename = f"golden_vectors/{layer_name}_output.txt"
    with open(filename, 'w') as f:
        f.write(f"# {layer_name} output: {height}x{width}x{channels}\n")
        f.write(f"# Format: channel, y, x, value\n")
        
        for c in range(channels):
            for y in range(height):
                for x in range(width):
                    value = int(output[0, y, x, c])
                    # Convert to unsigned byte representation if negative
                    if value < 0:
                        value = 256 + value  # 2's complement
                    f.write(f"{c}, {y}, {x}, {value}\n")

def save_flatten_output(output):
    """Save flattened output to file."""
    filename = f"golden_vectors/flatten1_output.txt"
    with open(filename, 'w') as f:
        f.write(f"# flatten1 output: {output.shape[1]} neurons\n")
        f.write(f"# Format: index, value\n")
        
        for i in range(output.shape[1]):
            value = int(output[0, i])
            # Convert to unsigned byte representation if negative
            if value < 0:
                value = 256 + value  # 2's complement
            f.write(f"{i}, {value}\n")

def save_fc_output(layer_name, output):
    """Save fully connected layer output to file."""
    filename = f"golden_vectors/{layer_name}_output.txt"
    with open(filename, 'w') as f:
        f.write(f"# {layer_name} output: {output.shape[1]} neurons\n")
        f.write(f"# Format: neuron_index, value\n")
        
        for i in range(output.shape[1]):
            value = int(output[0, i])
            # Convert to unsigned byte representation if negative
            if value < 0:
                value = 256 + value  # 2's complement
            f.write(f"{i}, {value}\n")

def visualize_test_image(image, expected_label, output_scores=None, predicted_label=None):
    """Visualize the test image and prediction results."""
    plt.figure(figsize=(8, 4))
    
    # Plot the image
    plt.subplot(1, 2, 1)
    plt.imshow(image, cmap='gray')
    plt.title(f"Test Image (Label: {expected_label})")
    plt.axis('off')
    
    # Plot the prediction scores if available
    if output_scores is not None and predicted_label is not None:
        plt.subplot(1, 2, 2)
        plt.bar(range(10), output_scores[0])
        plt.xticks(range(10))
        plt.xlabel('Digit')
        plt.ylabel('Score')
        plt.title(f"Prediction: {predicted_label}")
    
    plt.tight_layout()
    plt.savefig('golden_vectors/test_image.png')

def main():
    """Main function to run inference and dump intermediate outputs."""
    print("Loading test image...")
    test_image, expected_label = load_test_image("python/test_image.txt")
    
    print(f"Test image loaded with expected label: {expected_label}")
    export_raw_image(test_image)
    
    print("Loading LeNet-5 model...")
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
    
    print("Running inference and saving intermediate outputs...")
    outputs, prediction = save_intermediate_outputs(model, test_image)
    
    # Get final prediction
    predicted_label = np.argmax(prediction)
    
    print(f"Prediction results:")
    print(f"Expected: {expected_label}, Predicted: {predicted_label}")
    print(f"Confidence scores:")
    for i, score in enumerate(prediction[0]):
        print(f"  Digit {i}: {score:.4f}")
    
    # Visualize test image and prediction
    visualize_test_image(test_image, expected_label, prediction, predicted_label)
    
    print("Done! All intermediate outputs have been saved to the 'golden_vectors' directory.")

if __name__ == '__main__':
    main() 
