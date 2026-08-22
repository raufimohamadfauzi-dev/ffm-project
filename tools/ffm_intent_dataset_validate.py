#!/usr/bin/env python3
"""Validasi dataset intent FFM yang sudah disanitasi.

Jalankan lokal: python3 tools/ffm_intent_dataset_validate.py dataset.json
Alat ini tidak memakai jaringan dan tidak menulis ulang dataset sumber.
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

EXPECTED_FORMAT = "ffm-assistant-intent-dataset-v1"
ALLOWED_INTENTS = {
    "openPage",
    "listPages",
    "setupGuide",
    "featureHelp",
    "assistantIdentity",
    "calendarQuery",
    "transactionStats",
    "weeklyAnalysis",
    "financialWarnings",
    "createIncome",
    "createExpense",
    "createTransfer",
    "createGoalDeposit",
    "createGoalUsage",
    "createGoal",
    "createLiability",
    "createReceivable",
    "createAsset",
    "createBudget",
    "createMasterData",
    "createReminder",
    "createActivity",
    "explainJson",
    "createJsonTemplate",
    "exportReport",
    "replaceDraftText",
    "removeDraftItem",
    "teachMemory",
    "readLastResponse",
    "confirm",
    "cancel",
    "help",
    "unknown",
}
SENSITIVE_PATTERNS = {
    "telepon": re.compile(r"\b(?:\+?62|0)8\d{7,12}\b"),
    "email": re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.-]+\b"),
    "nomor_panjang": re.compile(r"\b\d{10,18}\b"),
}


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] in {"-h", "--help"}:
        print("Pakai: python3 tools/ffm_intent_dataset_validate.py <dataset.json>")
        return 0
    if len(sys.argv) != 2:
        print("Pakai: python3 tools/ffm_intent_dataset_validate.py <dataset.json>")
        return 2
    dataset_path = Path(sys.argv[1])
    try:
        payload = json.loads(dataset_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"Dataset tidak bisa dibaca: {error}")
        return 2
    if payload.get("formatVersion") != EXPECTED_FORMAT:
        print("Format dataset tidak cocok dengan kontrak FFM.")
        return 2
    examples = payload.get("examples")
    if not isinstance(examples, list) or not examples:
        print("Dataset belum mempunyai contoh aktif.")
        return 2

    errors: list[str] = []
    counts: Counter[str] = Counter()
    for index, example in enumerate(examples, start=1):
        if not isinstance(example, dict):
            errors.append(f"Baris {index}: contoh harus objek JSON.")
            continue
        text = str(example.get("input", "")).strip()
        intent = str(example.get("intent", "")).strip()
        if not (3 <= len(text) <= 500):
            errors.append(f"Baris {index}: panjang input harus 3–500 karakter.")
        if intent not in ALLOWED_INTENTS:
            errors.append(f"Baris {index}: intent '{intent}' tidak dikenal.")
        for label, pattern in SENSITIVE_PATTERNS.items():
            if pattern.search(text):
                errors.append(f"Baris {index}: kemungkinan {label} belum disamarkan.")
        counts[intent] += 1

    print(f"Contoh aktif: {len(examples)}")
    print("Distribusi intent:")
    for intent, count in sorted(counts.items()):
        print(f"  - {intent}: {count}")
    if errors:
        print("\nDataset belum layak dilatih:")
        for error in errors:
            print(f"  - {error}")
        return 1
    weak_labels = [intent for intent, count in counts.items() if count < 12]
    if weak_labels:
        print(
            "\nCatatan: intent berikut masih kurang dari 12 contoh dan sebaiknya "
            f"ditambah sebelum evaluasi: {', '.join(sorted(weak_labels))}."
        )
    print("\nDataset valid untuk evaluasi atau pelatihan offline.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
