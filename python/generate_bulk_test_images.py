#!/usr/bin/env python3
"""
Generate 100 MNIST test images for each digit (0-9) for bulk accuracy testing.
"""

import numpy as np
from tensorflow.keras.datasets import mnist
import os

def generate_bulk_test_images(output_dir='sim/cnn/test_images_bulk', num_per_digit=100):
    os.makedirs(output_dir, exist_ok=True)
    
    (_, _), (test_images, test_labels) = mnist.load_data()
    
    total_generated = 0
    
    for digit in range(10):
        indices = np.where(test_labels == digit)[0]
        if len(indices) < num_per_digit:
            num_to_use = len(indices)
            selected_indices = indices
        else:
            num_to_use = num_per_digit
            selected_indices = np.random.choice(indices, size=num_per_digit, replace=False)
        
        for i in range(num_to_use):
            image_index = selected_indices[i]
            image = test_images[image_index]
            
            image_normalized = image.astype('float32') / 255.0
            image_quantized = np.clip(np.round(image_normalized * 127), 0, 127).astype(np.int8)
            
            mem_filename = f'{output_dir}/test_image_{digit}_{i}.mem'
            with open(mem_filename, 'w') as f:
                for row in range(28):
                    for col in range(28):
                        val = int(image_quantized[row][col])
                        if val < 0:
                            val = 256 + val
                        f.write(f"{val:02X}\n")
            
            total_generated += 1
        
        print(f"Generated {num_to_use} images for digit {digit}")

    print(f"Output directory: {output_dir}")

if __name__ == "__main__":
    generate_bulk_test_images()
