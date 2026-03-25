import numpy as np
import os
# Read all weights, then generate an input image to produce a Golden Output Reference for comparison

def to_s8(n):
    return n if n < 128 else n - 256

def load_all_weights(path):
    with open(path, 'r') as f:
        hex_list = [line.split('//')[0].strip() for line in f if line.strip()]
        raw_weights = []
        for x in hex_list:
            for part in x.split(): # Handles multiple hex values on one line
                try:
                    raw_weights.append(to_s8(int(part, 16)))
                except ValueError:
                    continue # Skips things that aren't hex numbers
                    
    return np.array(raw_weights[:72]).reshape(8, 3, 3)

# --- Fix Weight Extraction ---
# These are the weights for Channel 0 from .mem file (3x3 = 9)
weights_path = r"C:\Users\marie\Downloads\person_detect_extracted\0_depthw_conv_2d\MobilenetV1_Conv2d_0_depthwise_weights_read.mem"
weights_loaded = load_all_weights(weights_path)

# --- Generate 96x96 Input ---
np.random.seed(42) 
input_bw = np.random.randint(0, 256, (96, 96, 8), dtype=np.uint8)

# 1. Create the input .mem for HDL
with open("video_input_96x96_bnw.mem", "w") as f:
    for r in range(96):
        for c in range(96):
            vals = [f"{input_bw[r, c, ch]:02x}" for ch in range(8)]
            f.write(" ".join(vals) + "\n")

# 2. Generate Golden Output (94x94)
golden_ref = []
for y in range(94):
    for x in range(94):
        cycle_out = []
        for ch in range(8):
            window = input_bw[y:y+3, x:x+3, ch]
            kernel = weights_loaded[ch]
            mac_sum = np.sum(window.astype(np.int32) * kernel.astype(np.int32))
            # Quantization (matching top_systolic_array.sv)
            final = (mac_sum * 256) >> 8 
            clipped = max(min(final, 127), -128)
            cycle_out.append(clipped & 0xFF)
        golden_ref.append(cycle_out)

with open("golden_output_ch0.mem", "w") as f:
    for row in golden_ref:
        f.write(" ".join([f"{val:02x}" for val in row]) + "\n")

print("Files generated: video_input_96x96_8ch.mem and golden_output_8ch.mem")