# Rencana Audit UI Pasca-SLM dan Arsip Source ZIP Tanpa Build

## Jawaban singkat

Tidak terlihat ada halaman utama yang otomatis menjadi tidak terpakai hanya karena SLM ditambahkan. SLM berada di belakang **Asisten global**, sedangkan halaman FFM tetap menjadi UI resmi untuk melihat data, mengedit form, melakukan konfirmasi, keamanan, backup, dan setup model. AppShell masih merender Beranda, Transaksi, Anggaran, Analisa, dan Lainnya; handler assistant juga masih memetakan destination ke halaman nyata.

Namun, ada beberapa UI yang perlu diaudit agar tidak terasa legacy atau duplikatif setelah SLM menjadi reasoning engine. Kandidat utama adalah **Pusat Latihan Asisten**, beberapa aksi Knowledge Pack/LLM manual, serta sebagian halaman yang saat ini baru menjadi target navigasi tetapi belum memiliki adapter capability nyata. Halaman tersebut belum boleh dihapus sebelum fungsi penggantinya jelas.

## Temuan audit awal

| Surface UI | Status setelah SLM | Kesimpulan |
|---|---|---|
| Beranda/Summary | Aktif dan tetap menjadi sumber ringkasan | Tidak boleh dihapus; prioritas adapter read dinamis |
| Transaksi | Aktif untuk daftar, filter, form, preview, dan konfirmasi | Tetap UI resmi; assistant belum menggantikan form resmi |
| Anggaran | Aktif sebagai domain finansial utama | Tetap dipakai; perlu read adapter dan workflow draft |
| Analisa | Aktif untuk perhitungan dan insight | Tetap dipakai; SLM hanya membantu reasoning/rangkuman |
| Lainnya | Aktif sebagai navigasi 18 menu | Bukan dead UI; perlu validasi setiap menu dan akses assistant |
| Model Asisten Lokal | Aktif untuk download/import/export/hapus model | Tidak legacy; ini setup SLM yang memang tetap diperlukan |
| Pusat Latihan Asisten | Aktif untuk memory, learning examples, unanswered questions, knowledge pack | Tidak boleh dihapus, tetapi perlu direposisi menjadi pusat User Model/Controlled Learning lokal; aksi manual yang duplikatif akan diaudit |
| Activity Log/Diagnostics | Aktif untuk audit dan troubleshooting | Tetap penting untuk agent yang dapat menjelaskan kegagalan |
| Backup/Privacy/Database Structure | Aktif untuk kontrol data, migrasi, dan transparansi | Tidak boleh dihapus; justru menjadi bagian safety agent |
| Halaman domain seperti aset, target, hutang/piutang, pengingat, recurring, laporan | Aktif dan dapat dibuka via handler | Bukan dead UI, tetapi coverage capability agent belum penuh |
| Form domain | Tetap diperlukan sebagai final review/confirmation surface | Tidak diganti oleh SLM; agent hanya mengisi draft dan menunggu konfirmasi |

## UI yang berpotensi duplikatif atau perlu reposisi

### Pusat Latihan Asisten

Halaman ini tetap berguna karena menyimpan dan meninjau memory/candidate secara lokal. Yang perlu diubah bukan menghapus halaman, melainkan mengelompokkan fungsi menjadi User Model, Approval Candidate, Knowledge Pack, dan Diagnostics. Fitur yang meminta pengguna menyalin prompt atau JSON ke LLM eksternal perlu diberi label jelas sebagai workflow opsional/legacy-support atau dipisahkan dari alur SLM lokal. Tidak boleh ada kesan bahwa pengguna wajib melatih model Qwen secara manual untuk percakapan biasa.

### Knowledge Pack dan aksi LLM manual

Aksi ekspor/import pengetahuan tetap relevan untuk migrasi, tetapi perlu dibedakan dari runtime knowledge base bawaan aplikasi. Runtime knowledge FFM harus read-only dan versioned; user memory serta approved candidate dapat diubah melalui approval. UI yang hanya membuat prompt untuk layanan eksternal tidak boleh diposisikan sebagai jalur utama agent offline.

### Tombol assistant di halaman

Launcher global dan chat sheet tetap digunakan. Yang perlu diperbaiki adalah agar tombol “Buka” tidak memberi kesan mutation sudah selesai. Untuk mutation, halaman/form resmi tetap menjadi preview dan confirmation boundary. Action Plan harus menerima callback hasil form agar status plan tidak false-completed.

## Pekerjaan eksekusi berikutnya

1. Buat matriks audit lengkap antara 24 destination katalog, 18 menu Lainnya, halaman yang dirender AppShell, page context yang aktif, dan handler assistant. Tandai setiap surface sebagai `active`, `active-but-legacy`, `adapter-missing`, atau `candidate-for-removal`.
2. Audit referensi kode dan UI setiap kandidat. Hapus hanya kode yang benar-benar tidak direferensikan dan tidak memiliki fungsi migrasi/backup/diagnostics. Jangan menghapus halaman hanya karena SLM dapat menjawab atau menavigasinya.
3. Reposisi Pusat Latihan Asisten menjadi pusat kontrol User Model dan Controlled Learning. Pertahankan approval, edit, archive, delete, serta rollback; pisahkan workflow eksternal/manual dari runtime SLM lokal.
4. Lanjutkan implementasi adapter capability nyata untuk read Summary, Transactions, Accounts, Categories, Budget, dan Analysis. UI halaman tetap dipertahankan sebagai visualisasi dan final review.
5. Hubungkan draft/form dengan Action Plan secara jujur: membuka form berarti `awaitingConfirmation`, batal berarti `cancelled` atau tetap menunggu, dan hanya hasil konfirmasi/simpan yang memicu execute/verify.
6. Tambahkan test coverage untuk setiap halaman yang dipertahankan, terutama menu Lainnya, setup model, training/user model, backup/privacy, dan form confirmation.
7. Setelah milestone kode selesai, jalankan `dart format`, `flutter analyze lib test`, targeted tests, lalu full `flutter test`. Jangan menjalankan build APK, Gradle, signing, atau packaging.
8. **Pada akhir setiap milestone/percakapan eksekusi**, buat satu arsip source ZIP baru dari direktori proyek aktif. Arsip harus mengecualikan model GGUF, key release, file rahasia, build output besar, cache, `.dart_tool`, dan APK lama. Jangan menimpa arsip asli `FFM-source-2d123ad-v67.original.zip`; gunakan nama versi baru dan lampirkan ZIP tersebut sebagai deliverable.

## Kebijakan arsip ZIP

Arsip ZIP hanya berisi source code, konfigurasi proyek yang aman, test, dokumentasi, dan file pendukung kecil yang diperlukan. Sebelum arsip dibuat, lakukan pemeriksaan nama/path untuk memastikan tidak ada `keyFFM.zip`, keystore, token, secret, model `.gguf`, APK, atau data pribadi. Arsip dibuat setelah validasi kode selesai, bukan sebelum perubahan selesai. Pembuatan ZIP tidak dianggap sebagai build APK dan tidak boleh memicu proses Gradle.

## Kriteria selesai audit

Audit dianggap selesai jika setiap halaman yang terdaftar memiliki status dan alasan yang terdokumentasi, tidak ada dead UI yang dibiarkan tanpa keputusan, Pusat Latihan Asisten tidak lagi membingungkan antara training SLM dan controlled learning, dan halaman resmi tetap menjadi boundary preview/confirmation. Full test serta analyzer harus lulus. Arsip ZIP source terbaru harus tersedia dan tidak mengandung key, model, APK, cache, atau secret.

## Asumsi dan risiko

Audit dilakukan berdasarkan referensi runtime Dart dan pemetaan AppShell saat ini; halaman yang dibuka melalui navigation internal atau deep link perlu diverifikasi selama eksekusi. Risiko terbesar adalah menghapus UI yang masih dibutuhkan untuk security, migration, diagnostics, atau confirmation. Karena itu default keputusan adalah mempertahankan halaman sampai ada bukti referensi dan fungsi pengganti yang aman.

Instruksi pengguna untuk tidak melakukan build berlaku terus. Hanya arsip source ZIP yang dibuat pada akhir milestone, dan arsip asli tetap dipreservasi.
