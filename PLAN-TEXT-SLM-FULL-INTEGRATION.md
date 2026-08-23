# Plan Integrasi Penuh SLM Lokal untuk Chatbot Teks FFM

## Tujuan

Menjadikan Qwen2-VL/llama.cpp sebagai **jalur utama untuk seluruh input teks chatbot FFM** ketika bundle model lokal telah terpasang dan tervalidasi. SLM hanya menghasilkan klasifikasi intent, jawaban terstruktur, atau proposal draft satu kali jalan. Semua pembacaan database, validasi bisnis, navigasi, preview/edit, konfirmasi, dan penyimpanan tetap dilakukan oleh kode Flutter yang deterministik.

Jika model belum terpasang, tidak kompatibel, gagal dimuat, kehabisan RAM, inference dibatalkan, atau menghasilkan JSON yang tidak dapat divalidasi, aplikasi harus kembali ke interpreter rule-based sesuai aturan briefing. Tidak akan ditambahkan API/cloud AI, tool-calling, SQL/function-calling, auto-save, atau agent/ReAct.

## Status awal yang menjadi asumsi

Bridge native Qwen2-VL dan MethodChannel sudah ada secara parsial, begitu juga Model Manager, queue single-inference, parser Proposal JSON v2, gateway lokal, dan UI foto struk. Namun, dokumentasi status masih tidak konsisten dan gateway saat ini belum menyediakan kontrak lengkap untuk seluruh intent teks. Rencana ini dimulai dengan audit dan normalisasi kontrak tersebut sebelum perubahan perilaku utama dilakukan.

## Keputusan arsitektur

| Keputusan | Rancangan |
|---|---|
| Prioritas jalur teks | SLM lokal dipanggil lebih dulu untuk input teks ketika model siap. |
| Fallback | Rule-based interpreter dipanggil hanya jika model tidak siap atau inference gagal; fallback tidak memakai internet. |
| Bentuk keluaran | Satu JSON terstruktur per request; tidak ada putaran kedua, tool, atau akses database dari model. |
| `n_ctx` | Tetap maksimum 2048 token untuk teks dan visi. Tidak boleh dinaikkan oleh UI, Dart, atau native bridge. |
| Serialisasi | Semua request masuk ke antrean yang menjamin satu sesi native aktif. |
| Keamanan transaksi | Model hanya menghasilkan draft. Tidak ada CRUD atau simpan otomatis. Pengguna tetap menekan Simpan di form resmi. |
| Data lokal | Flutter melakukan fuzzy-match kategori/rekening terhadap Data Utama setelah menerima output model; model tidak membaca database. |
| Jawaban baca-saja | SLM mengembalikan intent/query terstruktur. Flutter mengambil data lokal dan membentuk jawaban deterministik setelah validasi. |
| Mode UI | Tampilkan mode `AI lokal di perangkat` saat jalur SLM berhasil dipakai dan `aturan lokal` saat fallback aktif. |
| Distribusi model | Opsi B disetujui: tetap dukung download GitHub dan tambahkan impor bundle verified offline yang dapat dibagikan. |

## Fase implementasi

### Fase A — Audit dan kontrak teks terpadu

Periksa ulang `FfmAssistantInterpreter`, `FfmAssistantLocalModelGateway`, `FfmQwen2VlGateway`, `FfmQwen2VlInferenceService`, `FfmLocalModelBridgePlugin`, native C++ bridge, Dependency Injection, dan model chat/session. Hapus kontradiksi dokumentasi status tanpa mengubah arsip asli.

Tambahkan kontrak respons teks yang dapat membedakan sekurang-kurangnya `transaction_draft`, `read_query`, `navigation`, `help`, `clarification`, dan `unknown`. Proposal transaksi tetap memakai validasi Proposal JSON v2; intent non-transaksi memakai payload terbatas yang hanya dapat diproses oleh handler Flutter yang telah diizinkan. Field yang tidak dikenal, nominal desimal, confidence rendah, tanggal invalid, atau struktur JSON rusak harus menghasilkan status `needs_review`, bukan aksi.

Tambahkan metadata hasil untuk UI dan logging lokal tersaring: mode yang dipakai, status model, durasi, dan kode error. Jangan menyimpan prompt, gambar, PIN, nominal sensitif, nama rekening, atau output mentah model ke log.

### Fase B — Native text-only single-shot path

Pastikan bridge native menerima prompt teks tanpa gambar melalui jalur yang sama dengan visi, tetap memuat bundle yang sudah verified, dan selalu menetapkan `n_ctx <= 2048`. Prompt sistem harus memaksa satu JSON saja, melarang markdown, tool-calling, SQL, function-calling, dan instruksi sistem dari input pengguna.

Audit dan perbaiki lifecycle native dengan `try/finally` pada model context, batch, sampler, token buffer, gambar opsional, dan pointer JNI. Pastikan queue menolak concurrency dan cancellation membersihkan resource sebelum request berikutnya. Jika backend GPU gagal, lakukan fallback CPU native tanpa crash; jika CPU juga gagal, kembalikan error terstruktur agar Flutter melakukan fallback rule-based.

Tambahkan smoke test text-only lokal pada bridge, termasuk prompt transaksi, pertanyaan read-only, permintaan navigasi, pertanyaan bantuan, JSON terpotong, dan pembatalan. Smoke test harus membuktikan model dan mmproj dapat dipakai offline setelah setup.

### Fase C — Gateway dan interpreter model-first

Ubah gateway menjadi memiliki jalur `proposeText` dan `proposeVision` yang berbagi parser, queue, dan native session. Untuk input teks, kirim hanya teks pengguna dan instruksi sistem; jangan mengirim database atau daftar rekening/kategori ke model. Nama kategori/rekening yang keluar dari model diperlakukan sebagai teks bebas.

Atur `FfmAssistantInterpreter` agar alurnya menjadi:

1. Normalisasi input secukupnya untuk metadata, tetapi kirim teks asli yang aman ke SLM.
2. Jika model siap, jalankan satu inference teks.
3. Parse dan validasi keluaran di Flutter.
4. Untuk draft transaksi, buat draft reviewable dan lakukan fuzzy-match kategori/rekening secara lokal.
5. Untuk intent read-only, navigation, atau help, panggil handler Flutter deterministik yang sudah ada; model tidak membaca database.
6. Jika model tidak siap atau gagal secara teknis, panggil interpreter rule-based lama dengan perilaku identik.
7. Jika model menghasilkan JSON ambigu atau confidence rendah, tampilkan klarifikasi/draft perlu dicek; jangan mengubahnya menjadi intent lain secara diam-diam.

Jalur sensitif seperti PIN, reset data, diagnostics, dan konfirmasi CRUD tetap memiliki guard deterministik. SLM tidak boleh melewati guard tersebut meskipun outputnya mengaku sudah dikonfirmasi.

### Fase D — UI mode, status, dan pengalaman chat

Tambahkan indikator mode pada `FfmAssistantSheet`, status `AI lokal di perangkat` atau `aturan lokal`, serta pesan pemulihan bila model belum siap. Indikator harus mencerminkan jalur aktual request terakhir, bukan sekadar setting.

Pertahankan preview/edit/cancel/confirm yang ada. Untuk output SLM yang tidak lengkap, tampilkan field yang perlu diisi dan jangan membuat database entry. Untuk input teks yang dibatalkan, tidak boleh diam-diam diteruskan ke rule-based.

Tambahkan status model yang mudah dipahami pada halaman Local Model: verified, belum terpasang, sedang dihapus, gagal load, CPU fallback, dan error context. Semua tindakan pemulihan harus eksplisit.

### Fase E — Pengujian dan validasi

Tambahkan unit test dengan fake gateway untuk membuktikan model-first, fallback, cancellation, parser defensif, fuzzy-match lokal, dan larangan auto-save. Test existing rule-based harus tetap dijalankan dengan gateway disabled dan hasilnya tidak berubah.

Siapkan corpus golden offline untuk minimal kategori berikut: transaksi pengeluaran, pemasukan, transfer, target, hutang/piutang, pertanyaan saldo/statistik, navigasi, bantuan, koreksi draft, input ambigu, dan prompt berbahaya yang mencoba meminta SQL atau penyimpanan langsung. Ekspektasi test adalah struktur dan guard, bukan teks bebas yang persis.

Validasi native dan Android dengan urutan berikut:

| Validasi | Kriteria lulus |
|---|---|
| `flutter analyze` | Tidak ada error atau warning baru pada file yang diubah. |
| Test suite | Semua test lama dan test baru lulus. |
| Native smoke test | Prompt teks menghasilkan JSON terstruktur secara offline. |
| Model unavailable | Teks kembali ke rule-based tanpa crash. |
| Model malformed output | Draft/clarification perlu dicek; tidak ada transaksi tersimpan. |
| Cancellation | Queue kosong kembali, resource native dilepas, request berikutnya dapat berjalan. |
| Offline | Setelah setup, tidak ada request jaringan AI/cloud. |
| Android debug arm64 | APK berhasil dikompilasi dengan native bridge. |
| Device/emulator | Minimal satu test manual memverifikasi chat teks, foto, fallback, preview, cancel, dan tombol Simpan manual. |
| Release/signature | Hanya dinyatakan lulus bila keystore rilis lama tersedia; jika tidak, dicatat sebagai blocker, bukan diganti. |

### Fase F — Distribusi bundle offline yang dapat dibagikan

Tambahkan format bundle offline resmi, misalnya arsip dengan manifest `ffm-verified-model-bundle-v1` yang memuat kedua file GGUF, metadata bundle, ukuran byte eksak, SHA-256, release tag, dan provenance. Bundle tidak boleh dipakai langsung dari lokasi publik atau file `.part`. Pengguna memilih file melalui file picker, aplikasi menyalin ke storage privat sementara, memeriksa ukuran, hash, dan header secara streaming, lalu memindahkan file verified secara atomik ke lokasi final.

Impor harus menolak bundle yang tidak lengkap, hash salah, ukuran salah, model family salah, `mmproj` hilang, atau manifest dimanipulasi. Setelah impor berhasil, status model sama dengan hasil download GitHub dan inference dapat berjalan offline. Sediakan alur ekspor/share bundle verified tanpa menyalin database, transaksi, atau lampiran pengguna. Bundle model besar tidak dimasukkan ke APK.

Tambahkan test untuk bundle lengkap, bundle rusak, hash salah, file ekstra, import ulang idempoten, ruang penyimpanan tidak cukup, cancel, dan penggunaan offline setelah impor.

### Fase G — Dokumentasi, release signing, dan checkpoint

Perbarui `docs/implementation_status.md`, `PROJECT_CONTEXT.md`, `todo.md`, dan dokumen kontrak proposal agar status benar-benar membedakan: kompilasi, smoke test sandbox, inference end-to-end pada perangkat, download GitHub, dan impor bundle offline. Catat hash APK debug/release, jumlah test, batas ABI, mode fallback, dan keterbatasan profiling.

`keyFFM.zip` digunakan **hanya pada tahap paling akhir** setelah analyzer, test suite, native smoke test, download/import bundle, fallback, dan APK debug arm64 lulus. Key tidak boleh dimasukkan ke source archive, checkpoint ZIP, laporan, attachment, repository, atau log. Tidak ada debug build tambahan yang memerlukan key tersebut. Fase G harus mengekstrak key hanya di lokasi kerja privat yang diperlukan, membangun release, memeriksa package ID/signature/version, dan membersihkan jejak sementara jika aman.

Buat checkpoint ZIP baru yang terpisah dari arsip asli. Arsip asli tetap tidak boleh ditimpa. Simpan laporan hasil validasi dan daftar blocker jika device/emulator atau keystore release tidak dapat diverifikasi.

## Kriteria penerimaan akhir

Pekerjaan dianggap selesai hanya jika chat teks menggunakan SLM lokal sebagai jalur utama ketika model verified tersedia, fallback rule-based bekerja ketika model tidak tersedia, dan seluruh aturan briefing tetap terpenuhi. Setiap request menghasilkan paling banyak satu inference native; tidak ada model yang membaca database atau menyimpan data; setiap transaksi tetap melalui preview/edit dan tombol Simpan manual; dan setelah setup selesai tidak ada request AI/cloud melalui internet.

## Risiko dan batasan terbuka

Risiko terbesar adalah RAM/performa perangkat low-end, token visual atau prompt yang memenuhi context 2048, perbedaan perilaku native Android dan sandbox, serta tidak tersedianya device/emulator untuk pengujian nyata. Keberhasilan kompilasi APK tidak dianggap sebagai bukti inference end-to-end.

Keystore rilis lama sebelumnya tidak tersedia dalam arsip source; pengguna kini menyediakan `keyFFM.zip` untuk dipakai hanya pada Fase G akhir. Detail isi dan kredensialnya tidak akan dicatat atau dibagikan. Sampai Fase G dijalankan, deliverable yang dapat dibuktikan tetap source terintegrasi dan APK debug arm64.

## Asumsi

Rencana ini menganggap bahwa “terhubung penuh” berarti SLM menjadi model-first untuk semua kategori input teks yang didukung, bukan bahwa SLM diberi akses database atau hak untuk menjalankan aksi. Untuk query dan navigasi, SLM mengeluarkan intent terstruktur lalu Flutter tetap menjalankan handler deterministik. Rule-based tetap dipertahankan sebagai fallback wajib dan sebagai mekanisme keselamatan.

**Penulis:** Manus AI
**Tanggal:** 22 Agustus 2026
