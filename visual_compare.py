#!/usr/bin/env python3

import numpy as np
import matplotlib.pyplot as plt
import os

def read_output_file(filename):
    """Read channel, y, x, value data from output file"""
    data = {}
    try:
        with open(filename, 'r') as f:
            lines = f.readlines()
            for line in lines:
                line = line.strip()
                if line.startswith('#') or not line:
                    continue
                
                parts = line.split(',')
                if len(parts) == 4:
                    ch = int(parts[0])
                    y = int(parts[1])
                    x = int(parts[2])
                    val = int(parts[3])
                    
                    if ch not in data:
                        data[ch] = {}
                    if y not in data[ch]:
                        data[ch][y] = {}
                    
                    data[ch][y][x] = val
    except Exception as e:
        print(f"Error reading file {filename}: {e}")
    
    return data

def read_fc_output_file(filename):
    """Read neuron_idx, value data from FC output file"""
    data = {}
    try:
        with open(filename, 'r') as f:
            lines = f.readlines()
            for line in lines:
                line = line.strip()
                if line.startswith('#') or not line:
                    continue
                
                parts = line.split(',')
                if len(parts) == 2:
                    idx = int(parts[0])
                    val = int(parts[1])
                    data[idx] = val
    except Exception as e:
        print(f"Error reading file {filename}: {e}")
    
    return data

def create_activation_map(data, channel, height=24, width=24):
    """Create an activation map for a specific channel"""
    activation_map = np.zeros((height, width))
    
    if channel in data:
        for y in data[channel]:
            for x in data[channel][y]:
                if 0 <= y < height and 0 <= x < width:
                    activation_map[y, x] = data[channel][y][x]
    
    return activation_map

def visualize_activations(golden_file, sim_file, output_dir):
    """Visualize and compare activations between golden and simulation outputs"""
    golden_data = read_output_file(golden_file)
    sim_data = read_output_file(sim_file)
    
    os.makedirs(output_dir, exist_ok=True)
    
    # Determine the available channels
    all_channels = set(golden_data.keys()) | set(sim_data.keys())
    
    for channel in sorted(all_channels):
        # Create activation maps
        golden_map = create_activation_map(golden_data, channel)
        sim_map = create_activation_map(sim_data, channel)
        
        # Calculate difference
        diff_map = golden_map - sim_map
        
        # Plot
        plt.figure(figsize=(15, 5))
        
        plt.subplot(1, 3, 1)
        plt.imshow(golden_map, cmap='viridis')
        plt.title(f'Channel {channel} - Golden')
        plt.colorbar()
        
        plt.subplot(1, 3, 2)
        plt.imshow(sim_map, cmap='viridis')
        plt.title(f'Channel {channel} - Simulation')
        plt.colorbar()
        
        plt.subplot(1, 3, 3)
        plt.imshow(diff_map, cmap='RdBu')
        plt.title(f'Channel {channel} - Difference')
        plt.colorbar()
        
        plt.tight_layout()
        plt.savefig(f"{output_dir}/channel_{channel}_comparison.png")
        plt.close()
        
        # Print some stats
        print(f"Channel {channel}:")
        print(f"  Golden: min={np.min(golden_map)}, max={np.max(golden_map)}, non-zero={np.count_nonzero(golden_map)}")
        print(f"  Simulation: min={np.min(sim_map)}, max={np.max(sim_map)}, non-zero={np.count_nonzero(sim_map)}")
        print(f"  Difference: min={np.min(diff_map)}, max={np.max(diff_map)}, non-zero={np.count_nonzero(diff_map)}")
        print()

def compare_fc_outputs(golden_file, sim_file, output_dir):
    """Compare FC layer outputs (final classifications)"""
    golden_data = read_fc_output_file(golden_file)
    sim_data = read_fc_output_file(sim_file)
    
    os.makedirs(output_dir, exist_ok=True)
    
    # Get all indices
    all_indices = set(golden_data.keys()) | set(sim_data.keys())
    
    # Create arrays for plotting
    indices = np.array(sorted(all_indices))
    golden_values = np.array([golden_data.get(idx, 0) for idx in indices])
    sim_values = np.array([sim_data.get(idx, 0) for idx in indices])
    
    # Print comparison
    print("FC Layer comparison:")
    for idx in indices:
        golden_val = golden_data.get(idx, 0)
        sim_val = sim_data.get(idx, 0)
        print(f"  Index {idx}: Golden={golden_val}, Simulation={sim_val}, Diff={golden_val - sim_val}")
    
    # Plot comparison
    plt.figure(figsize=(12, 6))
    
    # Create bar positions
    x = np.arange(len(indices))
    width = 0.35
    
    # Plot bars
    bars1 = plt.bar(x - width/2, golden_values, width, label='Golden')
    bars2 = plt.bar(x + width/2, sim_values, width, label='Simulation')
    
    # Add labels and title
    plt.xlabel('Neuron Index')
    plt.ylabel('Output Value')
    plt.title('FC Layer Output Comparison')
    plt.xticks(x, indices)
    plt.legend()
    
    plt.tight_layout()
    plt.savefig(f"{output_dir}/fc_comparison.png")
    plt.close()
    
    # Determine which output has the maximum value
    golden_max_idx = indices[np.argmax(golden_values)]
    sim_max_idx = indices[np.argmax(sim_values)]
    
    print(f"Golden prediction: {golden_max_idx} (value: {golden_data.get(golden_max_idx, 0)})")
    print(f"Simulation prediction: {sim_max_idx} (value: {sim_data.get(sim_max_idx, 0)})")
    print(f"Matching prediction: {golden_max_idx == sim_max_idx}")

def main():
    # Path to files
    golden_conv1 = "golden_vectors/conv1_output.txt"
    sim_conv1 = "sim/cnn/formatted_output/conv1_output.txt"
    golden_fc3 = "golden_vectors/fc3_output.txt"
    sim_fc3 = "sim/cnn/formatted_output/fc3_output.txt"
    output_dir = "sim/cnn/comparison_plots"
    
    # Visualize conv1 activations
    print("Comparing CONV1 activations...")
    visualize_activations(golden_conv1, sim_conv1, output_dir)
    
    # Compare FC3 outputs (final digit classification)
    print("\nComparing FC3 outputs (final classification)...")
    compare_fc_outputs(golden_fc3, sim_fc3, output_dir)
    
    print(f"\nPlots saved to {output_dir}")

if __name__ == "__main__":
    main() 
