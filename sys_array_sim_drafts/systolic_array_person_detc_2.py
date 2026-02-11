"""
Create an automated compute for the most appropriate systolic array size for a specific model
Extract the different shapes of each layer, and then compute for the utilization 
add a layer extraction similar to the last npy_to_mem_format_converter.py

New thing I need to do:
find a way to actually simulate an image input and then see how the systolic array will handle that in a python sim and then the actual sys. array
also check the FPS that processes all the image inputs to find out if there is a significant speed up with the design
because currrently, the code only handles one conv, and not actually the whole image let alone multiple image inputs for a video stream
so given a target FPS and clock frequency, can you actually justify that the array size meets the target values?
"""
from dataclasses import dataclass
import pandas as pd

import numpy as np
import glob
import os

# mem files, need to just extract the comment info about the shape
root_folder = r"C:\Users\marie\Downloads\person_detect_extracted"

mem_files = glob.glob(os.path.join(root_folder, "**/*.mem"), recursive=True)
print(f"Found {len(mem_files)} .mem files") # ok this works, the files are found and we have 57 files

layers_info = [] # store here--

# set the targetted FPS with what clock (ABCore paper has 100 MHz constraint)
target_fps = 100 # say 30, but this can be adjusted anyways
f_clk = 100_000_000 # given 100 MHz
max_clk_cycles_per_frame = f_clk / target_fps
# cycles per frame is the accumulated sum of the cycles per image 
max_BW = 533_000_000 # for the zybo z7 20 

# now try to simulate the 96 x 96 BnW image input
H, W, C_in = 96, 96, 2 
input_image = np.zeros((H, W, C_in), dtype = np.uint8) # just black image, try to vary the input image later


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

# now make it load the HEX weights from the each mem file
def load_weights(mem_file):
    weights= []
    with open(mem_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line.startswith("#"):
                weights.append(int(line,16)) # skip the first line that has the comment then take the hex values

    return np.array(weights, dtype=np.uint8).view(np.int8)



# print case to check if the extraction works:
first_file = mem_files[0]
print(f"For checking- first 10 lines of {first_file}:")
with open(first_file, "r") as f:
    lines = f.readlines()

# Print the first 10 non-comment lines
count = 0
for line in lines:
    line = line.strip()
    if line.startswith("#"):
        continue  # skip comments
    print(line)
    count += 1
    if count >= 10:
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
                    # update: create an else statement to accomodate the other layers

def systolic_cycles(layer, row, col): # this is a per-layer analysis
                                      # update: now includes tiling 
    # estimates the number of cycles for pointwise conv for the row x col size systolic array
    t_macs = layer.H * layer.W * layer.C_in * layer.C_out # total number of MACs per layer of the person_detection.tflite model
    
    tile_in = (layer.C_in + row - 1) // row # how many tiles i need in to accomodate the input channel size, rounded up to the nearest integer
    tile_out = (layer.C_out + col - 1) // col
    total_cycles = 0

    for i in range (tile_in * tile_out):
        parallel_macs = min(layer.C_in, row) * min(layer.C_out, col)
        #mac_cycles = t_macs // parallel_macs assumes that the division is ideal
        mac_cycles = (t_macs + parallel_macs - 1) // parallel_macs
        overhead = row + col  - 2 # accounting for start up and data movement delays, -2 for filling and flushing (?)
        total_cycles += mac_cycles + overhead 
    return total_cycles 

def utilization(layer, row, col):
    # check out how much of the actual PEs are used over the total number placed
    active_PEs = min(layer.C_in, row) * min(layer.C_out, col)
    total_PEs = row * col
    return active_PEs / total_PEs

def bias_cycles(layer):
    return layer.H * layer.W * layer.C_out # just in case

def needed_BW(row, col, bitwidth = 8):
    # BW = transf rate * bitwidth * num of channels ?
    return (row + col) * bitwidth * f_clk

def sweep_size(layer, sizes):
    results = [] # store here
    for row, col in sizes: # iterate
        cycles = systolic_cycles(layer, row, col) # this is currently only for one part of an image
        utiliz = utilization(layer, row, col)

        results.append({
            "row" : row,
            "col" : col,
            "number of cycles": cycles,
            "utilization": utiliz
        })
    return pd.DataFrame(results)

sizes = [(3,3), (4,4), (8,8), (14,14), (16,16), (32,32)] # i just added 32x32 to see the difference of underutilization
                                                # it really isn't optimal to have a very large systolic array
                                                # what i see is 3x3 is really utilized in the beginning but has too many cycles
                                                # will make code that can show an average or conclude which size is appropriate

# OH MY GOODNESS AYOKO NA PLEASEEEEE SANA GUMANA KA NA PRE
def simulate_layer(layer, row, col, input_image, weights):
    cycles = systolic_cycles(layer, row, col)
    utilization_val = utilization(layer, row, col)

    H, W, C_in = input_image.shape
    output_image = np.zeros((layer.H, layer.W, layer.C_out), dtype=np.int32)
    for i in range(layer.H):
        for j in range(layer.W):
            for c_out in range(layer.C_out):
                region = input_image[i:i+H, j:j+W, :]  # pick all input channels
                filter_weights = weights[:, :, :, c_out]  # shape (H, W, C_in)
                output_image[i,j,c_out] = np.sum(region * filter_weights)

    if layer.kernel == 1:  # pointwise
        if weights.ndim != 2 or weights.shape != (layer.C_in, layer.C_out):
            raise ValueError(f"Pointwise weights shape mismatch for layer {layer}")
        else:
            flattened_input = input_image.reshape(-1, layer.C_in)
            output = np.dot(flattened_input, weights)
            output_image = output.reshape(layer.H, layer.W, layer.C_out)
    else:  # depthwise conv
        if weights.ndim != 3 or weights.shape != (layer.C_in, layer.kernel, layer.kernel):
            raise ValueError(f"Depthwise weights shape mismatch for layer {layer}")
        else: 
            for c in range(C_in):
                # simple valid convolution per channel
                for i in range(layer.H):
                    for j in range(layer.W):
                        region = input_image[i:i+layer.kernel, j:j+layer.kernel, c]
                        output_image[i, j, c] = np.sum(region * weights[c])
    return cycles, utilization_val, output_image


def sim_model_w_image(input_image, mem_files, layers_info, sizes, row, col):
    # pass one image through all the layers na
    all_layer_results = []
    current_input = input_image.copy()

    for i, layer_info in enumerate(layers_info):
        # made to handle either 4 or 1 input in shape per layer
        mem_file = mem_files[i]
        shape = layer_info["shape"]
        layer_name = layer_info["layer"]

        # Assuming shape = (1, H, W, C_out) for depthwise or (1,H,W,C_in) for pointwise
        # For depthwise separable, you might want C_in = C_out
        #H, W, C_in, C_out = shape # need to fix this, i forgot there are some files with just shape: (128,)
                                # the error that was thrown was expected 4, got 1

        weights = load_weights(mem_file)
        kernel = 1

        flat_size = weights.size
        if len(shape) == 4:
            H, W, C_in, C_out = shape

            if H == 1 and W == 1:
                if weights.size == C_in * C_out:
                    weights = weights.reshape(C_in, C_out)
                else:
                    raise ValueError(f"Warning: cannot reshape weights for {layer_name} to ({C_in},{C_out}), keeping flat.")
                #kernel = 1 #pointwise
                #weights = weights.reshape(C_in, C_out)
            else: 
                # DONT ASSUME INT kernel = int(np.sqrt(weights.size / C_in))
                # weights = weights.reshape(C_in, kernel, kernel)
                kernel = H
                if weights.size == C_in * kernel * kernel:
                    weights = weights.reshape(C_in, kernel, kernel)
                else: 
                    #kernel = 1 
                    #weights = weights.reshape(C_in, C_out)
                    raise ValueError (f"Warning: cannot reshape depthwise weights for {layer_name}, keeping flat.")


        elif len(shape) == 1:
            # like (128,)
            C_in, C_out = shape[0], shape[0]
            if weights.size == C_in * C_out:
                weights = weights.reshape(C_in, C_out)
            else:
                raise ValueError(f"Warning: cannot reshape depthwise weights for {layer_name}, keeping flat.")


        else: # just in case
            C_in, C_out = 1,1, shape [-2], shape[-1]
            if weights.size == C_in * C_out:
                weights = weights.reshape(C_in, C_out)
            else:
                print(f"Warning: cannot reshape depthwise weights for {layer_name}, keeping flat.")


        layer = ConvLayer(H=H, W=W, C_in=C_in, C_out=C_out, kernel=kernel)
        # Compute cycles + utilization for all diff sys array sizes
        df_layer = sweep_size(layer, sizes)
        df_layer["layer"] = layer_name
        all_layer_results.append(df_layer)

        cycles, utiliz, output = simulate_layer(layer, row, col, current_input, weights)
        print(f"{layer_name}: cycles={cycles}, utiliz={utiliz}")

        current_input = output  # feed output to next layer

    # Combine results for all layers
    df_all = pd.concat(all_layer_results, ignore_index=True)
    return df_all, current_input

# sum all the layers to determine how many clk cycles occur for ONE FULL IMAGE
cycles_per_frame = []
row, col = 16, 16 # chose this first
df_all, final_output = sim_model_w_image(input_image, mem_files, layers_info, sizes, row, col)

for (row,col), group in df_all.groupby(["row", "col"]):
    total_cycles = group["number of cycles"].sum()
    avg_utiliz = group["utilization"].mean()
    meet_fps_bool = total_cycles <= max_clk_cycles_per_frame # returns a bool
    bw_bool = needed_BW(row, col) <= max_BW 
    cycles_per_frame.append({
        "row": row,
        "col": col,
        "total_cycles_per_frame": total_cycles,
        "avg_utilization": avg_utiliz,
        "meet_fps_bool?": meet_fps_bool,
        "Bandwidth" : bw_bool
    })
print(f"Target FPS is:{target_fps}")
df_frame = pd.DataFrame(cycles_per_frame)
# print(df_frame)

# scoring the different systolic array sizes from best to worst
df_frame["score"] = (
    df_frame["meet_fps_bool?"].astype(int) * 100 + # bonus if it actually meets desired FPS
    df_frame["avg_utilization"] * 10  - # need to know the utilization 
    df_frame["row"] * df_frame["col"] * 0.01 # multiplier for oversize
)

best = df_frame.sort_values("score", ascending=False)
print(best)


