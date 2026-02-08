import numpy as np
import glob
import os

# Fix the path using raw string
root_folder = r"C:\Users\marie\Downloads\person_detect_extracted"

npy_files = glob.glob(os.path.join(root_folder, "**/*.npy"), recursive=True)
print(f"Found {len(npy_files)} .npy files")

for npy_file in npy_files:
    w = np.load(npy_file)

    # Convert to int8
    if w.dtype != np.int8:
        w = np.round(w * 127).astype(np.int8)

    shape = w.shape
    mem_file = os.path.splitext(npy_file)[0] + ".mem"

    with open(mem_file, "w") as f:
        f.write(f"# shape: {shape}\n")
        for v in w.flatten():
            f.write(f"{v & 0xff:02x}\n")

    print(f"Converted {npy_file} → {mem_file} (shape: {shape})")