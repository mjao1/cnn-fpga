import numpy as np
from tensorflow.keras.datasets import mnist

def create_test_image(image_index=0):
    (_, _), (test_images, test_labels) = mnist.load_data()
    
    image = test_images[image_index]
    label = test_labels[image_index]
    
    with open('test_image.txt', 'w') as f:
        f.write(f"{label}\n")
        
        for row in range(28):
            for col in range(28):
                f.write(f"{image[row][col]}\n")
    
    print(f"Created test image file for digit {label}")
    print(f"Image saved to test_image.txt")

if __name__ == "__main__":
    create_test_image(image_index=3) 
