import numpy as np
from scipy.linalg import toeplitz
import cv2

def toeplitz_but_bytes(first_col, first_row):
    n, m  = len(first_col), len(first_row)
    matrix = np.zeros((n, m), dtype=np.uint8)
    for i in range(n):
        for j in range(m):
            if i >= j:
                matrix[i, j] = first_col[i - j]
            else:
                matrix[i, j] = first_row[j - i]
    return bytearray(matrix.tobytes()) # this converts to row major NHWC
 
def get_stream(image, ker_size):
    output = bytearray()
    image_h, image_w = image.shape

    # if we have a stride of 1:
    # remove the excess, then jump 1
    for r in range(image_h - ker_size + 1):
        for c in range(image_w - ker_size + 1):
            patch = image[r:r + ker_size, c:c+ker_size] # get the kernel patch / extracted
            output.extend(patch.tobytes())
    return output

def get_nhwc_stream(image, ker_size):
    output_list = []
    if len(image.shape) == 3:
        h, w, c = image.shape
    else: 
        h, w = image.shape
        c = 1 # B&W 1 channel

    for r in range(h - ker_size + 1):
        for col in range(w - ker_size + 1):
            if c > 1:
                patch = image[r:r + ker_size, col:col + ker_size, :]
            else:
                patch = image[r:r + ker_size, col:col + ker_size]
            output_list.append(patch.flatten().tolist())
    return output_list

def verify_toe_output(matrix, image_w, ker_size):
    matches = 0 
    total_checks = 0 
    for i in range(len(matrix) - 1):
        current_patch = matrix[i]
        next_patch = matrix[i+1]

        # right 2 cols of N should match left 2 cols of the N + 1
        right_col = [1, 2, 4, 5, 7, 8]
        left_col  = [0, 1, 3, 4, 6, 7]

        for r_idx, l_idx in zip(right_col, left_col):
            total_checks += 1 
            if current_patch[r_idx] == next_patch[l_idx]:
                matches += 1
        
        accuracy = (matches / total_checks) * 100
        print(f"Consistency: {accuracy: .2f}%")
        return accuracy > 99 # accuracy should be 100% for stride = 1

# make a readjustable image input size
image_size = 5
kernel_size = 3
# if for example 5x5 then this will adjust based on the limitations
# image_input = np.arange(image_size * image_size, dtype=np.uint8).reshape(image_size, image_size)
# toeplitz_output_bytes = get_stream(image_input, kernel_size)
# print(image_input)

# using a real image:
image = r"C:\Users\marie\OneDrive\Desktop\DigAI Python\woman_blue_bg.jpg"
#r"C:\Users\marie\OneDrive\Desktop\DigAI Python\image_person_thumbsup.jpg"
image_raw = cv2.imread(image)
image_bnw = cv2.cvtColor(image_raw, cv2.COLOR_BGR2GRAY)
bw_image_resize = cv2.resize(image_bnw, (image_size, image_size))
toeplitz_output = get_nhwc_stream(bw_image_resize, kernel_size)
print(image_raw)
print(image_bnw)
print(toeplitz_output)
verify_toe_output(toeplitz_output, image_size, kernel_size)
