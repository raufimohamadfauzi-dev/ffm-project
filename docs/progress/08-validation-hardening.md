# 8. Validation Hardening

## Status: SELESAI ✓

## Deskripsi
Memastikan draft transaksi memiliki data lengkap sebelum disimpan.

## Yang Dilakukan
- Category wajib (severity `required`) untuk expense/income
- Account wajib (severity `required`) untuk expense/income
- `_intentForDraft` mengecek `categoryName` dan `fromAccountName`/`toAccountName`
- Proactive clarification saat data kurang: "buat kategori [nama]" atau "tambah rekening [nama]"

## Lokasi Kode
- `lib/features/assistant/domain/ffm_assistant_draft_validator.dart`
- `lib/features/assistant/data/ffm_assistant_interpreter.dart:1795-1818`

## Contoh Output Saat Data Kurang
```
"Kategori belum ada. Mau buat dulu? Ketik 'buat kategori [nama]'"
"Rekening sumber belum ada. Mau tambah dulu? Ketik 'tambah rekening [nama]'"
```
