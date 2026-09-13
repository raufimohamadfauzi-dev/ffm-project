# Audit Draft Assistant: Database dan UI

Tanggal audit: 2026-09-13  
Status: audit baseline selesai, implementasi perbaikan bertahap sedang berjalan.

## Urutan Eksekusi Wajib

- [ ] Selesaikan seluruh checklist file induk ini dari Phase 0 sampai Phase 6.
- [ ] Jalankan regression suite penuh dan validasi akhir file induk.
- [ ] Setelah file induk selesai, baru mulai `docs/vehicle_fuel_utility_migration_plan.md`.
- [ ] Selama file induk belum selesai, jangan melompat mengerjakan token listrik,
  BBM, kendaraan, atau meter listrik.

Catatan progress: implementasi awal kontrak canonical sudah dimulai pada
planner, form prefill, parser transaksi, dan resolver referensi dasar. Status
milestone tetap belum selesai sampai executor, verifier, dan seluruh reference
type diuji end-to-end.

## Progress Checklist

Gunakan checklist ini sebagai sumber status pekerjaan. Item hanya boleh diubah
menjadi `[x]` setelah implementasi, test, dan verifikasi database/UI selesai.

### Milestone Utama

- [x] Audit baseline draft, database, executor, dan UI selesai.
- [x] Baseline test targeted lulus: 53 test.
- [x] Baseline analyzer modul terkait bersih.
- [ ] Phase 0: kontrak canonical field dan reference resolver.
- [x] Phase 1: pemasukan, pengeluaran sederhana, pengeluaran kompleks, transfer.
- [ ] Phase 2: target keuangan dan setor/pakai target.
- [ ] Phase 3: aktivitas, timer, child activity, dan Catatan Harian.
- [ ] Phase 4: anggaran user-specific.
- [ ] Phase 5: pengingat, jam, recurrence, dan nada dering.
- [ ] Phase 6: hutang, piutang, aset, master data, task, routine, schedule,
  recurring transaction, AgroTrack, dan monitoring job.
- [ ] Dedicated LLM draft kendaraan/BBM dan listrik/PLN.
- [ ] Regression suite penuh lulus.
- [ ] Analyzer `flutter analyze lib test` lulus.
- [ ] Release ARM64 tetap dapat dibangun.

### Current Work Queue

- [ ] Buat matriks canonical field per jenis draft.
- [x] Pastikan planner tidak menghilangkan atau menimpa canonical field dengan
  `formValues`.
- [x] Pastikan mapper prefill form memprioritaskan field canonical dan tetap
  mempertahankan metadata UI-only.
- [x] Tambahkan resolver deterministic untuk account, category, merchant, tag,
  goal, dan parent activity.
- [x] Tambahkan resolver exact case-insensitive untuk lookup account, category,
  dan merchant pada adapter.
- [x] Hubungkan parser `daily_note` ke draft canonical.
- [x] Simpan dan verifikasi `dailyNote` pada tabel `daily_notes`, bukan
  `activity_sessions`.
- [x] Ganti notification ID draft pengingat dari `hashCode` ke helper stable.
- [x] Samakan executor setor/pakai target dengan form: rekening, tanggal, signed
  expense transaction, dan guard saldo target.
- [x] Sambungkan create budget ke executor dan verifier tanpa nama/periode
  hard-code; validasi kategori aktif dan household.
- [x] Tambahkan test database create budget dan readback verifier.
- [x] Tolak rincian item transaksi yang memiliki format, harga, atau jumlah
  tidak valid; jangan mengubahnya diam-diam menjadi daftar kosong.
- [x] Tambahkan fixture JSON LLM dan expected database row untuk tiap draft yang
  didukung proposal parser canonical (`test/fixtures/assistant_phase0_*`).
- [x] Tambahkan regression test parser/planner/prefill untuk memastikan canonical
  field tidak tertimpa dan field transaksi penting tidak hilang.

### Completion Rule

Setiap fase wajib memenuhi semua kondisi berikut sebelum checklist fase dicentang:

- [ ] Parser single dan multi proposal sesuai schema.
- [ ] Draft edit mempertahankan field yang tidak diubah.
- [ ] Validator memblokir field wajib dan reference ambigu.
- [ ] Preview menampilkan field yang benar-benar akan disimpan.
- [ ] Executor menyimpan ke tabel dan kolom yang tepat.
- [ ] Verifier membaca kembali row dan relasi dari database.
- [ ] Retry idempotent dan payload berbeda ditolak.
- [ ] Test positif, negatif, dan UI terkait lulus.

## Kesimpulan Eksekutif

Draft saat ini **belum dapat dianggap sama persis dengan database dan form UI**.
Masalah terbesar bukan pada kartu preview, tetapi pada kontrak yang berbeda antara
LLM JSON, `FfmAssistantDraft`, action planner, validator, executor, repository,
dan form halaman.

Prioritas tertinggi:

1. Catatan Harian (`daily_note`) belum berjalan end-to-end dan berisiko tersimpan
   sebagai aktivitas.
2. Pembuatan Anggaran ditawarkan oleh prompt/parser tetapi sengaja ditolak oleh
   executor; implementasi `_saveBudget` yang ada tidak terhubung dan membuang
   field penting.
3. Setor/pakai Target menyimpan transaksi dengan semantik amount/type/account
   yang tidak sama dengan form Target dan kemungkinan merusak saldo rekening.
4. Draft transaksi belum memiliki field kanonis untuk seluruh kolom form/database,
   terutama tag, item, pajak, diskon, attachment, dan relasi source.
5. Draft aktivitas berjalan belum membawa semua informasi nested activity secara
   konsisten; UI sebenarnya sudah mendukung child session.
6. Draft pengingat kehilangan nada dering dan preview hanya menampilkan tanggal,
   walaupun UI database sudah menyimpan jam serta sound.

## Ruang Lingkup dan Sumber Kebenaran

Sumber kebenaran yang harus dipakai saat perbaikan:

- Draft domain: `lib/features/assistant/domain/ffm_assistant_models.dart`
- Parser proposal: `lib/features/assistant/data/ffm_assistant_proposal_json_service.dart`
- Planner: `lib/features/assistant/domain/ffm_assistant_action_planner.dart`
- Validator: `lib/features/assistant/domain/ffm_assistant_draft_validator.dart`
- Executor: `lib/features/assistant/data/ffm_assistant_capability_adapters.dart`
- Database schema: `lib/core/database/tables.dart`
- Form transaksi: `lib/features/transaction/presentation/pages/transaction_form_page.dart`
- Form transfer: `lib/features/transaction/presentation/widgets/transfer_form_dialog.dart`
- Form target: `lib/features/transaction/presentation/pages/goal_contribution_form_page.dart`
- UI aktivitas: `lib/features/activity/presentation/pages/activity_page.dart`
- UI pengingat: `lib/features/reminder/presentation/pages/reminder_page.dart`
- UI anggaran: `lib/features/budget/presentation/pages/budget_page.dart`

Database tetap authoritative. LLM hanya mengusulkan nilai; ID, lookup,
validasi, business rule, penyimpanan, dan verifikasi dilakukan aplikasi.

## Matriks Audit

| Draft | Status saat ini | Kesesuaian DB/UI | Temuan utama |
|---|---|---|---|
| Pemasukan | Berjalan sebagian | Tidak persis | Amount, rekening, kategori, pihak, lokasi, nota tersimpan; tanggal dapat fallback ke waktu eksekusi; `incomeSource` belum menjadi relasi source yang tegas; tag/item/attachment belum menjadi field kanonis draft. |
| Pengeluaran sederhana | Berjalan sebagian | Tidak persis | Amount menjadi negatif dan rekening/kategori dicari; merchant boleh hilang tanpa error; tanggal fallback; tag baru hanya lewat `formValues`; field nota kompleks belum divalidasi konsisten. |
| Pengeluaran kompleks/struk | Parsial | Belum aman | Parser menerima item JSON dengan validasi minimal; item invalid dapat diam-diam menjadi kosong; tax/discount tidak ikut dihitung executor; paid/change dan total tidak divalidasi matematis; attachment tidak diteruskan planner. |
| Transfer | Paling dekat | Sebagian besar sesuai | Form memiliki asal, tujuan, amount, fee, tanggal, catatan dan executor membuat fee transaction; validasi memakai nama bukan ID, saldo belum dicek, dan preview tidak selalu menampilkan fee sebagai field utama. |
| Target baru | Berjalan sebagian | Tidak persis | Parser memberi default nominal/tanggal; validator hanya wajib nama; target date yang diwajibkan alur form belum diwajibkan validator; category/note belum dipetakan penuh ke tabel `goals`. |
| Setor/pakai Target | Berisiko salah | Tidak sesuai | Executor tidak memakai rekening draft, memakai `now` bukan tanggal draft, memasukkan amount positif untuk kedua tipe, dan `goalDeposit` diberi type `expense` sedangkan usage `income`; tidak ada guard saldo target sebelum mutasi. |
| Aktivitas catat | Berjalan sebagian | Tidak persis | Sudah menulis `activitySessions`, mode/category dapat dipakai, tetapi field mode entity diturunkan dari `kind`; mode eksplisit draft dapat hilang. |
| Aktivitas timer/berjalan | Parsial | Belum sesuai kebutuhan | Timer selalu mulai saat eksekusi sehingga tanggal mulai draft diabaikan; `parentSessionId` tersedia di UI, tetapi parser/draft/planner belum menjadi kontrak utama untuk menambah child ke aktivitas aktif. |
| Catatan Harian | Rusak end-to-end | Tidak sesuai | Prompt memakai `daily_note`, parser tidak mengenali tipe tersebut; adapter mengarahkan `dailyNote` ke `_saveActivity`, sehingga dapat masuk ke `activitySessions`, bukan tabel `dailyNotes`. |
| Anggaran | Tidak bisa create | Tidak sesuai | Prompt/parser membuat draft, validator hanya memeriksa amount, executor menolak `budget`; `_saveBudget` tidak terpakai, hard-code nama/periode, dan mengabaikan category IDs, note, alert, rollover, serta tanggal. |
| Pengingat | Parsial | Tidak persis | Parser membawa datetime, tetapi default otomatis `createdAt + 1 jam` bertentangan dengan aturan klarifikasi; executor membuang sound/source/origin dan memakai `id.hashCode.abs()`; weekdays/recurrence belum divalidasi ketat. |
| Hutang/piutang/aset/master data | Di luar fokus utama, perlu audit fase berikutnya | Belum dibuktikan penuh | Sudah ada parser/executor terpisah, tetapi perlu matriks field per entity dan integration test create/update/archive seperti draft utama. |

## Detail Per Kontrak

### 1. Transaksi Pemasukan dan Pengeluaran

Kolom database transaksi yang relevan:

- `type`, `categoryId`, `merchantId`, `accountId`, `goalId`, `amount`, `date`
- `recordedAt`, `note`, `owner`, `partyName`, `source`, `sourceId`
- `recurringTransactionId`, `location`, `linkedActivityId`
- `receiptRawText`, `receiptNumber`, `receiptPaidAmount`, `receiptChangeAmount`
- relasi terpisah `transaction_items`, `transaction_tags`, dan `attachments`

Form transaksi juga memiliki category ID, merchant ID, account ID, party,
source/source ID, recurring transaction, linked activity, tag master, item,
receipt number, paid/change, tax, discount, lokasi, dan attachment.

Kontrak draft saat ini menyimpan sebagian field sebagai properti (`amount`,
`partyName`, `merchantName`, `location`, item, receipt), tetapi sebagian lain
sebagai string bebas di `formValues`. Ini membuat preview terlihat lengkap
sementara planner atau executor dapat kehilangan data.

Gap yang harus ditutup:

- Tambahkan representasi kanonis untuk `tags`, `newTags`, `newMerchant`,
  `sourceId`, `recurringTransactionId`, `linkedActivityId`, attachment, tax,
  discount, dan receipt raw text; jangan hanya mengandalkan key bebas.
- Validasi item: nama wajib, qty > 0, price >= 0, total item konsisten dengan
  subtotal/nominal.
- Definisikan satu formula total: subtotal + tax - discount = amount, dan
  `paidAmount - change = amount` bila keduanya diberikan.
- Pastikan expense/income hanya memakai kategori bertipe yang benar dan lookup
  menghasilkan satu ID unik sebelum konfirmasi.
- Putuskan aturan merchant: jika LLM menyebut merchant yang belum ada, draft
  harus eksplisit memilih `buat merchant baru` atau `tanpa merchant`, bukan
  diam-diam menghilangkan merchant.
- Tanggal wajib dipertahankan dari draft sampai database; fallback waktu kini
  hanya boleh terjadi pada parser jika aturan produk memang menyatakannya.

### 2. Transfer

Transfer database membutuhkan `fromAccountId`, `toAccountId`, amount, admin fee,
date, recordedAt, note, source, dan fee transaction opsional. Form transfer
sudah memetakan nama draft menjadi ID account dan menolak account yang sama.

Yang sudah benar: amount, fee, tanggal, catatan, lookup account, dan fee sebagai
transaksi biaya ditangani oleh alur transfer.

Yang harus diperbaiki: resolver draft sebaiknya menghasilkan/menyimpan account ID
setelah lookup, validasi harus mendeteksi nama ambigu sebelum form, saldo sumber
dan total amount + fee harus diverifikasi, dan preview harus menampilkan semua
field yang akan masuk ke tabel transfer.

### 3. Target Keuangan

Tabel `goals` memiliki `name`, `targetAmount`, `currentAmount`, `targetDate`,
`categoryId`, active, dan timestamps. Form kontribusi juga mewajibkan target ID,
rekening ID, nominal, tanggal, dan mencegah pemakaian melebihi saldo target.

Draft hanya membawa nama target/rekening. Executor kontribusi belum mengikuti
kontrak form. Perbaikan wajib dilakukan sebagai transaksi atomik: resolve goal
dan account unik, gunakan tanggal draft, simpan accountId/goalId/category/source
sesuai aturan domain, update currentAmount, cek batas usage, lalu verifikasi
saldo dan transaksi yang sama.

### 4. Aktivitas, Timer, dan Child Activity

Database `activity_sessions` memiliki category ID/label, kind, mode, parent,
group, subject, started/ended/scheduled/due date, status, completion, priority,
notes, dan archive. UI `ActivityPage` sudah membedakan Timer dan Catat saja,
memiliki kategori bertipe `activity`, serta dapat memulai child session dengan
`parentSessionId`.

Saat ini draft dapat membawa mode, category, group, subject, dan tanggal, tetapi:

- executor timer mengganti `startedAt` dengan waktu eksekusi;
- `effectiveMode` entity dihitung dari kind dan mengabaikan mode tersimpan;
- child activity belum memiliki field draft/parser yang jelas dan konsisten;
- catatan harian, aktivitas catatan, task, dan schedule masih diarahkan ke
  helper `_saveActivity` yang sama walaupun tabel/domain-nya berbeda.

Kontrak target: `activity`, `dailyNote`, `task`, dan `schedule` harus menjadi
empat capability/database adapter berbeda. Untuk nested activity, draft harus
memuat `parentSessionId` atau resolusi target unik, memastikan parent aktif,
memastikan category activity valid, lalu insert child dengan parent ID yang sama.

### 5. Catatan Harian

Tabel `daily_notes` membutuhkan `noteDate`, body, title opsional, archive, dan
timestamps. Ini bukan `activitySessions` dan tidak boleh memakai tabel aktivitas.

Perbaikan minimum: parser menerima `daily_note` pada single dan multi proposal,
model membawa title/body/noteDate secara eksplisit, validator mewajibkan body dan
tanggal valid, executor memiliki `_saveDailyNote`, verifier membaca
`database.dailyNotes`, dan test memastikan tidak ada row baru di
`activitySessions`.

### 6. Anggaran

Tabel `envelope_budgets` membutuhkan nama, category ID tunggal atau JSON banyak
kategori, allocated, period type, start/end date, alert percent, rollover,
active, dan timestamps. UI juga menentukan periode, tanggal mulai, rollover,
ambang peringatan, serta kategori yang sedang dipilih.

Kekhawatiran bahwa anggaran berbeda tiap user benar. Karena itu LLM tidak boleh
menebak ID atau membuat pos tanpa membaca kategori aktif user. LLM boleh mengusulkan
nama/kategori/nominal/periode, lalu aplikasi harus resolve kategori aktif secara
unik dan membuka form bila ada ambiguitas. Setelah user konfirmasi, executor
dan `monthly`.

Keputusan implementasi: pilih satu kebijakan produk secara eksplisit:

- create budget langsung setelah kategori/periode tervalidasi; atau
- create budget selalu lewat form UI, tetapi draft harus menjadi prefill lengkap
  dan tidak boleh tampil sebagai action plan yang seolah siap dieksekusi.

Jangan mempertahankan kondisi sekarang, yaitu prompt menjanjikan create namun
executor menolak setelah konfirmasi.

### 7. Pengingat

Tabel `reminders` memiliki title, note, `scheduledAt` dengan jam, recurrence,
weekdays, sound URI/name, snooze, notification ID, source type/ID, origin,
dan calendar fields. UI `ReminderPage` sudah mempunyai pemilih tanggal+jam dan
pemilih nada dering.

Penyebab jam/nada tidak terlihat di draft:

- preview hanya memformat `date` sebagai tanggal tanpa jam;
- parser memang mengisi datetime, tetapi fallback satu jam membuat input yang
  tidak menyebut jam tampak seolah valid;
- `soundUri` dan `soundName` tidak diparse/dibawa executor;
- executor mengisi notification ID memakai `id.hashCode.abs()`, bukan helper
  stable notification ID yang sudah tersedia;
- source/origin juga tidak diteruskan dari draft.

Target: jika user menyebut "jam 7", draft menampilkan `07:00`; jika jam tidak
ada dan fitur membutuhkan jam, assistant meminta klarifikasi. Sound adalah
opsional tetapi jika dipilih harus sampai entity/repository/notifikasi.

## Isu Arsitektur Lintas Draft

- Ada dua proposal contract: `ffm-assistant-proposal-v1` dan
  `ffm-local-proposal-v2`; keduanya tidak mendukung jenis draft yang sama.
- `formValues` dapat menimpa field canonical di planner karena spread order.
- Validator murni tidak bisa memeriksa ID database, tetapi form/executor baru
  menemukan masalah setelah preview. Perlu tahap `resolveDraftReferences` yang
  deterministik sebelum confirmation.
- Semua jenis draft diarahkan ke pola `save_draft -> verify`, walaupun beberapa
  belum memiliki adapter tabel yang benar.
- Preview menampilkan key `formValues` generik sehingga bukan jaminan bahwa field
  tersebut benar-benar akan tersimpan.

## Rencana Implementasi Bertahap

### Phase 0: Kontrak dan fixture

- [x] Tetapkan `FfmAssistantDraft` field matrix per jenis draft.
- [x] Pisahkan field canonical dari metadata/form-only.
- [x] Buat fixture JSON LLM untuk setiap jenis draft dan fixture row database.
- [x] Tambahkan resolver reference untuk account/category/merchant/tag/goal/activity
  dengan hasil `resolved`, `missing`, atau `ambiguous`.
- [x] Tambahkan assertion planner bahwa setiap parameter penting tidak hilang.

Acceptance: satu fixture dapat dilacak dari JSON -> draft -> plan -> entity/
companion tanpa field hilang atau berubah diam-diam. Kontrak JSON -> draft ->
plan sudah diuji untuk seluruh 17 tipe proposal canonical. Acceptance database
lintas transaksi, goal, activity/daily note, budget, reminder, debt/receivable,
dan master data sudah memiliki focused integration test serta analyzer bersih.
Validasi notifikasi fisik di perangkat Android tetap menjadi validasi runtime,
bukan gap kontrak atau persistence Phase 0.

### Phase 1: Income, expense, transfer

- [x] Rapikan field transaksi dan tag/item/receipt/attachment.
- [x] Implementasikan validasi nominal, total struk, tax/discount, paid/change,
  category type, references, dan tanggal.
- [x] Pastikan transfer fee, source, account IDs, dan verifikasi saldo konsisten.
- [x] Perbarui preview dan edit dialog agar field yang ditampilkan sama dengan form.

Acceptance: integration test create income, simple expense, complex expense,
dan transfer memeriksa seluruh kolom serta relasi database. Tax dan discount
persisten via kolom nullable terpisah (schema 62), diverifikasi read-back DB.
`flutter analyze lib test` bersih; full suite 1.520 test lulus.

---

## 🚩 Checkpoint Handoff (13 Sep 2026)

**Status Terakhir:**
- **Phase 0 & Phase 1 SELESAI.**
- Schema Database: **Versi 62** (Penambahan kolom `tax` dan `discount` pada `transactions`).
- Kode Drift telah diregenerasi (`app_database.g.dart`).
- Analyzer Bersih (0 issues).
- Full Regression: **1.520 tests PASSED**.

**Instruksi Mulai Besok (Phase 2: Goal):**
1. Fokus ke perbaikan *create goal* (target amount/date/category/note).
2. Refactor *deposit/usage* asisten menjadi operasi atomik (ID rekening, tanggal, saldo).
3. **Penting:** Gunakan `tax` dan `discount` yang sudah ada di Phase 1 sebagai referensi cara kerja kolom baru.
4. **Dilarang:** Mengaudit ulang Phase 0 atau 1 kecuali ada *regression bug*.

### Phase 2: Goal

- [ ] Perbaiki create goal agar target amount/date/category/note sesuai UI.
- [ ] Refactor deposit/usage menjadi operasi atomik yang memakai account ID, tanggal,
  signed transaction sesuai aturan domain, dan guard saldo.
- [ ] Tambahkan idempotency dan verifikasi currentAmount/account balance.

Acceptance: deposit/usage dengan tanggal lampau, rekening tertentu, batas saldo,
retry, dan duplicate key memiliki hasil deterministik.

### Phase 3: Activity dan Daily Note

- [ ] Pisahkan adapter `saveActivity` dan `saveDailyNote`.
- [ ] Simpan mode secara authoritative dan pastikan `effectiveMode` tidak membuang
  nilai mode.
- [ ] Tambahkan `parentSessionId` ke parser, draft edit, planner, validator, dan
  executor; validasi parent aktif sebelum insert child.
- [ ] Tentukan perilaku tanggal timer: scheduled timer versus start-now harus berbeda.

Acceptance: test membuat timer utama, child timer, catatan aktivitas, dan daily
note; setiap jenis hanya membuat row di tabel yang benar.

### Phase 4: Budget

- [ ] Putuskan create langsung atau form-prefill sebagai kebijakan resmi.
- [ ] Hapus jalur yang menampilkan create plan tetapi selalu menolak.
- [ ] Persist name, categoryIds, period, start/end, rollover, alert percent, note,
  dan active sesuai UI.
- [ ] Uji kategori berbeda antar household dan kategori ambigu/tidak aktif.

Acceptance: dua user dengan kategori/period berbeda menghasilkan row budget yang
berbeda dan tidak ada field hard-code.

### Phase 5: Reminder

- [ ] Parse datetime dengan jam dan tampilkan jam di preview/edit.
- [ ] Klarifikasi jam yang hilang jika perintah memerlukan waktu spesifik.
- [ ] Bawa recurrence, weekdays, sound, source, origin, dan snooze sesuai kontrak.
- [ ] Ganti notification ID executor ke helper stable yang sudah ada.

Acceptance: perintah "ingatkan jam 07:00" tersimpan tepat pada waktu itu,
perintah tanpa jam diklarifikasi, dan sound terjaga sampai scheduling service.

### 8. Kendaraan dan Listrik

Saat audit ini, kedua fitur **belum memiliki kontrak dedicated Gemini draft**.

Kesimpulan struktur saat ini:

- UI kendaraan dan meter listrik sudah cukup lengkap untuk input manual.
- Kendaraan menyimpan biaya per pengisian pada `FuelLogEntry`, sehingga biaya
  motor/mobil dapat berbeda per kendaraan dan per pengisian.
- Meter listrik menyimpan `lastAmount` dan token terakhir per meter, tetapi belum
  memiliki riwayat pembelian lengkap pada model buku saku.
- Master kendaraan dan meter listrik disimpan di `SharedPreferences`, bukan tabel
  database Drift. Hanya pembelian token yang juga dicatat di
  `utilityTokenPurchases`.
- Jalur listrik lokal dapat mencocokkan meter dan membuat meter baru hanya jika
  payload mengirim `isNewMeter: true`; jika tidak ditemukan tanpa flag tersebut,
  proses berhenti tanpa hasil yang terlihat.
- Jalur BBM lokal membutuhkan `vehicleId` yang sudah ada. Belum ada alur aman
  untuk membuat master kendaraan baru saat kendaraan belum terdaftar.
- Gemini Cloud belum memiliki schema khusus sehingga belum dapat dijamin
  membedakan Rumah A/Rumah B atau Motor A/Motor B berdasarkan data aplikasi.

Keputusan arsitektur yang benar:

- [ ] Migrasikan master kendaraan dan meter listrik dari `SharedPreferences` ke
  tabel Drift.
- [ ] Gunakan nomor meter/IDPEL sebagai identifier pencocokan listrik dan plat
  nomor sebagai identifier pencocokan kendaraan; nama rumah/kendaraan hanya
  alias yang membantu percakapan.
- [ ] Buat tabel riwayat `fuel_logs` dan `utility_token_purchases` yang menyimpan
  tanggal, nominal, detail teknis, entity ID, dan household ID.
- [ ] Setiap pembelian listrik/BBM membuat **satu** transaksi pengeluaran di
  `transactions` dan satu row riwayat domain dengan `transactionId` yang sama.
  Jangan membuat dua transaksi keuangan untuk satu pembelian.
- [ ] Grafik bulanan/tahunan dihitung deterministik dari tabel riwayat dan
  transaksi, bukan dari angka yang ditebak LLM.
- [ ] Token listrik dari gambar diarahkan ke alur meter listrik: OCR membaca
  nomor meter/token/nominal, resolver memilih meter terdaftar atau meminta
  konfirmasi membuat meter baru, lalu setelah konfirmasi menyimpan riwayat token
  dan transaksi pengeluaran.
- [ ] Pembelian BBM dari gambar diarahkan ke alur kendaraan: OCR membaca plat,
  liter, nominal, jenis BBM, odometer, dan SPBU, lalu resolver memilih kendaraan
  terdaftar atau meminta konfirmasi kendaraan baru.
- [ ] Assistant boleh menjawab analisis seperti biaya listrik Rumah A bulan ini,
  biaya tahunan, tren boros, BBM per motor, dan biaya per kilometer hanya dari
  query tabel yang sudah terverifikasi.

- Jalur lokal sudah mengenali sebagian perintah listrik/PLN dan dapat membawa
  `utilityProposal` ke executor setelah transaksi dibuat.
- Jalur lokal juga memiliki `fuelProposal` untuk pencatatan BBM kendaraan.
- Namun schema `create_draft` Gemini belum menyediakan field khusus kendaraan,
  BBM, meter listrik, token, odometer, liter, jenis BBM, atau referensi meter.
- Karena itu Gemini tidak boleh dianggap sudah dapat membuat draft kendaraan atau
  listrik yang lengkap. Paling aman saat ini adalah draft transaksi biasa atau
  jalur lokal khusus, bukan claim bahwa semua kolom halaman sudah terisi.

Rencana perbaikan:

- [ ] Tetapkan kontrak `vehicle_fuel` dan `utility_meter` yang memuat field UI,
  entity ID/reference, nominal, tanggal, dan relasi transaksi.
- [ ] Tambahkan schema parser single/multi proposal serta prompt Gemini yang
  hanya mengusulkan nilai, bukan ID yang ditebak.
- [ ] Resolve kendaraan dan meter aktif secara unik dari household.
- [ ] Simpan transaksi dan log kendaraan/meter secara atomik dengan rollback bila
  salah satu bagian gagal.
- [ ] Tambahkan verifier khusus untuk fuel log dan utility purchase.
- [ ] Tambahkan fixture dan test untuk create, ambiguous reference, retry, dan
  mismatch nominal.

## Handoff Agent: Migrasi Kendaraan, BBM, dan Listrik

Bagian ini adalah instruksi implementasi untuk agent berikutnya. Jangan menandai
checklist hanya karena tabel berhasil dibuat; semua acceptance test harus lulus.

### Masalah yang Harus Diselesaikan

- Master kendaraan dan meter listrik masih berada di `SharedPreferences` JSON.
- Riwayat BBM masih tertanam di JSON kendaraan.
- Riwayat token belum menjadi sumber riwayat domain yang lengkap.
- Gemini Cloud belum memiliki draft dedicated untuk kendaraan/BBM/meter listrik.
- Sistem belum aman membedakan Rumah A/Rumah B atau Motor A/Motor B.
- Satu pembelian harus masuk ke laporan transaksi dan riwayat domain tanpa
  membuat transaksi keuangan ganda.

### Schema Drift yang Ditargetkan

Buat tabel baru di `lib/core/database/tables.dart` dan migrasi `app_database.dart`.
Nama kolom harus mengikuti konvensi Drift camelCase/SQLite snake_case proyek.

`vehicles`:

- `id` primary key.
- `householdId`.
- `name` alias kendaraan, wajib.
- `plateNumber` plat asli, wajib untuk kendaraan non-EV.
- `normalizedPlateNumber` hasil normalisasi alfanumerik uppercase.
- `brandModel` nullable/opsional.
- `vehicleType` (`motor`, `mobil`, `truk`, `traktor`, `lainnya`).
- `fuelType` (`Pertalite`, `Pertamax`, `Solar`, `Listrik/EV`, dan seterusnya).
- `tankCapacity`, `lastOdometer`, `notes`.
- `isArchived`, `createdAt`, `updatedAt`.
- Index household + normalized plate; resolver tidak boleh memilih dua kendaraan
  dengan plat yang sama.

`fuelLogs`:

- `id` primary key dan `householdId`.
- `vehicleId` foreign-reference ke kendaraan.
- `transactionId` nullable tetapi wajib bila nominal pembelian dicatat sebagai
  transaksi keuangan.
- `date`, `liters`, `totalAmount`, `pricePerLiter`.
- `odometerKm`, `fuelType`, `spbuLocation`, `notes`.
- `createdAt`, `updatedAt`.
- Index household + vehicle + date descending.

`utilityMeters`:

- `id` primary key dan `householdId`.
- `name` alias properti, misalnya Rumah Utama/Pompa Sawah/Ruko.
- `meterNumber` nilai asli dan `normalizedMeterNumber` hanya digit.
- `customerName`, `tariffPower`, `location`, `notes`.
- `isArchived`, `createdAt`, `updatedAt`.
- Unique/index household + normalized meter number; nomor meter tidak boleh
  menunjuk ke dua properti aktif.

`utilityTokenPurchases` yang sudah ada harus dipertahankan dan diperkuat:

- Pastikan `meterId`, `meterNumber`, `tokenCode`, `amount`, `purchasedAt`, dan
  `transactionId` terisi konsisten.
- Tambahkan field bila diperlukan untuk `source`, `createdAt`, dan `updatedAt`.
- Jangan menyimpan token mentah ke prompt Gemini selain yang dibutuhkan user;
  token adalah data sensitif dan harus dibatasi pada UI lokal.

### Migrasi Data Lama

- Baca semua JSON kendaraan dari `ffm_vehicles_<householdId>`.
- Insert master kendaraan dengan UUID baru atau pertahankan ID valid.
- Pindahkan setiap `FuelLogEntry` ke `fuelLogs`; jangan menggandakan log dengan
  ID yang sama.
- Baca semua JSON meter dari `ffm_utility_meters_<householdId>`.
- Insert master meter dan ubah `lastAmount/lastPurchasedAt/lastTokenNumber`
  menjadi satu history purchase bila data tersebut tersedia.
- Migrasi harus idempotent dan tidak menghapus JSON lama sebelum verifikasi
  jumlah row, nominal, identifier, dan tanggal berhasil.
- Setelah migrasi sukses, repository membaca Drift sebagai sumber kebenaran;
  JSON lama hanya dipertahankan sementara untuk rollback terkontrol.

### Resolver dan Routing

- Plat: normalisasi non-alfanumerik, uppercase, exact match dalam household.
- Nomor meter/IDPEL: buang semua non-digit, exact match dalam household.
- Alias nama hanya fallback dan jika lebih dari satu hasil harus meminta
  klarifikasi.
- Jika ditemukan satu entity: draft menunjuk entity ID dan menampilkan alias
  serta identifier sebelum konfirmasi.
- Jika tidak ditemukan: draft `create_new_vehicle` atau `create_new_meter` harus
  muncul terpisah dari draft pembelian; tidak boleh auto-create tanpa konfirmasi.
- Jika ambigu: jangan memilih hasil pertama dan jangan menyimpan transaksi.
- Gambar token listrik diarahkan ke meter listrik, bukan halaman transaksi umum;
  setelah draft disetujui, transaksi pengeluaran dibuat otomatis sebagai bagian
  dari workflow yang sama.
- Gambar struk BBM diarahkan ke kendaraan/BBM dengan fallback transaksi biasa
  hanya bila plat/kendaraan memang tidak tersedia dan user menyetujuinya.

### Atomic Write dan Verifikasi

- Buat satu transaksi expense dengan `source` khusus (`utility_token` atau
  `fuel_purchase`) dan simpan `transactionId` pada history row.
- Simpan history row dan transaksi dalam satu boundary yang dapat di-rollback;
  jangan mengandalkan operasi `SharedPreferences` best-effort.
- Retry dengan idempotency key tidak boleh membuat transaction/history duplicate.
- Verifier harus membaca transaction dan history row, mencocokkan household,
  entity ID, nominal, tanggal, dan identifier.
- Bila history gagal, transaksi juga tidak boleh dianggap sukses.

### LLM Contract

- Tambahkan schema proposal dedicated untuk `vehicle_fuel` dan `utility_meter`.
- Field proposal minimal: action, entity reference, entity ID bila hasil read,
  identifier, alias, date, amount, technical details, and `createNew` proposal.
- LLM tidak boleh menebak entity ID atau status terdaftar.
- Orchestrator harus menjalankan read capability household terlebih dahulu,
  kemudian parser dan resolver lokal menentukan `resolved/missing/ambiguous`.
- Semua nominal, total tahunan, tren boros, dan biaya per kilometer dihitung
  deterministik dari database.

### Acceptance Test Wajib

- [ ] Master kendaraan baru tersimpan di Drift dan dapat dibaca ulang.
- [ ] Master meter baru tersimpan di Drift dan dapat dibaca ulang.
- [ ] Migrasi JSON lama mempertahankan seluruh log dan token.
- [ ] Dua rumah dengan nomor meter berbeda tidak tertukar.
- [ ] Dua kendaraan dengan plat berbeda tidak tertukar.
- [ ] Identifier duplikat menghasilkan status ambiguous dan tidak menyimpan.
- [ ] Pembelian token existing meng-update meter yang benar, membuat satu
  transaksi, dan membuat satu history row.
- [ ] Pembelian token unknown menghasilkan draft create-meter dan menunggu
  konfirmasi.
- [ ] Pembelian BBM existing meng-update kendaraan yang benar dan membuat satu
  transaksi serta satu fuel log.
- [ ] Pembelian BBM unknown menghasilkan draft create-vehicle dan menunggu
  konfirmasi.
- [ ] Retry tidak menggandakan transaksi atau history.
- [ ] Query grafik bulanan/tahunan listrik dan BBM menghasilkan angka dari DB.
- [ ] Verifier menolak mismatch nominal, tanggal, household, atau entity ID.

### Phase 6: Semua draft lain dan regression suite

- [ ] Audit liability, receivable, asset, master data, recurring transaction, task,
  routine, schedule, AgroTrack, dan monitoring job dengan matriks yang sama.
- [ ] Satukan atau dokumentasikan batas dua proposal contract.
- [ ] Jalankan test targeted, `flutter analyze lib test`, dan `flutter test` penuh.
- [ ] Untuk perubahan release-relevant, jalankan build Android ARM64 canonical.

## Test Matrix Wajib

- Parser single dan multi proposal untuk semua tipe.
- Draft edit mempertahankan field yang tidak diedit.
- Planner tidak menghilangkan canonical fields.
- Validator memblokir field wajib dan reference ambiguous.
- Preview menampilkan tanggal **dan jam** serta semua field yang akan disimpan.
- Executor idempotency: retry aman, payload berbeda ditolak.
- Database integration: row utama, relasi tags/items/attachments, dan verifier.
- Negative tests: wrong category type, unknown account, duplicate name, saldo
  kurang, target usage melebihi saldo, invalid receipt, invalid weekday.
- UI tests terpisah untuk mode Aktivitas Timer versus Catat saja.

## Baseline Validasi Audit

Perintah yang dijalankan:

```text
flutter test test/assistant_transaction_draft_sync_test.dart test/activity_voice_draft_test.dart test/ffm_assistant_goal_deposit_proposal_test.dart test/ffm_assistant_goal_mutation_integration_test.dart test/ffm_assistant_budget_mutation_test.dart test/ffm_assistant_draft_edit_dialog_test.dart test/reminder_test.dart
```

Hasil: **53 test lulus**.

```text
flutter analyze lib/features/assistant lib/features/activity lib/features/reminder lib/features/budget lib/features/transaction
```

Hasil: **No issues found**.

Catatan penting: baseline ini membuktikan tidak ada error analyzer dan regresi
tertentu belum muncul, tetapi belum membuktikan seluruh draft benar-benar sama
dengan database. Test gap yang disebut di atas harus ditambahkan sebelum fase
terkait dinyatakan selesai.
