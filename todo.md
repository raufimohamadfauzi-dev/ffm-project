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

# Perbaikan Pemahaman & Pelatihan Asisten v60

- [x] Audit fallback pertanyaan tidak dikenali, knowledge pack, salin chat, lupa PIN, dan OCR nota.
- [x] Tambahkan jawaban lokal untuk panduan awal penggunaan dan pertanyaan tanggal Hijriah.
- [x] Ganti fallback menjadi singkat, jujur, serta mengarahkan ke Pusat Latihan tanpa contoh data fiktif.
- [x] Tambahkan alur Lupa PIN yang menjelaskan reset data lokal dan pemulihan cadangan tanpa bypass PIN.
- [x] Tambahkan tombol salin teks pertanyaan dan jawaban penuh pada kartu chat.
- [x] Simpan pertanyaan belum terjawab secara tersanitasi ke antrean pelatihan lokal dan sediakan ekspor JSON untuk LLM.
- [x] Uji OCR foto nota dari Asisten sampai menjadi preview transaksi yang menunggu konfirmasi.
- [x] Tambahkan regresi, jalankan analyzer dan seluruh test.
- [x] Commit, ZIP source, dan build APK release.

# Keandalan Asisten, PIN, dan OCR v61

- [x] Audit ulang alur PIN, Hijriah, launcher, knowledge pack, OCR, dan notifikasi pagi.
- [x] Ubah PIN baru menjadi empat digit dan reset keypad untuk setiap tahap verifikasi.
- [x] Perbaiki deteksi Hijriah serta lengkapi katalog jawaban bawaan Asisten.
- [x] Tambahkan paket konteks/templat LLM aman untuk knowledge pack.
- [x] Jadikan launcher Asisten dapat digeser dan tersimpan tanpa menghalangi FAB.
- [x] Uji OCR dengan alur nyata dan putuskan perbaiki atau hapus berdasarkan kriteria penerimaan.
- [x] Implementasikan pengingat pagi lokal yang aman tanpa aksi latar belakang otomatis.
- [x] Tambahkan regresi, jalankan analyzer dan seluruh test.
- [x] Commit, ZIP source, dan build APK release dengan keystore lama.

# Asisten FFM v63 — Query Data Nyata dan Pembelajaran Lokal

- [x] Audit kontrak offline, gateway model lokal, page context, query database, dan jalur simpan data.
- [x] Tambahkan registry query read-only untuk saldo rekening, ringkasan transaksi, aktivitas, target, serta hutang-piutang.
- [x] Tambahkan pencocokan fuzzy berbasis Dart murni untuk memori dan Knowledge Pack tanpa mengubah format ekspor.
- [x] Tambahkan action tool kontekstual yang hanya membuat draft tervalidasi dan tidak pernah menyimpan otomatis.
- [x] Rapikan bubble chat, indikator pertanyaan belum terjawab, dan aksesibilitas warna.
- [x] Tambahkan tab histori pertanyaan selesai, urutan berdasarkan frekuensi, serta ekspor histori opsional.
- [x] Tambahkan regresi read-only, fuzzy matcher, draft kontekstual, UI unknown, dan histori antrean.
- [x] Jalankan analyzer dan seluruh tes.
- [x] Commit source, buat ZIP, build APK release, dan verifikasi sertifikat lama.

# Asisten FFM v64 — Migrasi, Konteks Halaman, dan Database Dinamis

- [x] Audit migrasi database, status checklist v61, cakupan context halaman, dan jumlah tabel aktual.
- [x] Perbaiki pola migrasi database bila diperlukan serta buat regresi upgrade dari skema lama.
- [x] Tuntaskan atau dokumentasikan pembatalan resmi semua item v61 yang masih terbuka.
- [x] Pasang FfmAssistantPageContext pada seluruh halaman utama yang mempunyai destination.
- [x] Lengkapi detailFor untuk seluruh destination Asisten.
- [x] Ubah DatabaseStructurePage ke sumber skema Drift dinamis dan buat query chat read-only yang sama.
- [x] Tambahkan regresi cakupan context, struktur database, dan keamanan query read-only.
- [x] Jalankan analyzer, seluruh tes, commit, buat ZIP source, build APK, dan verifikasi sertifikat lama.

# Audit Pasca-Rilis v64 — Fitur dan Keamanan Data Lokal

- [x] Bandingkan jejak perubahan fitur v62 hingga v64 untuk memastikan tidak ada fitur selain OCR yang tercabut tanpa sengaja.
- [x] Verifikasi perlindungan migrasi dan susun langkah uji aman upgrade data lokal di perangkat pengguna.

# Asisten FFM — Perombakan UI, Navigasi, Kalender, dan Suara

- [x] Rapikan sheet chat: bubble pengguna proporsional, jawaban ringkas, disclosure pemahaman, toolbar aksi horizontal, menu `⋮`, dan chat selalu membuka pesan terbaru.
- [x] Sederhanakan akses riwayat pertanyaan belum terjawab serta hilangkan label ekspor yang menyebut merek AI tertentu.
- [x] Lengkapi alias navigasi Lainnya/PIN dan jawaban kalender besok Masehi-Hijriah dari waktu lokal.
- [x] Tambahkan kontrol TTS lokal: daftar suara perangkat, pilihan suara, berhenti, dan lanjutkan per kalimat.
- [ ] Tambahkan regresi UI, riwayat, navigasi, kalender, dan suara; jalankan analyzer, test, build, serta kemas artefak rilis.
