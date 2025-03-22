#!/usr/bin/env python3
"""
LeNet-5 Training Script for MNIST Digit Recognition
---------------------------------------------------
This script trains a LeNet-5 CNN on the MNIST dataset and exports
the weights in a format suitable for FPGA implementation.
"""

import os
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models
import matplotlib.pyplot as plt

os.makedirs('weights', exist_ok=True)
os.makedirs('python/plots', exist_ok=True)

def create_lenet5_model():
    """Create the LeNet-5 model architecture."""
    model = models.Sequential()
    
    model.add(layers.Conv2D(6, kernel_size=(5, 5), activation='relu', 
                           input_shape=(28, 28, 1), padding='valid'))
    
    model.add(layers.MaxPooling2D(pool_size=(2, 2), strides=(2, 2)))
    
    model.add(layers.Conv2D(16, kernel_size=(5, 5), activation='relu', padding='valid'))
    
    model.add(layers.MaxPooling2D(pool_size=(2, 2), strides=(2, 2)))
    
    model.add(layers.Flatten())
    
    model.add(layers.Dense(120, activation='relu'))
    
    model.add(layers.Dense(84, activation='relu'))
    
    model.add(layers.Dense(10, activation='softmax'))
    
    model.compile(
        optimizer='adam',
        loss='categorical_crossentropy',
        metrics=['accuracy']
    )
    
    return model

def quantize_weights(weights, bits=8):
    """
    Quantize weights to fixed-point representation with specified bits.
    For 8-bit signed integers, the range is [-128, 127].
    """
    max_abs_val = np.max(np.abs(weights))
    
    if max_abs_val == 0:
        return np.zeros_like(weights, dtype=np.int8)
    
    scale = 127.0 / max_abs_val
    
    quantized = np.round(weights * scale).astype(np.int8)
    
    return quantized, scale

def export_weights_to_verilog(model, layer_names=None):
    """
    Export the weights of the model to Verilog-compatible format.
    """
    if layer_names is None:
        layer_names = [layer.name for layer in model.layers if len(layer.get_weights()) > 0]
    
    for i, layer_name in enumerate(layer_names):
        layer = model.get_layer(layer_name)
        weights = layer.get_weights()
        
        if len(weights) == 0:
            continue
        
        weight_values = weights[0]
        bias_values = weights[1] if len(weights) > 1 else None
        
        quantized_weights, weight_scale = quantize_weights(weight_values)
        
        if bias_values is not None:
            quantized_biases, bias_scale = quantize_weights(bias_values)
        
        if isinstance(layer, layers.Conv2D):
            k_h, k_w, in_c, out_c = quantized_weights.shape
            
            verilog_file = f"weights/conv{i+1}_weights.v"
            with open(verilog_file, 'w') as f:
                f.write(f"// Weights for {layer_name}, Shape: {quantized_weights.shape}\n")
                f.write(f"// Quantization scale: {weight_scale}\n\n")
                
                f.write(f"module conv{i+1}_weights(\n")
                f.write("    input wire [7:0] filter_idx,  // Filter index\n")
                f.write("    input wire [7:0] kernel_idx,  // Kernel index (row * kernel_width + col)\n")
                f.write("    output reg signed [7:0] weight // Signed 8-bit weight value\n")
                f.write(");\n\n")
                
                f.write("    always @* begin\n")
                f.write("        case({filter_idx, kernel_idx})\n")
                
                for oc in range(out_c):
                    for kh in range(k_h):
                        for kw in range(k_w):
                            kernel_idx = kh * k_w + kw
                            weight = quantized_weights[kh, kw, 0, oc]  # Assuming in_c = 1 for first layer
                            f.write(f"            {{8'd{oc}, 8'd{kernel_idx}}}: weight = 8'sd{weight};\n")
                
                f.write("            default: weight = 8'sd0;\n")
                f.write("        endcase\n")
                f.write("    end\n\n")
                f.write("endmodule\n")
            
            if bias_values is not None:
                bias_file = f"weights/conv{i+1}_biases.v"
                with open(bias_file, 'w') as f:
                    f.write(f"// Biases for {layer_name}\n")
                    f.write(f"// Quantization scale: {bias_scale}\n\n")
                    
                    f.write(f"module conv{i+1}_biases(\n")
                    f.write("    input wire [7:0] filter_idx,  // Filter index\n")
                    f.write("    output reg signed [7:0] bias   // Signed 8-bit bias value\n")
                    f.write(");\n\n")
                    
                    f.write("    always @* begin\n")
                    f.write("        case(filter_idx)\n")
                    
                    for oc in range(out_c):
                        bias = quantized_biases[oc]
                        f.write(f"            8'd{oc}: bias = 8'sd{bias};\n")
                    
                    f.write("            default: bias = 8'sd0;\n")
                    f.write("        endcase\n")
                    f.write("    end\n\n")
                    f.write("endmodule\n")
        
        elif isinstance(layer, layers.Dense):
            in_features, out_features = quantized_weights.shape
            
            verilog_file = f"weights/fc{i+1}_weights.v"
            with open(verilog_file, 'w') as f:
                f.write(f"// Weights for {layer_name}, Shape: {quantized_weights.shape}\n")
                f.write(f"// Quantization scale: {weight_scale}\n\n")
                
                f.write(f"module fc{i+1}_weights(\n")
                f.write("    input wire [15:0] input_idx,     // Input neuron index\n")
                f.write("    input wire [7:0] output_idx,     // Output neuron index\n")
                f.write("    output reg signed [7:0] weight  // Signed 8-bit weight value\n")
                f.write(");\n\n")
                
                f.write("    always @* begin\n")
                f.write("        case({output_idx, input_idx})\n")
                
                max_entries = 1000
                entry_count = 0
                
                for o in range(out_features):
                    for i in range(in_features):
                        if entry_count < max_entries:
                            weight = quantized_weights[i, o]
                            f.write(f"            {{8'd{o}, 16'd{i}}}: weight = 8'sd{weight};\n")
                            entry_count += 1
                
                if entry_count >= max_entries:
                    f.write("            // Additional weights omitted for brevity\n")
                
                f.write("            default: weight = 8'sd0;\n")
                f.write("        endcase\n")
                f.write("    end\n\n")
                f.write("endmodule\n")
            
            if bias_values is not None:
                bias_file = f"weights/fc{i+1}_biases.v"
                with open(bias_file, 'w') as f:
                    f.write(f"// Biases for {layer_name}\n")
                    f.write(f"// Quantization scale: {bias_scale}\n\n")
                    
                    f.write(f"module fc{i+1}_biases(\n")
                    f.write("    input wire [7:0] output_idx,  // Output neuron index\n")
                    f.write("    output reg signed [7:0] bias   // Signed 8-bit bias value\n")
                    f.write(");\n\n")
                    
                    f.write("    always @* begin\n")
                    f.write("        case(output_idx)\n")
                    
                    for o in range(out_features):
                        bias = quantized_biases[o]
                        f.write(f"            8'd{o}: bias = 8'sd{bias};\n")
                    
                    f.write("            default: bias = 8'sd0;\n")
                    f.write("        endcase\n")
                    f.write("    end\n\n")
                    f.write("endmodule\n")

    export_mif_files(model)

def export_mif_files(model):
    """
    Export weights as Memory Initialization Files (.mif) for BRAM loading.
    """
    for i, layer in enumerate(model.layers):
        weights = layer.get_weights()
        
        if len(weights) == 0:
            continue
        
        weight_values = weights[0]
        bias_values = weights[1] if len(weights) > 1 else None
        
        quantized_weights, _ = quantize_weights(weight_values)
        
        if isinstance(layer, layers.Conv2D):
            mif_file = f"weights/conv{i+1}_weights.mif"
            
            k_h, k_w, in_c, out_c = quantized_weights.shape
            
            with open(mif_file, 'w') as f:
                f.write("DEPTH = {};\n".format(k_h * k_w * in_c * out_c))
                f.write("WIDTH = 8;\n")
                f.write("ADDRESS_RADIX = HEX;\n")
                f.write("DATA_RADIX = DEC;\n")
                f.write("CONTENT BEGIN\n")
                
                addr = 0
                for oc in range(out_c):
                    for ic in range(in_c):
                        for kh in range(k_h):
                            for kw in range(k_w):
                                weight = int(quantized_weights[kh, kw, ic, oc])
                                f.write("{:04X} : {};\n".format(addr, weight))
                                addr += 1
                
                f.write("END;\n")
            
            if bias_values is not None:
                quantized_biases, _ = quantize_weights(bias_values)
                bias_mif = f"weights/conv{i+1}_biases.mif"
                
                with open(bias_mif, 'w') as f:
                    f.write("DEPTH = {};\n".format(len(quantized_biases)))
                    f.write("WIDTH = 8;\n")
                    f.write("ADDRESS_RADIX = HEX;\n")
                    f.write("DATA_RADIX = DEC;\n")
                    f.write("CONTENT BEGIN\n")
                    
                    for idx, bias in enumerate(quantized_biases):
                        f.write("{:04X} : {};\n".format(idx, int(bias)))
                    
                    f.write("END;\n")
                
        elif isinstance(layer, layers.Dense):
            in_features, out_features = quantized_weights.shape
            
            mif_file = f"weights/fc{i+1}_weights.mif"
            with open(mif_file, 'w') as f:
                f.write("DEPTH = {};\n".format(in_features * out_features))
                f.write("WIDTH = 8;\n")
                f.write("ADDRESS_RADIX = HEX;\n")
                f.write("DATA_RADIX = DEC;\n")
                f.write("CONTENT BEGIN\n")
                
                addr = 0
                for o in range(out_features):
                    for i in range(in_features):
                        weight = int(quantized_weights[i, o])
                        f.write("{:04X} : {};\n".format(addr, weight))
                        addr += 1
                
                f.write("END;\n")
            
            if bias_values is not None:
                quantized_biases, _ = quantize_weights(bias_values)
                bias_mif = f"weights/fc{i+1}_biases.mif"
                
                with open(bias_mif, 'w') as f:
                    f.write("DEPTH = {};\n".format(len(quantized_biases)))
                    f.write("WIDTH = 8;\n")
                    f.write("ADDRESS_RADIX = HEX;\n")
                    f.write("DATA_RADIX = DEC;\n")
                    f.write("CONTENT BEGIN\n")
                    
                    for idx, bias in enumerate(quantized_biases):
                        f.write("{:04X} : {};\n".format(idx, int(bias)))
                    
                    f.write("END;\n")

def visualize_model(model, history):
    """
    Visualize the model architecture and training results.
    """
    plt.figure(figsize=(12, 4))
    
    plt.subplot(1, 2, 1)
    plt.plot(history.history['accuracy'])
    plt.plot(history.history['val_accuracy'])
    plt.title('Model Accuracy')
    plt.ylabel('Accuracy')
    plt.xlabel('Epoch')
    plt.legend(['Train', 'Validation'], loc='lower right')
    
    plt.subplot(1, 2, 2)
    plt.plot(history.history['loss'])
    plt.plot(history.history['val_loss'])
    plt.title('Model Loss')
    plt.ylabel('Loss')
    plt.xlabel('Epoch')
    plt.legend(['Train', 'Validation'], loc='upper right')
    
    plt.tight_layout()
    plt.savefig('python/plots/training_history.png')
    
    if isinstance(model.layers[0], layers.Conv2D):
        weights = model.layers[0].get_weights()[0]
        
        min_val = np.min(weights)
        max_val = np.max(weights)
        weights = (weights - min_val) / (max_val - min_val)
        
        plt.figure(figsize=(8, 4))
        for i in range(6):
            plt.subplot(2, 3, i+1)
            plt.imshow(weights[:, :, 0, i], cmap='viridis')
            plt.title(f'Filter {i+1}')
            plt.axis('off')
        
        plt.tight_layout()
        plt.savefig('python/plots/conv1_filters.png')
    
    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    x_test = x_test.reshape(-1, 28, 28, 1).astype('float32') / 255.0
    
    predictions = model.predict(x_test[:10])
    predicted_classes = np.argmax(predictions, axis=1)
    
    plt.figure(figsize=(15, 7))
    for i in range(10):
        plt.subplot(2, 5, i+1)
        plt.imshow(x_test[i].reshape(28, 28), cmap='gray')
        plt.title(f'True: {np.argmax(y_test[i])}\nPred: {predicted_classes[i]}')
        plt.axis('off')
    
    plt.tight_layout()
    plt.savefig('python/plots/predictions.png')

def main():
    """Main function to train the model and export weights."""
    print("Loading MNIST dataset...")
    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    
    x_train = x_train.reshape(-1, 28, 28, 1).astype('float32') / 255.0
    x_test = x_test.reshape(-1, 28, 28, 1).astype('float32') / 255.0
    
    y_train = tf.keras.utils.to_categorical(y_train, 10)
    y_test = tf.keras.utils.to_categorical(y_test, 10)
    
    print("Creating LeNet-5 model...")
    model = create_lenet5_model()
    
    model.summary()
    
    print("Training the model...")
    history = model.fit(
        x_train, y_train,
        batch_size=128,
        epochs=10,
        validation_data=(x_test, y_test),
        verbose=1
    )
    
    test_loss, test_accuracy = model.evaluate(x_test, y_test, verbose=0)
    print(f"Test accuracy: {test_accuracy:.4f}")
    
    print("Exporting weights to Verilog format...")
    export_weights_to_verilog(model)
    
    print("Creating visualization plots...")
    visualize_model(model, history)
    
    print("Done! Weights have been exported to the 'weights' directory.")

if __name__ == '__main__':
    main() 
