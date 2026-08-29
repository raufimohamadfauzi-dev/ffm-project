# 9. Gemini Anti-Hallucination (Master Data)

## Status: SELESAI ✓

## Deskripsi
Mencegah Gemini mengarang nama kategori/rekening yang tidak ada di database.

## Yang Dilakukan
1. **`_tryGeminiResponse`** menerima `accounts` dan `categories` sebagai parameter
2. **`_validateGeminiDraft`** — metode baru yang memvalidasi nama kategori/rekening dari proposal Gemini terhadap data master yang ada
3. **Fetch lebih awal** — `accounts` dan `categories` diambil di awal `interpret()`

## Lokasi Kode
- `lib/features/assistant/data/ffm_assistant_interpreter.dart:274-283` — parameter baru
- `lib/features/assistant/data/ffm_assistant_interpreter.dart:6920-6985` — `_validateGeminiDraft`
- `lib/features/assistant/data/ffm_assistant_interpreter.dart:333-353` — validasi sebelum `_intentForDraft`

## Alur Validasi
```
Gemini proposal → _validateGeminiDraft → Cek nama di database
├── Cocok → Gunakan nama yang benar (case-insensitive fuzzy match)
└── Tidak cocok → Set null → Validator flag sebagai missing → Clarification
```

## Contoh Output Saat Nama Tidak Ada
```
"Kategori 'Makan' belum ada di Data Utama. Mau buat dulu lewat perintah 'buat kategori Makan'?"
```
