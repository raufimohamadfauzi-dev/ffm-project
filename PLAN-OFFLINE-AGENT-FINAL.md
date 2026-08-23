# Rencana Induk FFM Offline Agent

## Tujuan

Mengembangkan Family Finance Manager (FFM) menjadi aplikasi dengan **agent orchestrator offline** yang memiliki akses penuh pada level aplikasi, mampu memahami dan mengoperasikan seluruh fitur FFM dengan bantuan SLM Qwen2-VL lokal, dapat membaca konteks halaman, menjalankan pekerjaan lintas halaman, serta selalu meminta konfirmasi pengguna sebelum perubahan final yang bersifat permanen.

Pengetahuan dasar FFM dan pembelajaran terkontrol pengguna harus dapat diekspor bersama backup JSON dan dipulihkan di perangkat baru. Model SLM tetap dipindahkan melalui bundle model terverifikasi yang terpisah dari database transaksi.

## Keputusan yang sudah disepakati

1. **Agent orchestrator adalah pengendali pekerjaan aplikasi.** SLM Qwen2-VL menjadi mesin pemahaman dan penalaran bahasa/visual lokal; orchestrator memilih langkah, kemampuan, konteks halaman, dan urutan eksekusi.
2. **Akses agent penuh berlaku pada level aplikasi FFM.** Agent dapat membaca halaman, berpindah halaman, mencari data, membuka form, mengisi draft, membaca hasil, dan menjalankan kemampuan aplikasi yang terdaftar.
3. **Konfirmasi final wajib.** Agent boleh menyiapkan seluruh rencana dan draft, tetapi perubahan permanen pada transaksi, saldo, pengaturan, penghapusan, atau data penting hanya boleh terjadi setelah ringkasan akhir dikonfirmasi pengguna.
4. **Tidak ada akses bebas ke perangkat atau root Android.** Agent hanya menggunakan kemampuan aplikasi dan permission Android yang sah.
5. **SLM harus offline setelah model terverifikasi.** Tidak ada pengiriman percakapan, transaksi, gambar, atau pengetahuan ke cloud.
6. **Pembelajaran agent bersifat terkontrol.** Agent boleh menganalisis perintah, hasil, dan koreksi secara lokal, tetapi kandidat memori/workflow harus dapat ditinjau, disetujui, diberi versi, dan dibatalkan.
7. **Pengetahuan aplikasi berbeda dari ajaran pengguna.** Manual internal FFM diberikan sejak awal; preferensi, alias, contoh, dan workflow pengguna disimpan sebagai data pembelajaran terpisah.
8. **Riwayat chat berbeda dari memori agent.** Riwayat chat perlu memiliki kebijakan penyimpanan, retensi, hapus, dan ekspor yang jelas.
9. **Gambar wajib tampil sebagai media nyata di chat.** Placeholder teks saja tidak dianggap selesai; targetnya thumbnail inline, buka ukuran besar, dan kembali/minimalkan.
10. **APK tetap arm64-only** untuk menjaga ukuran, dengan model SLM tidak dimasukkan ke APK atau source archive.

## Urutan pelaksanaan

Rencana dibuat sekaligus agar keputusan antarbagian konsisten, tetapi pelaksanaan dilakukan **satu fase demi satu fase**. Setiap fase memiliki hasil yang dapat diperiksa dan menjadi syarat masuk fase berikutnya. Tidak ada implementasi besar yang dilakukan sekaligus tanpa checkpoint.

### Fase 1 — Bekukan keputusan dan audit arsitektur saat ini

Mendokumentasikan arsitektur yang sudah ada: chat launcher, session, interpreter, gateway SLM, model manager, page context, destination catalog, repository memori, repository contoh belajar, backup, dan alur konfirmasi. Memisahkan kemampuan yang sudah aktif dari kemampuan yang masih berupa fondasi atau fallback rule-based.

**Output:** matriks status kemampuan, daftar gap, keputusan terminologi, dan batasan yang harus dipertahankan. Pada fase ini tidak ada perubahan behavior sebelum desain disetujui.

### Fase 2 — Definisikan pengetahuan dasar FFM dan kontrak agent

Menyusun knowledge base internal yang menjelaskan nama FFM, tujuan aplikasi, jenis data, seluruh halaman, istilah bisnis, cara kerja transaksi, urutan workflow, aturan validasi, tindakan aman, tindakan sensitif, serta prosedur pemulihan error.

Kontrak agent harus mendefinisikan input, output, rencana langkah, status setiap langkah, kebutuhan klarifikasi, hasil tool/capability, error, dan konfirmasi. Pengetahuan dasar ini tidak boleh tercampur dengan memori pribadi pengguna.

**Output:** spesifikasi perilaku agent dan katalog pengetahuan dasar FFM yang dapat dipakai SLM dan orchestrator.

### Fase 3 — Rancang registry capability dan page context penuh

Mendaftarkan seluruh kemampuan aplikasi sebagai capability yang dapat dipanggil agent. Setiap capability harus menyatakan parameter, prasyarat, dampak, tingkat risiko, hasil, dan apakah memerlukan konfirmasi.

Setiap halaman harus menyediakan page context yang dapat dibaca agent: nama halaman, fungsi, data penting, filter aktif, status kosong/error, elemen yang tersedia, serta aksi yang boleh dilakukan. Agent harus dapat bekerja lintas halaman melalui rencana langkah, bukan hanya membuka destination.

**Output:** capability registry, page-context contract, dan peta navigasi/aksi seluruh fitur FFM.

### Fase 4 — Rancang integrasi SLM, perencanaan, eksekusi, dan konfirmasi

Menetapkan kapan permintaan dikirim ke SLM lokal, kapan guard deterministik mengambil alih, dan bagaimana hasil SLM diubah menjadi rencana terstruktur. SLM tidak diberi akses mentah ke database atau fungsi CRUD.

Alur standar yang harus dirancang adalah:

> Perintah pengguna → pemahaman SLM → rencana agent → pemeriksaan konteks → klarifikasi bila perlu → draft/preview → konfirmasi akhir → eksekusi capability → verifikasi hasil → laporan.

Agent harus dapat menangani perintah tunggal maupun rangkaian perintah. Untuk rangkaian perubahan, agent dapat menggabungkan pekerjaan menjadi satu rencana, tetapi ringkasan perubahan final tetap wajib dikonfirmasi.

**Output:** spesifikasi action plan, status machine, preview, confirmation, rollback/error, dan aturan fallback lokal.

### Fase 5 — Rancang pembelajaran offline terkontrol

Membuat loop pembelajaran lokal yang mencatat secara selektif perintah, hasil, koreksi, dan persetujuan. SLM dapat menganalisis pola untuk membuat kandidat memori, alias, preferensi, atau workflow.

Kandidat tidak langsung aktif. Kandidat harus dapat ditinjau, diuji pada data aman atau simulasi, disetujui, diberi versi, dan dihapus/rollback. Agent tidak boleh belajar untuk melewati PIN, konfirmasi, validasi, permission, atau batas keamanan.

Fase ini juga menentukan klasifikasi data sensitif, kebijakan opt-in, pembersihan data, dan apakah riwayat chat boleh dijadikan sumber pembelajaran. Default-nya adalah **riwayat chat tidak otomatis menjadi training data**.

**Output:** desain tabel/entitas learning, approval flow, versioning, rollback, privacy policy, dan status pembelajaran background.

### Fase 6 — Rancang migrasi dan backup lintas perangkat

Memisahkan komponen yang dipindahkan:

- **Finance data:** transaksi, rekening, kategori, anggaran, target, dan data keuangan.
- **Agent knowledge data:** manual version, memori, alias, contoh disetujui, workflow disetujui, koreksi, dan pertanyaan tak terjawab.
- **Chat history:** opsional, dengan retensi dan pilihan ekspor tersendiri.
- **SLM bundle:** file model dan projector terverifikasi melalui `.ffmbundle`, bukan dimasukkan sebagai isi JSON.

Impor harus memeriksa versi schema, checksum, konflik, duplikasi, data rusak, dan kompatibilitas. Setelah dipulihkan di HP baru, agent tetap memahami pengetahuan dasar FFM dan mendapatkan kembali pengetahuan pengguna yang disetujui, meskipun SLM belum tersedia. Setelah bundle SLM dipasang dan diverifikasi, mode model lokal dapat digunakan kembali.

**Output:** schema backup/migration, aturan kompatibilitas, conflict handling, dan prosedur pemulihan.

### Fase 7 — Implementasikan chat modern, riwayat, gambar, dan indikator SLM

Setelah kontrak agent stabil, memperbarui pengalaman chat. Riwayat chat dibuat persisten secara lokal dengan kontrol hapus dan retensi. Gambar ditampilkan inline sebagai thumbnail, dapat diperbesar, dan dapat ditutup/minimalkan; metadata gambar tidak bocor ke log atau knowledge pack tanpa persetujuan.

UI menampilkan perbedaan yang jelas antara:

- SLM lokal siap dan bekerja offline.
- SLM sedang diperiksa atau sedang memproses.
- SLM belum dipasang sehingga mode fallback lokal digunakan.
- Agent sedang merencanakan, menjalankan langkah, menunggu input, atau menunggu konfirmasi.

Banner setup harus tetap menawarkan **Unduh dari GitHub** atau **Impor bundle offline**, tanpa download otomatis. Composer chat dibuat modern, lapang, accessible, dan tidak menghilangkan fungsi voice, lampiran, kirim, reset, serta pembukaan halaman.

**Output:** chat UX final, persistensi history, media rendering, progress/status, dan setup SLM yang mudah ditemukan.

### Fase 8 — Implementasi capability aplikasi secara bertahap

Menghubungkan registry capability dengan halaman dan layanan FFM secara kelompok, dimulai dari operasi baca dan navigasi, kemudian draft/form, lalu tindakan yang memerlukan konfirmasi. Setiap capability diuji secara terisolasi sebelum dimasukkan ke rencana lintas halaman.

Urutan prioritas:

1. Membaca halaman dan berpindah halaman.
2. Membaca data lokal dan menjawab pertanyaan.
3. Membuka form dan mengisi draft.
4. Preview dan validasi.
5. Konfirmasi akhir.
6. Eksekusi perubahan dan verifikasi hasil.
7. Workflow lintas halaman dan pembelajaran dari hasil yang disetujui.

**Output:** agent yang benar-benar dapat mengoperasikan fitur aplikasi, bukan hanya menjawab atau memetakan destination.

### Fase 9 — Validasi keamanan, pembelajaran, migrasi, dan perangkat

Menjalankan full test, analyzer, unit/widget/integration test untuk action plan, confirmation, duplicate request, stale response, image rendering, persistence, import/export, versioning, rollback, dan privacy.

Memverifikasi secara statis bahwa APK hanya berisi `arm64-v8a`, tidak berisi GGUF/projector/model, package/version benar, signature valid, dan source archive tidak berisi key maupun model. Pengujian inference Android nyata, lifecycle, temperatur, RAM, latency, dan foto nyata harus dilaporkan terpisah dari keberhasilan compile/build.

**Output:** laporan validasi dan daftar keterbatasan yang masih tersisa.

### Fase 10 — Release signed dan dokumentasi akhir

Hanya jika seluruh validasi lulus, melakukan build release arm64-only signed menggunakan key yang dipasang sementara pada fase final. Key tidak boleh masuk source archive, log, atau attachment. APK diverifikasi dengan signature checker, package/version checker, dan inspeksi ABI.

Membuat source archive aman yang mengecualikan build artifacts, `.dart_tool`, Gradle cache, CMake cache, key, dan model proprietary. Dokumentasi proyek diperbarui agar status implementasi dan batasan tidak menyesatkan.

**Output:** APK release signed arm64-only, source archive aman, checksum, laporan perubahan, dan dokumentasi penggunaan migrasi/SLM.

## Strategi pengujian

Pengujian dilakukan pada setiap fase, bukan hanya di akhir. Test utama mencakup pemahaman perintah, routing SLM, page context, capability authorization, rangkaian action plan, klarifikasi, preview, final confirmation, duplicate voice/request, cancellation, stale response, fallback ketika SLM tidak tersedia, memory approval, learning rollback, JSON migration, conflict handling, image preview, history retention, dan accessibility/layout.

Validasi Android dibagi menjadi tiga kategori. **Build validation** memeriksa compile, link, ABI, packaging, dan signature. **Static security validation** memeriksa tidak ada model atau key yang masuk APK/source archive. **Device validation** memeriksa runtime inference, lifecycle, permission, force-close, memory, latency, dan interaksi kamera/gambar. Build tidak boleh diklaim sebagai bukti inference device end-to-end.

## Asumsi dan risiko terbuka

1. Qwen2-VL tetap dijalankan offline melalui native bridge yang sudah ada dan tidak dimasukkan ke APK.
2. “Full akses” dibatasi pada capability aplikasi FFM dan tidak berarti akses root perangkat.
3. Fine-tuning bobot model tidak menjadi bagian utama fase pertama; fokusnya adalah agent knowledge, workflow, dan memori lokal.
4. Background learning harus hemat baterai/RAM dan dapat dihentikan pengguna.
5. Data sensitif dan gambar tidak boleh masuk learning dataset tanpa persetujuan eksplisit.
6. Fitur yang belum memiliki capability terdaftar harus dilaporkan sebagai belum didukung, bukan dipalsukan seolah-olah berhasil.
7. Semua perubahan source dilakukan pada direktori kerja persisten `/home/ubuntu/FFM-source-2d123ad-v67`; arsip asli tetap tidak disentuh.

## Gate persetujuan

Rencana induk ini menyatukan seluruh pekerjaan di muka agar desain tidak terpecah. Setelah rencana disetujui, implementasi tetap dimulai dari Fase 1 dan maju satu checkpoint setiap kali hasil fase sebelumnya tervalidasi. Tidak ada coding atau perubahan behavior sebelum persetujuan terhadap rencana dan keputusan terbuka yang relevan.
