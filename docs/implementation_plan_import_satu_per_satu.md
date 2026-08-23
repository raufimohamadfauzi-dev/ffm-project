# Rencana Implementasi Redesign Impor Satu per Satu

## 1. `FfmStagingStatus`
Membuat class `FfmStagingStatus` untuk mewakili status file di dalam folder staging (apakah `model.gguf` ada, apakah `projector.gguf` ada). (Sudah dibuat di `lib/features/assistant/data/ffm_staging_status.dart`).

## 2. Modifikasi `FfmLocalModelService`
Menambahkan method baru:
- `_stagingDirectory()`: Folder `staging/{bundleId}` di dalam `_modelsRoot()`.
- `getStagingStatus()`: Mengecek keberadaan file model dan projector di dalam folder staging.
- `importSingleGguf(PlatformFile selected)`:
  1. Menyalin file ke temporary file (menggunakan `readAsByteStream` seperti `_importPickedFile`).
  2. Menghitung `checksum` file tersebut.
  3. Mencocokkan hash dengan `FfmQwen2VlBundle.modelSha256` atau `projectorSha256`.
  4. Jika cocok dengan model, pindahkan (rename) file temporary ke `staging/model.gguf`.
  5. Jika cocok dengan projector, pindahkan ke `staging/projector.gguf`.
  6. Jika tidak cocok keduanya, lempar `FfmLocalModelManifestException`.
- `commitStaging()`:
  1. Mengecek apakah `getStagingStatus().isReadyToCommit` bernilai true.
  2. Jika ya, memvalidasi ukuran, hash, dan header GGUF dari kedua file di staging.
  3. Membuat file `verified_manifest.json` di dalam staging.
  4. Memindahkan folder staging ke `_finalDirectory()`.
  5. Mengembalikan `FfmLocalModelInfo`.
- `clearStaging()`: Menghapus folder staging.

Memodifikasi `exportVerifiedBundle`:
Mengubah agar `exportVerifiedBundle` tidak lagi membuat `.ffmbundle` ZIP, melainkan mengembalikan daftar `File` (model dan projector) untuk dibagikan secara terpisah, atau tetap membagikan ZIP. *Keputusan: Karena fitur impor satu per satu yang diminta, fitur ekspor sebaiknya tetap bisa membagikan ZIP atau dibiarkan seperti sekarang (opsional, tidak wajib diubah jika fokus hanya pada impor).*
*Rekomendasi: Tetap gunakan `.ffmbundle` untuk ekspor agar membagikan lebih mudah (1 file), namun tambahkan kemampuan mengimpor GGUF satu per satu dari UI.*

## 3. Modifikasi `LocalModelPage`
- Menambahkan `FfmStagingStatus? _stagingStatus` pada state.
- Di `_load()`, selain memanggil `getInstalled()`, panggil juga `getStagingStatus()`.
- Ubah UI ketika `_model == null`:
  - Jika `_stagingStatus` kosong:
    - Tampilkan tombol "Unduh dari GitHub".
    - Tampilkan tombol "Impor File GGUF (Satu per Satu)".
  - Jika `_stagingStatus` parsial (salah satu ada):
    - Tampilkan status: "Model GGUF: Tersedia", "Projector GGUF: Belum".
    - Tampilkan tombol "Impor File GGUF yang Kurang".
    - Tampilkan tombol "Batal / Hapus Staging".
  - Jika `_stagingStatus` lengkap:
    - Tampilkan tombol "Rakit dan Pasang SLM".
- Mengubah pemanggilan `FilePicker` pada `_importBundle` (atau fungsi baru `_importGguf`) agar `allowedExtensions: ['gguf', 'ffmbundle', 'zip']`.

## 4. Modifikasi Test
- `ffm_local_model_service_test.dart`: Tambahkan test untuk `importSingleGguf` dan `commitStaging`.
- Pastikan test lama untuk `pickAndInstallBundle` tetap berfungsi atau dihapus jika fiturnya diganti total.

## 5. Keputusan Desain yang Membutuhkan Persetujuan
- Apakah fitur impor `.ffmbundle` (ZIP) akan dihapus sepenuhnya, atau dipertahankan sebagai opsi bersama dengan impor GGUF satu per satu? (Asumsi: dipertahankan agar kompatibel ke belakang, tetapi opsi GGUF satu per satu menjadi jalur utama).
- Jika pengguna mengimpor file yang salah (hash tidak cocok), aplikasi akan langsung menolak dan menghapus file sementara tersebut.

Dokumen ini akan diserahkan untuk persetujuan.
