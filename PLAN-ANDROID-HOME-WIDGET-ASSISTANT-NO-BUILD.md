# Rencana Integrasi Asisten FFM ke Widget Home Screen Android — Tanpa Build APK

## Jawaban teknis

**Bisa**, tetapi widget Home Screen tidak boleh diperlakukan sebagai pengganti penuh chat sheet atau sebagai jalur bebas untuk menyimpan transaksi. Widget dapat menjadi akses cepat ke Asisten FFM tanpa pengguna membuka aplikasi terlebih dahulu untuk perintah aman tertentu. Untuk perintah yang membutuhkan reasoning SLM, input panjang, gambar, atau mutation finansial, widget harus mengarahkan ke surface assistant/confirmation yang sesuai.

Batas penting Android: widget memakai `RemoteViews` dan proses background yang singkat. Widget tidak cocok untuk menjalankan Qwen2-VL besar secara lama atau menampilkan UI Flutter penuh. Karena itu SLM tetap dijalankan oleh service/orchestrator aplikasi saat process tersedia; widget menjadi gateway perintah, status, dan hasil ringkas. Jika process belum aktif atau model belum siap, widget tidak boleh diam-diam mengunduh model dan tidak boleh mengklaim eksekusi berhasil.

## Model akses yang aman

| Jenis interaksi dari widget | Perilaku yang diizinkan | Perlu membuka UI aplikasi? |
|---|---|---|
| Baca saldo/ringkasan/transaksi | Jalankan capability read-only lokal yang sudah di-allowlist dan tampilkan hasil ringkas | Tidak selalu; widget dapat diperbarui langsung |
| Buka halaman FFM | Kirim deep link/action ke AppShell | Ya, untuk menampilkan halaman tujuan |
| Ketik perintah bebas | Kirim teks ke orchestrator; jika membutuhkan SLM, buka assistant surface ringan/full | Umumnya ya |
| Perintah suara | Terima input melalui mekanisme Android yang tersedia, lalu kirim ke orchestrator | Ya jika perlu review/SLM |
| Baca gambar/struk | Tidak dijalankan diam-diam dari widget; buka flow kamera/import yang resmi | Ya |
| Membuat draft finansial | Boleh menyiapkan draft, tetapi hanya tampilkan preview/pending state | Ya, untuk preview |
| Simpan transaksi, transfer, ubah, hapus, restore, privacy/PIN | Tidak boleh dieksekusi hanya dari tap widget | Wajib membuka UI konfirmasi resmi |
| Mutation yang sudah pernah dikonfirmasi | Tetap wajib memakai idempotency dan state plan; widget tidak boleh menganggap tap kedua sebagai izin baru | Wajib jika confirmation surface tidak sedang valid |

Dengan demikian, “langsung bisa diakses” tercapai untuk status, pertanyaan read-only, dan shortcut. “Eksekusi” mutation tetap mengikuti kebijakan FFM: widget dapat memulai rencana, tetapi keputusan final tetap berada pada pengguna di preview/confirmation UI.

## Komponen yang akan dibangun

### 1. Widget contract dan action protocol

Definisikan action allowlist yang kecil dan eksplisit, misalnya `open_assistant`, `read_summary`, `read_balance`, `read_transactions`, `open_transaction_form`, `open_scan`, dan `open_model_setup`. Setiap action memiliki parameter tervalidasi, timestamp, request ID, source `home_widget`, dan expiry. Widget tidak menerima capability ID arbitrer dari teks pengguna.

Pisahkan `WidgetActionRequest`, `WidgetActionResult`, dan `WidgetActionState`. Result harus memiliki status `accepted`, `needsApp`, `awaitingConfirmation`, `completed`, `failed`, atau `expired`, serta pesan ringkas yang aman ditampilkan di widget.

### 2. Jalur read-only cepat

Implementasikan handler read-only yang memanggil adapter orchestrator, bukan membaca database mentah dari widget. Prioritas pertama adalah ringkasan bulan ini, saldo rekening yang sudah dipilih/terverifikasi, dan transaksi terbaru. Hasil disanitasi, dibatasi panjangnya, lalu ditulis kembali ke widget dengan timestamp “terakhir diperbarui”.

Jika data membutuhkan entity ambigu, PIN, atau model belum siap, widget hanya menampilkan instruksi untuk membuka Asisten FFM. Tidak ada daftar rekening mentah atau detail sensitif berlebihan yang ditampilkan pada Home Screen.

### 3. Quick command dan handoff ke orchestrator

Tambahkan input cepat yang mengirim perintah ke satu orchestrator yang sama dengan chat sheet. Widget tidak memiliki parser kedua yang berbeda. Deterministic guard berjalan lebih dulu; SLM lokal hanya dipanggil jika memang diperlukan dan session native tersedia.

Untuk command yang menghasilkan help, navigasi, query read-only, atau draft, widget menampilkan hasil sesuai status. Untuk draft mutation, widget membuka preview resmi dengan data yang sudah divalidasi. Untuk input bebas yang panjang, widget membuka assistant sheet/activity agar history, koreksi, image, dan status plan tetap konsisten.

### 4. Confirmation boundary mutation

Rancang deep link/intent seperti `ffm://assistant/plan/{planId}` atau action equivalent yang membuka preview plan. Hanya confirmation UI aplikasi yang boleh memanggil `controller.confirm(...)`. Widget tidak boleh memiliki tombol “Simpan” yang langsung memanggil repository.

Setelah execute dan verify berhasil, orchestrator menyimpan ringkasan status lokal dan memperbarui widget. Jika gagal, widget menampilkan “Gagal diverifikasi — buka Asisten untuk detail”, bukan pesan sukses palsu.

### 5. Update dan lifecycle widget

Tambahkan receiver/provider untuk pemasangan, refresh manual, dan update setelah perubahan data penting. Hindari polling agresif. Update dilakukan ketika widget dipasang, saat pengguna menekan refresh/action, setelah mutation terverifikasi, dan melalui mekanisme refresh Android yang wajar.

Model Qwen tidak dijalankan terus-menerus di background widget. Jika process dihentikan, request tidak boleh hilang tanpa status; gunakan request ID dan state lokal minimal untuk menandai `needsApp` atau `expired`. Tidak ada download model otomatis dari widget.

### 6. UI widget yang jelas

Sediakan ukuran widget minimal dan opsi yang lebih besar. Minimal widget menampilkan nama FFM/Asisten, status model lokal, satu ringkasan read-only, tombol refresh, tombol buka assistant, serta shortcut aman. Widget besar dapat menampilkan input perintah, tetapi hasil panjang diarahkan ke aplikasi.

Status harus membedakan “AI lokal siap”, “aturan lokal”, “perlu buka aplikasi”, dan “menunggu konfirmasi”. Jangan menampilkan status `Selesai` bila yang terjadi baru membuka form atau membuat draft.

## Urutan implementasi wajib

### Tahap A — Widget Home Screen

1. Audit mekanisme widget Android yang sudah ada dan dokumentasikan action yang telah tersedia.
2. Buat contract action/protocol yang allowlisted dan expiry-aware pada layer domain.
3. Hubungkan action read-only ke adapter orchestrator dan buat update hasil ringkas.
4. Hubungkan shortcut widget ke deep link AppShell/assistant tanpa mutation.
5. Hubungkan quick command ke session/orchestrator yang sama, tanpa parser duplikat.
6. Implementasikan handoff draft ke preview dan confirmation resmi.
7. Tambahkan lifecycle, request state, refresh, dan error handling.
8. Tambahkan widget test/unit test untuk status, duplicate request, expired request, no-model state, dan read-only result.

### Tahap B — Langsung menyelesaikan agent orchestrator setelah widget

9. Setelah widget lulus contract dan test, **langsung lanjut tanpa jeda ke agent orchestrator**.
10. Hubungkan executor dengan adapter read-only nyata untuk Summary, Transactions, Accounts, Categories, Budget, dan Analysis.
11. Perbaiki lifecycle draft/form agar membuka form tetap `awaitingConfirmation`; hanya explicit confirmation yang boleh mengubah plan menjadi executing.
12. Implementasikan adapter mutation income, expense, dan transfer dengan preview, idempotency key, execute sekali, dan verify.
13. Tambahkan workflow multi-langkah, dependency output antar-step, pause/cancel/expiry/retry aman, partial failure, serta recovery.
14. Lengkapi page context dinamis dan resolver entity lokal agar SLM memahami halaman tanpa menerima raw database.
15. Lanjutkan controlled learning/user model UI dengan approval, edit, archive, delete, version, dan rollback; candidate pending tidak aktif.
16. Tambahkan integration test: widget request → orchestrator → read/draft → preview → explicit confirm → execute sekali → verify → update widget.

### Tahap C — Validasi dan arsip

17. Jalankan `dart format`, `flutter analyze lib test`, targeted tests, dan full `flutter test`.
18. Pastikan tidak ada klaim full app control jika adapter atau verifier belum selesai.
19. Pada akhir setiap milestone, buat source ZIP baru yang aman; **tidak membuat APK, tidak menjalankan Gradle assemble, dan tidak melakukan signing**.
20. ZIP harus mengecualikan key release, keystore, model GGUF, APK, build output, cache, token, secret, dan data pribadi; arsip asli tidak boleh ditimpa.

## Pengujian dan keamanan

| Skenario | Expected result |
|---|---|
| Tap refresh widget | Read-only summary diperbarui atau status error jujur |
| Widget dipakai saat model belum siap | Shortcut setup atau aturan lokal; tidak ada download otomatis |
| Perintah “berapa pengeluaran bulan ini” | Read adapter berjalan tanpa membuka form mutation |
| Perintah “catat pengeluaran...” | Plan/draft dibuat, lalu handoff ke preview; tidak ada save |
| Tap action dua kali | Request ID/idempotency mencegah duplicate execution |
| Request melewati expiry | Ditolak dan meminta pengguna membuka ulang assistant |
| Entity rekening ambigu | Meminta klarifikasi di app, tidak menebak |
| Widget process restart | Tidak ada klaim sukses; state menjadi `needsApp`/`expired` |
| SLM invalid/unknown capability | Ditolak oleh validator allowlist |
| PIN/restore/privacy mutation | Wajib melalui UI resmi, permission, atau PIN gate |
| Data widget sensitif | Ringkasan diminimalkan dan tidak menampilkan raw database/secret |
| Android launcher tidak mendukung input tertentu | Fallback ke tombol buka assistant, bukan crash |

## Alternatif desain

| Pendekatan | Trade-off | Biaya | Kompleksitas setup |
|---|---|---|---|
| Widget shortcut + read-only cards | Paling stabil, cepat, aman; command bebas tetap membuka aplikasi | Rendah | Rendah |
| Widget interaktif dengan text/voice handoff | Pengalaman lebih mirip assistant; perlu menangani lifecycle, launcher, dan process restart | Sedang | Sedang-tinggi |
| Menjalankan Qwen penuh langsung dari widget/background | Tidak direkomendasikan: berat, rawan process kill, boros baterai, sulit menampilkan preview/confirmation, dan dapat menghasilkan status tidak konsisten | Tinggi | Tinggi dan berisiko |

Implementasi dimulai dari pendekatan pertama, lalu memperluas ke input cepat setelah contract dan safety flow stabil. Pendekatan ketiga tidak dipakai.

## Asumsi dan risiko

Asumsi utama adalah action widget Android yang sudah ada dapat diperluas tanpa mengganti AppShell dan tanpa membuat session inference kedua. Jika Android launcher membatasi RemoteViews input/voice, fallback resmi adalah membuka assistant surface. Risiko terbesar adalah mencoba menjalankan inference Qwen2-VL penuh dari context widget; risiko ini dihindari dengan menjadikan widget sebagai gateway dan mempertahankan satu orchestrator/session aplikasi.

Perubahan widget akan membutuhkan validasi pada emulator/perangkat Android ketika fase build/test perangkat memang diizinkan. Pada fase ini hanya source, unit/integration test, analyzer, dan dokumentasi yang dikerjakan; tidak ada APK.

## Kriteria keberhasilan

Fase widget dianggap berhasil jika pengguna dapat melihat status dan ringkasan read-only dari Home Screen, membuka assistant atau halaman tertentu melalui shortcut, mengirim command ke orchestrator yang sama, mendapatkan draft/preview mutation tanpa autosave, dan melakukan confirmation hanya di UI resmi. Duplicate/expired/stale request ditolak, error ditampilkan jujur, dan source ZIP aman tersedia di akhir milestone.
