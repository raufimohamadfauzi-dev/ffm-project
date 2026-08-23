# Rencana Perbaikan Sekarang — Respons Agent, Laporan Chat, dan Saran SLM

## Tujuan

Memperbaiki ketidaksesuaian antara capability yang sudah tersedia di kode dan jawaban agent ketika user bertanya “kamu bisa apa?”. Setelah milestone ini, agent harus menjawab berdasarkan capability aktual, bukan klaim statis atau target masa depan. Pada milestone yang sama, report service yang sudah dibuat harus benar-benar masuk ke alur chat, saran berbantuan SLM harus memiliki pipeline fakta → insight → opsi yang aman, dan **kepintaran orchestrator meningkat secara nyata**.

Upgrade kepintaran yang dimaksud bukan sekadar memperpanjang prompt. Orchestrator harus menjadi lapisan yang mampu memahami konteks halaman/user, memecah tujuan menjadi langkah, memilih capability yang tepat, meminta klarifikasi hanya jika perlu, menggabungkan hasil beberapa adapter, memeriksa konflik, memverifikasi hasil, menjelaskan batasan, dan belajar hanya dari feedback yang disetujui. SLM membantu reasoning/extraction/narasi, tetapi policy, fakta angka, izin, dan eksekusi tetap dikendalikan aplikasi.

Semua pekerjaan dilakukan tanpa build APK/debug/release/signing. Setelah validasi selesai, buat source ZIP bersih tanpa key, model GGUF, APK/AAB, cache, build output, log build, atau arsip source asli.

## Perubahan utama

### 1. Upgrade reasoning dan planning orchestrator

Tambahkan `FfmAssistantReasoningContext` yang menggabungkan halaman aktif, capability aktif, user context approved, draft/session yang relevan, hasil adapter sebelumnya, status model, dan batas privacy. Context harus bounded, teredaksi, memiliki timestamp, dan tidak membawa raw database.

Perluas planner menjadi goal-oriented dan multi-step: deteksi tujuan user, pisahkan fakta/permintaan/constraint, pilih adapter, buat dependency graph sederhana, minta klarifikasi untuk field wajib, dan berhenti aman jika confidence rendah atau capability tidak tersedia. Setiap step harus memiliki input/output schema, risk, confirmation policy, timeout/expiry, dan verifier.

Tambahkan memory-aware response policy: memory approved boleh memengaruhi gaya/format dan resolusi alias; memory pending tidak boleh memengaruhi keputusan. Feedback user seperti koreksi kategori, penolakan saran, atau revisi draft harus menjadi event terstruktur untuk candidate learning, bukan auto-training.

Tambahkan explainability contract: agent menyatakan sumber jawaban (`knowledge`, `local data`, `SLM insight`, atau `user-approved memory`), confidence/klarifikasi bila perlu, dan status action (`preview`, `awaiting confirmation`, `executed`, `verified`, `failed`). Uji bahwa SLM tidak dapat memaksa capability atau melewati gate.

### 2. Capability self-description dinamis

Tambahkan service yang menyusun jawaban kemampuan agent dari registry aktual dan status runtime. Jawaban dibagi jelas menjadi:

- **Bisa sekarang**: navigasi, query read-only yang sudah memiliki adapter, laporan preview yang sudah tersedia, dan mutation income/expense/transfer yang melewati preview-confirm-verify;
- **Membutuhkan konfirmasi**: seluruh draft, save, archive, delete, restore, perubahan security/privacy, dan operasi sensitif;
- **Memakai SLM jika siap**: pemahaman bahasa alami, ekstraksi nota/gambar, narasi laporan, dan penjelasan insight;
- **Masih dikembangkan**: adapter domain yang belum terpasang dan callback form yang belum penuh.

Service harus menggunakan registry/capability handler sebagai sumber kebenaran. Jangan menulis daftar kemampuan kedua yang mudah tidak sinkron. Respons harus menjelaskan bahwa angka berasal dari data lokal, SLM bukan sumber angka, tidak ada auto-save, dan user tetap menjadi pemberi keputusan final.

Integrasikan service ke intent `assistantIdentity`, `featureHelp`, dan `listPages`/`bisa apa saja`. Respons boleh tetap deterministic untuk pertanyaan identitas, tetapi isinya harus dinamis dan mencerminkan runtime.

### 2. Integrasi report service ke chat

Perluas intent `exportReport` dengan parameter periode, gaya, modul, anonimisasi, dan format yang dapat divalidasi. Interpreter mengenali variasi seperti laporan bulan ini, laporan bulan lalu, cashflow, budget, target, atau laporan custom.

Di chat:

1. interpreter menghasilkan request laporan;
2. orchestrator memanggil report service lokal;
3. chat menampilkan preview laporan dan modul yang dipakai;
4. SLM, jika siap, menyusun narasi dari JSON lokal tanpa mengubah angka;
5. user dapat memilih copy/share/export melalui jalur UI resmi;
6. penyimpanan atau ekspor final memerlukan aksi eksplisit user.

Jika integrasi file export belum dapat selesai dalam satu milestone, minimal hasil preview dan payload report harus terlihat di chat, bukan hanya membuka halaman Backup. Jangan mengklaim file sudah dibuat sebelum exporter benar-benar menghasilkan berkas.

### 4. Recommendation pipeline aman

Buat model `FfmAssistantRecommendation` yang membedakan `facts`, `insight`, `suggestedActions`, `risk`, dan `expiresAt`. Fakta dihitung deterministic dari adapter lokal. SLM hanya menyusun penjelasan/insight dan opsi bahasa alami dari fakta yang sudah disanitasi.

Mulai dengan read-only rules:

- budget mendekati atau melewati batas;
- cashflow negatif;
- target tertinggal;
- recurring atau reminder mendekati jatuh tempo;
- transaksi tidak biasa berdasarkan ringkasan bounded;
- data master atau model SLM belum siap.

Recommendation harus memiliki deduplication key, dismiss/snooze, batas frekuensi, halaman sumber, dan tidak memanggil mutation. Jika user memilih saran yang mengubah data, buat draft Action Plan dan tampilkan preview/confirmation.

### 4. Self-description dan recommendation tests

Tambahkan test untuk:

- respons kemampuan selalu memuat kemampuan aktual dan gap yang benar;
- capability yang tidak memiliki handler tidak disebut sebagai “bisa sekarang”;
- status SLM siap/belum siap mengubah bagian respons yang relevan;
- request laporan periode/style terurai dengan benar;
- report preview tidak mengubah angka dan tidak langsung menulis;
- recommendation facts berasal dari adapter, deduplication bekerja, dismiss/snooze bekerja, dan tidak ada mutation;
- prompt SLM tidak memuat raw SQL, secret, PIN, atau seluruh rows.

## Urutan implementasi

1. audit API registry, status model, report service, chat session, dan user model;
2. implementasikan reasoning context, goal planner, explainability contract, dan policy status;
3. implementasikan self-description service dan sambungkan ke interpreter;
4. implementasikan parser/request report dan output preview chat;
5. implementasikan model serta rule engine recommendation read-only;
6. sambungkan SLM hanya pada extraction, narasi, dan insight terstruktur;
7. tambahkan feedback event terkontrol untuk candidate learning tanpa auto-approval;
8. tambahkan tests targeted dan full suite;
9. perbarui `PROJECT_CONTEXT.md` dan `docs/implementation_status.md` dengan klaim aktual;
10. buat source ZIP milestone bersih.

## Batasan dan risiko

Report service saat ini menyiapkan JSON/prompt/preview, tetapi belum tentu sudah memiliki file exporter yang dipanggil langsung dari chat. Integrasi harus mempertahankan pemisahan antara preview dan export final. Self-description tidak boleh mengatakan “semua fitur sudah bisa” sebelum adapter domain dan callback form selesai. Recommendation tidak boleh menjadi kanal autosave atau background mutation. Tidak ada build APK dalam milestone ini.

## Kriteria selesai

Milestone dianggap selesai jika pertanyaan “kamu bisa apa?” menghasilkan daftar dinamis yang jujur, reasoning context dan planner memakai konteks user/halaman secara bounded, hasil dan sumber jawaban dapat dijelaskan, permintaan laporan menampilkan preview nyata dari data lokal di chat, saran read-only dapat dibentuk dari facts yang teruji, feedback tidak menjadi auto-learning, semua test lulus, analyzer bersih, dan source ZIP baru tersedia.
