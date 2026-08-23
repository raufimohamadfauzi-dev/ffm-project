# Rencana Fase Berikutnya — Real Capability Adapters dan Workflow Agent Tanpa Build

## Tujuan

Melanjutkan dari fondasi registry, Action Plan, user model, page context, dan SLM gateway menuju orchestrator yang benar-benar dapat mengoperasikan fitur FFM pada level aplikasi. Fokus utama bukan kosmetik UI dan bukan build APK. Fokusnya adalah membuat agent mampu membaca data lokal, menyusun hasil, menyiapkan draft, berhenti pada preview, menjalankan mutation hanya setelah konfirmasi akhir, lalu memverifikasi hasil secara jujur.

Seluruh pekerjaan dilakukan pada source code, test, database in-memory, dan dokumentasi. Tidak boleh menjalankan `flutter build`, Gradle assemble, signing, packaging, atau membuat APK sampai pengguna memberi perintah build terpisah.

## Status awal dan keputusan penting

Fondasi executor telah dikompilasi dan diuji untuk eksekusi serial serta blocking mutation tanpa konfirmasi. Namun executor belum memiliki adapter domain nyata dan UI saat ini masih banyak membuka halaman/form melalui callback. Karena itu fase berikutnya harus menghubungkan executor ke use case/repository FFM secara eksplisit, bukan membuat agent melakukan tap UI atau memberi akses SQL bebas kepada SLM.

Mutation tetap mengikuti kontrak wajib: `Understand → Plan → Prepare → Validate → Preview → Confirm → Execute → Verify`. Tidak ada auto-save, autonomous CRUD, bypass PIN, atau eksekusi workflow pending. SLM hanya mengusulkan intent/parameter terstruktur; orchestrator dan capability adapter yang memvalidasi serta mengeksekusi.

## Tahap 1 — Kontrak runtime executor yang lebih kuat

Perkuat model runtime Action Plan agar setiap step memiliki dependency, input terfilter, output ringkas, error, retry policy, idempotency key, dan status yang dapat dipulihkan. Tambahkan pembeda antara step navigasi, read, draft, preview, confirm, execute, dan verify sehingga status `completed` tidak diberikan hanya karena form berhasil dibuka.

Tambahkan aturan bahwa mutation plan hanya dapat masuk `executing` melalui controller setelah confirmation token yang valid. Plan read-only boleh berjalan langsung. Plan yang sudah terminal, expired, cancelled, atau pernah berhasil dieksekusi tidak boleh dijalankan ulang. Error step harus tersimpan pada plan dan tidak boleh hilang dari hasil executor.

## Tahap 2 — Adapter read-only prioritas

Buat registry handler aplikasi yang terpisah dari UI. Prioritas pertama adalah capability read untuk Summary, Transactions, Accounts, Categories, Budget, dan Analysis. Handler menggunakan use case/repository resmi FFM, melakukan agregasi lokal, dan hanya mengembalikan DTO ringkas yang aman untuk chat atau step berikutnya.

Implementasikan resolver entity lokal untuk nama rekening, kategori, target, dan periode. Resolver harus mengembalikan `unique`, `ambiguous`, atau `notFound`; agent harus bertanya jika ada lebih dari satu kemungkinan. Jangan mengirim daftar mentah database ke SLM. Buat redaction/minimization untuk hasil yang diteruskan ke reasoning engine.

## Tahap 3 — Alur read → draft → preview

Hubungkan interpreter/planner dengan executor untuk contoh end-to-end: membaca ringkasan transaksi atau transaksi terfilter, menyusun ringkasan, lalu membuat draft transaksi dari input teks atau gambar lokal. Draft harus divalidasi menggunakan validator yang sudah ada, menampilkan field kurang, dan berhenti pada preview.

Perbaiki lifecycle UI agar membuka form tidak menandai mutation sebagai selesai. Form harus mengembalikan hasil yang jelas: cancelled, edited, confirmed-and-saved, atau failed. Hanya hasil `confirmed-and-saved` yang boleh memanggil controller untuk melanjutkan execute/verify. Jika user keluar dari form atau menekan batal, plan tetap cancelled atau awaiting confirmation, bukan completed.

## Tahap 4 — Mutation adapter domain pertama

Implementasikan secara bertahap adapter nyata untuk pemasukan, pengeluaran, dan transfer menggunakan use case transaksi yang sudah ada. Setiap adapter wajib memiliki validasi parameter, resolver rekening/kategori, preview payload yang terbaca manusia, idempotency key, eksekusi satu kali, serta verifier yang membaca kembali hasil lokal tanpa menyerahkan raw database ke SLM.

Setelah transaksi dasar stabil, lanjutkan recurring transaction, lalu domain target, asset, liability, receivable, dan budget. Delete, perubahan sensitif, backup/restore, privacy, PIN, dan diagnostics tetap diperlakukan sebagai capability berisiko tinggi dengan confirmation policy khusus dan tidak boleh digeneralisasi sebelum kontraknya diuji.

## Tahap 5 — Workflow multi-langkah dan recovery

Tambahkan dependency antar-step sehingga output read dapat menjadi input draft, dan output draft dapat menjadi input preview. Implementasikan pause, cancel, expiry, retry aman, partial failure, dan recovery. Retry tidak boleh menggandakan mutation; verifier harus membedakan `already applied`, `not applied`, dan `unknown`.

Buat satu integration scenario sebagai baseline: “baca pengeluaran bulan ini, rangkum, siapkan transaksi baru, tampilkan preview, minta konfirmasi, simpan sekali, lalu verifikasi.” Skenario harus bekerja dengan database in-memory dan fake/local handler sebelum domain lain diperluas.

## Tahap 6 — Page context dinamis

Setelah adapter read pertama stabil, isi page context dinamis untuk Summary, Transactions, Budget, dan Analysis terlebih dahulu. Context mencakup tujuan halaman, periode/filter aktif, jumlah hasil, state loading/error, item terpilih yang telah direduksi, serta capability aktif. Context tidak boleh memasukkan PIN, token, atau data mentah yang tidak relevan.

Tambahkan test stale snapshot: context lama tidak boleh dipakai untuk mengeksekusi mutation setelah filter atau item berubah. SLM menerima context sebagai informasi terbatas, bukan sebagai otorisasi.

## Tahap 7 — Controlled learning dan proactive assistance setelah executor aman

Jangan mengaktifkan background learning otomatis sebelum executor dan UI approval stabil. Lanjutkan dengan UI daftar candidate profile/preference/workflow yang menampilkan alasan, sumber, confidence, versi, dan dampak. User dapat approve, reject, edit, archive, dan rollback. Candidate pending tidak boleh masuk prompt sebagai aturan aktif dan tidak boleh dieksekusi.

Saran proaktif tetap read-only, opt-in/opt-out, dibatasi frekuensinya, dan memiliki alasan yang dapat dijelaskan. Observasi harus disanitasi dan tidak menyimpan isi transaksi mentah sebagai memory tanpa persetujuan.

## Tahap 8 — Migrasi agent knowledge

Pertahankan memory/user model/learning candidate dalam backup `ffm-v23-full`, tetapi pisahkan status approved, pending, rejected, dan archived saat preview/import. Chat history tetap opt-in; image path tidak disertakan kecuali suatu saat file gambar dipaketkan secara aman. Tambahkan test round-trip dan konflik import tanpa mengaktifkan candidate pending secara diam-diam.

## Pengujian wajib sebelum fase dianggap selesai

| Area | Pengujian |
|---|---|
| Executor | Serial order, dependency, status transition, cancellation, expiry, retry, partial failure, missing handler, exception, terminal idempotency |
| Confirmation | Mutation diblokir tanpa token, token salah/stale ditolak, confirmation ganda tidak menggandakan eksekusi |
| Resolver | Entity unik, ambigu, tidak ditemukan, alias approved, filter/periode invalid |
| Read adapters | Summary, transactions, accounts, categories, budget, analysis memakai database in-memory |
| Mutation adapters | Income, expense, transfer: preview → confirm → execute sekali → verify |
| Workflow | Read output menjadi input draft, draft invalid berhenti, form cancel tidak complete |
| Security | Tidak ada raw SQL ke SLM, unknown capability ditolak, prompt injection-like text tidak mengubah allowlist, PIN/token tidak masuk context |
| Page context | Dynamic filter, minimization, stale snapshot, selected entity, error/loading state |
| Learning | Candidate approval/rejection/archive/rollback, pending tidak aktif, version conflict |
| Backup | Optional chat history, image path filtering, memory/candidate status round-trip |
| Kualitas kode | `dart format`, `flutter analyze lib test`, targeted tests setelah setiap tahap, full `flutter test` setelah milestone |

## Urutan implementasi yang disarankan

1. Runtime executor dan hasil/error step.
2. Registry adapter read-only dan resolver entity.
3. Integration test read → plan → execute read → output.
4. Draft/preview lifecycle dan callback form yang jujur.
5. Adapter income/expense/transfer dengan confirmation dan verify.
6. Workflow multi-langkah serta recovery/idempotency.
7. Page context dinamis prioritas.
8. UI controlled learning dan migrasi conflict handling.
9. Full validation tanpa build.

## Asumsi dan risiko terbuka

Asumsi utama adalah use case/repository transaksi yang ada dapat dipanggil dari layer adapter tanpa perubahan schema Drift besar. Jika API domain tidak seragam, adapter akan dibuat per fitur dengan kontrak DTO yang sama, bukan memaksakan satu repository generik.

Risiko terbesar adalah lifecycle form lama belum mengembalikan event confirmation ke Action Plan; ini harus dibereskan sebelum mengklaim full app control. Risiko lain meliputi entity ambigu, crash di tengah mutation, stale page context, performa SLM pada perangkat kecil, dan kemungkinan data sensitif masuk ke prompt. Semua risiko tersebut ditangani dengan allowlist, minimization, confirmation gate, verifier, dan test negatif.

## Kriteria keberhasilan fase ini

Fase ini dianggap berhasil jika minimal Summary/Transactions/Accounts/Analysis dapat dibaca melalui adapter, income/expense/transfer dapat melalui alur draft-preview-confirm-execute-verify, duplicate execution ditolak, error dilaporkan tanpa klaim sukses palsu, dan integration test in-memory lulus. Setelah itu domain lain dapat diperluas dengan pola yang sama. Keberhasilan fase ini tidak mencakup build APK; build tetap menjadi fase terpisah yang hanya dimulai atas perintah eksplisit pengguna.
