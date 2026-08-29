# 5. Master Data CRUD via Gemini

## Status: SELESAI ✓

## Deskripsi
Gemini bisa membuat/mengubah data utama (kategori, rekening, tag, toko, sumber pemasukan).

## Yang Dilakukan
- Pattern matching untuk: kategori, rekening, tag, toko, sumber pemasukan
- Draft creation untuk setiap jenis data
- Verify handlers untuk semua jenis data

## Lokasi Kode
- `lib/features/assistant/data/ffm_assistant_interpreter.dart`
  - `_parseCategoryMutation()` — buat/ubah/hapus kategori
  - `_parseAccountMutation()` — buat/ubah/hapus rekening
  - `_parseTagMutation()` — buat/ubah/hapus tag
  - `_parseMerchantMutation()` — buat/ubah/hapus toko
  - `_parseIncomeSourceMutation()` — buat/ubah/hapus sumber pemasukan

## Contoh Perintah
```
"Buat kategori Transportasi"
"Tambah rekening BCA"
"Buat tag investasi"
"Tambah toko Alfamart"
"Buat sumber pemasukan Gaji"
```
