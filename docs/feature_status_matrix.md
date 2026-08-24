# Matriks Status Fitur FFM Berdasarkan Source Terbaru

Tanggal audit dan implementasi: 23 Agustus 2026.

Baseline: `FFM-source-PersonalLifeManager-Siklus1.zip` dengan SHA-256 `b88b8a3a7fd20dc0a2869f9e2076c4fd665b7881c82a59c9af44aee95c8a6a14`.

Status menggunakan empat label: **ada di source**, **ada tetapi belum tervalidasi**, **belum ada**, dan **terblokir SDK/perangkat**.

## Personal Life Manager

| Fitur | Status | Bukti source | Kekurangan yang tersisa |
|---|---|---|---|
| Aktivitas bertimed | Ada tetapi belum tervalidasi | `features/activity/presentation/pages/activity_page.dart`, `activity_bloc.dart`, `activity_repository.dart`, tabel `ActivitySessions`, `ActivityCheckpoints`, `ActivityEntries` | Belum ada analyzer/test/device pada worktree terbaru; integrasi jurnal bebas belum ada. |
| Jurnal/catatan teks bebas | Belum ada | Tidak ada `DailyNotes`, `DailyNotesPage`, atau repository Daily Notes | Harus dibuat sebagai tab/section di Aktivitas & Jurnal, bukan navbar kedua. |
| Profil/kebiasaan user | Ada sebagian tetapi belum tervalidasi | `FfmAssistantUserModelService` memakai `assistant_memories` untuk data yang disetujui | Belum ada UI/domain profil khusus dan belum terhubung ke aktivitas/rutinitas. |
| Tasks/pekerjaan | Belum ada | Tidak ada tabel/class/page Tasks | Dikerjakan setelah Daily Notes selesai. |
| Rutinitas | Belum ada | Tidak ada `DailyRoutines` | Dikerjakan setelah Tasks atau sesuai spesifikasi final. |
| Jadwal belajar/pertemuan | Belum ada | Tidak ada `ScheduleItems` atau kalender manager | Dikerjakan setelah domain sebelumnya tervalidasi. |
| Pengingat lokal | Ada tetapi belum tervalidasi | Reminder repository, BLoC, page, `Reminders`, `ReminderHistories`, permission exact alarm | Perlu uji perangkat dan uji pembukaan aplikasi dari notifikasi. |
| Saran manager pribadi lintas domain | Belum ada | Asisten baru memiliki ringkasan/kapabilitas keuangan dan aktivitas existing | Menunggu domain data harian, bounded context, dan adapter read-only. |

## SLM lokal dan chat

| Fitur | Status | Bukti source | Kekurangan yang tersisa |
|---|---|---|---|
| Halaman Model Asisten Lokal | Ada di source | `features/assistant/presentation/pages/local_model_page.dart` | UI/device belum tervalidasi. |
| Download GitHub | Ada di source, belum tervalidasi | `_download()` memanggil `downloadBundle()`; URL model dan projector ada di `FfmQwen2VlBundle` | Belum diuji end-to-end pada device; tidak berjalan background setelah app ditutup. |
| Impor model GGUF satu per satu | Ada di source, belum tervalidasi | `importSingleGguf()` menyalin path atau stream `PlatformFile`, lalu mencocokkan hash ke model/projector | Belum diuji Android SAF pada device. |
| Staging dua aset | Ada di source, belum tervalidasi | `FfmStagingStatus`, `getStagingStatus()`, `commitStaging()` | Generated/build/device belum divalidasi. |
| Verifikasi SHA-256, ukuran, header, manifest | Ada di source dan sebagian diuji unit | `FfmLocalModelService`; `ffm_local_model_service_test.dart` | Unit test belum dijalankan pada environment ini; end-to-end belum dilakukan. |
| Impor `.ffmbundle` | Ada di source dan sebagian diuji unit | `pickAndInstallBundle()`, `_importPickedFile()`, `importBundle()`; test path traversal | Belum diuji file provider/device. |
| Ekspor bundle untuk dibagikan | Ada di source, belum tervalidasi | `exportVerifiedBundle()` dan tombol `Bagikan bundle` | Belum diuji share provider dan file besar pada device. |
| Hapus model | Ada di source | `_remove()` meminta konfirmasi lalu `clear()` dan `clearStaging()` | Perlu uji storage/permission nyata. |
| Penyimpanan privat | Ada di source, belum tervalidasi | `_modelsRoot()` memakai application support directory | Perlu uji lokasi aktual pada Android. |
| Runtime gateway Qwen2-VL | Ada di source, belum terbukti berjalan | `FfmQwen2VlGateway`, `FfmQwen2VlInferenceService`, MethodChannel native | Vendor `third_party/llama.cpp` sudah tersedia di ZIP terbaru. Flutter SDK, library native, ABI arm64, dan inference device belum diuji. |
| Fallback tanpa model | Ada di source secara arsitektur | `FfmAssistantDisabledLocalModelGateway` dan interpreter fallback | Perlu uji alur chat nyata. |
| Chat teks ke SLM | Ada di source secara routing, belum terbukti berjalan | Injection mendaftarkan `FfmQwen2VlGateway`; interpreter memanggil `proposeWithContext` | Runtime native menunggu pengujian build/inference arm64. |
| Chat vision/foto | Ada di kontrak source, belum tervalidasi | `imagePath` diteruskan sampai native `generateSingleShotNative` | Belum ada uji device/inference vision. |
| Background download/salinan | Belum ada | UI menyatakan tidak ada unduhan otomatis background | Harus dirancang dengan WorkManager/foreground service bila nanti diperlukan; tidak boleh diklaim ada. |

## Asisten, tindakan, dan keamanan

| Fitur | Status | Bukti source | Kekurangan yang tersisa |
|---|---|---|---|
| Navigasi halaman utama | Ada di source, belum tervalidasi | Navbar lima item dan routing di `main.dart` | Perlu analyzer/widget test. |
| Analisa di menu Lainnya | Ada di source, belum tervalidasi | `OtherMenuPage` menampilkan `AnalysisPage`; routing asisten diarahkan ke index Lainnya lalu halaman Analisa | Perlu test UI. |
| Mutasi memakai preview/konfirmasi | Ada di source secara arsitektur | Capability mutation `requiresConfirmation`; self-description menyatakan no autosave | Perlu regresi menyeluruh. |
| Pembacaan raw DB oleh SLM | Dilarang oleh kontrak source | Gateway menyatakan angka harus berasal dari evidence/query lokal dan tidak boleh mengarang | Perlu audit setiap adapter baru. |
| Memori user terkontrol | Ada di source | `FfmAssistantUserModelService` menyimpan hanya data approved di `assistant_memories` | Belum menjadi manager lintas domain dan UI belajar perlu ditata. |
| Identitas Rafi Sinkkat | Diterapkan di worktree terbaru, belum tervalidasi | `FfmAssistantSelfDescriptionService` memuat nama dan tautan; test ditambah | Belum dijalankan analyzer/test dan belum dipastikan renderer Markdown chat. |
| Pembuat aplikasi di ZIP sumber | Belum ada sebelum perubahan worktree | Self-description baseline hanya generik | Perubahan sudah ditambahkan pada worktree terbaru, tidak pada arsip asli. |

## Database

Audit menemukan 29 tabel existing dan seluruhnya memiliki referensi source. `ActivitySessions`, `ActivityCheckpoints`, dan `ActivityEntries` tetap dipakai. Tidak ada tabel yang dihapus. Domain baru belum menambah tabel karena baseline terbaru ternyata belum membawa implementasi yang diklaim dokumennya.

## Validasi dan release

Flutter SDK tidak tersedia di sandbox. `flutter pub get`, `build_runner`, analyzer, formatter Dart, unit test, widget test, migration test, native inference test, APK build, signing, dan ZIP release belum dijalankan pada worktree ini.

APK dan ZIP release tidak dibuat. Release baru boleh dilakukan setelah seluruh status penting berubah menjadi **ada di source dan tervalidasi**, lalu pengguna memberikan perintah build eksplisit.
