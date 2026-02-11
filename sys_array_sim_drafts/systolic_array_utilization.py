# Create an automated compute for the most appropriate systolic array size for a specific model
# Extract the different shapes of each layer, and then compute for the utilization 
# add a layer extraction similar to the last npy_to_mem_format_converter.py
from dataclasses import dataclass
import pandas as pd

# import numpy as np
import glob
import os

# mem files, need to just extract the comment info about the shape
root_folder = r"C:\Users\marie\Downloads\person_detect_extracted"

mem_files = glob.glob(os.path.join(root_folder, "**/*.mem"), recursive=True)
print(f"Found {len(mem_files)} .mem files") # ok this works, the files are found and we have 57 files

layers_info = [] # store here

for mem_file in mem_files:
    layer_name = os.path.splitext(os.path.basename(mem_file))[0]
    with open(mem_file, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("# shape:"): # just take the first line info
                shape_str = line[len("# shape:"):].strip()
                #convert to tuple of integers
                shape = tuple(int(x.strip()) for x in shape_str.strip("()").split(",") if x.strip())
                layers_info.append({
                    "layer": layer_name,
                    "shape": shape
                })
                break


@dataclass
class ConvLayer:
    H: int
    W: int
    C_in: int
    C_out: int
    kernel: int = 1 # assumes pointwise, but note that person_detection.tflite is depthwise separable
                    # where depthwise seperable is a comp of depthwise conv then a pointwise conv
                    # expected input for this class: ConvLayer(H = n, W = n, C_in = x, C_out = x)

def systolic_cycles(layer, row, col):
    # estimates the number of cycles for pointwise conv for the row x col size systolic array
    t_macs = layer.H * layer.W * layer.C_in * layer.C_out # total number of MACs per layer of the person_detection.tflite model
    parallel_macs = min(layer.C_in, row) * min(layer.C_out, col)
    mac_cycles = t_macs // parallel_macs # int
    overhead = row + col # accounting for start up and data movement delays
    return mac_cycles + overhead 

def utilization(layer, row, col):
    # check out how much of the actual PEs are used over the total number placed
    active_PEs = min(layer.C_in, row) * min(layer.C_out, col)
    total_PEs = row * col
    return active_PEs / total_PEs

def bias_cycles(layer):
    return layer.H * layer.W * layer.C_out # just in case

def sweep_size(layer, sizes):
    results = [] # store here
    for row, col in sizes: # iterate
        cycles = systolic_cycles(layer, row, col)
        utiliz = utilization(layer, row, col)

        results.append({
            "row" : row,
            "col" : col,
            "num cycles": cycles,
            "utilization": utiliz
        })
    return pd.DataFrame(results)

sizes = [(3,3), (4,4), (8,8), (16,16), (32,32)] # i just added 32x32 to see the difference of underutilization
                                                # it really isn't optimal to have a very large systolic array
                                                # what i see is 3x3 is really utilized in the beginning
                                                # will make code that can show an average or conclude which size is appropriate

all_layer_results = []

for layer_info in layers_info: # made to handle either 4 or 1 input in shape per layer
    shape = layer_info["shape"]
    layer_name = layer_info["layer"]

    # Assuming shape = (1, H, W, C_out) for depthwise or (1,H,W,C_in) for pointwise
    # For depthwise separable, you might want C_in = C_out
    #H, W, C_in, C_out = shape # need to fix this, i forgot there are some files with just shape: (128,)
                              # the error that was thrown was expected 4, got 1

    # fix for different cases:
    if len(shape) == 4: # usual cases
        H, W, C_in, C_out = shape
    elif len(shape) == 1:
        H, W, C_in, C_out = 1, 1, shape[0], shape[0] # this is for the casse of just (128,)
    else:
        H, W, C_in, C_out = 1, 1, shape[-2], shape[-1] # just in case something else

    layer = ConvLayer(H=H, W=W, C_in=C_in, C_out=C_out)

    # Compute cycles + utilization for all sizes
    df_layer = sweep_size(layer, sizes)
    df_layer["layer"] = layer_name
    all_layer_results.append(df_layer)

# Combine results for all layers
df_all = pd.concat(all_layer_results, ignore_index=True)
print(df_all)

# Sort by number of cycles
print(df_all.sort_values("num cycles"))
