# Rencana Milestone Berikutnya — Mutation Adapter Agent Tanpa Build

## Tujuan

Mengubah fondasi orchestrator dan adapter read-only menjadi alur mutation yang nyata untuk tiga operasi prioritas: **pemasukan, pengeluaran, dan transfer**. Agent harus mampu memahami permintaan, menyiapkan draft, memvalidasi entity/parameter, menampilkan preview, menunggu konfirmasi eksplisit, menyimpan melalui use case resmi FFM, lalu membaca kembali hasilnya untuk verifikasi.

Pekerjaan dilakukan hanya pada source code, adapter domain, test database in-memory, dan dokumentasi. Tidak ada `flutter build`, Gradle assemble, signing, APK, atau packaging. Source ZIP baru dibuat setelah milestone selesai dan divalidasi.

## Kontrak safety yang tidak boleh dilanggar

> **Understand → Plan → Prepare → Validate → Preview → Confirm → Execute → Verify → Explain**

Membuka form, menyiapkan draft, atau menekan shortcut widget tidak sama dengan menyimpan transaksi. SLM hanya mengusulkan intent/parameter terstruktur. Orchestrator melakukan allowlist capability, resolver entity lokal, validasi, confirmation gate, dan idempotency. Tidak ada auto-save, autonomous CRUD, bypass PIN, atau akses SQL mentah dari SLM.

## Tahap implementasi

### 1. Perkuat model runtime mutation

Tambahkan metadata yang diperlukan pada Action Plan/step: `confirmationToken` atau approval version, `idempotencyKey`, payload preview yang sudah disanitasi, status execution, dan hasil verification. Pastikan mutation hanya dapat berpindah dari `awaitingConfirmation` ke `executing` melalui controller `confirm` yang valid.

Plan yang sudah `completed`, `cancelled`, `expired`, `failed`, atau `blocked` tidak boleh dieksekusi ulang. Konfirmasi ganda, callback ganda, response SLM terlambat, dan retry harus menghasilkan no-op aman.

### 2. Adapter pemasukan dan pengeluaran

Buat adapter application-level yang menggunakan `SaveTransaction` atau use case transaksi resmi, bukan meniru tap UI. Adapter harus:

- menyelesaikan rekening, kategori, sumber/pihak, tanggal, nominal, dan catatan dari draft;
- membedakan pemasukan dan pengeluaran secara eksplisit;
- menolak nominal tidak valid, entity ambigu, rekening/kategori tidak ditemukan, dan field wajib kosong;
- menghasilkan preview manusiawi sebelum eksekusi;
- membentuk idempotency key stabil dari plan/version/entity/parameter yang sudah tervalidasi;
- melakukan save satu kali setelah konfirmasi;
- membaca kembali transaksi melalui `GetTransaction` atau query resmi;
- mengembalikan verifier result `verified`, `alreadyApplied`, atau `failed` secara jujur.

Jika form resmi masih dipakai sebagai boundary UI, callback form harus mengembalikan hasil yang membedakan `cancelled`, `edited`, `readyForConfirmation`, dan `confirmedAndSaved`. Membuka form saja tidak boleh menandai plan completed.

### 3. Adapter transfer

Buat adapter transfer dengan resolver rekening asal dan tujuan, nominal, biaya admin, tanggal, dan catatan. Tolak rekening asal sama dengan tujuan, entity ambigu, nominal nol/negatif, serta parameter yang tidak sesuai schema. Transfer dan biaya terkait harus memakai mekanisme domain yang sudah tersedia dan diverifikasi dengan membaca kembali kedua saldo/record yang relevan.

Mutation transfer tetap tidak boleh berjalan dari widget secara langsung. Widget hanya membuat request/handoff; confirmation final terjadi di aplikasi.

### 4. Orchestrator flow dan UI handoff

Hubungkan intent draft dari interpreter/planner ke satu runtime orchestrator. Untuk read-only, executor boleh berjalan langsung. Untuk mutation, executor berhenti di `awaitingConfirmation`, menampilkan ringkasan perubahan, field yang dipakai, sumber data lokal, dan risiko. Setelah user menekan konfirmasi, controller menjalankan adapter tepat satu kali dan menampilkan hasil verify.

Perbaiki callback AppShell/form yang sekarang membuka halaman agar status plan tidak false-completed. Bila user membatalkan form, plan menjadi `cancelled` atau kembali ke draft yang menunggu revisi. Bila validasi form gagal, error disimpan pada step dan tidak ada write database.

### 5. Test wajib

| Area | Skenario |
|---|---|
| Pemasukan | Draft valid, rekening/category resolver unik, preview, confirm, save satu kali, verify |
| Pengeluaran | Draft valid dan field wajib kosong/invalid |
| Transfer | Asal/tujuan unik, asal sama tujuan, saldo/record verify, biaya admin |
| Safety | Tanpa confirmation mutation diblokir; token/version salah ditolak |
| Idempotency | Confirm dua kali, execute dua kali, retry setelah timeout, callback duplikat |
| Error | Missing adapter, exception repository, entity ambigu, verifier mismatch |
| UI lifecycle | Buka form tidak complete; cancel tidak save; confirmed callback menyelesaikan plan |
| Widget handoff | Widget request membuka preview, bukan save langsung |
| Security | Unknown capability, parameter ekstra, prompt injection-like text, raw SQL/secret tidak diteruskan |
| Integration | Planner → preview → confirm → adapter → database in-memory → verify |

### 6. Validasi dan arsip

Setelah implementasi milestone:

1. Jalankan `dart format lib test`.
2. Jalankan `flutter analyze lib test`.
3. Jalankan targeted tests mutation/orchestrator.
4. Jalankan full `flutter test`.
5. Perbarui `PROJECT_CONTEXT.md` dan `docs/implementation_status.md` dengan jumlah test aktual serta gap yang masih ada.
6. Buat source ZIP baru dengan nama versi berikutnya.
7. ZIP wajib mengecualikan model GGUF, key release, keystore, APK/AAB, folder build, `.dart_tool`, `.gradle`, log build, token, secret, dan arsip asli. Jangan menimpa arsip source asli.

## Urutan pengerjaan

1. Runtime state, approval/version, dan idempotency.
2. Resolver entity transaksi.
3. Adapter pemasukan/pengeluaran.
4. Adapter transfer.
5. Callback form dan Action Plan UI.
6. Integration test tiga mutation.
7. Error/retry/verification test.
8. Full validation dan source ZIP.

## Kriteria keberhasilan

Milestone berhasil jika minimal pemasukan, pengeluaran, dan transfer dapat melewati alur draft → validation → preview → explicit confirmation → execute sekali → verify pada database in-memory, tanpa mutation ketika belum dikonfirmasi, tanpa duplicate write ketika di-retry, dan tanpa status sukses palsu. Widget hanya menjadi akses/handoff; seluruh mutation tetap melalui confirmation UI. Tidak ada build APK pada milestone ini.

## Risiko dan asumsi

Asumsi utama adalah use case transaksi yang sudah ada dapat dipakai adapter tanpa migrasi Drift besar. Jika API transfer berbeda dari transaksi biasa, adapter akan memakai use case transfer aktual dengan DTO hasil yang sama. Risiko utama adalah form legacy belum mengembalikan confirmation callback yang cukup detail; perubahan akan dilakukan di caller/form boundary tanpa menghapus form resmi. Validasi native Android belum termasuk dalam milestone karena build dilarang.
