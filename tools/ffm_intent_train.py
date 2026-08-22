#!/usr/bin/env python3
"""Latih classifier intent FFM dari dataset teranonimkan secara lokal.

Contoh:
  python3 tools/ffm_intent_train.py dataset.json --output-dir ./artifacts

Butuh Python 3.10+ dan TensorFlow 2.x yang dipasang di komputer pengembang.
Tidak ada panggilan jaringan di skrip ini; TensorFlow harus sudah tersedia lokal.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import sys
from collections import Counter
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path, help="Dataset JSON dari FFM")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("ffm-intent-artifacts"),
        help="Folder artefak model dan manifest",
    )
    parser.add_argument("--epochs", type=int, default=24)
    parser.add_argument("--seed", type=int, default=54)
    parser.add_argument("--minimum-confidence", type=float, default=0.85)
    return parser.parse_args()


def load_examples(dataset_path: Path) -> tuple[list[str], list[str]]:
    payload = json.loads(dataset_path.read_text(encoding="utf-8"))
    if payload.get("formatVersion") != "ffm-assistant-intent-dataset-v1":
        raise ValueError("Format dataset FFM tidak cocok.")
    examples = payload.get("examples")
    if not isinstance(examples, list):
        raise ValueError("Dataset tidak memiliki daftar examples.")
    texts = [str(item["input"]).strip() for item in examples]
    labels = [str(item["intent"]).strip() for item in examples]
    if not texts or any(not text for text in texts) or any(not label for label in labels):
        raise ValueError("Dataset memuat input atau label kosong.")
    counts = Counter(labels)
    thin = [label for label, count in counts.items() if count < 12]
    if thin:
        raise ValueError(
            "Setiap intent yang dilatih minimal butuh 12 contoh. Kurang: "
            + ", ".join(sorted(thin))
        )
    if len(counts) < 2:
        raise ValueError("Classifier butuh setidaknya dua intent berbeda.")
    return texts, labels


def main() -> int:
    args = parse_args()
    if not 0.85 <= args.minimum_confidence <= 1:
        print("--minimum-confidence harus antara 0.85 dan 1.")
        return 2
    try:
        import tensorflow as tf
    except ModuleNotFoundError:
        print(
            "TensorFlow belum tersedia. Pasang di komputer pengembang, lalu jalankan ulang. "
            "Contoh: python3 -m pip install tensorflow"
        )
        return 2
    try:
        texts, label_texts = load_examples(args.dataset)
    except (OSError, KeyError, ValueError, json.JSONDecodeError) as error:
        print(f"Dataset tidak siap dilatih: {error}")
        return 2

    random.seed(args.seed)
    tf.keras.utils.set_random_seed(args.seed)
    labels = sorted(set(label_texts))
    label_to_index = {label: index for index, label in enumerate(labels)}
    pairs = list(zip(texts, (label_to_index[label] for label in label_texts)))
    random.shuffle(pairs)
    validation_size = max(len(labels), round(len(pairs) * 0.2))
    validation_size = min(validation_size, len(pairs) - len(labels))
    if validation_size <= 0:
        print("Dataset terlalu kecil untuk memisahkan evaluasi.")
        return 2
    validation_pairs = pairs[:validation_size]
    train_pairs = pairs[validation_size:]
    train_texts, train_labels = zip(*train_pairs)
    validation_texts, validation_labels = zip(*validation_pairs)

    vectorize = tf.keras.layers.TextVectorization(
        max_tokens=4000,
        output_mode="int",
        output_sequence_length=28,
        standardize="lower_and_strip_punctuation",
    )
    vectorize.adapt(tf.data.Dataset.from_tensor_slices(list(train_texts)).batch(32))
    model = tf.keras.Sequential(
        [
            tf.keras.Input(shape=(1,), dtype=tf.string),
            vectorize,
            tf.keras.layers.Embedding(4000, 32, mask_zero=True),
            tf.keras.layers.GlobalAveragePooling1D(),
            tf.keras.layers.Dense(32, activation="relu"),
            tf.keras.layers.Dropout(0.15),
            tf.keras.layers.Dense(len(labels), activation="softmax"),
        ]
    )
    model.compile(
        optimizer="adam",
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.fit(
        tf.constant([[text] for text in train_texts]),
        tf.constant(train_labels),
        validation_data=(
            tf.constant([[text] for text in validation_texts]),
            tf.constant(validation_labels),
        ),
        epochs=args.epochs,
        verbose=2,
        callbacks=[tf.keras.callbacks.EarlyStopping(patience=4, restore_best_weights=True)],
    )
    _, accuracy = model.evaluate(
        tf.constant([[text] for text in validation_texts]),
        tf.constant(validation_labels),
        verbose=0,
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    model_path = args.output_dir / "ffm_intent_classifier.tflite"
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS,
    ]
    model_path.write_bytes(converter.convert())
    sha256 = hashlib.sha256(model_path.read_bytes()).hexdigest()
    manifest = {
        "formatVersion": "ffm-assistant-intent-classifier-v1",
        "modelFile": model_path.name,
        "sha256": sha256,
        "labels": labels,
        "minimumConfidence": args.minimum_confidence,
        "evaluation": {
            "validationExamples": len(validation_pairs),
            "validationAccuracy": round(float(accuracy), 4),
        },
    }
    manifest_path = args.output_dir / "ffm_intent_classifier.manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Model: {model_path}")
    print(f"Manifest: {manifest_path}")
    print(f"Akurasi validasi: {accuracy:.2%}")
    print("Model hanya boleh diaktifkan setelah evaluasi skenario FFM dan rilis runtime terpisah.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
