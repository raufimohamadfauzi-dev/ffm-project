# Pembelajaran Offline Terkontrol dan Migrasi Lintas Perangkat

## 1. Konsep Pembelajaran Terkontrol

Agent Orchestrator di FFM tidak melatih ulang bobot SLM (Qwen2-VL). Sebagai gantinya, ia menggunakan sistem **Controlled Learning** (Pembelajaran Terkontrol) yang menyimpan pola, preferensi, dan alur kerja ke dalam database lokal.

### A. Siklus Pembelajaran
1. **Observasi:** Agent mengamati pola input pengguna, koreksi yang dilakukan pada draf, dan aksi yang sering diulang.
2. **Kandidasi:** SLM menganalisis log observasi dan mengusulkan "Candidate Skill" atau "Candidate Memory".
3. **Persetujuan (Approval):** Kandidat ditampilkan kepada pengguna. Contoh: *"Saya perhatikan Anda sering mentransfer Rp100.000 ke 'Tabungan Pendidikan' setiap tanggal 1. Apakah Anda ingin saya menyimpan ini sebagai rutinitas?"*
4. **Penyimpanan:** Jika disetujui, kandidat disimpan ke tabel SQLite khusus (`assistant_memories` atau `assistant_learning_examples`).
5. **Penggunaan:** Pada percakapan berikutnya, Orchestrator akan menyertakan memori ini sebagai konteks tambahan saat mengirim prompt ke SLM.

### B. Jenis Data Pembelajaran
- **Alias/Kosakata:** (misal: "Gojek" -> Kategori: Transportasi).
- **Preferensi Default:** (misal: Rekening default untuk pengeluaran adalah "BCA").
- **Workflow/Rutinitas:** Rangkaian langkah yang sering dilakukan bersamaan.

## 2. Agent Knowledge Pack

Semua hasil pembelajaran terkontrol dikemas ke dalam satu entitas logis yang disebut **Agent Knowledge Pack**. Ini memastikan pengetahuan agent terpisah dari data transaksi keuangan.

Struktur konseptual JSON:
```json
{
  "agentKnowledgeVersion": 1,
  "memories": [
    {
      "id": "mem-001",
      "type": "alias",
      "trigger": "beli kopi",
      "resolution": "kategori: Makanan & Minuman",
      "approvedAt": "2026-08-22T10:00:00Z"
    }
  ],
  "workflows": [
    {
      "id": "wf-001",
      "name": "Gaji Bulanan",
      "steps": [...]
    }
  ]
}
```

## 3. Strategi Migrasi Lintas Perangkat

Ketika pengguna berganti perangkat, mereka harus dapat membawa data keuangan dan kecerdasan agent mereka.

### A. Pemisahan Komponen Migrasi
Migrasi penuh terdiri dari tiga bagian terpisah:
1. **Finance Data (JSON):** Data transaksi, rekening, anggaran.
2. **Agent Knowledge Pack (JSON):** Memori dan hasil pembelajaran agent.
3. **SLM Bundle (.ffmbundle):** File bobot model (Qwen2-VL) dan projector.

*Catatan:* File model sangat besar (~2GB) dan tidak boleh dimasukkan ke dalam JSON.

### B. Alur Pemulihan (Restore) di Perangkat Baru
1. Pengguna menginstal FFM di perangkat baru.
2. Pengguna memulihkan file backup gabungan (berisi Finance Data dan Agent Knowledge Pack).
3. Orchestrator membaca Agent Knowledge Pack. Meskipun SLM belum diunduh, Orchestrator sudah mengingat preferensi pengguna (bisa digunakan untuk rule-based fallback).
4. Aplikasi menyarankan pengguna untuk mengunduh ulang SLM dari GitHub atau mengimpor `.ffmbundle` dari perangkat lama.
5. Setelah SLM tersedia dan terverifikasi, agent kembali beroperasi dengan kapasitas penuh (penalaran SLM + pengetahuan lokal yang dipulihkan).
