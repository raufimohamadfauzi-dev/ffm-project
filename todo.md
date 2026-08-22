# Perbaikan Ringkasan FFM

- [x] Telusuri sumber nominal Rp1.000.000 dan prediksi Rp600.000 pada Ringkasan.
- [x] Hapus seluruh fallback, contoh, dan prediksi yang tidak bersumber dari transaksi nyata.
- [x] Tampilkan keadaan kosong yang jujur saat belum ada transaksi.
- [x] Tambahkan skala, nilai nominal, dan sumber data pada grafik tren pengeluaran.
- [x] Tambahkan regression test untuk data kosong, data nyata, dan grafik.
- [x] Jalankan formatter, analyzer, seluruh test, commit, packaging, dan build APK release.

# Asisten FFM Lokal

- [x] Audit modul, navigasi, voice, dan kontrak keuangan yang akan dilayani asisten.
- [x] Buat katalog halaman lokal serta model intent dan draft aman.
- [x] Buat interpreter teks/voice, query data lokal, dan draft transaksi lintas modul.
- [x] Tambahkan chatbot mengambang dengan konteks lintas halaman dan navigasi aman.
- [x] Tambahkan memori lokal, saran terjelaskan, JSON, dan laporan.
- [x] Tambahkan regression test dan validasi perilaku offline.
- [x] Commit, packaging source, dan APK release Asisten FFM.

# Rancangan Model Bahasa Lokal

- [x] Evaluasi runtime LLM lokal Android yang cocok untuk Flutter dan perangkat target.
- [x] Tetapkan batas tegas antara keluaran model, validasi aturan keuangan, draft, dan penyimpanan.
- [x] Tentukan strategi ukuran model, instalasi, performa, serta fallback tanpa model.
- [ ] Susun tahapan implementasi dan keputusan yang perlu disetujui sebelum kode diubah.

# Perbaikan Voice Update Aktivitas

- [x] Audit jalur STT, parser, state sesi aktif, dan lifecycle listener setelah aktivitas dimulai.
- [x] Perbaiki update, checkpoint, dan selesai agar selalu menerima konteks sesi aktif yang terbaru.
- [x] Perjelas preview, koreksi, status mikrofon, dan penanganan aktivitas ambigu/paralel.
- [x] Tambahkan regression test lalu jalankan formatter, analyzer, dan seluruh test.
- [x] Commit, kemas source, dan build APK release dengan keystore lama.

# Kolom Perintah FFM Lintas Halaman

- [x] Audit kontrak draft, navigasi, dan prefill formulir pada modul target.
- [x] Buat antrean CommandDraft lintas halaman dengan validasi deterministik.
- [x] Hubungkan perintah banyak tindakan ke navigasi dan formulir tujuan yang aman.
- [x] Tambahkan status/fallback model lokal opsional tanpa mengubah keamanan draft.
- [x] Tambahkan regression test lalu jalankan formatter, analyzer, dan seluruh test.
- [x] Commit, kemas source, dan build APK release dengan keystore lama.

# Penjaga Anggaran dan Arus Kas

- [x] Audit sumber data transaksi, pos anggaran, pengingat, dan Ringkasan untuk saran offline.
- [x] Bangun aturan saran berbasis transaksi nyata tanpa nominal atau asumsi contoh.
- [x] Tampilkan saran yang menjelaskan alasan dan membuka tindakan yang relevan.
- [x] Tambahkan regression test lalu jalankan formatter, analyzer, dan seluruh test.
- [x] Commit, kemas source, dan build APK release dengan keystore lama.

# Akses Asisten dan Respons Gagal-Paham

- [x] Audit FAB halaman dan contoh pertanyaan yang belum dipahami Asisten.
- [x] Pindahkan akses Asisten ke AppBar pada halaman yang sudah memiliki FAB utama.
- [x] Perjelas status “Yang Aku Pahami” serta bantuan untuk pertanyaan di luar kemampuan aplikasi.
- [x] Tambahkan regresi, jalankan formatter, analyzer, dan seluruh test.
- [x] Commit, kemas source, dan build APK release dengan keystore lama.

# Pintasan Koreksi dan Pembelajaran Asisten

- [x] Audit kartu respons tidak dipahami, preview draft, dan alur ajaran saat ini.
- [x] Tambahkan konteks koreksi yang aman untuk disalin tanpa data finansial otomatis.
- [x] Tambahkan tombol salin konteks dan Ajarkan Asisten pada jawaban chat yang tidak sesuai.
- [x] Tambahkan pintasan koreksi nominal/draft yang selalu menjalankan review ulang.
- [x] Tambahkan regression test untuk konteks salin, ajaran, dan revisi draft.
- [x] Jalankan formatter, analyzer, dan seluruh test.
- [x] Commit, ZIP source, dan build APK release.
