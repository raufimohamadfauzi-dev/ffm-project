# Workplan Agent: Agent Inbox dan Proactive Loop

## Status Dokumen

Dokumen ini khusus untuk eksekusi agent. Jangan dianggap sebagai dokumentasi pengguna atau panduan penggunaan aplikasi.

- [x] Seluruh tahap selesai.
- [x] Test relevan lulus.
- [x] `flutter analyze lib test` bersih.
- [x] Perubahan tidak menimpa pekerjaan agent lain.

## Tujuan

Menyelesaikan delivery loop Agent FFM:

```text
Perubahan data atau jadwal
    -> evaluasi deterministik
    -> insight tersimpan
    -> notifikasi aman
    -> Agent Inbox
    -> user meninjau
    -> action plan
    -> konfirmasi jika mutasi
    -> eksekusi dan verifikasi
```

Target utama:

- [x] Agent Inbox mudah ditemukan.
- [x] Insight baru dapat diketahui user tanpa membuka halaman secara manual.
- [x] Inbox menampilkan data baru setelah kembali aktif atau menerima event background.
- [x] Evaluasi tidak berjalan berulang-ulang secara berlebihan.
- [x] Tidak ada mutasi finansial otomatis tanpa konfirmasi eksplisit.
- [x] Seluruh delivery dapat diaudit, dideduplikasi, dan diuji.

## Batasan Agent

- [x] Fokus hanya pada Agent Inbox, proactive insight, background evaluation, notification delivery, dan test terkait.
- [x] Reuse `AutonomousEvaluationCoordinator`, `FfmAssistantInsightRepository`, `FfmAssistantAutonomyWorker`, dan `ReminderNotificationService` sebelum membuat abstraction baru.
- [x] Jangan membuat orchestrator, planner, capability registry, atau executor baru.
- [x] Jangan mengizinkan notification callback mengubah transaksi secara langsung.
- [x] Jangan menampilkan nominal atau data sensitif pada lock screen secara default.
- [x] Payload notifikasi hanya boleh memuat `insightId`, tipe insight, dan metadata navigasi yang aman.
- [x] Semua mutation tetap melewati action plan, policy, confirmation, executor, persistence, audit, dan verification.
- [x] Jangan menghapus event atau insight sebagai cara menangani duplikasi; gunakan idempotency dan status.
- [x] Sebelum menyentuh file bersama, periksa `git status` dan isi file terbaru.

## File Pemilik Perilaku

- [x] Baca [agent_inbox_page.dart](../../lib/features/assistant/presentation/pages/agent_inbox_page.dart).
- [x] Baca [other_menu_page.dart](../../lib/features/settings/presentation/pages/other_menu_page.dart).
- [x] Baca [autonomous_evaluation_coordinator.dart](../../lib/features/assistant/domain/autonomous_evaluation_coordinator.dart).
- [x] Baca [ffm_assistant_proactive_evaluation_task.dart](../../lib/features/assistant/data/ffm_assistant_proactive_evaluation_task.dart).
- [x] Baca [ffm_assistant_autonomy_background_dispatcher.dart](../../lib/features/assistant/data/ffm_assistant_autonomy_background_dispatcher.dart).
- [x] Baca [ffm_assistant_autonomy_background_scheduler.dart](../../lib/features/assistant/data/ffm_assistant_autonomy_background_scheduler.dart).
- [x] Baca [ffm_assistant_insight_repository.dart](../../lib/features/assistant/data/ffm_assistant_insight_repository.dart).
- [x] Baca [reminder_notification_service.dart](../../lib/features/reminder/data/services/reminder_notification_service.dart).
- [x] Cari seluruh pemanggil `database.changed`, `enqueueEvent`, dan `getActiveInsights`.

## Tahap 0 - Baseline Sebelum Edit

- [x] Jalankan `git status --short`.
- [x] Catat perubahan agent lain pada file yang akan disentuh.
- [x] Jalankan test Inbox dan autonomy yang sudah ada.
- [x] Jalankan `flutter analyze lib test` atau analyzer scoped yang tersedia.
- [x] Catat baseline failure yang bukan disebabkan pekerjaan ini.
- [x] Tuliskan satu hipotesis lokal tentang titik perilaku yang akan diubah.
- [x] Tentukan satu pemeriksaan murah yang dapat membantah hipotesis tersebut.

## Tahap 1 - Akses Agent Inbox

- [x] Pertahankan menu saat ini: `Lainnya` -> `Pengingat dan alat` -> `Laporan & Kotak Masuk Asisten`.
- [x] Tambahkan shortcut Agent Inbox pada permukaan Assistant yang paling sering dibuka, jika route dan pola navigasi sudah mendukung.
- [x] Tampilkan jumlah insight `newInsight` sebagai badge jika state dapat dibaca tanpa query berulang yang mahal.
- [x] Pastikan shortcut tidak membuat halaman Inbox menjadi sumber data kedua.
- [x] Pastikan navigasi dari shortcut dan menu lama menuju halaman yang sama.
- [x] Tambahkan widget test untuk menu lama, shortcut baru, dan badge unread.

Acceptance:

- [x] User dapat membuka Inbox dari `Lainnya`.
- [x] User dapat membuka Inbox dari permukaan Assistant utama jika shortcut ditambahkan.
- [x] Badge hanya menghitung insight aktif berstatus baru.
- [x] Tidak ada duplikasi route atau repository insight.

## Tahap 2 - Refresh Inbox yang Konsisten

- [x] Pastikan load awal memanggil `getActiveInsights` dan `getAllInsights`.
- [x] Tambahkan refresh saat halaman kembali terlihat setelah navigasi atau lifecycle resume.
- [x] Tambahkan mekanisme refresh ringan ketika insight baru masuk jika stream database tersedia.
- [x] Jika stream belum tersedia, gunakan polling terbatas atau refresh saat `AppLifecycleState.resumed`.
- [x] Hindari menjalankan evaluasi penuh pada setiap rebuild widget.
- [x] Bedakan aksi `refresh data` dan `evaluate now` agar evaluator tidak terpanggil tanpa sengaja.
- [x] Tampilkan error state yang jujur jika query atau evaluasi gagal.
- [x] Jangan menelan exception tanpa menyimpan diagnostik yang relevan.
- [x] Tambahkan test bahwa Inbox menampilkan insight yang dibuat setelah halaman dibuka.

Acceptance:

- [x] Insight baru dari background terlihat setelah user kembali ke aplikasi.
- [x] Pull-to-refresh tetap menjalankan evaluasi manual seperti kontrak sekarang.
- [x] Tidak ada loop refresh tak terbatas.
- [x] Loading state tidak menimpa daftar lama secara tidak perlu.

## Tahap 3 - Trigger Evaluasi Setelah Perubahan Data

- [x] Audit event `database.changed` dari transaksi, aktivitas, dan domain lain.
- [x] Tentukan detector mana yang relevan untuk setiap tipe perubahan.
- [x] Tambahkan event evaluasi yang aman dan bounded, atau gunakan coalescing event yang sudah ada.
- [x] Jangan menjalankan enam detector penuh untuk setiap perubahan kecil secara bersamaan.
- [x] Terapkan debounce/coalescing per household, misalnya satu evaluasi tertunda dalam jendela waktu tertentu.
- [x] Pastikan trigger hanya memasukkan metadata scalar yang sudah disanitasi.
- [x] Pastikan trigger gagal tidak membatalkan transaksi authoritative.
- [x] Pastikan event evaluasi memiliki idempotency key.
- [x] Pastikan `reminder.due` tidak berubah menjadi jalur mutation finansial.
- [x] Tambahkan test untuk event valid, event duplikat, payload tidak aman, dan trigger failure.

Acceptance:

- [x] Perubahan transaksi dapat memicu evaluasi tanpa menunggu user membuka Inbox.
- [x] Evaluasi tidak dipanggil berkali-kali untuk burst perubahan yang sama.
- [x] Event duplikat tidak membuat insight duplikat.
- [x] Kegagalan trigger tidak merusak penyimpanan transaksi.

## Tahap 4 - Delivery Notifikasi Android

- [x] Audit API dan channel yang sudah dimiliki `ReminderNotificationService`.
- [x] Reuse gateway notifikasi yang ada; jangan membuat plugin wrapper kedua.
- [x] Tambahkan channel agent yang terpisah untuk urgent, action-needed, dan digest bila diperlukan.
- [x] Buat notification payload minimal: `insightId` dan tipe insight.
- [x] Buat idempotency key delivery berdasarkan insight ID dan channel.
- [x] Jangan menjadwalkan ulang notifikasi yang sudah terkirim.
- [x] Terapkan expiry insight sebelum notifikasi dikirim.
- [x] Terapkan quiet hours, daily limit, enablement, dan detector preference sebelum delivery.
- [x] Default lock-screen content harus generik dan tidak memuat nominal finansial.
- [x] Ketukan notifikasi harus membuka Agent Inbox dan memfokuskan insight terkait.
- [x] Jika insight sudah dismissed, acted, atau expired, jangan mengirim delivery baru.
- [x] Catat status delivery berhasil, ditolak policy, gagal, atau permission denied.
- [x] Tambahkan test payload, deduplikasi, expiry, policy, dan deep link.

Acceptance:

- [x] Insight baru dapat menghasilkan local notification pada perangkat Android yang mengizinkan notifikasi.
- [x] Notification tap membuka Inbox yang benar.
- [x] Notifikasi tidak membocorkan nominal di lock screen secara default.
- [x] Delivery yang gagal tidak menghapus insight dari Inbox.
- [x] Retry delivery tetap bounded dan idempotent.

## Tahap 5 - Permission dan Kontrol Pengguna

- [x] Minta permission notifikasi secara kontekstual setelah fitur proactive insight diaktifkan atau insight berguna pertama tersedia.
- [x] Jangan meminta permission berulang-ulang setelah user menolak.
- [x] Simpan preference enable/disable secara lokal sesuai pola preference aplikasi.
- [x] Tambahkan kontrol kategori urgency.
- [x] Tambahkan kontrol quiet hours.
- [x] Tambahkan batas notifikasi harian.
- [x] Tambahkan kontrol privacy lock screen.
- [x] Tambahkan pilihan detector yang aktif.
- [x] Pastikan preference dibaca dan ditegakkan di foreground maupun WorkManager.
- [x] Pastikan Inbox tetap berfungsi jika permission ditolak.
- [x] Tambahkan test default policy, permission denied, quiet hours, daily limit, dan disabled detector.

Acceptance:

- [x] User memiliki kontrol eksplisit atas delivery notifikasi.
- [x] Permission denied tidak menghilangkan insight lokal.
- [x] Policy yang sama berlaku pada foreground dan background.
- [x] Tidak ada notifikasi di luar daily limit atau quiet hours.

## Tahap 6 - Action dari Insight

- [x] Audit `destination`, `suggestedAction`, dan `actionPayload` pada setiap detector.
- [x] Pastikan action read-only dapat membuka halaman tujuan.
- [x] Untuk usulan rebalance atau action lain, tampilkan preview sebelum eksekusi.
- [x] Pastikan action payload divalidasi ulang saat user menekan tombol.
- [x] Pastikan mutation selalu memerlukan konfirmasi eksplisit.
- [x] Pastikan executor melakukan persistence atomik, audit, dan verification.
- [x] Tampilkan status `awaiting confirmation`, `completed`, `failed`, atau `blocked` dengan jelas.
- [x] Jangan menganggap tombol `Tindak lanjuti` berarti mutation sudah dilakukan.
- [x] Tambahkan integration test insight -> preview -> confirmation -> executor -> verify.

Acceptance:

- [x] Insight hanya mengusulkan tindakan.
- [x] Tidak ada mutation dari background evaluator atau notification callback.
- [x] User dapat membedakan rekomendasi, draft, dan tindakan yang sudah selesai.
- [x] Kegagalan action dapat dipulihkan tanpa duplikasi.

## Tahap 7 - Observability dan Recovery

- [x] Tampilkan waktu evaluasi terakhir pada Monitoring Agent.
- [x] Tampilkan jumlah insight dibuat, dideduplikasi, expired, dan gagal delivery.
- [x] Simpan error terstruktur tanpa payload sensitif.
- [x] Pastikan event gagal memiliki retry count dan batas retry.
- [x] Pastikan event completed tidak diproses ulang.
- [x] Pastikan insight expired dibersihkan statusnya secara deterministik.
- [x] Tambahkan diagnostik jika scheduler gagal diinisialisasi.
- [x] Tambahkan test concurrency atau duplicate worker untuk claim event.
- [x] Tambahkan test background callback dengan dependency/database yang gagal.

Acceptance:

- [x] Agent dapat menjelaskan kapan evaluasi terakhir berjalan.
- [x] Event gagal tidak retry tanpa batas.
- [x] Duplikasi worker tidak menggandakan eksekusi.
- [x] Error dapat ditelusuri tanpa membuka data sensitif.

## Tahap 8 - Validasi Final

- [x] Jalankan test focused untuk Inbox.
- [x] Jalankan test focused untuk proactive service dan cooldown.
- [x] Jalankan test worker dan event repository.
- [x] Jalankan test notification/deep link.
- [x] Jalankan test mutation safety dan confirmation.
- [x] Jalankan `flutter analyze lib test`.
- [x] Uji lifecycle foreground -> background -> resume pada Android.
- [x] Uji permission notification diizinkan dan ditolak.
- [x] Uji layar Android kecil dan layar umum.
- [x] Jika perubahan release-relevant, jalankan `flutter build apk --target-platform android-arm64 --release`.
- [x] Verifikasi APK hanya memuat ABI `arm64-v8a`.
- [x] Periksa `git diff` dan pastikan tidak ada perubahan tidak terkait.
- [x] Catat test yang dijalankan, hasil, blocker, dan residual risk.

## Acceptance Criteria Agent

- [x] Agent Inbox dapat ditemukan dan dibuka dari jalur aplikasi yang jelas.
- [x] Evaluasi insight berjalan terjadwal dan dapat dipicu oleh perubahan data dengan debounce.
- [x] Insight baru tersimpan lokal dengan deduplikasi dan expiry.
- [x] Inbox memperbarui data setelah resume atau event insight baru.
- [x] Notifikasi menggunakan payload minimal dan deep link yang benar.
- [x] Lock screen tidak membocorkan nominal secara default.
- [x] User dapat mengatur permission dan notification policy.
- [x] Background task hanya menjalankan capability yang aman dan read-only.
- [x] Semua mutation tetap membutuhkan confirmation.
- [x] Event, delivery, action, dan failure memiliki audit/recovery yang bounded.
- [x] Test focused lulus dan analyzer bersih.
- [x] Tidak ada secret, data mentah, atau prompt mentah yang disimpan di event/notification payload.

## Catatan Eksekusi Agent

- [x] Sebelum edit: baca file aktual, cek status git, dan tentukan symbol pemilik perilaku.
- [x] Sebelum edit: tulis satu hipotesis lokal dan satu pemeriksaan murah yang dapat membantahnya.
- [x] Setelah edit pertama: jalankan validasi executable paling sempit.
- [x] Jika validasi gagal: perbaiki slice yang sama dan ulangi validasi sebelum pindah area.
- [x] Jangan mencentang pekerjaan hanya karena kode sudah ditulis; centang setelah perilaku terbukti.
- [x] Jangan menghapus atau melemahkan test yang gagal.
- [x] Jangan menimpa perubahan agent lain.
- [x] Jika ada blocker, catat file, gejala, penyebab sementara, dan langkah pemulihan.
