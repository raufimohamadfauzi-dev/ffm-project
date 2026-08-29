# 10. Conversation Memory

## Status: SELESAI ✓

## Deskripsi
Memastikan ingatan percakapan bekerja untuk follow-up dan konteks.

## Yang Dilakukan
1. **Conversation history ditingkatkan** — dari 5 menjadi 8 pesan terakhir
2. **Snippet lebih panjang** — dari 100 karakter menjadi 3 baris atau 200 karakter
3. **Draft info ditambahkan** — menampilkan jenis dan nominal draft di history
4. **Orchestrator instruction diperbarui** — menambahkan aturan follow-up

## Lokasi Kode
- `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart:2301-2328` — `_buildRecentConversationHistory()`
- `lib/features/assistant/data/ffm_gemini_cloud_orchestrator.dart:216-260` — `_instruction()`

## Aturan Follow-up yang Ditambahkan
```
ATURAN FOLLOW-UP:
- Jika user bertanya tentang sesuatu yang sudah dibahas sebelumnya, gunakan riwayat percakapan.
- Jika user bertanya "tentang apa?" atau "maksudnya?", lihat pesan asisten sebelumnya.
- Jika user merujuk ke transaksi/data yang sudah disebut, gunakan konteks dari riwayat.
- Jangan minta user mengulang pertanyaan jika konteks sudah ada di riwayat.
```

## Contoh Follow-up yang Berhasil
```
User: "Berapa total pengeluaran bulan ini?"
Asisten: "Total pengeluaran bulan ini Rp 2.500.000"
User: "Terdiri dari apa saja?"
Asisten: "Dari data yang saya lihat, terdiri dari kategori Makan, Transportasi, dan Belanja."
```
