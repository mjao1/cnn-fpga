#!/usr/bin/env python3
"""Sweep FC_SCALE_FACTOR to find the best post-training scaling factor for
the FC layers before Q1.7 quantization.

The FC layer weights span roughly [-0.60, +0.47], so with scale=128 a raw
value of -0.6 quantizes to -77, losing headroom for the accumulator. By
dividing FC weights by `s` before quantizing, we trade weight precision for
accumulator headroom, avoiding saturation in the output of FC1/FC2/FC3.

We evaluate each candidate on:
  * the 1000 bulk images that tb_cnn_top_bulk uses, and
  * the full 10,000 MNIST test set (for a more statistically stable number).
"""

import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))

import tensorflow as tf  # noqa: E402

from train_lenet5 import create_lenet5_model  # noqa: E402
from accuracy_compare import (  # noqa: E402
    load_bulk_images,
    get_quantized_params,
    run_quant_inference_batch,
)


def run_on_set(images_q17, labels, params):
    preds, _ = run_quant_inference_batch(images_q17, params)
    return int((preds == labels).sum()), len(labels)


def mnist_to_q17():
    (_, _), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    x = x_test.astype(np.float32) / 255.0
    q = np.clip(np.round(x * 127), 0, 127).astype(np.int8)
    return q.reshape(-1, 28, 28, 1), y_test.astype(np.int32)


def main():
    print("Loading bulk 1000-image test set...")
    bulk_q, bulk_y = load_bulk_images()
    print("Loading full 10k-image MNIST test set (Q1.7)...")
    full_q, full_y = mnist_to_q17()

    print("Loading trained model...")
    model = create_lenet5_model()
    model.load_weights("python/lenet5.weights.h5")

    scales = [1.0, 1.25, 1.5, 1.76, 2.0, 2.25, 2.5, 3.0, 3.5, 4.0]

    print(f"\n{'FC_SCALE':>10s} | {'Bulk 1000':>10s} | {'MNIST 10k':>10s}")
    print("-" * 40)
    for s in scales:
        params = get_quantized_params(model, use_fc_scale=True, fc_scale_factor=s)
        b_c, b_t = run_on_set(bulk_q, bulk_y, params)
        f_c, f_t = run_on_set(full_q, full_y, params)
        print(f"{s:10.2f} | {b_c:5d}/{b_t:4d} | {f_c:5d}/{f_t:5d}  "
              f"({100.0*b_c/b_t:.2f}%, {100.0*f_c/f_t:.2f}%)")


if __name__ == "__main__":
    main()
