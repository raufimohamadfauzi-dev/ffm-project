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
- [x] Tambahkan regresi UI, riwayat, navigasi, kalender, dan suara; jalankan analyzer, test, build, serta kemas artefak rilis.

# Audit Dokumen Analisis Asisten Offline

- [x] Baca dan nilai rekomendasi dokumen terhadap kontrak offline-first, data lokal, serta alur draf-konfirmasi FFM.
- [x] Terapkan hanya rekomendasi yang relevan, terukur, dan aman tanpa mengaktifkan cloud atau simpan otomatis.
- [x] Tambahkan regresi, validasi penuh, dan kemas artefak bila ada perubahan kode.

# Fondasi ZIP Terbaru dan Qwen2-VL Offline

- [ ] Inventarisasi ZIP `FFM-af35a82-v08.zip` dan dua dokumen pelengkap tanpa menimpa proyek aktif.
- [ ] Bandingkan struktur, commit, konfigurasi build, database, serta aturan keamanan ZIP terbaru terhadap fondasi FFM aktif.
- [ ] Lengkapi dan buktikan seluruh gerbang Fase 0: release asset, ukuran byte, hash, header GGUF, ABI, lisensi, dan kompatibilitas `llama.cpp`.
- [ ] Konsolidasikan spesifikasi model, penyimpanan/impor lokal, orkestrator single-shot, fallback rule-based, dan test case terukur.
- [ ] Minta persetujuan fondasi final sebelum menulis kode Fase 1.

# Pemulihan Unduhan Model Qwen2-VL

- [x] Hentikan build audit yang tidak diminta; jangan buat APK debug atau release untuk pekerjaan ini.
- [x] Telusuri kegagalan DNS/host `github.com`, perilaku resume, dan pesan pemulihan tanpa melemahkan verifikasi ukuran, hash, atau header GGUF.
- [x] Pastikan impor bundle offline tetap menjadi jalur setara saat jaringan perangkat tidak tersedia.
- [x] Tambahkan regresi untuk kegagalan DNS, retry eksplisit, resume aman, dan tidak adanya unduhan otomatis.
- [x] Validasi source tanpa build APK, lalu buat ZIP source terbaru setelah perbaikan selesai.

# Rilis Source dan APK Qwen2-VL

- [x] Periksa source, versionCode, keystore lama, dan perubahan lokal sebelum commit rilis.
- [x] Simpan source terbaru ke Git lokal dengan commit rilis yang jelas.
- [x] Build APK release memakai package ID `com.ffm_manager` dan keystore lama.
- [ ] Verifikasi package/version, signature sertifikat lama, dan ZIP source dari commit rilis.

# Asisten — Jawaban Halaman Aktif

- [x] Audit page context, interpreter, dan jalur chat untuk pertanyaan halaman aktif.
- [x] Jawab pertanyaan “sedang di halaman apa?” dari konteks UI yang nyata tanpa model atau data contoh.
- [x] Tambahkan regresi, validasi source, dan kemas ZIP pembaruan.

# Asisten — Screen Awareness

- [x] Audit router aktif, page context yang sudah ada, dan budget prompt 1.900 token.
- [x] Klasifikasikan halaman menjadi konteks nama-saja atau nama-plus-ringkasan aman.
- [x] Tetapkan desain injeksi konteks tanpa tool call/Action Plan serta batas detail sensitif.
- [x] Jawab keputusan desain pengguna sebelum implementasi kode.

# Asisten — Status SLM dan Langkah Berikutnya

- [x] Audit status bundle model, verifikasi, halaman setup, dan indikator di chat setelah unduhan.
- [x] Tampilkan status siap/belum siap/gagal yang jujur beserta alasan dan tindakan berikutnya.
- [x] Tambahkan regresi status SLM, validasi source, dan kemas pembaruan.

# Asisten — Navigasi, Respons, dan Profil

- [x] Audit pemindahan halaman, tombol cek/buka, dan pencegahan navigasi berulang.
- [x] Audit auto-scroll chat saat jawaban baru selesai ditambahkan.
- [x] Audit profil pengguna/asisten serta jawaban identitas dan kemampuan.
- [x] Tambahkan regresi, validasi source, dan kemas pembaruan.

# Perapian Label Navigasi Aktivitas

- [x] Audit label menu navigasi dan nama halaman terkait Aktivitas.
- [x] Sederhanakan label navigasi menjadi “Aktivitas” tanpa mengubah destination.
- [x] Validasi source dan kemas pembaruan bila ada perubahan.

# Deteksi SLM Hasil Unduhan Latar Belakang

- [x] Audit lokasi file hasil unduhan, proses impor, dan pembacaan status siap.
- [x] Perbaiki deteksi atau pesan pemulihan bila file selesai belum dapat ditemukan.
- [x] Tambahkan regresi, validasi source, dan kemas pembaruan bila ada perubahan.

# Verifikasi APK Patch SLM

- [x] Rekonstruksi error impor ulang berdasarkan screenshot APK lama dan cocokkan dengan patch source.
- [x] Tambahkan regresi bila masih ada jalur status yang belum tercakup.
- [x] Build APK release patch, verifikasi package/version/tanda tangan lama, lalu kemas source.

# Penguatan Download SLM dan Cakupan Rule-Based

- [x] Audit path DownloadManager, race file selesai, struktur package Kotlin, dan error diagnostik.
- [x] Tambahkan retry, validasi ukuran, serta diagnostik aman untuk file unduhan background.
- [x] Rapikan lokasi source Kotlin agar selaras dengan package `com.ffm_manager`.
- [x] Audit katalog intent/query lokal dan implementasikan cek kelengkapan data yang dapat dibuktikan.
- [x] Bedakan pertanyaan ambigu dari gap knowledge baku serta tambahkan regresi.
- [x] Jalankan validasi, build APK patch, verifikasi rilis, dan kemas source.

# Aksi Chat dan Katalog Kemampuan/Data

- [x] Audit hilangnya tombol Cek/Buka dari respons chat serta pastikan lintas halaman tetap dapat dinavigasi.
- [x] Pulihkan aksi Cek/Buka pada respons yang memiliki destination atau draft tanpa menciptakan loop halaman aktif.
- [x] Petakan seluruh section dan fitur FFM ke katalog kemampuan/data terpusat dengan sinonim serta tipe pertanyaan dasar.
- [x] Bangun handler generik untuk pertanyaan kemampuan, kelengkapan/status, dan daftar isi berbasis katalog.
- [x] Tambahkan regresi katalog, validasi penuh, build APK patch, dan kemas source.

# Pemulihan Spinner Model Asisten Lokal

- [x] Audit semua tahap `_load()`, timeout yang mungkin terjadi, dan pemanggilan lifecycle yang tumpang tindih.
- [x] Tambahkan pengunci pemuatan, batas waktu, error state yang selalu mematikan spinner, serta diagnostik aman.
- [x] Tambahkan regresi pemuatan sukses, timeout, error, dan resume lifecycle.
- [x] Jalankan validasi penuh, build APK patch, verifikasi rilis, dan kemas source.

# SafeArea Indikator Asisten dan Spinner Perangkat

- [x] Audit AppShell tanpa AppBar untuk memastikan indikator tidak menabrak status bar pada notch maupun layar datar.
- [x] Terapkan SafeArea sisi atas tanpa mengubah posisi bottom navigation.
- [x] Audit ulang spinner perangkat setelah v72 dan tambahkan pemulihan untuk jalur yang masih dapat menggantung.
- [x] Tambahkan regresi layout dan pemulihan status, lalu validasi penuh serta build APK patch.

# Path DownloadManager dan Konteks Data Utama SLM

- [x] Audit penggunaan `COLUMN_LOCAL_URI`, fallback path manual, dan diagnostik perbedaan path pada bridge Android.
- [x] Jadikan URI DownloadManager sebagai sumber path utama, dengan fallback yang aman bila URI tidak dapat dibuka.
- [x] Verifikasi katalog kemampuan/data generik yang sudah ada dan dokumentasikan cakupannya.
- [x] Tambahkan konteks privat nama rekening dan kategori aktif ke prompt SLM dengan batas jumlah/token.
- [x] Tambahkan regresi URI/path, katalog, konteks Data Utama, validasi penuh, dan build APK patch.

# Progres Rakit dan Pasang SLM

- [x] Audit verifikasi hash streaming, commit staging, dan status yang bertahan setelah halaman ditutup.
- [x] Tambahkan model status persisten untuk tahap, byte diproses, hasil sukses, dan ringkasan kegagalan.
- [x] Hubungkan callback progres byte nyata dari verifikasi model dan projector ke proses rakit SLM.
- [x] Tampilkan progress bar, tahap 1/2 dan 2/2, peringatan navigasi, serta aksi sukses/gagal yang relevan.
- [x] Tambahkan regresi progres, recovery lifecycle, validasi penuh, dan build APK patch.

# Audit dan Upgrade Capability Agen FFM

- [x] Inventarisasi intent, registry, adapter, planner, executor, draft, repository, ekspor, knowledge, dan audit yang benar-benar tersambung.
- [x] Catat mismatch aktual dan prioritaskan capability P0 yang aman untuk diselesaikan pada arsitektur sekarang.
- [x] Implementasikan capability P0 terpilih melalui jalur chat sampai hasil terverifikasi dan konfirmasi eksplisit.
- [x] Tambahkan regresi lintas jalur, validasi penuh, build APK patch, dan matriks capability aktual.

# Phase 1 Lanjutan — Mutation Entity Non-Transaksi

- [x] Audit kontrak update, archive/delete, verifikasi, dan audit log pada Aktivitas serta Pengingat.
- [x] Implementasikan hanya entity yang memiliki kontrak repository dan semantik aman dari chat sampai hasil terverifikasi.
- [x] Catat entity yang ditunda karena relasi/side-effect belum dapat disinkronkan oleh jalur resmi.
- [x] Tambahkan regresi lintas entity, validasi penuh, build APK patch, dan perbarui matriks capability.

# Perbaikan Deep-Link Notifikasi Pengingat

- [x] Audit payload notifikasi, callback respons, lifecycle start/resume, dan rute Pengingat saat notifikasi diketuk.
- [x] Pastikan ketukan notifikasi membuka Pengingat lalu rincian/riwayat kejadian yang tepat, bukan hanya menutup notifikasi.
- [x] Pastikan aksi notifikasi dan ketukan biasa mempertahankan ID pengingat/kejadian yang sama tanpa membuat alarm duplikat.
- [x] Tambahkan regresi, validasi penuh, build APK patch, dan dokumentasikan uji perangkat nyata.

# Pemulihan Unduh Parsial dan Deduplikasi SLM

- [x] Audit file final, staging, unduhan background, dan state komponen model/projector setelah koneksi terputus.
- [x] Deteksi komponen valid per file dan unduh hanya komponen yang belum lengkap atau hash-nya tidak cocok.
- [x] Lanjutkan unduhan parsial bila server mendukung resume; hapus hanya salinan sementara/duplikat yang terbukti tidak valid.
- [x] Ringkas pesan koneksi tanpa menampilkan URL signed dan tampilkan tindakan pemulihan per komponen.
- [x] Tambahkan regresi, validasi penuh, build APK patch, serta dokumentasikan uji perangkat nyata.

# Audit dan Sinkronisasi GitHub Lintas Perangkat

- [x] Audit commit, branch, file, ukuran, dan konfigurasi repository GitHub terbaru.
- [x] Periksa secret, keystore, file konfigurasi lokal, artefak build, model besar, dan data pengguna yang tidak boleh disinkronkan.
- [x] Bandingkan baseline GitHub dengan source FFM lokal v79 tanpa force push atau overwrite.
- [x] Dokumentasikan cara mendeteksi update dari perangkat lain sebelum source lokal diubah.

# Publikasi Source FFM v79 ke GitHub

- [x] Audit akhir file tracked dan aturan ignore sebelum source lokal dipush ke GitHub.
- [ ] Push commit source FFM v79 ke branch baru tanpa mengubah branch `main` legacy.
- [ ] Verifikasi commit, branch, dan file remote setelah push; catat baseline sinkronisasi lintas perangkat.
