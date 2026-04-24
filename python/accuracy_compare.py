#!/usr/bin/env python3
"""
Compare software accuracy against the hardware accuracy.

Evaluates the trained LeNet-5 model in three modes on the same 1000
Q1.7 test images that the RTL testbench uses (sim/cnn/test_images_bulk/):

1. FP32 inference: the raw Keras model on the Q1.7-dequantized inputs.
2. Quantized inference (Q1.7, hardware-matching): bit-exactly replicates
   the RTL arithmetic using quantized weights / FC_SCALE_FACTOR scaling.
3. Quantized inference without the FC_SCALE_FACTOR divisor.

This lets us see how much accuracy we lose from quantization vs. RTL bugs.
"""

import os
import sys
import argparse
import time
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))

import tensorflow as tf  # noqa: E402

from train_lenet5 import (  # noqa: E402
    create_lenet5_model,
    quantize_weights_fpga,
    FRAC_BITS,
    FIXED_SCALE,
    FC_SCALE_FACTOR,
)

BULK_DIR = "sim/cnn/test_images_bulk"
NUM_PER_DIGIT = 100
NUM_DIGITS = 10


def load_bulk_images(bulk_dir=BULK_DIR, num_per_digit=NUM_PER_DIGIT):
    """Load all .mem files the hardware testbench uses.

    Each .mem file is 784 lines of 2-char hex (the Q1.7 pixel value, 0..127
    since MNIST inputs are non-negative).
    Returns (images_q17 as int8[N,28,28,1], labels as int[N]).
    """
    imgs = []
    labels = []
    for d in range(NUM_DIGITS):
        for i in range(num_per_digit):
            p = os.path.join(bulk_dir, f"test_image_{d}_{i}.mem")
            with open(p, "r") as f:
                vals = [int(line.strip(), 16) for line in f if line.strip()]
            assert len(vals) == 28 * 28, f"{p} has {len(vals)} values"
            arr = np.array(vals, dtype=np.int32)
            arr = np.where(arr >= 128, arr - 256, arr).astype(np.int8)
            imgs.append(arr.reshape(28, 28, 1))
            labels.append(d)
    return np.stack(imgs, axis=0), np.array(labels, dtype=np.int32)


def get_quantized_params(model, use_fc_scale=True, fc_scale_factor=FC_SCALE_FACTOR):
    """Extract all weights & biases as Q1.7 int8, identical to
    `export_weights_to_mem` / `run_quantized_inference`."""
    p = {}

    c1w, c1b = model.layers[0].get_weights()
    p["c1w"] = quantize_weights_fpga(c1w)[0]
    p["c1b"] = np.clip(np.round(c1b * FIXED_SCALE), -128, 127).astype(np.int8)

    c2w, c2b = model.layers[2].get_weights()
    p["c2w"] = quantize_weights_fpga(c2w)[0]
    p["c2b"] = np.clip(np.round(c2b * FIXED_SCALE), -128, 127).astype(np.int8)

    f1w, f1b = model.layers[5].get_weights()
    f2w, f2b = model.layers[6].get_weights()
    f3w, f3b = model.layers[7].get_weights()
    if use_fc_scale:
        s = float(fc_scale_factor)
    else:
        s = 1.0

    p["f1w"] = quantize_weights_fpga(f1w / s)[0]
    p["f1b"] = np.clip(np.round((f1b / s) * FIXED_SCALE), -128, 127).astype(np.int8)
    p["f2w"] = quantize_weights_fpga(f2w / s)[0]
    p["f2b"] = np.clip(np.round((f2b / s) * FIXED_SCALE), -128, 127).astype(np.int8)
    p["f3w"] = quantize_weights_fpga(f3w / s)[0]
    p["f3b"] = np.clip(np.round((f3b / s) * FIXED_SCALE), -128, 127).astype(np.int8)
    return p


def _conv_valid(inp_q17, kernel_q17, bias_q17, frac_bits=FRAC_BITS):
    """Vectorized valid convolution matching `quantized_conv2d` semantics.

    Accumulates int32 sum of Q1.7*Q1.7 products per output channel,
    adds bias<<frac_bits, then arithmetic right-shifts and saturates to int8.
    """
    b, h, w, ic = inp_q17.shape
    kh, kw, _, oc = kernel_q17.shape
    oh = h - kh + 1
    ow = w - kw + 1

    inp = inp_q17.astype(np.int32)
    ker = kernel_q17.astype(np.int32)

    # Build sliding-window view: [b, oh, ow, kh, kw, ic]
    s = inp.strides
    shape = (b, oh, ow, kh, kw, ic)
    strides = (s[0], s[1], s[2], s[1], s[2], s[3])
    windows = np.lib.stride_tricks.as_strided(inp, shape=shape, strides=strides)
    # Contract (kh, kw, ic) against kernel (kh, kw, ic, oc) -> (b, oh, ow, oc)
    acc = np.einsum("bhwijc,ijco->bhwo", windows, ker, optimize=True).astype(np.int64)
    acc += (bias_q17.astype(np.int64) << frac_bits)[None, None, None, :]

    # Arithmetic right shift (Python >> on np.int64 is arithmetic for signed)
    shifted = acc >> frac_bits
    return np.clip(shifted, -128, 127).astype(np.int8)


def _maxpool2x2(x):
    # x: [b,h,w,c]; out: [b,h/2,w/2,c] with max over 2x2 blocks
    b, h, w, c = x.shape
    x = x.reshape(b, h // 2, 2, w // 2, 2, c)
    return x.max(axis=(2, 4))


def _dense_q17(x_flat_q17, w_q17, b_q17, relu=True, frac_bits=FRAC_BITS, sat_min=None):
    """Matches fc_layer_*.v:
    acc = (bias<<frac_bits) + sum(x*w);  out = saturate(acc >>> frac_bits).
    For FC1/FC2 the RTL clamps negatives to 0 (fused ReLU via clipping
    the scaled result to [0,127]). FC3 uses signed saturate to [-128,127].
    """
    x = x_flat_q17.astype(np.int32)
    w = w_q17.astype(np.int32)
    acc = x @ w  # (N, out)
    acc = acc.astype(np.int64) + (b_q17.astype(np.int64) << frac_bits)[None, :]
    shifted = acc >> frac_bits
    if relu:
        return np.clip(shifted, 0, 127).astype(np.int8)
    lo = sat_min if sat_min is not None else -128
    return np.clip(shifted, lo, 127).astype(np.int8)


def run_quant_inference_batch(images_q17, params):
    """Bit-exact Q1.7 forward pass matching the RTL. Returns argmax digit
    predictions and the final FC3 Q1.7 scores."""
    x = images_q17  # (N,28,28,1) int8
    x = _conv_valid(x, params["c1w"], params["c1b"])  # -> (N,24,24,6)
    x = np.maximum(x, 0)
    x = _maxpool2x2(x)  # -> (N,12,12,6)
    x = _conv_valid(x, params["c2w"], params["c2b"])  # -> (N,8,8,16)
    x = np.maximum(x, 0)
    x = _maxpool2x2(x)  # -> (N,4,4,16)

    # Flatten in channel-minor (matches RTL flatten: addr = pos*16 + channel).
    # Our tensor is (N,4,4,16); flattening row-major gives exactly that.
    n = x.shape[0]
    xf = x.reshape(n, -1)

    x1 = _dense_q17(xf, params["f1w"], params["f1b"], relu=True)
    x2 = _dense_q17(x1, params["f2w"], params["f2b"], relu=True)
    x3 = _dense_q17(x2, params["f3w"], params["f3b"], relu=False)
    preds = np.argmax(x3, axis=1)
    return preds, x3


def summarize(name, preds, labels):
    correct_per = np.zeros(10, dtype=np.int32)
    total_per = np.zeros(10, dtype=np.int32)
    for p, l in zip(preds, labels):
        total_per[l] += 1
        if p == l:
            correct_per[l] += 1
    print(f"\n=== {name} ===")
    for d in range(10):
        print(f"Digit {d}: {correct_per[d]}/{total_per[d]} "
              f"({100.0 * correct_per[d] / max(1, total_per[d]):.1f}%)")
    tot = correct_per.sum()
    ttot = total_per.sum()
    print(f"Total: {tot}/{ttot} ({100.0 * tot / ttot:.2f}%)")
    return correct_per, total_per


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", default="python/lenet5.weights.h5")
    parser.add_argument("--mode", default="all", choices=["all", "fp32", "quant", "quant_no_scale"])
    parser.add_argument("--fc-scale", type=float, default=FC_SCALE_FACTOR)
    args = parser.parse_args()

    print("Loading bulk Q1.7 test images used by tb_cnn_top_bulk...")
    imgs_q17, labels = load_bulk_images()
    print(f"Loaded {imgs_q17.shape[0]} images, shape={imgs_q17.shape}")

    print("Loading trained model...")
    model = create_lenet5_model()
    model.load_weights(args.weights)

    if args.mode in ("all", "fp32"):
        # Convert Q1.7 ints back to floats (divide by 128) so the model sees
        # exactly the same input it would for normal FP32 inference.
        x_fp = imgs_q17.astype(np.float32) / 128.0
        print("\n[FP32] Running Keras predict...")
        t0 = time.time()
        probs = model.predict(x_fp, verbose=0, batch_size=256)
        t1 = time.time()
        preds_fp = np.argmax(probs, axis=1)
        summarize(f"FP32 software accuracy ({t1 - t0:.1f}s)", preds_fp, labels)

    if args.mode in ("all", "quant"):
        params = get_quantized_params(model, use_fc_scale=True,
                                       fc_scale_factor=args.fc_scale)
        print(f"\n[QUANT, FC_SCALE_FACTOR={args.fc_scale}] Running Q1.7 inference...")
        t0 = time.time()
        preds_q, _ = run_quant_inference_batch(imgs_q17, params)
        t1 = time.time()
        summarize(f"Q1.7 quantized accuracy (FC_SCALE={args.fc_scale}, "
                  f"{t1 - t0:.1f}s)", preds_q, labels)

    if args.mode in ("all", "quant_no_scale"):
        params = get_quantized_params(model, use_fc_scale=False)
        print("\n[QUANT, NO FC scaling] Running Q1.7 inference...")
        t0 = time.time()
        preds_q, _ = run_quant_inference_batch(imgs_q17, params)
        t1 = time.time()
        summarize(f"Q1.7 quantized accuracy (no FC scale, {t1 - t0:.1f}s)",
                  preds_q, labels)


if __name__ == "__main__":
    main()
