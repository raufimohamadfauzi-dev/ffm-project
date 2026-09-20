# FFM Assistant Activity Expansion Plan

Status: Implemented; physical-device verification pending

Tujuan dokumen ini adalah mengarahkan perluasan kemampuan Asisten FFM pada halaman Aktivitas tanpa memberi akses SQL langsung kepada LLM, tanpa membuat draft kind yang tumpang tindih, dan tanpa mengubah perilaku bisnis yang belum dispesifikasikan.

## Status Ringkas

- [x] Audit awal halaman Aktivitas, draft, parser, query, capability adapter, dan test.
- [x] Perbaiki handoff draft Asisten ke halaman Aktivitas.
- [ ] Bentuk kontrak query Aktivitas terpadu.
- [x] Implementasikan query tambahan bernilai tinggi.
- [x] Samakan keyword dan routing intent untuk alias yang sudah didukung.
- [x] Perkuat validasi draft dan mutation yang dapat diverifikasi deterministik.
- [x] Lengkapi confirmation, execution, verification, dan error handling untuk alur mutation yang sudah ada.
- [ ] Tambahkan test unit, widget, integration, dan golden conversation.
- [x] Jalankan analyze, test suite, dan build release.
- [ ] Lakukan verifikasi perangkat dan review keamanan data.

## Prinsip Batasan

- [ ] LLM tidak boleh menjalankan SQL langsung.
- [ ] Semua pembacaan data memakai query tool/capability adapter terkontrol.
- [ ] Semua perubahan bisnis tetap melalui draft, validasi, konfirmasi, use case, dan verifikasi.
- [ ] Jangan menambah `FfmAssistantDraftKind` baru sebelum terbukti timer dan Daily Note tidak cukup.
- [ ] Jangan mengubah rumus durasi, status, atau agregasi tanpa aturan produk dan test.
- [ ] Query harus bounded: gunakan filter periode, limit, dan field yang diperlukan saja.
- [ ] Data pribadi/keuangan tidak boleh masuk log atau prompt melebihi kebutuhan intent.

## 1. Audit Dan Kontrak Data

- [ ] Petakan seluruh field yang ditampilkan halaman Aktivitas.
- [ ] Petakan perbedaan `activity_sessions` dan `daily_notes`.
- [ ] Tentukan arti resmi Timer, Daily Note, checkpoint, parent activity, child activity, kategori, tag, prioritas, archive, dan durasi.
- [ ] Tentukan apakah aktivitas dapat memiliki biaya/transaksi terkait.
- [ ] Tentukan aturan periode: hari ini, minggu ini, bulan ini, bulan lalu, dan rentang kustom.
- [ ] Tentukan aturan timezone untuk scheduled time dan durasi.
- [ ] Tentukan aturan aktivitas berulang jika tanggal/jam asal sudah lewat.
- [ ] Tentukan field yang boleh dibuat/diubah Asisten.
- [ ] Dokumentasikan field yang hanya boleh dibaca dan tidak boleh dimutasi Asisten.
- [ ] Pastikan kontrak ini konsisten dengan `activity_notes_handoff.md` dan spesifikasi produk.

## 2. Draft Handoff Ke Halaman Aktivitas

Target file utama:

- `lib/main.dart`
- `lib/features/activity/presentation/pages/activity_page.dart`
- `lib/features/assistant/domain/ffm_assistant_models.dart`
- `lib/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart`

- [x] Pertahankan `FfmAssistantDraftKind.activity` untuk Timer.
- [x] Pertahankan `FfmAssistantDraftKind.dailyNote` untuk Catatan Harian.
- [x] Teruskan `draft.activityMode` saat membuka ActivityPage.
- [x] Teruskan `draft.date`.
- [x] Teruskan `draft.scheduledAt`.
- [x] Teruskan `draft.parentSessionId`.
- [ ] Teruskan kategori.
- [x] Teruskan tag/form values yang memang didukung ActivityPage.
- [x] Pastikan draft `history` membuka alur Daily Note, bukan Timer.
- [x] Pastikan draft Timer membuka alur pencatatan waktu.
- [x] Pastikan draft terjadwal mempertahankan waktu yang dipilih.
- [ ] Pastikan parent activity tetap tervalidasi saat form dibuka.
- [ ] Tambahkan error yang jelas jika parent sudah tidak tersedia.
- [ ] Tambahkan test handoff Timer.
- [x] Tambahkan test handoff Daily Note.
- [ ] Tambahkan test handoff scheduled activity.
- [ ] Tambahkan test handoff child activity.

## 3. Query Aktivitas Terpadu

Target file utama:

- `lib/features/assistant/data/ffm_assistant_query_tools.dart`
- `lib/features/assistant/data/ffm_assistant_capability_adapters.dart`
- `lib/features/assistant/data/ffm_assistant_financial_snapshot_service.dart`

Keputusan awal: gunakan query `read.activities` atau perluas kontrak `read.activity`; jangan membuat sistem query paralel.

- [ ] Tetapkan nama tool dan schema input/output.
- [x] Dukung `dateFrom` dan `dateTo`.
- [x] Dukung `limit` dengan batas maksimum.
- [x] Dukung `includeArchived`.
- [x] Dukung filter `status`.
- [x] Dukung filter `mode`: timer atau daily note.
- [x] Dukung filter kategori.
- [x] Dukung filter tag.
- [x] Dukung pencarian judul/catatan.
- [x] Dukung `includeCheckpoints` secara eksplisit.
- [x] Dukung `includeChildren` secara eksplisit.
- [x] Dukung ringkasan durasi.
- [ ] Gabungkan Timer dan Daily Note tanpa duplikasi legacy.
- [ ] Bedakan sumber data pada output bila diperlukan.
- [ ] Kembalikan field yang bounded dan relevan saja.
- [ ] Sertakan sumber/periode data untuk jawaban yang dapat diaudit.
- [ ] Tolak parameter tidak valid dengan error terstruktur.
- [ ] Jangan mengembalikan SQL atau raw database exception ke user.

## 4. Query Bernilai Tinggi

- [x] Query “aktivitas yang sedang berjalan”.
- [x] Query “aktivitas terbaru”.
- [x] Query “aktivitas pada periode tertentu”.
- [ ] Query total jumlah aktivitas.
- [ ] Query total durasi pada periode.
- [x] Query durasi aktivitas berdasarkan judul/ID.
- [x] Query aktivitas berdasarkan kategori.
- [x] Query aktivitas berdasarkan tag.
- [ ] Query aktivitas prioritas.
- [x] Query checkpoint terakhir.
- [x] Query checkpoint berdasarkan aktivitas.
- [x] Query child/sub-activity berdasarkan parent.
- [ ] Query perbandingan Timer dan Daily Note.
- [ ] Query aktivitas terarsip jika diminta secara eksplisit.
- [ ] Query biaya terkait aktivitas hanya jika relasi produk sudah didefinisikan.
- [ ] Tambahkan pagination/limit untuk riwayat panjang.

## 5. Daily Note Query Parity

- [ ] Samakan dukungan tag antara query registry dan capability adapter.
- [ ] Tambahkan filter tag ke `_readDailyNotes` jika kontrak mengizinkan.
- [ ] Tambahkan filter priority jika field tersebut authoritative.
- [ ] Tambahkan filter treatment/type hanya jika model sudah mendefinisikannya.
- [x] Pastikan Daily Note tidak dihitung sebagai Timer.
- [x] Pastikan query “catatan kejadian” menggunakan `daily_notes` sebagai sumber authoritative.

## 6. Keyword Dan Intent Routing

Centralisasi vocabulary agar cloud classifier, local interpreter, voice parser, query registry, dan page context memakai istilah yang sama.

- [ ] Tambahkan alias Timer: `timer`, `stopwatch`, `mulai aktivitas`.
- [ ] Tambahkan alias durasi: `durasi`, `berapa lama`, `berapa jam`.
- [ ] Tambahkan alias Daily Note: `catat kejadian`, `kejadian`, `jurnal`, `catatan harian`.
- [ ] Tambahkan alias aktivitas aktif: `sedang apa`, `lagi apa`, `aktivitas berjalan`.
- [ ] Tambahkan alias checkpoint: `checkpoint`, `sampai`, `tiba`, `update perjalanan`.
- [ ] Tambahkan alias hierarchy: `sub-aktivitas`, `aktivitas anak`, `aktivitas induk`.
- [ ] Tambahkan alias priority: `prioritas`, `penting`.
- [ ] Tambahkan alias archive: `arsip`, `pulihkan`, `kembalikan`.
- [ ] Pastikan `pengingat` tidak salah dirutekan menjadi Aktivitas.
- [ ] Pastikan `tugas` tidak salah dirutekan menjadi Aktivitas jika intent sebenarnya task.
- [ ] Pastikan `catat` tidak salah dirutekan menjadi transaksi keuangan.
- [x] Tambahkan clarification ketika target aktivitas ambigu.
- [ ] Tambahkan clarification ketika pengguna hanya menyebut kategori tanpa aksi.
- [x] Tambahkan test untuk keyword Bahasa Indonesia dan variasinya.

## 7. Draft Validation

Target file:

- `lib/features/assistant/domain/ffm_assistant_draft_validator.dart`
- `lib/features/assistant/domain/ffm_assistant_action_planner.dart`

- [x] Validasi judul aktivitas wajib.
- [x] Validasi body Daily Note wajib.
- [ ] Validasi tanggal dan timezone.
- [x] Validasi scheduled time untuk Timer terjadwal.
- [ ] Izinkan waktu lampau hanya untuk recurrence yang memang dapat dihitung ulang.
- [ ] Validasi kategori aktif.
- [ ] Validasi parent session tersedia dan aktif.
- [ ] Tolak parent yang sama dengan child.
- [ ] Validasi mode-specific fields.
- [ ] Validasi checkpoint target dan label.
- [x] Validasi tag yang dipilih.
- [ ] Validasi target tidak sudah dihapus/diarsipkan untuk mutation.
- [x] Perbaiki pesan “Transaksi target belum ditemukan” menjadi pesan Aktivitas.
- [ ] Pastikan validator tidak menggantikan validasi final di repository/use case.

## 8. Mutation Dan Capability Adapter

- [ ] Review create Timer.
- [ ] Review create Daily Note.
- [ ] Review finish/reopen activity.
- [ ] Review add/edit/delete checkpoint.
- [ ] Review edit title/category/note/date.
- [ ] Review set/unset priority.
- [ ] Review archive/restore/delete.
- [ ] Pastikan mutation aktif tidak bisa dihapus tanpa aturan yang jelas.
- [ ] Pastikan mutation ambiguous selalu meminta klarifikasi.
- [ ] Pastikan preview tidak memutasi database.
- [ ] Pastikan execute memakai transaction bila lebih dari satu tabel berubah.
- [ ] Pastikan verify membaca ulang authoritative state.
- [ ] Pastikan mutation idempotent.
- [ ] Pastikan audit log memakai istilah Aktivitas/Daily Note yang benar.

## 9. UI Confirmation Dan Error

Target file:

- `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart`
- `lib/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart`

- [ ] Tampilkan preview aktivitas sebelum mutasi.
- [ ] Tampilkan mode Timer atau Daily Note secara jelas.
- [ ] Tampilkan tanggal/jam, kategori, tag, parent, dan catatan jika relevan.
- [ ] Tampilkan checkpoint yang akan dibuat/diubah.
- [ ] Tampilkan target aktivitas secara unik saat mutation.
- [ ] Gunakan istilah manusia, bukan nama tool/field internal.
- [ ] Tampilkan error di dalam dialog jika dialog masih terbuka.
- [ ] Jangan gunakan Snackbar di belakang modal untuk error kritis.
- [ ] Pertahankan input user saat validasi gagal.
- [ ] Tombol konfirmasi tidak boleh membuat duplikasi saat ditekan dua kali.
- [ ] Setelah berhasil, reload data halaman Aktivitas.

## 10. Test Matrix

### Unit

- [x] Keyword routing Aktivitas.
- [x] Period parsing.
- [ ] Duration aggregation.
- [x] Checkpoint query.
- [x] Category/tag filter.
- [x] Timer/Daily Note separation.
- [ ] Next occurrence calculation.
- [x] Draft validation.
- [x] Ambiguous target resolution.

### Widget

- [ ] Draft Timer membuka form Timer.
- [x] Draft Daily Note membuka form Daily Note.
- [ ] Field scheduled time tampil benar.
- [ ] Parent activity tampil benar.
- [ ] Error tampil di dalam dialog.
- [ ] Confirmation menampilkan ringkasan benar.

### Integration

- [x] Buat Timer melalui Asisten lalu verifikasi database.
- [x] Buat Daily Note melalui Asisten lalu verifikasi `daily_notes`.
- [x] Selesaikan aktivitas melalui Asisten.
- [x] Tambah checkpoint melalui Asisten.
- [x] Edit aktivitas melalui Asisten.
- [x] Archive/restore melalui Asisten.
- [x] Delete dengan target unik.
- [x] Tolak delete target ambigu.
- [x] Query aktivitas aktif.
- [x] Query aktivitas periode.
- [x] Query kategori/tag.
- [x] Query Daily Note.
- [x] Query checkpoint.
- [x] Query child activity.
- [x] Uji idempotency dan reload authoritative state.

### Golden Conversation

- [ ] “Mulai perjalanan.”
- [ ] “Catat kejadian panen selesai.”
- [ ] “Sedang apa saya?”
- [ ] “Berapa lama perjalanan saya?”
- [ ] “Tambah checkpoint sampai pasar.”
- [ ] “Ubah judul aktivitas itu.”
- [ ] “Selesaikan aktivitas perjalanan.”
- [ ] “Tampilkan aktivitas bulan lalu.”
- [ ] “Tampilkan aktivitas kategori kerja.”
- [ ] “Tampilkan catatan dengan tag keluarga.”
- [ ] “Hapus aktivitas itu.” dengan target unik.
- [ ] “Hapus aktivitas itu.” dengan target ambigu.
- [ ] Batal sebelum konfirmasi.
- [ ] Konfirmasi ulang setelah error.

## 11. Security, Privacy, Dan Performance

- [x] Query hanya mengembalikan household/user scope yang benar.
- [ ] Jangan mengirim seluruh riwayat Aktivitas ke cloud.
- [x] Terapkan limit dan date range default.
- [ ] Jangan log isi catatan pribadi atau lokasi sensitif.
- [ ] Jangan menampilkan ID internal kepada user biasa.
- [ ] Uji query dengan riwayat besar.
- [ ] Pastikan pagination tidak mengubah total/summary.
- [ ] Pastikan pekerjaan berat tidak memblokir UI.
- [ ] Pastikan mutation tidak membuat child/orphan record.

## 12. Release Gate

- [ ] Semua checklist P0/P1 Aktivitas selesai.
- [x] Tidak ada test Aktivitas yang gagal.
- [x] `dart format --output=none --set-exit-if-changed .` lulus.
- [x] `flutter analyze` lulus.
- [x] Test Aktivitas dan Asisten lulus.
- [x] Full `flutter test` lulus atau failure terdokumentasi sebagai pre-existing.
- [x] `flutter build apk --release` lulus.
- [ ] Uji APK di perangkat Android nyata.
- [ ] Uji notifikasi/deep-link ke Aktivitas.
- [ ] Uji permission dan recovery setelah restart.
- [ ] Review diff hanya berisi perubahan yang direncanakan.
- [ ] Tidak ada secret, data pribadi, atau build artifact yang ikut berubah.

## Acceptance Criteria

Pekerjaan dianggap selesai jika:

- [ ] Asisten dapat membuka form Timer atau Daily Note sesuai mode draft.
- [ ] Semua field penting draft tetap utuh saat berpindah ke ActivityPage.
- [ ] Asisten dapat menjawab aktivitas aktif, histori, durasi, kategori, tag, checkpoint, dan Daily Note dengan query authoritative.
- [ ] Asisten tidak menjawab dengan data yang tidak tersedia atau tidak terverifikasi.
- [ ] Mutasi Aktivitas selalu memakai preview dan konfirmasi.
- [ ] Target ambigu tidak dimutasi secara acak.
- [ ] Error tampil di permukaan UI yang benar.
- [x] Query dibatasi scope, periode, dan jumlah hasil.
- [ ] Test unit, widget, integration, dan golden conversation tersedia dan lulus.
- [x] Analyze dan release APK lulus.
- [ ] Perangkat Android nyata berhasil melakukan alur utama.

## Blocked By Decision

Isi bagian ini jika ada aturan produk yang belum ditentukan. Jangan menandai implementasi selesai dengan asumsi.

- [ ] Apakah biaya/transaksi dapat dikaitkan dengan Aktivitas?
- [ ] Apakah durasi Daily Note memiliki arti atau hanya berlaku untuk Timer?
- [ ] Apakah aktivitas terarsip boleh muncul pada jawaban default?
- [ ] Apakah aktivitas prioritas merupakan field authoritative atau hanya flag UI?
- [ ] Apakah child activity boleh dibuat lewat Asisten tanpa parent yang sedang aktif?
- [ ] Apakah checkpoint boleh mengandung lokasi bebas atau hanya label/catatan?

## Changelog Checklist

- [ ] Tambahkan entry perubahan di changelog/release notes.
- [ ] Dokumentasikan query dan parameter baru.
- [ ] Dokumentasikan keyword baru.
- [ ] Dokumentasikan perubahan draft handoff.
- [ ] Dokumentasikan test evidence.
- [ ] Dokumentasikan item yang masih memerlukan keputusan produk.

## Verification Notes

- Activity interpreter + integration + widget suite → PASS, 34 tests setelah alur tag baru ditambahkan.
- `flutter test test/ffm_assistant_activity_v59_test.dart` → PASS, 6 tests.
- `flutter test test/ffm_assistant_activity_mutation_integration_test.dart` → PASS, termasuk pembuatan tag baru + Catatan Harian dalam satu plan, koneksi `daily_note_tags`, validasi tag, dan pencegahan orphan tag.
- `flutter test` → PASS, 1.693 tests.
- `flutter analyze` → PASS, no issues found.
- `dart format --output=none --set-exit-if-changed .` → PASS, 620 files unchanged.
- `flutter build apk --target-platform android-arm64 --release` → PASS, `app-release.apk` 37,8 MB.
- Verifikasi perangkat Android nyata → belum dijalankan.

## Activity Command Matrix

Checklist ini memetakan kemungkinan perintah pengguna ke draft dan eksekusi yang diharapkan.

### Membuat Data

- [x] “Mulai aktivitas pupuk cabai” → draft Timer Aktivitas.
- [x] “Catat kejadian pupuk cabai” → draft Catatan Harian.
- [x] “Catat kejadian pupuk cabai dengan tag Kebun” → Catatan Harian memakai tag aktif dari Data Utama.
- [x] “Catat sekarang ... dan buat tag baru AB” → satu draft dengan `tags=AB` dan `newTags=AB`; tag, catatan, dan relasi dibuat atomik setelah konfirmasi.
- [x] Tag baru yang tidak tercantum pada `tags` ditolak validator.
- [x] Tag yang diminta sebagai baru tetapi sudah ada ditolak agar tidak duplikat.
- [x] Tag yang tidak ada dan tidak ditandai sebagai baru ditolak dengan pesan Data Utama.
- [x] “Mulai sub-aktivitas makan di dalam perjalanan” → parent aktif diverifikasi.
- [x] Aktivitas terjadwal mempertahankan `scheduledAt`.

### Mengubah Data

- [x] Selesaikan atau buka kembali aktivitas dengan target unik.
- [x] Ubah judul, kategori, catatan, tanggal, dan prioritas.
- [x] Tambah, ubah, atau hapus checkpoint.
- [x] Arsipkan, pulihkan, atau hapus Catatan Harian/aktivitas.
- [x] Target ambigu meminta klarifikasi dan tidak dimutasi.

### Membaca Data

- [x] Aktivitas aktif dan terbaru.
- [x] Filter periode, status, mode, kategori, tag, teks, dan arsip.
- [x] Checkpoint dan parent/child activity.
- [x] Ringkasan durasi hasil filter.
- [x] Catatan Harian dibaca dari `daily_notes`, bukan sesi Timer.

### Batasan Yang Tetap Eksplisit

- [ ] Timer Aktivitas belum memiliki tabel relasi tag; tag hanya authoritative untuk Catatan Harian.
- [ ] Permintaan gabungan yang sangat bebas tetap bergantung pada structured draft dari cloud; local parser menjamin pola eksplisit yang diuji.
- [ ] Golden conversation untuk seluruh variasi bahasa belum lengkap.
- [ ] Build APK release dan pengujian perangkat nyata belum selesai.
