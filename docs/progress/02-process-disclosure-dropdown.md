# 2. Process Disclosure Dropdown

## Status: SELESAI ✓

## Deskripsi
Menampilkan detail proses di dropdown collapsible di atas chat, bukan di body utama.

## Yang Dilakukan
- Menghapus `_OriginBadge` duplikat dari message card
- Menggabungkan ke `FfmAssistantProcessDisclosure`
- Dropdown menampilkan: asal jawaban, waktu, langkah action plan, event proses

## Lokasi Kode
- `lib/features/assistant/presentation/widgets/chat/ffm_assistant_process_disclosure.dart`
- `lib/features/assistant/presentation/widgets/chat/ffm_assistant_message_card.dart:82-88`

## Struktur Dropdown
```
[Gemini Cloud · 1.25 dtk] ▼
├── T+0 ms: Permintaan diterima
├── T+0.5 dtk: Membaca ringkasan transaksi
├── T+1.0 dtk: Gemini Cloud mengembalikan jawaban
└── Langkah Action Plan (jika ada)
```
