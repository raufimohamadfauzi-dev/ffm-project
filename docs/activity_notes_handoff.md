# Handoff — Penyatuan Catatan Kejadian dan Aktivitas Timer

Tanggal: 15 September 2026  
Status: implementasi utama selesai; validasi terarah hijau (50 tests); validasi penuh dan visual QA masih perlu dilanjutkan.

## Permintaan dan keputusan pengguna

- Semua catatan harus memakai satu tampilan kartu putih dan satu linimasa bulanan.
- Catatan lama berbasis `activity_sessions` mode history/note harus dimigrasikan ke `daily_notes`.
- Bagian UI `Catatan dari Aktivitas` boleh dihapus agar tampilan mudah dipahami.
- Kartu catatan harus dapat diedit serta mempunyai aksi prioritas, arsip, pulihkan, dan hapus permanen.
- Kategori aktivitas tidak diperlukan untuk catatan biasa.
- Tag tidak wajib, tetapi dianjurkan agar catatan dapat dicari dan difilter.
- FAB Catat dan Timer harus menjadi dua alur yang terpisah.
- Form Catat khusus bernama `Catat Kejadian`, memakai ikon menulis, label `Judul catatan`, dan tidak menawarkan perpindahan ke Timer.
- Tag baru dibuat melalui dialog inline tanpa berpindah ke halaman Data Utama.
- Tag baru harus tersimpan melalui jalur Data Utama resmi, langsung muncul, dan langsung terpilih tanpa menghilangkan isian catatan.
- Asisten/LLM harus memperlakukan catatan sebagai `daily_note`, bukan aktivitas berjalan.

## Implementasi yang sudah dilakukan

### Database dan migrasi

- Schema database dinaikkan dari 63 ke 64 dengan tetap mempertahankan perubahan schema 63 milik pekerjaan reminder yang sudah ada.
- Kolom `priority INTEGER NOT NULL DEFAULT 0` ditambahkan ke `daily_notes`.
- Drift generated file sudah diperbarui melalui `build_runner`; generator selesai menghasilkan database tetapi keseluruhan command berstatus gagal karena error sintaks yang saat itu ada di `test/payment_notification_parser_test.dart` (pekerjaan paralel, bukan perubahan ini).
- `ActivityRepository.migrateHistorySessionsToDailyNotes` memindahkan sesi `mode=history` atau `kind=note` ke `daily_notes` dengan mempertahankan ID, household, judul, isi, tanggal, arsip, prioritas, created/updated time.
- Checkpoint legacy dihapus, referensi journal entry dilepas, dan child session dilepas dari parent sebelum session legacy dihapus.
- Migrasi idempoten memakai preference key `migration_history_sessions_to_daily_notes_v1_done`.

### Repository dan BLoC

- Tag pada `saveDailyNote` menjadi opsional; tag yang diberikan tetap divalidasi sebagai tag aktif pada household yang sama.
- Ditambahkan aksi repository/BLoC untuk edit, arsip, pulihkan, hapus permanen, dan toggle prioritas Daily Note.
- Ditambahkan pemuatan relasi tag per Daily Note ke `ActivityState.dailyNoteTags`.
- Pembuatan dan pembaruan catatan melalui BLoC memuat ulang state agar kartu langsung muncul.
- Voice note tidak lagi mewajibkan kategori atau tag.

### UI halaman Aktivitas

- FAB Catat membuka `_DailyNoteForm` khusus, bukan `_SessionForm` aktivitas.
- Form berjudul `Catat Kejadian` dan memiliki field `Judul catatan`, `Isi catatan`, tanggal kejadian, tag opsional, serta tombol simpan.
- Ikon orang berlari tidak tampil di form Catat. Ikon itu tetap dipakai secara benar pada form Timer.
- Tidak ada pilihan beralih Timer/Catat di form Catat.
- Dialog `Tambah tag baru` tetap berada di form, memakai `TagRepository.create`, kemudian menambahkan dan memilih tag baru.
- Kartu biru Daily Note diganti `_DailyNoteCard` putih dalam pengelompokan bulan yang sama.
- Kartu menampilkan badge Catatan, isi, tanggal, chip tag, edit, prioritas, arsip/pulihkan, dan hapus permanen.
- Cabang UI `Catatan dari Aktivitas` dihapus.
- Filter tag ditambahkan ke filter sheet dan chip filter aktif.

### Asisten

- Proposal JSON `daily_note` valid tanpa tag.
- Capability lama `activity + activityMode=history` dirutekan ke penyimpanan Daily Note kanonis, sehingga tidak lagi membuat sesi aktivitas semu.
- Prompt Gemini diperjelas bahwa catatan adalah catatan kejadian non-timer, tidak harus dibuat setiap hari, dan tag dianjurkan tetapi opsional.

## File implementasi utama

- `lib/core/database/tables.dart`
- `lib/core/database/app_database.dart`
- `lib/core/database/app_database.g.dart`
- `lib/features/activity/data/repositories/activity_repository.dart`
- `lib/features/activity/domain/activity_voice.dart`
- `lib/features/activity/presentation/bloc/activity_bloc.dart`
- `lib/features/activity/presentation/pages/activity_page.dart`
- `lib/features/activity/presentation/widgets/activity_filter_sheet.dart`
- `lib/features/assistant/data/ffm_assistant_capability_adapters.dart`
- `lib/features/assistant/data/ffm_assistant_proposal_json_service.dart`
- `lib/features/assistant/data/ffm_gemini_cloud_orchestrator.dart`

## Test yang diubah/ditambahkan

- `test/activity_fab_smoke_test.dart`
  - Memastikan form Catat memakai copy/ikon catatan dan tidak menampilkan ikon berjalan atau pilihan Timer.
  - Memastikan tag baru dapat dibuat inline, tersimpan, dan langsung tersedia.
- `test/activity_test.dart`
  - Memastikan Daily Note dapat disimpan tanpa tag.
  - Memastikan sesi history legacy dimigrasikan ke Daily Note beserta prioritas.
  - Test auto-healing lama disesuaikan dengan sumber data kanonis baru.
- `test/ffm_assistant_activity_mutation_integration_test.dart`
  - `activityMode=history` sekarang diverifikasi menghasilkan Daily Note.
  - Idempotensi history diverifikasi pada `daily_notes`.
- `test/daily_note_card_ui_test.dart`
  - Widget test end-to-end kartu Catatan Harian: edit (ketuk kartu), prioritas (bintang), arsip, hapus permanen, pulihkan, dan filter tag pada filter sheet.
- `test/database_migration_v64_test.dart`
  - Memastikan schema 64 menambah priority tanpa menghilangkan Daily Note lama.
- `test/monthly_report_data_test.dart`
  - Fixture `DailyNote` diberi `priority: 0` sesuai data class schema baru.

## Hasil validasi terakhir

- Analyzer terarah pada seluruh modul yang disentuh: **No issues found**.
- Test terarah terakhir: **50 tests passed** (termasuk 6 widget test UI baru).
- Command test terakhir:

```powershell
C:\flutter\bin\cache\dart-sdk\bin\dart.exe --packages=C:\flutter\packages\flutter_tools\.dart_tool\package_config.json C:\flutter\bin\cache\flutter_tools.snapshot test --no-test-assets test/activity_fab_smoke_test.dart test/activity_test.dart test/ffm_assistant_activity_mutation_integration_test.dart test/database_migration_v64_test.dart test/monthly_report_data_test.dart test/daily_note_card_ui_test.dart
```

- `flutter analyze lib test` dijalankan: **No issues found** (lint info pekerjaan paralel sudah diperbaiki oleh pemiliknya).

## Pekerjaan lanjutan wajib

1. Jalankan ulang `flutter analyze lib test` dan pastikan tidak ada error. Jangan mengubah lint pada file pekerjaan paralel tanpa memeriksa ownership perubahan.
2. Jalankan full suite `flutter test` dengan reporter default. Jika output akhir terpotong, ulangi dengan `--reporter expanded`. Jangan memakai `--concurrency=1` kecuali sedang mengisolasi hang.
3. Lakukan visual QA halaman Aktivitas pada ukuran Android yang sama dengan screenshot:
   - tab Semua;
   - tab Catatan Harian;
   - catatan tanpa tag;
   - catatan dengan banyak tag;
   - menu overflow kartu;
   - edit catatan;
   - arsip dan pulihkan;
   - filter tag;
   - dark mode;
   - keyboard terbuka dan layar kecil.
4. Periksa hasil migrasi pada database yang benar-benar memiliki session history legacy, termasuk child/checkpoint/entry, untuk memastikan tidak ada kehilangan data tak terduga.
5. ~~Pertimbangkan menambahkan test UI untuk edit, prioritas, arsip, hapus, pulihkan, dan filter tag; saat ini aksi repository/BLoC tercakup secara parsial, tetapi seluruh menu kartu baru belum diuji end-to-end.~~ Selesai: `test/daily_note_card_ui_test.dart` (6 test) menutupi semua skenario ini.
6. Setelah semua validasi hijau dan bila akan commit, ikuti AGENTS.md: `flutter analyze lib test`, full `flutter test`, lalu commit konvensional. Build ARM64 hanya diperlukan bila pekerjaan ini akan dijadikan release deliverable.

## Catatan working tree

- Repository sudah kotor sebelum pekerjaan ini. Ada perubahan pengguna/paralel pada reminder, payment detector, assistant knowledge/interpreter, summary, `main.dart`, dan file lain. Jangan me-reset atau menimpa perubahan tersebut.
- Formatter sempat dijalankan terlalu luas; perubahan file di luar daftar yang dilindungi sudah dikembalikan. Tetap periksa `git diff` sebelum commit dan stage hanya file yang relevan.
- Ada salinan validasi sementara di `C:\Users\naya\AppData\Local\Temp\ffm_activity_validation_20260915_2`. Percobaan penghapusan otomatis ditolak oleh kebijakan tool; aman dihapus manual bila sudah tidak diperlukan.

## Saran langkah pertama agent berikutnya

Mulai dengan membaca file ini, `AGENTS.md`, lalu jalankan:

```powershell
git status --short
git diff --check
flutter analyze lib test
flutter test
```

Jika Flutter tertahan tanpa output, periksa apakah ada proses `flutter test` lain pada workspace. Jangan hentikan proses milik pengguna; gunakan executable Flutter tool langsung seperti pada command test terarah di atas bila wrapper `flutter.bat` menunggu lock.
