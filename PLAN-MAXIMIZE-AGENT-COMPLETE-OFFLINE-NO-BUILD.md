# Rencana Utama — Memaksimalkan Agent FFM Menjadi Asisten Offline Nyata

## Tujuan

Mengembangkan orchestrator FFM dari fondasi katalog, read adapter, dan tiga mutation adapter menjadi **asisten/operator aplikasi lokal** yang memahami seluruh halaman, fitur, alur, dan struktur database FFM; dapat membaca dan merangkum data; membuat laporan sesuai permintaan; memberi saran berbantuan Qwen2-VL lokal; mengingat user secara terkontrol; serta menjalankan workflow lintas halaman dengan preview, confirmation, idempotency, dan verifikasi.

Agent bukan bot rule-based yang menggantikan SLM. SLM lokal berperan sebagai reasoning/extraction engine, sedangkan orchestrator menjadi pengendali yang menyediakan konteks terpilih, memilih capability, memvalidasi keluaran, menjalankan use case resmi, dan menjaga batas keamanan.

Semua pekerjaan dilakukan tanpa build APK/debug/release/signing. Setelah milestone selesai dan validasi lulus, dibuat source ZIP bersih yang tidak memuat key, model, APK/AAB, cache, build output, log rahasia, atau arsip source asli.

## Prinsip kerja agent

> **Understand → Observe → Plan → Resolve → Prepare → Preview → Confirm → Execute → Verify → Explain → Learn only with approval**

SLM tidak diberi raw SQL, seluruh database, PIN, token, atau data sensitif yang tidak dibutuhkan. SLM mengembalikan proposal terstruktur yang melewati schema validation dan allowlist. Tidak ada auto-save, autonomous financial mutation, silent upload, cloud fallback setelah mode offline terverifikasi, atau pembelajaran tanpa persetujuan.

## Kemampuan akhir yang dituju

### 1. Memahami seluruh aplikasi FFM

Buat runtime knowledge registry yang versioned dan bounded, tidak hanya prompt Markdown. Registry memuat:

- identitas dan tujuan FFM;
- seluruh 24 destination dan alias bahasa alami;
- fungsi setiap halaman dan subfitur;
- prasyarat, input, output, dan batasan setiap workflow;
- relasi domain: transaksi–rekening–kategori–budget–target–aset–utang/piutang–recurring–reminder–aktivitas–audit;
- aturan bisnis seperti transfer bukan income/expense, biaya admin sebagai expense terpisah, dan draft bukan persistence;
- capability risk, parameter schema, confirmation policy, dan verifier;
- database schema map yang hanya menjelaskan relasi/label aman, bukan mengirim seluruh rows ke SLM.

Tambahkan self-check knowledge: agent dapat menjawab “aplikasi ini apa”, “langkah pertama apa”, “setelah input transaksi apa yang terjadi”, “menu ini untuk apa”, dan “data apa yang terkait” dari registry lokal.

### 2. Membaca seluruh domain melalui adapter aman

Perluas adapter dari `summary`, `transactions`, `accounts`, `categories`, dan `analysis` ke:

| Domain | Read capability yang dituju |
|---|---|
| Budget | Daftar budget, periode, alokasi, pemakaian, status alert |
| Goals | Target, progress, kontribusi, sisa target |
| Assets | Aset aktif, nilai, tipe, lokasi |
| Liabilities/Receivables | Saldo, cicilan, jatuh tempo, status |
| Recurring | Jadwal, status, next occurrence, histori proses |
| Reminders | Pengingat aktif, jadwal, status notifikasi |
| Activity | Session, durasi, checkpoint, ringkasan log |
| Audit | Aktivitas mutation yang aman untuk dibaca user |
| Backup/Privacy/Offline/Diagnostics | Status konfigurasi dan kesehatan lokal, tanpa secret |
| Database Structure | Skema/versi/migrasi dan status integritas, tanpa raw data |

Setiap adapter mengembalikan DTO/ringkasan bounded, mendukung filter aktif halaman, redaction, pagination/limit, dan error yang dapat dijelaskan.

### 3. Membuat laporan sesuai permintaan user

Bangun report orchestration layer yang menerima permintaan seperti laporan harian/mingguan/bulanan, laporan pemasukan-pengeluaran, cashflow, budget variance, target progress, aset versus kewajiban, recurring upcoming, aktivitas, audit, dan laporan custom berdasarkan periode/filter.

Alur laporan:

1. Interpreter mengklasifikasikan jenis laporan dan periode.
2. Orchestrator memilih adapter data yang diperlukan.
3. Adapter mengagregasi data lokal secara deterministic.
4. SLM membantu menyusun narasi, insight, judul, dan rekomendasi dari ringkasan teredaksi.
5. User mendapat preview struktur laporan sebelum ekspor atau penyimpanan.
6. Exporter membuat Markdown/JSON/CSV atau format yang sudah didukung aplikasi; PDF hanya jika user meminta.
7. Laporan tersimpan hanya setelah aksi eksplisit user jika memang ada persistence.

Laporan harus bisa dibuat dari chat, halaman laporan, dan kelak widget sebagai handoff aman. SLM tidak menghitung angka utama secara bebas; angka berasal dari aggregator lokal.

### 4. Memberi saran berbantuan SLM

Buat recommendation pipeline yang memisahkan fakta, interpretasi, dan saran. Fakta berasal dari adapter lokal; SLM menyusun penjelasan dan pilihan; keputusan tetap milik user.

Kategori saran yang dituju meliputi anomali pengeluaran, budget mendekati batas, cashflow negatif, target tertinggal, recurring akan jatuh tempo, data master belum lengkap, kualitas data, dan langkah setup berikutnya. Saran proaktif hanya read-only, bounded, tidak berulang mengganggu, memiliki alasan, timestamp, dismiss/snooze, dan tidak mengubah database.

Untuk saran yang berpotensi mutation, agent hanya menawarkan plan dan preview; tidak membuat transaksi/anggaran/pengingat otomatis.

### 5. Menyelesaikan mutation semua domain

Setelah income/expense/transfer stabil, tambahkan adapter prepare/save/verify untuk goal, goal deposit/usage, asset, liability, receivable, budget, recurring transaction, reminder, activity, dan master data.

Setiap adapter wajib memakai use case resmi, resolver entity lokal, schema validation, preview, explicit confirmation, idempotency key, audit record, dan read-back verifier. Mutation sensitif seperti delete, archive, reset, PIN, privacy, backup restore, dan perubahan konfigurasi harus memiliki risk level lebih tinggi serta confirmation yang lebih eksplisit.

### 6. Workflow lintas halaman

Agent harus dapat merencanakan rangkaian seperti:

- cek kesiapan data master → buka/setup rekening/kategori → kembali ke transaksi;
- baca transaksi → identifikasi pola → buat preview budget;
- baca target → siapkan setoran → pilih rekening → preview → confirm;
- cek recurring → tampilkan yang jatuh tempo → siapkan transaksi tanpa autosave;
- buat laporan → tampilkan insight → tawarkan export;
- baca error/diagnostic → sarankan perbaikan → hanya membuka halaman perbaikan.

Action Plan harus menyimpan dependency antar-step, output aman antar-step, status per step, cancel/expiry, retry, verifier, dan alasan ketika workflow berhenti.

### 7. Mengenal user dan controlled learning

Perluas user model lokal dengan profile, alias, preferensi bahasa/format laporan, kebiasaan yang disetujui, dan konteks household. Semua fakta personal harus explicit approval, dapat diedit/dihapus, memiliki scope, confidence, source, timestamp, dan status archived.

Controlled learning harus mencakup:

- observation opt-in dan sanitization;
- candidate workflow yang pending secara default;
- layar review perbedaan sebelum approval;
- approve/reject/archive/rollback/version;
- tidak memakai candidate pending untuk eksekusi;
- import/export lintas perangkat dengan status approval tetap terjaga;
- tidak memasukkan PIN, token, nomor rekening penuh, atau data raw sensitif ke knowledge pack.

### 8. Widget dan akses cepat

Pertahankan widget sebagai gateway offline. Widget dapat menampilkan cache ringkasan dan shortcut perintah aman. Perintah bebas atau mutation harus membuka aplikasi dan masuk ke orchestrator preview/confirmation. Jangan menjalankan Qwen2-VL atau mutation financial langsung dari background widget.

### 9. UI agent yang jelas

Chat UI harus menampilkan perbedaan antara:

- jawaban dari knowledge registry;
- data yang baru dibaca dari database;
- saran dari SLM;
- draft yang belum tersimpan;
- menunggu konfirmasi;
- sedang mengeksekusi;
- berhasil dan sudah diverifikasi;
- gagal atau dibatalkan.

Tambahkan progress Action Plan, daftar step, alasan blocked, tombol preview/edit/confirm/cancel, dan hasil verify. Form resmi tetap menjadi boundary validasi jika lebih aman daripada direct adapter.

## Fase pengerjaan

### Fase A — Runtime knowledge dan schema registry

Bangun knowledge registry versioned, alias halaman, domain relation map, database schema map bounded, capability schema, dan self-check tests.

### Fase B — Adapter read semua domain

Implementasikan adapter read untuk budget, goals, assets, liabilities/receivables, recurring, reminders, activity, audit, diagnostics, privacy, backup status, dan database structure. Integrasikan filter/page context dan redaction.

### Fase C — Report orchestration

Implementasikan report request schema, aggregator deterministic, narrative SLM prompt, preview, export Markdown/JSON/CSV, dan report tests.

### Fase D — Recommendation/proactive pipeline

Implementasikan fact extraction lokal, recommendation schema, SLM explanation, deduplication, dismiss/snooze, dan safety tests.

### Fase E — Mutation dan verifier seluruh domain

Implementasikan adapter mutation per domain secara bertahap, mulai dari goal/asset/liability/receivable, kemudian budget/recurring/reminder/activity/master data. Setiap domain harus lulus preview-confirm-execute-verify sebelum masuk domain berikutnya.

### Fase F — Cross-page orchestrator dan UI lifecycle

Satukan navigation handoff, form callback, Action Plan persistence/in-memory lifecycle, progress UI, cancellation, expiry, retry, and verification. Pastikan membuka halaman tidak dianggap selesai.

### Fase G — User model dan controlled learning

Bangun UI training/privacy untuk review profile, preference, alias, dan workflow candidate; tambahkan import/export semantics, rollback, conflict resolution, dan audit.

### Fase H — Validasi dan arsip

Jalankan formatter, analyzer, targeted tests, full test, audit source untuk secret/model/build output, update dokumentasi status, lalu buat source ZIP milestone. Tidak ada build APK.

## Test plan utama

| Area | Validasi minimum |
|---|---|
| Knowledge | Semua destination/domain/alias ditemukan, self-check menjawab fungsi dan alur utama |
| Database | Semua 31 tabel hanya diakses melalui adapter/aggregator yang allowlisted; tidak ada raw DB ke prompt |
| Read adapter | Empty state, populated state, filter, pagination/limit, redaction, error |
| Report | Angka berasal dari aggregator, periode benar, narrative SLM tidak mengubah angka, export preview |
| Suggestion | Fakta/saran terpisah, dedupe, dismiss, no mutation |
| Mutation | Preview, confirmation, idempotency, verify, cancel, expiry, duplicate callback |
| Cross-page | Dependency step, handoff, form cancel/save callback, no false completion |
| User model | Approval, edit, delete, archive, scope, backup/restore, pending candidate inactive |
| Widget | Shortcut allowlist, cache safe, mutation opens app/confirmation |
| Offline | Tidak ada cloud fallback setelah setup offline, model belum siap ditampilkan jujur |
| Safety | Unknown capability, extra parameters, prompt injection text, secret leakage, raw SQL attempts |

## Kriteria keberhasilan akhir

Agent boleh disebut **asisten/operator offline FFM yang matang** jika:

1. memahami seluruh halaman, fitur, domain, relasi, dan schema melalui registry bounded;
2. dapat membaca seluruh domain melalui adapter dan menghasilkan ringkasan benar;
3. dapat membuat laporan sesuai permintaan dengan angka deterministic dan narasi SLM;
4. dapat memberi saran proaktif berbasis fakta lokal tanpa mutation otomatis;
5. dapat menjalankan workflow lintas halaman dan semua mutation melalui preview-confirm-execute-verify;
6. mengenali user hanya dari memory yang disetujui dan belajar melalui controlled learning;
7. dapat di-backup/restore dengan status learning dan approval yang benar;
8. memiliki status/error/verify yang jujur pada UI;
9. lulus analyzer dan full tests tanpa build APK;
10. menghasilkan source ZIP bersih pada akhir setiap milestone.

## Risiko dan keputusan

Risiko terbesar adalah luasnya domain dan perbedaan API use case antar halaman. Implementasi harus bertahap dan tidak membuat generic write adapter yang mem-bypass model domain. SLM boleh membantu reasoning, tetapi tidak boleh menjadi sumber kebenaran angka atau izin mutation. Validasi Android native Qwen/widget baru dilakukan ketika user memberikan perintah build/test perangkat secara eksplisit; sampai saat itu semua validasi bersifat source/Dart/database in-memory.
