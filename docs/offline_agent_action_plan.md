# Rancangan Alur SLM, Rencana Aksi, dan Konfirmasi Akhir

## 1. Peran SLM (Qwen2-VL)

SLM bertindak murni sebagai **Reasoning Engine** (Mesin Penalaran). Tugas utamanya adalah:
- Memahami input bahasa alami pengguna.
- Mengekstrak informasi relevan (entitas) seperti nominal, tanggal, kategori, dan deskripsi.
- Membaca teks dari gambar (struk belanja) jika dilampirkan.
- Memetakan niat pengguna ke salah satu dari *Capability* yang tersedia di Orchestrator.
- **Batasan:** SLM tidak pernah memanggil fungsi database secara langsung. Output SLM selalu berupa struktur data (JSON/Intent Object) yang diserahkan kembali ke Orchestrator.

## 2. Struktur Rencana Aksi (Action Plan)

Ketika Orchestrator menerima output dari SLM, ia akan membuat sebuah `Action Plan`. Rencana ini bisa terdiri dari satu atau beberapa langkah.

Contoh Struktur `Action Plan`:
```json
{
  "plan_id": "req-12345",
  "intent": "create_expense",
  "steps": [
    {
      "step_id": 1,
      "capability": "navigate_to",
      "params": { "destination": "transactions" },
      "status": "pending"
    },
    {
      "step_id": 2,
      "capability": "draft_transaction",
      "params": {
        "type": "expense",
        "amount": 50000,
        "category": "Makanan",
        "account": "Tunai"
      },
      "status": "pending"
    }
  ],
  "requires_confirmation": true
}
```

## 3. Alur Eksekusi dan Preview

1. **Evaluasi Langkah:** Orchestrator mengevaluasi setiap langkah dalam `Action Plan`.
2. **Eksekusi Aman:** Langkah-langkah berisiko rendah (seperti navigasi) langsung dieksekusi.
3. **Penyusunan Draft:** Langkah berisiko menengah (pembuatan data) menghasilkan objek `Draft` di memori.
4. **Preview:** Orchestrator menghentikan eksekusi otomatis dan menampilkan `Draft` tersebut di UI Chat dalam bentuk kartu ringkasan (Preview Card).

## 4. Konfirmasi Akhir (Final Confirmation)

Ini adalah gerbang keamanan utama aplikasi.
- Preview Card akan memiliki tombol aksi yang jelas: **[Konfirmasi & Simpan]**, **[Edit Draft]**, dan **[Batal]**.
- Jika pengguna menekan **[Konfirmasi & Simpan]**, Orchestrator akan mengambil data dari `Draft` dan mengeksekusi *Capability Risiko Tinggi* (menyimpan ke database).
- Jika pengguna memilih **[Edit Draft]**, form manual akan terbuka dengan data yang sudah diisi sebagian.
- Setelah penyimpanan berhasil, Orchestrator akan menambahkan entri chat baru: *"Berhasil disimpan: Pengeluaran Rp50.000 untuk Makanan."*

## 5. Penanganan Input Ganda (Deduplikasi)

Seperti yang telah diimplementasikan pada input suara (Voice), setiap `Action Plan` akan memiliki ID unik (atau hash dari input). Jika pengguna menekan tombol konfirmasi dua kali secara cepat, Orchestrator akan menolak eksekusi kedua karena `plan_id` tersebut sudah ditandai sebagai "completed".
