# Desain Redesign Instalasi SLM FFM (Impor Satu per Satu)

## Latar Belakang
Saat ini, FFM mewajibkan pengguna untuk mengimpor satu file `.ffmbundle` berukuran ~2.27 GB. Bundle ini adalah ZIP *store-only* yang memuat `model.gguf`, `projector.gguf`, dan `manifest.json`. Karena ukuran file tunggal sangat besar, beberapa perangkat Android kesulitan menyalin file dari `Downloads` ke *private storage* atau membagikannya.
Pengguna meminta agar instalasi dapat dilakukan dengan mengimpor file **satu per satu** (misalnya `model.gguf` dulu, baru `projector.gguf`), yang kemudian diproses, divalidasi, dan digabungkan di dalam aplikasi.

## Analisis Arsitektur Saat Ini
1.  **Validasi Ketat (All-or-Nothing):**
    `FfmLocalModelService.getInstalled()` dan `verifyInstalled()` mensyaratkan kedua file (model dan projector) serta `manifest.json` yang valid (SHA-256 cocok) harus berada di dalam satu folder `_finalDirectory()`. Jika salah satu kurang, model dianggap belum terpasang.
2.  **Struktur Penyimpanan:**
    -   `_downloadDirectory()`: Tempat file `.part` untuk unduhan GitHub dan `picked-...ffmbundle.part` untuk SAF import.
    -   `_finalDirectory()`: Tempat model siap pakai (`models/qwen2-vl/qwen2-vl-2b-instruct-iq4-nl-v1`).
3.  **Keterbatasan UI (`LocalModelPage`):**
    Hanya ada satu state `FfmLocalModelInfo? _model`. Jika `null`, tombol "Unduh" dan "Impor bundle offline" muncul. Tidak ada state *provisional* atau *partial installation* (misal: "Model sudah ada, projector belum").

## Desain Solusi (Impor Satu per Satu)

Untuk mengakomodasi impor satu per satu tanpa merusak keamanan dan stabilitas saat ini, kita harus menambahkan konsep **Staging / Partial Installation**.

### 1. Perubahan pada `FfmLocalModelService`
*   **Folder Staging:**
    Kita buat folder staging tetap: `path.join(_modelsRoot, 'staging', FfmQwen2VlBundle.bundleId)`.
*   **Fungsi `importSingleFile(PlatformFile file)`:**
    1.  Membaca file yang dipilih pengguna via SAF.
    2.  Menghitung SHA-256 secara *streaming* saat menyalin ke folder staging.
    3.  Mencocokkan hash dengan `FfmQwen2VlBundle.modelSha256` atau `projectorSha256`.
    4.  Jika cocok dengan model, simpan sebagai `model.gguf` di staging. Jika cocok dengan projector, simpan sebagai `projector.gguf`. Jika tidak cocok keduanya, tolak dengan *error* "File GGUF tidak dikenali atau rusak".
*   **Fungsi `checkStagingStatus()`:**
    Mengembalikan objek state (misal `FfmStagingStatus`) yang memberi tahu UI file mana saja yang sudah ada di staging.
*   **Fungsi `commitStaging()`:**
    Jika `checkStagingStatus()` menyatakan kedua file sudah lengkap di staging:
    1.  Aplikasi akan membuat `manifest.json` secara otomatis (karena kita sudah memvalidasi hash saat impor).
    2.  Memindahkan (rename atomic) folder staging ke `_finalDirectory()`.
    3.  SLM menjadi *verified* dan siap pakai.

### 2. Perubahan pada UI (`LocalModelPage`)
UI harus berevolusi dari *binary state* (Ada / Tidak Ada) menjadi *multi-state*:
*   **State 1: Kosong (Belum ada apa-apa)**
    -   Tombol: "Unduh Otomatis (GitHub)"
    -   Tombol: "Impor File Model (936 MB)"
    -   Tombol: "Impor File Projector (1.33 GB)"
*   **State 2: Parsial (Salah satu file sudah diimpor)**
    -   Info: "File Model GGUF sudah ada di staging."
    -   Tombol: "Impor File Projector (1.33 GB)" (Untuk melengkapi)
    -   Tombol: "Hapus Staging" (Batal)
*   **State 3: Terverifikasi (Lengkap)**
    -   Info: "Qwen2-VL terverifikasi."
    -   Tombol: "Hapus Model"
    -   Tombol: "Bagikan Bundle"

### 3. Nasib `.ffmbundle`
*   Fitur "Impor bundle offline" (.ffmbundle) dapat dipertahankan sebagai *legacy/fast-path*, ATAU diganti sepenuhnya dengan impor file GGUF satu per satu.
*   Fitur "Bagikan bundle" tetap merakit `.ffmbundle` agar pengguna bisa membagikan 1 file ZIP utuh jika mau, atau kita ubah agar membagikan 2 file GGUF secara terpisah (menggunakan array `XFile` pada `share_plus`). *Rekomendasi: Bagikan 2 file GGUF terpisah agar konsisten dengan cara impor baru.*

## Risiko & Mitigasi
1.  **Ruang Penyimpanan (Storage):**
    Mengimpor satu per satu berarti file disalin dari `Downloads` ke *private storage*. Pengguna tetap harus menghapus file mentah di `Downloads` secara manual setelah instalasi selesai untuk menghindari duplikasi ~2.27 GB.
2.  **Kebingungan Pengguna:**
    Pengguna mungkin salah mengimpor file (memilih file video/PDF alih-alih GGUF). Mitigasi: Ekstensi file picker dibatasi ke `.gguf`, dan validasi SHA-256 ketat menolak file salah.
3.  **Migration:**
    Pengguna yang sudah punya `.ffmbundle` dari versi sebelumnya mungkin bingung. Mitigasi: Kita tetap bisa membiarkan tombol "Impor .ffmbundle utuh" sebagai opsi tambahan di menu *dropdown* atau *advanced*.

## Rencana Implementasi (Next Steps)
1.  **Refactor `FfmLocalModelService`:** Tambahkan manajemen folder `staging`, fungsi validasi hash *on-the-fly* untuk file GGUF mentah, dan fungsi `commit`.
2.  **Refactor `LocalModelPage`:** Ubah UI untuk menampilkan *progress* staging (centang untuk model, centang untuk projector).
3.  **Update Test:** Ubah `ffm_local_model_service_test.dart` untuk menguji alur *staging* parsial.
4.  **Hapus Ketergantungan `.ffmbundle` untuk Impor:** Ubah file picker agar menerima `.gguf`.

---
*Dokumen ini adalah proposal desain. Tidak ada kode aplikasi atau build yang diubah sebelum proposal ini disetujui.*
