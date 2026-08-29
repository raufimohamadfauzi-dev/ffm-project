# 1. Greeting Response

## Status: SELESAI ✓

## Deskripsi
Membuat variasi sapaan agar tidak monoton dan kontekstual berdasarkan halaman aktif.

## Yang Dilakukan
- Pool 8 sapaan acak di `_greetingResponses`
- 3 sapaan kontekstual per destination di `_contextualGreeting`
- Metode `_randomGreeting()` untuk pemilihan acak

## Lokasi Kode
- `lib/features/assistant/data/ffm_assistant_interpreter.dart:6903-6920`

## Contoh Output
- "Halo! Ketik saja apa yang perlu."
- "Hai! Ada yang bisa kubantu?"
- Sapaan kontekstual berdasarkan halaman aktif
