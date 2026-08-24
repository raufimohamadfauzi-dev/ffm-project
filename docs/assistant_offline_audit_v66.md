# Audit Dokumen Analisis Asisten Offline — v66

Dokumen ini mencatat keputusan implementasi atas `Analisis_Asisten_Offline_MANUS.md`. Audit dilakukan dengan prinsip bahwa FFM tetap **offline-first**, tidak menggunakan API/cloud/LLM/SLM aktif, tidak melatih diri dari transaksi secara otomatis, dan tidak boleh menyimpan perubahan data tanpa alur **draf → review/form → Simpan** yang eksplisit.

| Rekomendasi | Keputusan | Alasan dan status |
|---|---|---|
| Fuzzy matching untuk typo | **Diterapkan** | Matcher lokal Dart murni kini memakai optimal-string-alignment Damerau–Levenshtein. Transposisi huruf bersebelahan, misalnya `pni` untuk `pin`, dihitung sebagai satu kesalahan ketik. Ambang konservatif `bestUnique` tetap dipertahankan agar hasil ambigu tidak dipilih otomatis. |
| Stemming dan stopword penuh | Ditunda | Penghilangan kata secara luas dapat merusak nama rekening, aset, kategori, atau entitas lokal. Tidak diperlukan untuk perbaikan typo yang aman ini. |
| Naive Bayes atau classifier lokal aktif | Ditunda | Contract classifier dan gateway model memang disiapkan sebagai guardrail masa depan, tetapi sengaja tidak aktif. Mengaktifkannya membutuhkan desain persetujuan, siklus model, evaluasi kesalahan, dan perlindungan agar tidak belajar otomatis dari transaksi pengguna. |
| Vosk STT offline | Ditunda | Integrasi akan menambah model suara berukuran puluhan MB, jalur native, izin, serta pengujian perangkat. Parser teks setelah transkripsi dan TTS lokal yang ada tetap dipakai. |
| Rule engine JSON anggaran | Ditunda | `BudgetGuardService` saat ini deterministik, read-only, memakai data anggaran dan threshold yang nyata, serta telah diuji. Memindahkan formula ke JSON tanpa kontrak bisnis akan meningkatkan risiko perubahan perhitungan finansial. |
| Retensi/cleanup memori | Tidak diterapkan otomatis | Riwayat pertanyaan terbuka dan selesai dipakai untuk koreksi serta pembaruan APK. Tidak ada penghapusan senyap. Pilihan aman di masa depan adalah arsip eksplisit atau batas tampilan/ekspor tanpa menghapus histori. |

## Batas yang Diverifikasi

`OfflineAiEngineService` tetap merupakan stub lokal dan tidak memanggil layanan eksternal. Gateway model lokal tetap dinonaktifkan. Alur query Asisten tetap read-only, sedangkan tindakan perubahan data tetap memerlukan draf yang dapat diperiksa pengguna sebelum membuka formulir dan disimpan secara eksplisit.

## Validasi v66

| Pemeriksaan | Hasil |
|---|---|
| `dart format .` | 149 berkas diperiksa, tidak ada perubahan tambahan |
| `flutter analyze` | Bersih, tanpa isu |
| `flutter test` | 154 tes lulus |
| `flutter build apk --release` | Berhasil; hanya ada peringatan kompatibilitas masa depan dari plugin `speech_to_text` terkait Kotlin Gradle Plugin |
| Tanda tangan APK | Diverifikasi dengan sertifikat lama FFM SHA-256 `35dbb5702258f0199ce20ab5e045ac8f3c91823c00fcc73619b0d1cb4503e629` |

> Tidak ada migrasi basis data, tidak ada perubahan format ekspor, dan tidak ada data keuangan contoh yang ditambahkan oleh audit ini.

