# Rencana Maksimalisasi FFM Offline Agent Orchestrator

## Tujuan

Meningkatkan FFM Offline Agent dari fondasi Registry Capability dan Action Plan menjadi agent operator aplikasi yang nyata. Agent harus memahami FFM melalui pengetahuan dasar dan page context, menggunakan SLM Qwen2-VL lokal untuk memahami bahasa/gambar serta menyusun rencana, mengakses seluruh capability pada level aplikasi, menjalankan pekerjaan lintas halaman, dan meminta konfirmasi pengguna sebelum perubahan final.

Prioritas tahap ini adalah **kemampuan agent**, bukan UI kosmetik, APK size, atau release build. Tidak ada build release sampai seluruh kriteria selesai dan tervalidasi.

## Prinsip tetap

1. **Orchestrator adalah pengendali operasional.** SLM adalah mesin pemahaman/penalaran lokal, bukan pemegang akses database mentah.
2. **Full access berarti full access pada level aplikasi FFM.** Agent dapat membaca, menavigasi, menyiapkan, dan menjalankan capability yang terdaftar, tetapi tidak memperoleh root/device access dan tetap mengikuti permission Android.
3. **Konfirmasi akhir wajib.** Read-only dan navigasi dapat berjalan langsung; mutation, penghapusan, dan perubahan sensitif wajib melalui preview dan konfirmasi.
4. **Offline setelah setup.** Tidak ada cloud inference, upload data, atau cloud learning. Download GitHub hanya opsi setup awal; impor bundle offline tetap tersedia.
5. **Belajar terkontrol.** Agent boleh mengusulkan memori, preferensi, dan workflow dari penggunaan, tetapi tidak boleh mengubah guard keamanan atau capability registry secara otomatis.
6. **Tidak ada klaim sukses palsu.** Setiap langkah harus memiliki status dan hasil yang dapat diverifikasi.

## Tahap implementasi

### Fase A — Kontrak agent dan capability registry final

Audit dan standarkan seluruh capability FFM: navigation, read, search/filter, create draft, update, archive, delete, model setup, backup/restore, report, reminder, recurring, activity, goal, asset, liability, receivable, budget, master data, dan security.

Setiap capability harus memiliki ID stabil, schema parameter, prasyarat, data input yang diizinkan, output, risk level, confirmation policy, idempotency key, error contract, dan supported/unsupported status. Capability yang belum memiliki adapter tidak boleh dipresentasikan sebagai eksekusi penuh.

### Fase B — Page context dinamis seluruh halaman

Lengkapi setiap root page dan detail/form penting dengan context yang dapat dibaca agent. Context harus memuat destination, tujuan halaman, data penting yang sedang terlihat, filter/sort, selected item, form fields, field yang kosong/invalid, status loading/empty/error, capability yang tersedia, dan hasil aksi terakhir.

Data context harus diringkas dan diminimalkan. Hanya data yang relevan terhadap perintah yang dikirim ke SLM. Context harus memiliki timestamp/version dan dianggap stale setelah halaman berubah.

### Fase C — Planner dan executor multi-langkah

Ubahlah Action Plan menjadi state machine runtime yang menjalankan langkah secara berurutan: inspect context, navigate, read, transform/compute, prepare draft, validate, preview, await confirmation, execute, verify, dan report.

Plan harus dapat dihentikan, dilanjutkan, dibatalkan, expired, gagal dengan aman, dan tidak mengeksekusi langkah dua kali. Plan ID, step ID, idempotency key, serta status harus tetap konsisten ketika sheet ditutup atau route berubah.

### Fase D — Adapter domain dan full app control

Implementasikan adapter capability nyata secara bertahap. Mulai dari read/search untuk Summary, Transactions, Budget, Analysis, Activity, Goals, Liabilities, Assets, Recurring, Reminders, Backup, dan Data Utama. Setelah read stabil, tambahkan draft, preview, dan executor mutation.

Executor tidak boleh mengakses widget secara rapuh jika use case/domain service tersedia. Semua mutation harus melalui validasi lokal, permission/confirmation gate, transaksi database bila diperlukan, dan verifikasi hasil sesudah write.

Urutan prioritas domain:

1. Summary dan Transactions.
2. Accounts, categories, merchants, tags, dan master data.
3. Budget, recurring transaction, dan reminders.
4. Goals, assets, liabilities, dan receivables.
5. Activity, analysis, reports, backup, diagnostics, dan privacy/security.

### Fase E — Integrasi SLM yang benar-benar planner-aware

Berikan SLM knowledge dasar FFM, context halaman, daftar capability yang sedang tersedia, schema parameter, dan aturan output terstruktur. SLM hanya mengusulkan intent/plan; orchestrator memvalidasi target, parameter, risk, dan capability sebelum menjalankan apa pun.

Perlu dipastikan bahwa general text, query, gambar/struk, navigasi, dan perintah multi-langkah memiliki jalur yang konsisten. Guard untuk PIN, konfirmasi, security, delete, dan operasi sensitif tetap deterministik.

### Fase F — Confirmation, verification, dan recovery

Buat preview yang merangkum semua perubahan final: objek, nilai, sumber/tujuan, tanggal, kategori, dampak, dan jumlah langkah. Pengguna dapat confirm, edit, atau cancel. Confirm hanya berlaku satu kali untuk plan/version yang tepat.

Setelah eksekusi, agent membaca kembali hasil atau status database dan melaporkan apa yang benar-benar terjadi. Partial failure harus menunjukkan langkah yang berhasil/gagal. Rollback hanya boleh ditawarkan jika capability menyatakan dukungan rollback; jika tidak, agent tidak boleh menjanjikan rollback otomatis.

### Fase G — Controlled learning agent

Pisahkan tiga jenis data: memori pengguna, contoh perintah/koreksi, dan workflow/skill aplikasi. Setiap kandidat hasil belajar harus berisi sumber, confidence, scope, versi, tanggal, dan status pending/approved/rejected/retired.

Background processing boleh menganalisis log lokal saat idle, tetapi hasilnya hanya kandidat. Aktivasi workflow harus memerlukan approval pengguna, conflict check, replay pada data aman, versioning, dan rollback. Guard keamanan dan capability registry tidak dapat diubah oleh proses belajar.

### Fase H — Migrasi antarperangkat

Pastikan backup JSON membawa finance data, memories, approved learning examples, unanswered questions, approved workflows, aliases, corrections, chat history bila dipilih, serta schema/knowledge version. Import harus memiliki preview, validasi versi, deteksi konflik, mode merge/replace yang jelas, dan tidak mengaktifkan workflow berisiko tanpa review.

SLM `.ffmbundle` tetap dipindahkan terpisah dari JSON database. Setelah restore pada HP baru, agent harus tetap dapat memahami FFM walaupun model belum dipasang, lalu beralih ke SLM lokal setelah bundle terverifikasi.

## Contoh acceptance scenario

1. Pengguna: “Buka transaksi bulan ini dan cari pengeluaran terbesar.” Agent membuka halaman, membaca context, melakukan read-only query, dan merangkum hasil tanpa konfirmasi.
2. Pengguna: “Siapkan pengeluaran berdasarkan struk ini.” Agent membaca gambar secara lokal, membuat draft, menunjukkan ketidakpastian, dan tidak menyimpan.
3. Pengguna: “Ubah rekeningnya ke rekening utama, lalu simpan.” Agent memperbarui draft, menampilkan preview final, menunggu konfirmasi, menyimpan satu kali setelah confirm, memverifikasi hasil, dan melaporkan ID/hasil lokal.
4. Pengguna: “Kalau saya bilang makan kantor, gunakan kategori Makan dan rekening utama.” Agent membuat kandidat preferensi, meminta approval, lalu menggunakan preferensi tersebut pada perintah berikutnya.
5. Pengguna memindahkan backup ke HP baru. Finance data, memori, workflow approved, dan chat pilihan pengguna dapat dipulihkan; workflow pending/rejected tidak aktif.
6. Pengguna memberi dua perintah berantai. Agent membentuk plan dengan langkah berurutan, bukan menjalankan semua secara paralel tanpa dependency atau confirmation gate.

## Rencana pengujian

### Unit test

Uji registry lookup, schema parameter, risk classification, page-context stale detection, plan state transition, dependency ordering, idempotency, duplicate confirmation, cancellation, expiry, unsupported capability, partial failure, retry, dan result verification.

### Integration test

Gunakan database in-memory untuk menguji read → draft → preview → confirm → execute → verify pada setiap domain prioritas. Pastikan tidak ada perubahan database sebelum confirm dan tidak ada duplicate write setelah confirm/retry.

### SLM contract test

Gunakan fake gateway dan proposal fixture untuk memastikan SLM menerima context yang tepat, output invalid ditolak, target navigation di-allowlist, query tetap deterministic, image proposal melalui validasi, dan fallback tetap aman ketika model unavailable.

### Migration test

Uji export/import dengan memories, examples, unanswered questions, approved workflows, chat history, image metadata, schema version, konflik, corrupted JSON, path traversal, dan bundle SLM terpisah.

### UI/e2e test

Uji perpindahan halaman, plan progress, preview, confirm/edit/cancel, stale route, sheet reopen, thumbnail image, history restore, dan accessibility pada layar portrait 720×1639-like. Widget test sederhana yang tidak menyediakan dependency lengkap tidak dianggap sebagai validasi e2e.

### Device validation

Sebelum release, jalankan smoke test pada perangkat Android arm64 nyata: startup tanpa model, import bundle, load SLM, text inference, image inference, chat history, background/resume, memory pressure, latency, dan temperature. Emulator x86_64 tidak boleh dipakai sebagai bukti SLM arm64.

## Release gate

APK release arm64-only baru boleh dibuat setelah:

- seluruh capability prioritas memiliki adapter nyata atau ditandai unsupported secara eksplisit;
- planner dan executor multi-langkah lulus integration test;
- mutation selalu menunggu confirmation dan idempotent;
- page context dinamis teruji;
- controlled learning dan migration round-trip lulus;
- full analyzer dan test suite lulus tanpa error;
- debug arm64 terbaru lulus dan ABI APK terverifikasi hanya `arm64-v8a`;
- inference pada perangkat arm64 nyata telah diuji atau keterbatasannya disetujui secara eksplisit;
- hanya pada titik terakhir key release dipasang, lalu dibersihkan dari source/archive/log.

## Asumsi dan risiko terbuka

1. Tidak semua fitur FFM mungkin memiliki domain use case yang seragam; adapter harus mengikuti API aktual tiap fitur.
2. Qwen2-VL lokal dapat lebih lambat atau membutuhkan RAM besar pada HP tertentu; planner harus mendukung fallback dan serial inference.
3. “Full access” tidak menghapus permission Android, PIN, atau confirmation gate.
4. Dynamic page context dapat memerlukan perubahan pada banyak halaman dan perlu dilakukan bertahap agar tidak menimbulkan regresi.
5. True fine-tuning bobot SLM bukan bagian dari fase ini; pembelajaran yang ditargetkan adalah memori dan workflow terkontrol.
6. Chat history dapat mengandung informasi sensitif; ekspor harus bersifat opt-in atau memiliki pilihan jelas sebelum dibawa ke perangkat lain.
7. Build lama v0.1.70 bukan bukti source final setelah perubahan berikutnya; release baru wajib dibangun ulang hanya setelah release gate lulus.
