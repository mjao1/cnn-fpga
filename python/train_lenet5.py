#!/usr/bin/env python3
"""
LeNet-5 Training Script for MNIST Digit Recognition:
Trains a LeNet-5 CNN on the MNIST dataset and exports
the weights in MIF format for BRAM initialization.
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

def export_weights_to_mif(model):
    """
    Export weights as .mif for BRAM loading
    """
    for i, layer in enumerate(model.layers):
        weights = layer.get_weights()
        
        if len(weights) == 0:
            continue
        
        weight_values = weights[0]
        bias_values = weights[1] if len(weights) > 1 else None
        
        quantized_weights, weight_scale = quantize_weights(weight_values)
        
        if isinstance(layer, layers.Conv2D):
            k_h, k_w, in_c, out_c = quantized_weights.shape
            
            # Export weights
            mif_file = f"weights/conv{i+1}_weights.mif"
            with open(mif_file, 'w') as f:
                f.write(f"// Weights for {layer.name}, Shape: {quantized_weights.shape}\n")
                f.write(f"// Quantization scale: {weight_scale}\n")
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
            
            # Export biases
            if bias_values is not None:
                quantized_biases, bias_scale = quantize_weights(bias_values)
                bias_mif = f"weights/conv{i+1}_biases.mif"
                
                with open(bias_mif, 'w') as f:
                    f.write(f"// Biases for {layer.name}\n")
                    f.write(f"// Quantization scale: {bias_scale}\n")
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
            
            # Export weights
            mif_file = f"weights/fc{i+1}_weights.mif"
            with open(mif_file, 'w') as f:
                f.write(f"// Weights for {layer.name}, Shape: {quantized_weights.shape}\n")
                f.write(f"// Quantization scale: {weight_scale}\n")
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
            
            # Export biases
            if bias_values is not None:
                quantized_biases, bias_scale = quantize_weights(bias_values)
                bias_mif = f"weights/fc{i+1}_biases.mif"
                
                with open(bias_mif, 'w') as f:
                    f.write(f"// Biases for {layer.name}\n")
                    f.write(f"// Quantization scale: {bias_scale}\n")
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
    
    print("Exporting weights to MIF format...")
    export_weights_to_mif(model)
    
    print("Creating visualization plots...")
    visualize_model(model, history)
    
    print("Done! Weights have been exported to the 'weights' directory.")

if __name__ == '__main__':
    main() 
