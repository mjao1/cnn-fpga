#!/usr/bin/env python3
"""
LeNet-5 Training Script for MNIST Digit Recognition:
Trains a LeNet-5 CNN on the MNIST dataset and exports
the weights in MEM format for BRAM initialization.

FPGA Quantization:
- Uses uniform Q1.7 fixed-point format (FRAC_BITS=7, scale=128)
"""

import os
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models
import matplotlib.pyplot as plt

os.makedirs('weights_mem', exist_ok=True)
os.makedirs('python/plots', exist_ok=True)

FRAC_BITS = 7
FIXED_SCALE = float(2 ** FRAC_BITS)

# Set to True for uniform scaling, False for per-layer power-of-two scaling
USE_UNIFORM_SCALE = True

# FC layer scaling factor to prevent output saturation
FC_SCALE_FACTOR = 2.0

def create_lenet5_model():
    """Create the deployment LeNet-5 model architecture.
    
    Kept dropout-free so quantize/export code can index layers 0, 2, 5, 6, 7
    directly without needing to account for regularization layers only
    present at train time.
    """
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


def create_training_model():
    """Create the training LeNet-5 model with 10% dropout before FC1.
    (this is only used during training, weights are transferred into a
    dropout-free deployment model before quantization so layer indices stay
    consistent with test_lenet5.py / export_weights_to_mem)
    """
    model = models.Sequential()
    model.add(layers.Conv2D(6, kernel_size=(5, 5), activation='relu',
                            input_shape=(28, 28, 1), padding='valid'))
    model.add(layers.MaxPooling2D(pool_size=(2, 2), strides=(2, 2)))
    model.add(layers.Conv2D(16, kernel_size=(5, 5), activation='relu',
                            padding='valid'))
    model.add(layers.MaxPooling2D(pool_size=(2, 2), strides=(2, 2)))
    model.add(layers.Flatten())
    model.add(layers.Dropout(0.1))
    model.add(layers.Dense(120, activation='relu'))
    model.add(layers.Dense(84, activation='relu'))
    model.add(layers.Dense(10, activation='softmax'))
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss='categorical_crossentropy',
                  metrics=['accuracy'])
    return model

def quantize_weights_fpga(weights, frac_bits=FRAC_BITS, use_uniform=USE_UNIFORM_SCALE):
    """
    Quantize weights to FPGA-friendly fixed-point representation.
    Args:
        weights: numpy array of floating-point weights
        frac_bits: number of fractional bits (7 for Q1.7, 6 for Q2.6)
        use_uniform: if True, use fixed scale; if False, use power of two
    
    Returns:
        quantized: int8 numpy array of quantized weights
        scale: scale factor used
        frac_bits: the fractional bits used (for FRAC_BITS parameter)
    """
    if use_uniform:
        scale = float(2 ** frac_bits)
    else:
        max_abs_val = np.max(np.abs(weights))
        if max_abs_val == 0:
            return np.zeros_like(weights, dtype=np.int8), 1.0, frac_bits
        
        # Find nearest power of two that keeps max value within int8 range
        raw_scale = 127.0 / max_abs_val
        frac_bits = int(np.round(np.log2(raw_scale)))
        frac_bits = max(0, min(frac_bits, 15))
        scale = float(2 ** frac_bits)
    
    quantized_float = np.round(weights * scale)
    
    # Clip to int8 range
    clipped = np.clip(quantized_float, -128, 127)
    num_clipped = np.sum(np.abs(quantized_float - clipped) > 0)
    if num_clipped > 0:
        print(f"    WARNING: {num_clipped} values clipped to int8 range")
    
    quantized = clipped.astype(np.int8)
    
    return quantized, scale, frac_bits


def quantize_weights(weights, bits=8):
    """
    Old wrapper for backward compatibility, uses FPGA friendly quantization now.
    """
    quantized, scale, _ = quantize_weights_fpga(weights)
    return quantized, scale

def export_weights_to_mem(model):
    """
    Export weights as .mem files
    - Uniform Q1.7 format (FRAC_BITS=7, scale=128) across all layers
    """
    layer_to_module_name = {
        0: "conv1",
        2: "conv2",
        5: "fc1",
        6: "fc2",
        7: "fc3"
    }
    
    # Track quantization info for each layer
    quant_info = {}
    
    print(f"\nQuantization config: FRAC_BITS={FRAC_BITS}, SCALE={FIXED_SCALE}")
    print(f"Mode: {'Uniform scaling' if USE_UNIFORM_SCALE else 'Per-layer power-of-two scaling'}\n")
    
    for i, layer in enumerate(model.layers):
        weights = layer.get_weights()
        
        if len(weights) == 0:
            continue
        
        weight_values = weights[0]
        bias_values = weights[1] if len(weights) > 1 else None
        
        # Skip pooling and other layers we don't need weights for
        if i not in layer_to_module_name:
            continue
            
        # Use module name for the weight files
        module_name = layer_to_module_name[i]
        
        print(f"Processing {module_name}:")
        print(f"  Weights shape: {weight_values.shape}")
        print(f"  Weights range: [{weight_values.min():.4f}, {weight_values.max():.4f}]")
        
        # Quantize weights
        quantized_weights, weight_scale, used_frac_bits = quantize_weights_fpga(weight_values)
        
        print(f"  Weight scale: {weight_scale} (FRAC_BITS={used_frac_bits})")
        
        if isinstance(layer, layers.Conv2D):
            k_h, k_w, in_c, out_c = quantized_weights.shape
            
            # Export weights
            mem_file = f"weights_mem/{module_name}_weights.mem"
            with open(mem_file, 'w') as f:
                for oc in range(out_c):
                    for ic in range(in_c):
                        for kh in range(k_h):
                            for kw in range(k_w):
                                weight = int(quantized_weights[kh, kw, ic, oc])
                                if weight < 0:
                                    weight = 256 + weight  # 2's complement for 8-bit
                                f.write("{:02X}\n".format(weight & 0xFF))
            
            # Export biases
            if bias_values is not None:
                print(f"  Biases range: [{bias_values.min():.4f}, {bias_values.max():.4f}]")
                
                quantized_biases = np.round(bias_values * weight_scale).astype(np.int8)
                quantized_biases = np.clip(quantized_biases, -128, 127).astype(np.int8)
                
                bias_mem = f"weights_mem/{module_name}_biases.mem"
                with open(bias_mem, 'w') as f:
                    for bias in quantized_biases:
                        bias_val = int(bias)
                        if bias_val < 0:
                            bias_val = 256 + bias_val  # 2's complement for 8-bit
                        f.write("{:02X}\n".format(bias_val & 0xFF))
        
        elif isinstance(layer, layers.Dense):
            # Apply FC scaling factor to prevent output saturation
            if FC_SCALE_FACTOR != 1.0:
                print(f"  Applying FC_SCALE_FACTOR={FC_SCALE_FACTOR} to prevent saturation")
                scaled_weights = weight_values / FC_SCALE_FACTOR
                scaled_biases = bias_values / FC_SCALE_FACTOR if bias_values is not None else None
                quantized_weights, weight_scale, used_frac_bits = quantize_weights_fpga(scaled_weights)
            else:
                scaled_biases = bias_values
            
            in_features, out_features = quantized_weights.shape
            
            # Export weights
            mem_file = f"weights_mem/{module_name}_weights.mem"
            with open(mem_file, 'w') as f:
                for o in range(out_features):
                    for inp in range(in_features):
                        weight = int(quantized_weights[inp, o])
                        if weight < 0:
                            weight = 256 + weight  # 2's complement for 8-bit
                        f.write("{:02X}\n".format(weight & 0xFF))
            
            # Export biases
            if scaled_biases is not None:
                print(f"  Biases range: [{scaled_biases.min():.4f}, {scaled_biases.max():.4f}]")
                
                quantized_biases = np.round(scaled_biases * weight_scale).astype(np.int8)
                quantized_biases = np.clip(quantized_biases, -128, 127).astype(np.int8)
                
                bias_mem = f"weights_mem/{module_name}_biases.mem"
                with open(bias_mem, 'w') as f:
                    for bias in quantized_biases:
                        bias_val = int(bias)
                        if bias_val < 0:
                            bias_val = 256 + bias_val
                        f.write("{:02X}\n".format(bias_val & 0xFF))
        
        # Store quantization info for this layer
        quant_info[module_name] = {
            'frac_bits': used_frac_bits,
            'scale': weight_scale,
            'weight_range': (weight_values.min(), weight_values.max()),
            'bias_range': (bias_values.min(), bias_values.max()) if bias_values is not None else None
        }
        print()
    
    # Export quantization for RTL reference
    info_file = "weights_mem/quantization_info.txt"
    with open(info_file, 'w') as f:
        f.write("# FPGA Quantization Configuration\n")
        f.write(f"# Generated with FRAC_BITS={FRAC_BITS}, SCALE={FIXED_SCALE}\n")
        f.write(f"# Mode: {'Uniform' if USE_UNIFORM_SCALE else 'Power-of-two per layer'}\n\n")
        for layer_name, info in quant_info.items():
            f.write(f"{layer_name}:\n")
            f.write(f"  frac_bits: {info['frac_bits']}\n")
            f.write(f"  scale: {info['scale']}\n")
            f.write(f"  weight_range: {info['weight_range']}\n")
            f.write(f"  bias_range: {info['bias_range']}\n\n")
    
    print(f"Quantization info saved to {info_file}")

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
        plt.title(f'True: {y_test[i]}\nPred: {predicted_classes[i]}')  # Use raw label directly
        plt.axis('off')
    
    plt.tight_layout()
    plt.savefig('python/plots/predictions.png')

def main():
    """Train the LeNet-5 model (with dropout + LR schedule + early stopping),
    transfer the weights into the deployment (dropout-free) model, then
    export Q1.7 .mem files."""
    print("Loading MNIST dataset...")
    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    
    x_train = x_train.reshape(-1, 28, 28, 1).astype('float32') / 255.0
    x_test = x_test.reshape(-1, 28, 28, 1).astype('float32') / 255.0
    
    y_train_1h = tf.keras.utils.to_categorical(y_train, 10)
    y_test_1h = tf.keras.utils.to_categorical(y_test, 10)
    
    print("Creating training LeNet-5 model (with dropout)...")
    train_model = create_training_model()
    train_model.summary()
    
    callbacks = [
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor='val_accuracy', factor=0.5, patience=2,
            min_lr=1e-5, verbose=1),
        tf.keras.callbacks.EarlyStopping(
            monitor='val_accuracy', patience=6,
            restore_best_weights=True, verbose=1),
    ]
    
    print("Training the model...")
    history = train_model.fit(
        x_train, y_train_1h,
        batch_size=128,
        epochs=25,
        validation_data=(x_test, y_test_1h),
        callbacks=callbacks,
        verbose=2,
    )
    
    # Transfer weights into the dropout-free deployment model so downstream
    # quantization/export logic can index layers 0, 2, 5, 6, 7 as usual.
    # Training model indices (with dropout): 0 conv1, 2 conv2, 6 fc1, 7 fc2, 8 fc3
    # Deploy model indices (no dropout): conv1, 2 conv2, 5 fc1, 6 fc2, 7 fc3
    model = create_lenet5_model()
    model.build(input_shape=(None, 28, 28, 1))
    model.layers[0].set_weights(train_model.layers[0].get_weights())
    model.layers[2].set_weights(train_model.layers[2].get_weights())
    model.layers[5].set_weights(train_model.layers[6].get_weights())
    model.layers[6].set_weights(train_model.layers[7].get_weights())
    model.layers[7].set_weights(train_model.layers[8].get_weights())
    
    test_loss, test_accuracy = model.evaluate(x_test, y_test_1h, verbose=0)
    print(f"Test accuracy after transfer: {test_accuracy:.4f}")
    
    # Save weights (just the deployment model; 10-epoch training model dropped)
    model_weights_path = 'python/lenet5.weights.h5'
    print(f"Saving model weights to {model_weights_path}...")
    model.save_weights(model_weights_path)

    print("Exporting weights to MEM format...")
    export_weights_to_mem(model)
    
    print("Creating visualization plots...")
    visualize_model(model, history)
    
    print("Done! Weights have been exported to the 'weights_mem' directory.")

if __name__ == '__main__':
    main() 
