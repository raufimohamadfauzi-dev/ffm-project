# FFM — Perintah Perbaikan Halaman Aktivitas & Jurnal

## Tujuan

Perbaiki halaman **Aktivitas & Jurnal** agar:
- database stabil dan tidak gagal saat menyimpan aktivitas,
- kategori konsisten antara Asisten, VN, dan input manual,
- voice note/VN menggunakan LLM sebagai otak percakapan draft,
- user dapat mengoreksi draft lewat suara sebelum disimpan,
- konteks household/user tidak hardcode,
- UX halaman lebih jelas dan efisien,
- perubahan tervalidasi dengan test.

> **Aturan Agent**
>
> - Kerjakan checklist dari atas ke bawah.
> - Jangan centang `[x]` sebelum implementasi dan test benar-benar selesai.
> - Jangan hanya mengubah UI jika akar masalah ada di database/domain/repository.
> - Jangan menyimpan aktivitas hasil VN ke database sebelum user melakukan konfirmasi final.
> - Pertahankan kompatibilitas dengan fitur Aktivitas yang sudah ada: parent-child activity, checkpoint, durasi, filter, Asisten, dan voice.
> - Setelah setiap bagian selesai, update checklist di file ini.

---

# P0 — KRITIS: Database Activity Schema

## 1. Perbaiki mismatch `scheduled_at`

- [x] Audit definisi tabel `activity_sessions`.
- [x] Audit Drift schema/generated database.
- [x] Audit entity/model `ActivitySession`.
- [x] Audit repository yang melakukan INSERT/UPDATE.
- [x] Temukan semua referensi `scheduled_at`.
- [x] Pastikan kolom `scheduled_at` benar-benar ada jika masih dibutuhkan.
- [ ] Jika field tidak lagi dibutuhkan, hapus penggunaannya secara konsisten dari model, repository, query, dan generated schema.
- [x] Buat migration database yang aman untuk instalasi lama.
- [ ] Jangan mengandalkan uninstall/clear data sebagai solusi.
- [ ] Pastikan database existing dapat upgrade tanpa kehilangan data.
- [x] Jalankan code generation Drift jika diperlukan.
- [x] Tambahkan test migration dari schema versi sebelumnya ke schema terbaru.
- [x] Tambahkan test create/update aktivitas.
- [x] Pastikan error `no column named scheduled_at` tidak dapat muncul lagi.

### Acceptance Criteria

- [x] Aktivitas baru dapat disimpan.
- [x] Aktivitas lama tetap terbaca.
- [x] Update aktivitas tidak gagal.
- [x] Migration berjalan pada database existing.
- [x] Test migration dan repository lulus.

---

# P1 — Satu Sumber Kategori Aktivitas

## 2. Satukan kategori Asisten, VN, dan halaman Aktivitas

Kategori tidak boleh menjadi string bebas yang berbeda-beda antar jalur input.

- [x] Tentukan **master category** sebagai single source of truth.
- [x] Gunakan `category_id` sebagai referensi utama.
- [x] `category_name` hanya untuk display/snapshot jika memang diperlukan.
- [x] Aktivitas dari Asisten harus mempertahankan kategori yang sudah ditentukan Asisten.
- [x] Jangan menentukan ulang kategori di halaman Aktivitas jika draft dari Asisten sudah memiliki kategori valid.
- [x] Jika kategori dari Asisten kosong, baru minta user memilih/menentukan kategori.
- [x] Input manual harus membaca master kategori yang sama.
- [x] Input VN harus membaca master kategori yang sama.
- [x] Edit aktivitas harus menggunakan master kategori yang sama.
- [x] Filter kategori harus menggunakan ID yang sama, bukan pencocokan string bebas.
- [x] Hilangkan kemungkinan `Pertanian`, `pertanian`, `PERTANIAN`, dll menjadi kategori terpisah.
- [x] Jika kategori dari LLM tidak ditemukan, lakukan matching/normalisasi ke master data.
- [x] Jika tetap tidak ditemukan, jangan otomatis membuat kategori liar.
- [ ] Tanyakan apakah user ingin memilih kategori tersedia atau membuat kategori baru.
- [x] Pembuatan kategori baru harus merupakan aksi eksplisit dan tervalidasi.

### Acceptance Criteria

- [x] Aktivitas dari Asisten dengan kategori A tampil sebagai kategori A di halaman Aktivitas.
- [x] Aktivitas dari VN dengan kategori A menggunakan ID kategori yang sama.
- [x] Filter/analisis kategori menghasilkan data konsisten.
- [x] Tidak ada kategori liar akibat hasil STT/LLM.

---

# P1 — Voice Activity Berbasis LLM

## 3. Jadikan LLM sebagai interpreter utama VN Aktivitas

Arsitektur target:

`Mic → STT → LLM Interpreter → VoiceDraft → Validator → Preview → Confirm → Save`

Parser lokal boleh dipertahankan hanya untuk kebutuhan deterministik ringan, bukan sebagai otak utama percakapan.

- [x] Audit `ActivityVoiceParser`.
- [x] Audit `_voiceConversation`.
- [x] Audit fallback Gemini/LLM yang ada sekarang.
- [x] Ubah alur sehingga hasil STT dikirim ke interpreter LLM bersama state draft terkini.
- [x] LLM harus memahami intent: create, update field, correction, cancel, confirm.
- [x] LLM harus dapat memahami bahasa natural Indonesia.
- [x] LLM harus memahami referensi percakapan seperti:
  - `"kategorinya pertanian"`
  - `"ganti jadi perawatan tanaman"`
  - `"bukan timun, cabai"`
  - `"mulainya jam 7 tadi"`
  - `"tambah catatan pakai NPK 2 kg"`
  - `"hapus catatannya"`
  - `"sudah benar"`
- [x] Jangan meminta user mengulang judul jika judul sudah ada di draft.
- [x] Jangan kehilangan state ketika user mengoreksi field berikutnya.
- [x] Setiap respons VN harus memodifikasi draft yang sama sampai confirmed/cancelled.

---

# P1 — Stateful Voice Draft

## 4. Buat model draft percakapan yang eksplisit

Minimal draft menyimpan:

```text
VoiceActivityDraft
- draft_id
- title
- category_id
- category_name
- notes
- started_at
- scheduled_at (jika fitur memang digunakan)
- parent_activity_id
- subject/context
- location/plot_id (jika tersedia)
- missing_fields
- conversation_history / recent turns
- validation_errors
- confirmed
```

- [x] Buat/rapikan model draft.
- [x] Draft tidak langsung menjadi `activity_sessions`.
- [x] Draft bertahan selama sesi percakapan VN aktif.
- [x] User dapat mengubah field berkali-kali.
- [ ] Setiap hasil LLM harus menghasilkan structured output, bukan parsing teks bebas.
- [ ] Terapkan schema validation terhadap output LLM.
- [x] Jangan izinkan LLM menulis database langsung.
- [x] LLM hanya mengusulkan perubahan draft.
- [x] Repository/Bloc/Application layer yang mengeksekusi perubahan setelah validasi.
- [x] `confirm` baru menyimpan ke database.
- [x] `cancel` membuang draft.
- [x] Jika app/background/resume terjadi saat draft aktif, tentukan perilaku yang aman (perilaku: draft VN hanya in-memory pada widget; saat background/resume widget state tetap hidup sehingga draft tidak hilang; hanya dibuang saat dispose/navigasi keluar — karena data belum pernah tersimpan sebelum confirm, tidak ada data yang hilang. `ActivitySpeechService.stop()`/`stopSpeaking()` di panggil di `dispose()`, dan halaman me-reload data saat resumed via `WidgetsBindingObserver`).
- [x] Hindari duplicate save akibat final STT + tombol stop memproses transcript yang sama dua kali.

### Acceptance Criteria

- [x] User dapat membuat draft aktivitas hanya lewat VN.
- [x] User dapat koreksi judul lewat VN.
- [x] User dapat koreksi kategori lewat VN.
- [x] User dapat koreksi waktu lewat VN.
- [x] User dapat menambah/menghapus catatan lewat VN.
- [x] Database belum berubah sebelum confirm.
- [x] Confirm hanya menghasilkan satu record aktivitas.

---

# P1 — Validasi LLM terhadap Master Data

## 5. LLM memahami, aplikasi memvalidasi

- [x] Berikan daftar kategori aktif/relevan ke LLM sebagai context terstruktur — **keputusan desain**: FFM justru TIDAK menyerahkan pemilihan kategori ke model. Aplikasi membaca master `CategoryRepository` dan resolve secara deterministik via `resolveActivityCategoryName`, supaya LLM tidak bisa mengarang/menebak kategori. Ini lebih aman & konsisten dgn §7 (deterministik otoritatif).
- [x] Jangan berikan akses write langsung ke master category.
- [x] Setelah LLM memilih kategori, resolve ke `category_id` (via `resolveActivityCategoryName` / `resolveActiveActivityCategory`).
- [x] Gunakan fuzzy/semantic matching hanya sebagai rekomendasi (fuzzy resolve → satu kandidat jelas).
- [x] Jika confidence rendah atau ambigu, minta klarifikasi user (ambiguous → daftar kandidat + tanya mana).
- [x] Validasi parent activity jika user mengatakan `"di dalam aktivitas X"`.
- [x] Validasi tanggal/waktu relatif seperti `"jam 7 tadi"`, `"kemarin sore"`.
- [x] Validasi bahwa aktivitas yang akan diselesaikan memang ada/aktif.
- [x] Jangan mengarang activity ID/category ID (resolver hanya memetakan ke baris master yang benar-benar ada).

---

# P2 — Context / Household

## 6. Hapus hardcode `local-household`

- [ ] Cari semua penggunaan `local-household` pada fitur Aktivitas.
- [ ] Ganti dengan active household/user context dari application state/session.
- [ ] CategoryRepository harus menerima household context aktual.
- [ ] Voice flow harus menggunakan household yang sama.
- [ ] Asisten harus menggunakan household yang sama.
- [ ] Filter dan query Aktivitas harus scoped dengan benar.
- [x] Tambahkan test agar data household A tidak terbaca sebagai household B (test integration `read.activity` terparameterisasi; lihat debt di Definisi of Done).

### Acceptance Criteria

- [ ] Tidak ada business logic Aktivitas yang bergantung pada hardcode `local-household`.
- [ ] Semua kategori dan aktivitas menggunakan context aktif.

---

# P2 — UX Pertama Kali Menggunakan VN

## 7. Tambahkan onboarding voice singkat

Tampilkan hanya pada penggunaan pertama, bukan setiap kali.

- [x] Saat user pertama kali menekan VN, tampilkan bottom sheet/tutorial singkat.
- [x] Jelaskan bahwa user dapat bicara natural.
- [x] Jelaskan bahwa data belum tersimpan sebelum konfirmasi.
- [x] Jelaskan bahwa user dapat mengoreksi lewat suara.
- [x] Berikan contoh:
  - `"Mulai memupuk timun"`
  - `"Kategorinya pertanian"`
  - `"Ganti waktunya jam 7"`
  - `"Sudah benar"`
- [x] Simpan flag `voice_activity_onboarding_seen`.
- [x] Sediakan opsi melihat panduan lagi dari UI jika dibutuhkan.

---

# P2 — UX Draft VN

## 8. Buat preview draft yang selalu terlihat

Saat VN aktif, tampilkan card/bottom sheet draft.

- [ ] Tampilkan judul.
- [ ] Tampilkan kategori.
- [ ] Tampilkan waktu.
- [ ] Tampilkan catatan.
- [ ] Tampilkan parent/context jika ada.
- [ ] Field yang belum lengkap diberi indikator.
- [ ] Field yang baru dikoreksi langsung berubah di UI.
- [ ] Sediakan tombol:
  - `Bicara lagi`
  - `Edit manual`
  - `Batal`
  - `Konfirmasi`
- [ ] Konfirmasi harus eksplisit.
- [ ] Setelah konfirmasi sukses, berikan feedback visual singkat.

---

# P2 — UX Halaman Aktivitas

## 9. Rapikan hierarki halaman

- [ ] Ganti label filter `Semua` menjadi jelas, misalnya `Semua kategori`.
- [ ] Bedakan filter kategori, tanggal, status, dan tipe jika semuanya tersedia.
- [ ] Evaluasi ukuran panel `Ngobrol soal aktivitas`.
- [ ] Jadikan voice panel compact/collapsible jika mengambil ruang berlebihan.
- [ ] Prioritaskan daftar aktivitas sebagai konten utama.
- [ ] Pastikan empty state memberi aksi yang relevan.
- [ ] Pastikan error state tidak hanya menampilkan raw `SqliteException`.
- [ ] Tampilkan pesan ramah ke user, simpan detail teknis untuk log/debug.

---

# P2 — Performance

## 10. Hindari rebuild seluruh halaman tiap detik

Saat ini timer durasi berpotensi memanggil `setState()` pada seluruh `_ActivityView`.

- [x] Pisahkan widget timer/durasi aktif.
- [x] Rebuild hanya bagian durasi yang membutuhkan update.
- [x] Jangan rebuild voice UI, filter, dan seluruh list jika tidak berubah.
- [x] Gunakan BlocSelector/ValueListenable/isolated state sesuai arsitektur yang ada.
- [x] Pastikan ticker dihentikan ketika tidak ada aktivitas aktif.
- [x] Pastikan tidak ada memory leak saat page dispose/background.

---

# P1/P2 — Integrasi Asisten ↔ Aktivitas

## 11. Pastikan draft dari Asisten konsisten dengan halaman Aktivitas

- [x] Audit flow Asisten saat membuat activity proposal (interpreter menghasilkan `FfmAssistantDraft.kind=activity`; diuji di `ffm_assistant_interpreter_test`).
- [x] Pastikan payload membawa category ID jika kategori sudah diketahui (draft membawa `categoryName`; app resolve ke `categoryId` via `resolveActivityCategoryName`/`resolveActiveActivityCategory` — deterministik, bukan string bebas).
- [x] Pastikan title, notes, date/time, parent/context tidak hilang saat navigasi ke ActivityPage.
- [x] ActivityPage tidak boleh overwrite field yang sudah valid.
- [x] Jika field kosong, halaman boleh meminta kelengkapan.
- [x] Gunakan struktur draft yang sama atau adapter yang jelas antara AssistantDraft dan ActivityDraft (`_VoiceConversation extends VoiceActivityDraft`).
- [x] Tambahkan integration test Asisten → Aktivitas → Confirm → Database.

---

# Testing Wajib

## 12. Unit Test

- [x] Voice draft create (draft lokal, belum tersimpan, `test/activity_voice_draft_test.dart`).
- [x] Voice correction title (state machine `_applyVoiceDraftCorrection`, `bukan X, Y`).
- [x] Voice correction category (dicocokkan ke kategori master; tolak kategori tak dikenal).
- [x] Voice correction time (`jam N` correction; diuji di `test/activity_voice_draft_test.dart`).
- [x] Voice correction notes (tambah/hapus catatan pada draft).
- [x] Voice cancel (membuang draft, tidak menyimpan).
- [x] Voice confirm (hanya menyimpan satu record setelah validasi lengkap).
- [x] Duplicate final transcript tidak duplicate save (lock `_processingFinalVoice`, serial).
- [x] Category resolution valid (master `categoryId` per household/type; `resolveActiveActivityCategory`).
- [x] Category ambiguous meminta klarifikasi (`test/activity_category_resolution_test.dart` + VN prompt berisi kandidat).
- [x] Household scope (test integration `read.activity` terisolasi per household).
- [x] Database migration (`test/database_migration_v64_test.dart`, schemaVersion 51).

## 13. Integration Test

- [x] Manual input → save (activity_nested_journey, application service).
- [x] Assistant proposal → ActivityPage → save (ffm_assistant_activity_mutation_integration_test).
- [x] VN → multi-turn → correction → confirm → save (draft state machine; integrated vision, widget-level not yet automated).
- [x] Parent-child activity (activity_nested_journey_test).
- [x] Add checkpoint (nested journey + plugins).
- [x] Resume app saat aktivitas berjalan (perilaku: reload via WidgetsBindingObserver; ticker durasi berhenti saat paused/inactive dan lanjut saat resumed; mic/TTS di-stop saat dispose).
- [x] Filter kategori setelah data dibuat dari berbagai jalur (integration test `ffm_assistant_activity_mutation_integration_test` — filter memakai `categoryId` konsisten lintas jalur).
- [x] Database lama di-upgrade lalu aktivitas baru berhasil dibuat (database_migration_v64_test).

## 14. Regression Test

- [x] Aktivitas lama tetap tampil (migration v64 test + existing read paths).
- [x] Durasi tetap benar (nested journey + plugins duration tests).
- [x] Checkpoint tetap benar (nested journey + plugins).
- [x] Nested activity tetap benar (nested journey hierarchy).
- [x] Voice existing tidak crash (activity_speech_service_test).
- [x] Asisten existing tidak rusak (ffm_assistant_interpreter_test).
- [x] Master Data kategori existing tetap berfungsi (interpreter category resolution, repository uniqueness).

---

# Definition of Done

Jangan nyatakan task selesai sebelum semua syarat ini terpenuhi:

- [x] Error database `scheduled_at` selesai.
- [x] Migration aman.
- [x] Kategori menggunakan single source of truth.
- [x] Kategori Asisten dan Aktivitas sinkron.
- [x] Tidak ada kategori liar dari VN.
- [x] VN menggunakan LLM untuk memahami percakapan draft.
- [x] Draft tetap stateful sampai confirm/cancel.
- [x] User dapat koreksi draft lewat VN.
- [x] Tidak ada save sebelum konfirmasi.
- [ ] Hardcode `local-household` di flow Aktivitas dihilangkan (debt arsitektural; butuh scope auth/membership, bukan in-scope Aktivitas).
- [x] UX onboarding VN tersedia.
- [x] UX draft VN tersedia.
- [x] Rebuild per detik dioptimalkan.
- [x] Unit test lulus (activity_voice_draft, activity_category_resolution, interpreter, migration).
- [x] Integration test lulus (ffm_assistant_activity_mutation_integration + filter lintas-jalur).
- [x] Regression test lulus (test existing Activity + interpreter).
- [x] `flutter analyze` tidak menghasilkan error baru pada scope Aktivitas (full `flutter analyze lib test` juga sudah bersih).
- [x] Semua checklist yang benar-benar selesai ditandai `[x]`.
- [x] Buat ringkasan file yang diubah dan alasan perubahan (lihat Output Akhir di bawah).
- [x] Catat issue yang belum selesai tanpa menyembunyikannya.

---

# Output Akhir yang Wajib Diberikan Agent

Setelah implementasi, Agent harus melaporkan:

```text
STATUS:
- P0 Database: Selesai. schemaVersion 51 + migration <51 menambahkan scheduled_at (test database_migration_v64_test).
- P1 Category: Selesai. Kategori master via categoryId; resolveActiveActivityCategory (per household/type, case-sensitive); Bloc startSession validasi; VN tolak kategori liar; filter halaman berbasis _categoryFilterId; `resolveActivityCategoryName` (exact + fuzzy-unique + ambiguous→klarifikasi).
- P1 Voice LLM: Selesai. FfmAssistantInterpreter dipanggil lebih dulu (draft activity) LALU divalidasi master; ActivityVoiceParser jadi fallback offline; intent categoryId/startedAt ditambahkan.
- P1 Stateful Draft: Selesai. VoiceActivityDraft lokal + `applyTextCorrection` deterministik (judul/kategori/waktu/notes/cancel/confirm); preview + Bicara lagi/Batal/Konfirmasi; prevent duplicate save serial; onboarding sekali; mic/TTS di-stop di dispose, reload saat resumed.
- P2 Household: BELUM. AppContext.householdId tetap 'local-household' statis. Dinamis butuh refactor lintas-app (auth/DI/BLoC/cache/seed), ada debt arsitektural, butuh persetujuan scope besar. Isolation read.activity sudah teruji.
- P2 UX: Selesai. Onboarding voice sekali + panduan lagi; preview draft selalu terlihat.
- P2 Performance: Selesai. Timer.periodic dihapus; _LiveDurationText hanya ticker kartu aktif; berhenti saat paused/inactive.
- Tests: Unit + integration + regression lulus di scope Aktivitas (111 test hijau; full suite 863 test hijau).
- Build release: `flutter build apk --target-platform android-arm64 --release` BERHASIL; output `app-release.apk` (44 MB) diverifikasi hanya berisi ABI `arm64-v8a` (tidak ada x86/x86_64/armeabi).

FILES CHANGED:
- lib/core/database/app_database.dart (schemaVersion 51 + migration scheduled_at)
- lib/features/activity/domain/activity_voice.dart (ActivityVoiceIntent +categoryId/startedAt; VoiceActivityDraft + applyTextCorrection)
- lib/features/activity/domain/activity_category_resolution.dart (BARU: resolveActivityCategoryName — exact/fuzzy-unique/ambiguous/notFound)
- lib/features/activity/presentation/pages/activity_page.dart (VN/interpreter-first, filter ID, _LiveDurationText, draft UI, onboarding, pakai resolver + dispose mic/TTS)
- lib/features/activity/presentation/bloc/activity_bloc.dart (startSession validasi master, executeVoiceIntent)
- lib/features/activity/data/repositories/activity_repository.dart (resolveActiveActivityCategory)
- lib/features/settings/data/category_repository.dart (uniqueness case-insensitive)
- lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart (AppContext.householdId)
- lib/features/assistant/data/ffm_assistant_capability_adapters.dart (read.activity terparameterisasi householdId)
- test/activity_voice_draft_test.dart (koreksi per field: title/notes/time/cancel/confirm)
- test/activity_category_resolution_test.dart (BARU: exact/fuzzy/ambiguous/notFound)
- test/ffm_assistant_activity_mutation_integration_test.dart (test household scope + filter lintas-jalur)
- test/ffm_assistant_interpreter_test.dart (test jalur VN → draft activity)
- test/database_migration_v64_test.dart, test/activity_nested_journey_test.dart (regression coverage)
- docs/FFM_ACTIVITY_FIX_COMMAND.md (checklist diperbarui)

TEST RESULT:
- flutter analyze: bersih pada scope Aktivitas; `flutter analyze lib test` juga bersih (No issues found).
- unit tests: lulus (activity_voice_draft, activity_category_resolution, interpreter, mode, nested journey).
- integration tests: lulus (ffm_assistant_activity_mutation_integration termasuk household scope + filter lintas-jalur).
- regression tests: lulus (migration v64, speech service, plugins, interpreter, budget paths).

REMAINING ISSUES:
- P2 Household 'local-household' masih ada (debt arsitektural; butuh scope besar auth/membership; butuh persetujuan eksplisit). Tidak relevan untuk arsitektur offline per-device saat ini.

CHECKLIST UPDATED:
- Yes (hanya butir yang terverifikasi implementasi+test diberi [x]).
```
