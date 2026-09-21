#!/usr/bin/env python3
"""Train the production BNN: 2-bit input, 32x6x6 conv1, 48x4x4 conv2, 128-bit hidden layer.

python train_mnist64_bnn.py

"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.keras.layers import (
    BatchNormalization, Conv2D, Dense, Flatten, Layer, RandomTranslation)


BATCH_SIZE = 128
MNIST_REPEAT = 4
LEARNING_RATE = 1e-3


def prepare_images(images: np.ndarray) -> np.ndarray:
    """Center-crop to 24x24 and quantize to four levels in [-1, 1]."""
    images = images[:, 2:26, 2:26]
    levels = np.rint(images.astype(np.float32) * 3.0 / 255.0)
    return ((2.0 * levels - 3.0) / 3.0)[..., None]


def load_data(seed: int):
    """MNIST + EMNIST Digits pool with a 1/6 validation split.

    Returns (train, validation, MNIST test, EMNIST test). 
    """
    import tensorflow_datasets as tfds

    def load_emnist(split):
        images, labels = tfds.as_numpy(tfds.load(
            "emnist/digits", split=split, as_supervised=True, batch_size=-1,
            builder_kwargs={"file_format": "tfrecord"},
        ))
        # EMNIST is stored transposed relative to MNIST.
        return images.squeeze(-1).transpose(0, 2, 1).astype(np.uint8), labels.astype(np.int64)

    (mnist_x, mnist_y), (mnist_test_x, mnist_test_y) = tf.keras.datasets.mnist.load_data()
    emnist_x, emnist_y = load_emnist("train")
    emnist_test_x, emnist_test_y = load_emnist("test")

    images = np.concatenate([mnist_x, emnist_x])
    labels = np.concatenate([mnist_y, emnist_y])
    order = np.random.default_rng(seed).permutation(len(labels))
    n_val = len(labels) // 6
    val_idx, train_idx = order[:n_val], order[n_val:]

    train_mnist = train_idx[train_idx < len(mnist_y)]
    train_emnist = train_idx[train_idx >= len(mnist_y)]
    train_idx = np.concatenate([train_mnist] * MNIST_REPEAT + [train_emnist])
    return (
        (prepare_images(images[train_idx]), labels[train_idx]),
        (prepare_images(images[val_idx]), labels[val_idx]),
        (prepare_images(mnist_test_x), mnist_test_y),
        (prepare_images(emnist_test_x), emnist_test_y),
    )


@tf.custom_gradient
def sign_mad(x):
    """Binarize to +-1; MAD gradient, max(0, 1 - |x|)."""
    y = tf.where(x >= 0.0, tf.ones_like(x), -tf.ones_like(x))
    def grad(dy):
        return dy * tf.maximum(tf.zeros_like(x), 1.0 - tf.abs(x))
    return y, grad


def clip_weights(weights):
    return tf.clip_by_value(weights, -1.0, 1.0)


class BinaryConv2D(Conv2D):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, kernel_constraint=clip_weights, **kwargs)

    def convolution_op(self, inputs, kernel):
        return super().convolution_op(inputs, sign_mad(kernel))

class BinaryDense(Dense):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, kernel_constraint=clip_weights, **kwargs)

    def call(self, inputs):
        return tf.linalg.matmul(inputs, sign_mad(self.kernel))


class Sign(Layer):
    def call(self, inputs):
        return sign_mad(inputs)


class RandomGamma(Layer):
    """Per-image gamma with black and white held fixed."""
    def call(self, inputs, training=None):
        if not training:
            return inputs
        gamma = tf.random.uniform([tf.shape(inputs)[0], 1, 1, 1], 0.7, 1.3, dtype=inputs.dtype)
        return tf.pow((inputs + 1.0) * 0.5, gamma) * 2.0 - 1.0


def build_model():
    inp = tf.keras.Input((24, 24, 1), name="binary_pixels")
    x = BinaryConv2D(32, 6, strides=2, padding="valid", use_bias=False, name="conv1")(inp)
    x = BatchNormalization(momentum=0.9, name="conv1_bn")(x)
    x = Sign(name="conv1_sign")(x)
    x = BinaryConv2D(48, 4, strides=2, padding="valid", use_bias=False, name="conv2")(x)
    x = BatchNormalization(momentum=0.9, name="conv2_bn")(x)
    x = Sign(name="conv2_sign")(x)
    x = Flatten()(x)
    x = BinaryDense(128, use_bias=False, name="hidden")(x)
    x = BatchNormalization(momentum=0.9, name="hidden_bn")(x)
    x = Sign(name="hidden_sign")(x)
    logits = Dense(10, name="output")(x)
    return tf.keras.Model(inp, logits, name="mnist64_bnn")


def quantize_output_in_place(model) -> None:
    """Round the output layer to int8 weights / integer bias, as deployed."""
    layer = model.get_layer("output")
    weights, bias = (np.asarray(v) for v in layer.get_weights())
    scale = max(float(np.max(np.abs(weights))) / 127.0, 1e-12)
    layer.set_weights([
        np.rint(weights / scale).clip(-127, 127) * scale,
        np.rint(bias / scale) * scale,
    ])


def pack_sign_weights(weights: np.ndarray) -> np.ndarray:
    return np.packbits((weights.reshape(-1) >= 0).astype(np.uint8), bitorder="little")


def bn_threshold(bn, dot_scale: int = 1) -> tuple[np.ndarray, np.ndarray]:
    """Fold BatchNorm + sign into an integer threshold and a polarity bit."""
    gamma, beta, mean, variance = (np.asarray(v) for v in bn.get_weights())
    boundary = mean - beta * np.sqrt(variance + bn.epsilon) / gamma
    threshold = np.ceil(boundary * dot_scale).clip(-32768, 32767).astype("<i2")
    return threshold, (gamma >= 0).astype(np.uint8)


def export(model, output: Path, accuracy: float, epochs: int) -> None:
    arrays = {}
    for name in ("conv1", "conv2", "hidden"):
        arrays[f"{name}_weights"] = pack_sign_weights(model.get_layer(name).kernel.numpy())
        # conv1 sees 2-bit pixels in {-3,-1,1,3}/3, so its dot product is scaled by 3.
        threshold, polarity = bn_threshold(model.get_layer(f"{name}_bn"),
                                           3 if name == "conv1" else 1)
        arrays[f"{name}_thresholds"] = threshold
        arrays[f"{name}_polarity"] = np.packbits(polarity, bitorder="little")

    weights, bias = (np.asarray(v) for v in model.get_layer("output").get_weights())
    scale = max(float(np.max(np.abs(weights))) / 127.0, 1e-12)
    arrays["output_weights_int8"] = np.rint(weights / scale).clip(-127, 127).astype(np.int8)
    arrays["output_bias_int32"] = np.rint(bias / scale).astype("<i4")
    arrays["output_scale"] = np.asarray(scale, np.float32)

    arrays["metadata_json"] = np.asarray(json.dumps({
        "format": "mnist64-bnn-v1", "test_accuracy": accuracy,
        "dataset": "eemnist", "mnist_repeat": MNIST_REPEAT, "emnist_repeat": 1,
        "epochs": epochs, "translate": 1.5,
        "augmentation": {
            "translation": {"pixels": 1.5, "interpolation": "bilinear"},
            "gamma": {"minimum": 0.7, "maximum": 1.3},
        },
    }))
    output.parent.mkdir(parents=True, exist_ok=True)
    np.savez(output, **arrays)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--output", type=Path, default=Path("model.npz"))
    ap.add_argument("--epochs", type=int, default=400)
    ap.add_argument("--seed", type=int, default=6502)
    args = ap.parse_args()

    tf.keras.utils.set_random_seed(args.seed)

    (x_train, y_train), validation, (x_mnist, y_mnist), (x_emnist, y_emnist) = load_data(args.seed)
    model = build_model()
    trainer = tf.keras.Sequential([
        tf.keras.Input((24, 24, 1)),
        RandomTranslation(1.5 / 24, 1.5 / 24, fill_mode="constant", fill_value=-1.0,
                          interpolation="bilinear"),
        RandomGamma(name="gamma_augmentation"),
        model,
    ])

    steps_per_epoch = math.ceil(len(x_train) / BATCH_SIZE)
    learning_rate = tf.keras.optimizers.schedules.CosineDecay(
        LEARNING_RATE, steps_per_epoch * args.epochs, alpha=1e-6 / LEARNING_RATE)
    trainer.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate),
        loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
        metrics=["accuracy"],
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    history = trainer.fit(
        x_train, y_train, validation_data=validation,
        epochs=args.epochs, batch_size=BATCH_SIZE, shuffle=True, verbose=2,
        callbacks=[
            tf.keras.callbacks.EarlyStopping(monitor="val_accuracy", mode="max",
                                             patience=12,
                                             restore_best_weights=True),
            tf.keras.callbacks.CSVLogger(str(args.output.with_suffix(".history.csv"))),
        ],
    )

    quantize_output_in_place(model)
    _, mnist_accuracy = trainer.evaluate(x_mnist, y_mnist, batch_size=512, verbose=2)
    _, emnist_accuracy = trainer.evaluate(x_emnist, y_emnist, batch_size=512, verbose=2)
    combined = ((mnist_accuracy * len(y_mnist) + emnist_accuracy * len(y_emnist))
                / (len(y_mnist) + len(y_emnist)))
    export(model, args.output, float(mnist_accuracy), len(history.epoch))
    print(f"MNIST test accuracy: {mnist_accuracy:.4%}")
    print(f"EMNIST Digits test accuracy: {emnist_accuracy:.4%}")
    print(f"MNIST+EMNIST test accuracy: {combined:.4%}")
    print(f"exported {args.output}")


if __name__ == "__main__":
    main()
