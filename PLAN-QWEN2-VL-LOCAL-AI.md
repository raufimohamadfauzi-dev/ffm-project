# Plan Implementasi FFM — Qwen2-VL AI Lokal On-Device

## Tujuan

Menambahkan kemampuan FFM untuk mengubah foto struk dan perintah teks bahasa natural menjadi **proposal transaksi terstruktur** menggunakan **Qwen2-VL-2B-Instruct** secara on-device melalui `llama.cpp`, tanpa API/cloud AI setelah setup awal. Alur yang dipertahankan secara mutlak adalah:

> Input foto atau teks → model lokal single-shot → Proposal JSON v2 → parser dan validator Flutter → preview/edit pengguna → tombol Simpan manual → CRUD/database resmi FFM.

Model tidak boleh membaca atau menulis database, memanggil tool, menjalankan SQL, melakukan ReAct/multi-step reasoning, atau menyimpan transaksi secara otomatis.

## Status dan keputusan awal

Pengguna telah menyetujui pelaksanaan **Fase 0 lengkap**, termasuk pengunduhan dua aset model dari GitHub ke sandbox untuk verifikasi nyata. Implementasi kode belum dimulai. Direktori kerja persisten adalah `/home/ubuntu/FFM-source-2d123ad-v67`, dan arsip sumber asli harus tetap dipertahankan tanpa ditimpa.

Batas mutlak yang akan menjadi acceptance criteria lintas fase adalah `n_ctx` maksimum 2048 untuk semua mode, hashing SHA-256 streaming dengan chunk kecil, paling banyak satu sesi inferensi native aktif, pembersihan resource native dalam `try-finally`, decode gambar langsung pada resolusi target dengan sisi terpanjang maksimal 1024 px, file `.part` tidak boleh dipakai inference, move final dan manifest secara atomik, fallback GPU ke CPU, fallback teks ke rule-based, tidak ada cloud fallback, serta tidak ada auto-save atau auto-kategorisasi.

## Fase 0 — Gerbang kelayakan dan bukti nyata

Fase ini dikerjakan lebih dahulu dan tidak membuat kode fitur. Semua bukti dicatat dalam laporan khusus, termasuk command/output penting, URL, timestamp, ukuran byte, hash, header, dan keputusan.

| ID | Pekerjaan | Bukti dan kriteria lulus |
|---|---|---|
| G0-01 | Memeriksa repository `raufimohamadfauzi-dev/ffm-project`, release `v1.0.0`, dan kedua URL aset | Metadata HTTP aktual dari URL release, status, redirect, `Content-Length` atau ukuran final, serta identitas release yang cocok |
| G0-02 | Mengunduh `Qwen2-VL-2B-Instruct-IQ4_NL.gguf` dan `mmproj-Qwen2-VL-2B-Instruct-f16.gguf` | File nyata berhasil diunduh; ukuran byte eksak dicatat; SHA-256 dihitung streaming dan cocok persis dengan hash briefing: `7df01d...815e8` dan `05cc3a...b8bc3` |
| G0-03 | Memeriksa header kedua file | Empat byte awal adalah `GGUF`; versi format GGUF dibaca langsung dan dicatat |
| G0-04 | Menentukan versi/commit `llama.cpp` | Sumber resmi `llama.cpp`/changelog/dokumentasi menunjukkan dukungan Qwen2-VL dengan `mmproj` terpisah di Android; commit/tag dipin dan alasan kompatibilitas dicatat. Bila perlu, smoke test build kecil direncanakan setelah Fase 0 atau dilakukan hanya jika tooling tersedia |
| G0-05 | Menetapkan ABI Android | Keputusan awal `arm64-v8a` saja, dengan analisis ukuran APK, perangkat sasaran, dan risiko kompatibilitas |
| G0-06 | Memverifikasi lisensi | Sumber resmi Alibaba/Qwen dan lisensi model/artefak kuantisasi diperiksa; kesimpulan redistribusi GGUF dan penggunaan on-device dicatat. Jika tidak jelas atau tidak mengizinkan, status menjadi blocker |
| G0-07 | Menetapkan status gerbang | Jika G0-01 sampai G0-06 lulus, Fase 0 dinyatakan lulus dan pengguna menerima laporan. Jika satu saja gagal/tidak cocok, pekerjaan implementasi berhenti; tidak mengganti model atau pendekatan sepihak |

**Output Fase 0:** `docs/qwen2_vl_phase0_verification.md` dan artefak bukti lokal yang tidak dimasukkan ke APK/source archive. Ukuran model yang besar tidak akan di-commit ke repository. Hashing bukti akan memakai pembacaan chunk kecil, bukan `readAsBytes()`.

## Gerbang persetujuan setelah Fase 0

Setelah laporan selesai, pekerjaan berhenti untuk meminta konfirmasi pengguna jika terdapat blocker atau keputusan yang memerlukan persetujuan. Implementasi Fase 1–7 hanya dimulai setelah Fase 0 lulus secara eksplisit. Jika pengguna menyetujui lanjut, setiap fase selesai dengan test dan catatan bukti sebelum fase berikutnya dimulai.

## Fase 1 — Manifest, storage privat, dan Model Manager

Membangun kontrak manifest `ffm-verified-model-manifest-v1`, lokasi storage privat berbasis `ApplicationSupportDirectory`/`filesDir`, status model, download eksplisit, resume via HTTP Range, metadata `ETag`/`Last-Modified`, file `.part`, validasi ukuran dan SHA-256 streaming, penghapusan parsial yang invalid, move atomik, dan penulisan manifest atomik. Tidak ada auto-download di background. File final hanya dianggap siap bila manifest, ukuran, hash, bundle ID, dan status verifikasi konsisten.

Test mencakup resume, koneksi putus, cancel, aset berubah, server tanpa resume, hash salah, ukuran salah, ruang gagal bila dapat disimulasikan, restart aplikasi, penghapusan model, serta larangan `.part` masuk ke inference.

## Fase 2 — Bridge native Flutter–Android–llama.cpp

Menambahkan bridge yang kompatibel dengan versi `llama.cpp` yang telah dipin, dengan konfigurasi `n_ctx` yang dikunci maksimal 2048 dan dapat diturunkan untuk profil RAM rendah. Menyediakan satu jalur single-shot untuk teks dan visi, menerima input yang sudah disiapkan, menghasilkan teks proposal, dan tidak memiliki akses database/tool-calling. Semua pointer, context, bitmap, dan handle native dibersihkan di `try-finally` pada jalur sukses, error, dan cancel.

GPU dicoba hanya jika didukung dan stabil; kegagalan wajib kembali ke CPU tanpa crash. Token visual pada resolusi target diukur nyata melalui smoke test `mmproj`; apabila budget tidak aman, resolusi diturunkan bertahap sesuai briefing, bukan menaikkan context. Test membuktikan tidak ada konfigurasi atau fallback yang dapat melewati 2048.

## Fase 3 — Queue inference dan Proposal JSON v2

Menerapkan antrean dengan satu inference aktif, cancel idempoten, state yang konsisten saat request berulang, parser JSON defensif, dan validator Proposal JSON v2. Validator memeriksa tipe integer nominal, tanggal, timezone, confidence, warnings terstruktur, kebutuhan klarifikasi, serta menghitung ulang jumlah item dan menambahkan `sum_mismatch` bila perlu.

Output rusak atau ambigu harus menjadi draf `perlu dicek`, bukan diam-diam dibuang atau diubah menjadi transaksi. Pencocokan kategori/rekening dilakukan Flutter terhadap Data Utama setelah output model diterima. Kategori/rekening baru tidak boleh dibuat otomatis.

## Fase 4 — Integrasi teks ke Asisten FFM

Menghubungkan mode AI lokal ke jalur Asisten yang sudah ada melalui kontrak gateway/orchestrator. Saat model tidak dipasang, gagal load, RAM kurang, atau error native, input teks kembali ke rule-based interpreter yang sudah ada dan menampilkan status mode yang jujur. Saat model gagal, tidak ada cloud fallback.

Hasil model selalu masuk ke draft/preview dan alur koreksi yang telah ada. Test regresi memastikan perintah teks tidak membuat transaksi sebelum konfirmasi manual, fallback rule-based tetap identik, dan PIN, navigasi, draft, serta perilaku existing tidak rusak.

## Fase 5 — Jalur visi foto struk

Menambahkan input kamera/galeri sesuai kemampuan aplikasi, decode langsung pada resolusi target dengan sisi terpanjang maksimal 1024 px, kompresi lokal bila diperlukan, dan pembersihan bitmap/file sementara segera setelah selesai atau dibatalkan. Foto hanya dikirim ke native inference lokal setelah model verified-ready. Hasilnya Proposal JSON v2 yang tampil pada preview editable resmi.

Jika inference foto gagal atau context penuh, tampilkan pemulihan yang eksplisit sesuai briefing: turunkan resolusi, isi manual, atau batal. Tidak ada fallback pura-pura ke transaksi lain. Tidak ada request jaringan setelah setup model.

## Fase 6 — UX setup dan status operasional

Menyediakan layar pengaturan model yang menjelaskan status belum terpasang, mengunduh, melanjutkan, memverifikasi, siap, gagal, dan dihapus. Menampilkan mode aturan lokal versus AI lokal di perangkat, status CPU fallback, progres, ukuran, hash/status verifikasi, pesan error yang tidak membocorkan foto, nominal, rekening, prompt, atau PIN, serta tombol hapus model dengan konfirmasi.

UX tidak boleh menjanjikan penyimpanan otomatis. Pengguna selalu melihat dan mengedit preview sebelum menekan Simpan pada form resmi.

## Fase 7 — Hardening, profiling, dan rilis

Menjalankan unit, widget, integrasi, dan manual test untuk semua kondisi wajib: model belum ada, offline setelah setup, unduhan putus, `.part` korup, hash salah, ruang habis, RAM rendah, GPU gagal, CPU fallback, foto besar/buram, struk panjang, context penuh, cancel, sesi berulang, force close, migrasi database, dan update APK di atas versi lama.

Melakukan profiling RAM/CPU pada perangkat target yang tersedia, audit bahwa tidak ada API/cloud AI, audit isolasi database, verifikasi bahwa hanya `arm64-v8a` yang ditargetkan bila keputusan Fase 0 tetap demikian, build release, verifikasi package ID `com.ffm_manager`, serta verifikasi signature menggunakan keystore rilis lama. Database lama harus tetap dapat dibuka dan di-update tanpa kehilangan data.

## Rencana pengujian dan definisi selesai

Pekerjaan dianggap selesai hanya jika seluruh fase yang disetujui memiliki bukti tertulis, test otomatis relevan lulus, analyzer/formatter lulus bila Flutter SDK tersedia, smoke test native berjalan pada environment target, dan seluruh aturan mutlak dapat ditelusuri ke test atau audit kode. Dua pembuktian manual selalu wajib untuk teks dan visi: setelah setup tidak ada request AI/cloud, dan tidak ada transaksi/kategori/rekening yang tercipta sebelum tombol Simpan ditekan.

Jika environment sandbox tidak memiliki Flutter SDK/Android SDK/device atau akses native yang dibutuhkan, keterbatasan tersebut akan dicatat sebagai blocker teknis dan langkah verifikasi yang belum dapat dijalankan tidak akan diklaim lulus. Model berukuran besar tetap berada di luar source archive dan tidak dimasukkan ke Git.

## Risiko dan asumsi terbuka

Risiko terbesar adalah dukungan Qwen2-VL plus `mmproj` pada commit `llama.cpp` Android yang dapat dipin, kompatibilitas binding Flutter/NDK, kebutuhan RAM perangkat low-end, ukuran distribusi model, lisensi redistribusi artefak GGUF, serta kemampuan melakukan profiling/update-install tanpa perangkat fisik. Semua risiko tersebut sengaja ditempatkan sebelum atau pada gerbang fase terkait.

Asumsi kerja saat ini adalah Android 64-bit menjadi target awal, model diunduh berdasarkan pilihan eksplisit pengguna, model pertama hanya menangani pemahaman/koreksi/ringkasan, dan jalur rule-based existing tetap menjadi fallback teks. Impor model dari perangkat lain ditunda dan tidak termasuk scope awal kecuali disetujui kemudian.
