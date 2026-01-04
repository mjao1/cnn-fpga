#!/usr/bin/env python3
"""
Generate specific or random test images from MNIST dataset for RTL simulation.

Usage:
    python generate_test_image.py --digit 7
    python generate_test_image.py --random
    python generate_test_image.py --digit 4 --index 10  # Use 10th occurrence of digit 4
"""

import argparse
import numpy as np
from tensorflow.keras.datasets import mnist
import os

def generate_test_image(digit=None, random=False, index=0, output_dir='sim/cnn/test_images'):
    os.makedirs(output_dir, exist_ok=True)
    
    # Load MNIST dataset
    (_, _), (test_images, test_labels) = mnist.load_data()
    
    # Select digit
    if random:
        digit = np.random.randint(0, 10)
        print(f"Randomly selected digit: {digit}")
    elif digit is None:
        print("Error: Must specify either --digit or --random")
        return
    
    if digit < 0 or digit > 9:
        print(f"Error: Digit must be between 0 and 9, got {digit}")
        return
    
    # Find all occurrences of the digit
    indices = np.where(test_labels == digit)[0]
    if len(indices) == 0:
        print(f"Error: No digit {digit} found in test set!")
        return
    
    if index >= len(indices):
        print(f"Warning: Only {len(indices)} occurrences of digit {digit} found, using last one")
        index = len(indices) - 1
    
    image_index = indices[index]
    image = test_images[image_index]
    label = test_labels[image_index]
    
    print(f"Using digit {label} at MNIST test index {image_index} (occurrence {index + 1} of {len(indices)})")
    
    # Create .txt file
    txt_filename = f'{output_dir}/test_image_{digit}.txt'
    with open(txt_filename, 'w') as f:
        f.write(f"{label}\n")
        
        for row in range(28):
            for col in range(28):
                f.write(f"{image[row][col]}\n")
    
    # Create .mem file
    image_normalized = image.astype('float32') / 255.0
    image_quantized = np.clip(np.round(image_normalized * 127), 0, 127).astype(np.int8)
    
    mem_filename = f'{output_dir}/test_image_{digit}.mem'
    with open(mem_filename, 'w') as f:
        for row in range(28):
            for col in range(28):
                val = int(image_quantized[row][col])
                if val < 0:
                    val = 256 + val
                f.write(f"{val:02X}\n")
    
    print(f"Created test image files for digit {label}:")
    print(f"  Text file: {txt_filename}")
    print(f"  Memory file: {mem_filename}")

def main():
    parser = argparse.ArgumentParser(
        description='Generate MNIST test images for RTL simulation',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--digit', type=int, choices=range(0, 10))
    group.add_argument('--random', action='store_true')
    
    parser.add_argument('--index', type=int, default=0)
    parser.add_argument('--output-dir', type=str, default='sim/cnn/test_images')
    
    args = parser.parse_args()
    
    generate_test_image(
        digit=args.digit,
        random=args.random,
        index=args.index,
        output_dir=args.output_dir
    )

if __name__ == "__main__":
    main()
