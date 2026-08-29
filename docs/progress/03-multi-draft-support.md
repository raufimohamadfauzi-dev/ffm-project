# 3. Multi-Draft Support

## Status: SELESAI ✓

## Deskripsi
Mendukung beberapa draft sekaligus dari satu pesan Gemini.

## Yang Dilakukan
- `parseMultiple()` di proposal service untuk parse array JSON
- Class `_InterpretResult` untuk menampung multiple intents
- `_pendingGeminiExtraIntents` di interpreter untuk draft tambahan

## Lokasi Kode
- `lib/features/assistant/data/ffm_assistant_proposal_json_service.dart:182`
- `lib/features/assistant/data/ffm_assistant_interpreter.dart:6925`
- `lib/features/assistant/data/ffm_assistant_interpreter.dart:1023`

## Contoh Input
```
User: "Catat beli kopi 25rb dan beli roti 15rb"
```

## Contoh Output
- 2 draft expense dikembalikan sekaligus
- User bisa review dan konfirmasi satu per satu atau bersamaan
