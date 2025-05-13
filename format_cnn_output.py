#!/usr/bin/env python3

import re
import os
from collections import defaultdict

# Paths
log_file = "sim/cnn/cnn_results.log"
output_dir = "sim/cnn/formatted_output"
golden_dir = "golden_vectors"

# Create output directory if it doesn't exist
os.makedirs(output_dir, exist_ok=True)

# Patterns for extracting layer outputs
patterns = {
    "fc1": r"FC1 \[t=(\d+)\]: idx=(\d+), val=(-?\d+)",
    "fc2": r"FC2 \[t=(\d+)\]: idx=(\d+), val=(-?\d+)",
    "fc3": r"FC3 \[t=(\d+)\]: idx=(\d+), val=(-?\d+)",
    "flatten": r"FLATTEN \[t=(\d+)\]: idx=(\d+), val=(-?\d+)",
    "conv1": r"CONV1 \[t=(\d+)\]: ch=(\d+), y=(\d+), x=(\d+), val=(-?\d+)",
    "pool1": r"POOL1 \[t=(\d+)\]: ch=(\d+), y=(\d+), x=(\d+), val=(-?\d+)",
    "conv2": r"CONV2 \[t=(\d+)\]: ch=(\d+), y=(\d+), x=(\d+), val=(-?\d+)",
    "pool2": r"POOL2 \[t=(\d+)\]: ch=(\d+), y=(\d+), x=(\d+), val=(-?\d+)"
}

# Initialize storage for layer outputs
layer_outputs = defaultdict(lambda: defaultdict(int))
layer_sizes = {
    "fc1": 120,
    "fc2": 84,
    "fc3": 10,
    "flatten": 256
}

# Process the log file
with open(log_file, 'r') as f:
    log_content = f.read()

# Extract data for FC and flatten layers
for layer in ["fc1", "fc2", "fc3", "flatten"]:
    pattern = patterns[layer]
    matches = re.findall(pattern, log_content)
    for match in matches:
        time_stamp, idx, val = match
        idx = int(idx)
        val = int(val)
        # Keep the latest value
        layer_outputs[layer][idx] = val

# Extract data for convolutional and pooling layers (treat differently)
conv_pool_outputs = defaultdict(list)
for layer in ["conv1", "pool1", "conv2", "pool2"]:
    pattern = patterns[layer]
    matches = re.findall(pattern, log_content)
    for match in matches:
        if layer in ["conv1", "pool1", "conv2", "pool2"]:
            time_stamp, ch, y, x, val = match
            ch, y, x, val = int(ch), int(y), int(x), int(val)
            conv_pool_outputs[layer].append((ch, y, x, val))

# Write formatted output files for FC and flatten layers
for layer, outputs in layer_outputs.items():
    output_file = f"{output_dir}/{layer}_output.txt"
    with open(output_file, 'w') as f:
        # Write header
        if layer == "flatten":
            f.write(f"# {layer} output: {layer_sizes[layer]} neurons\n")
            f.write("# Format: index, value\n")
        else:
            f.write(f"# {layer} output: {layer_sizes[layer]} neurons\n")
            f.write("# Format: neuron_index, value\n")
        
        # Write the values in order of index
        for idx in range(layer_sizes[layer]):
            val = outputs.get(idx, 0)  # Default to 0 if index not found
            f.write(f"{idx}, {val}\n")

# Write formatted output files for convolutional and pooling layers
for layer, outputs in conv_pool_outputs.items():
    output_file = f"{output_dir}/{layer}_output.txt"
    
    # Organize by channel, y, x
    organized_outputs = defaultdict(lambda: defaultdict(dict))
    for ch, y, x, val in outputs:
        organized_outputs[ch][y][x] = val
    
    with open(output_file, 'w') as f:
        # Write header
        if layer == "conv1":
            f.write(f"# {layer} output: 6 channels\n")
        elif layer == "pool1":
            f.write(f"# {layer} output: 6 channels\n")
        elif layer == "conv2":
            f.write(f"# {layer} output: 16 channels\n")
        elif layer == "pool2":
            f.write(f"# {layer} output: 16 channels\n")
        
        f.write("# Format: channel, y, x, value\n")
        
        # Write the values organized by channel, y, x
        for ch in sorted(organized_outputs.keys()):
            for y in sorted(organized_outputs[ch].keys()):
                for x in sorted(organized_outputs[ch][y].keys()):
                    val = organized_outputs[ch][y][x]
                    f.write(f"{ch}, {y}, {x}, {val}\n")

def compare_with_golden(layer_name):
    """Compare formatted output with golden vector for a specific layer"""
    actual_file = f"{output_dir}/{layer_name}_output.txt"
    golden_file = f"{golden_dir}/{layer_name}_output.txt"
    
    if not os.path.exists(golden_file):
        print(f"Golden file for {layer_name} not found")
        return False
    
    # Read actual and golden data
    actual_data = {}
    golden_data = {}
    
    with open(actual_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                parts = line.split(',')
                if len(parts) == 2:  # FC or flatten layers
                    idx, val = int(parts[0]), int(parts[1])
                    actual_data[idx] = val
    
    with open(golden_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                parts = line.split(',')
                if len(parts) == 2:  # FC or flatten layers
                    idx, val = int(parts[0]), int(parts[1])
                    golden_data[idx] = val
    
    # Compare data
    if not golden_data:
        print(f"No data found in golden file for {layer_name}")
        return False
    
    differences = []
    for idx in golden_data:
        golden_val = golden_data.get(idx, 0)
        actual_val = actual_data.get(idx, 0)
        if golden_val != actual_val:
            differences.append((idx, golden_val, actual_val))
    
    if differences:
        print(f"Differences found in {layer_name}:")
        print(f"{'Index':<10}{'Golden Value':<15}{'Actual Value':<15}")
        for idx, golden_val, actual_val in differences[:10]:  # Show first 10 differences
            print(f"{idx:<10}{golden_val:<15}{actual_val:<15}")
        if len(differences) > 10:
            print(f"... and {len(differences) - 10} more differences")
        return False
    else:
        print(f"Layer {layer_name} matches golden vector")
        return True

print("Formatted output files created in", output_dir)

# Compare FC layers with golden vectors
print("\nComparing with golden vectors:")
for layer in ["fc1", "fc2", "fc3", "flatten"]:
    compare_with_golden(layer) 
