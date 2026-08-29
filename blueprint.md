# Blueprint FFM

## Status utama

- Aktivitas / FAB / voice: sebagian besar sudah selesai di code dan test.
- Draft AI / prefill form: sudah ada fondasi, belum merata di semua halaman.
- Supabase config: sudah ada UI input URL + anon key, masih manual.
- Multi-activity dalam satu hari: model sudah ada, UI perlu validasi manual.
- Parent/child aktivitas: data support ada, UX perlu dibenahi.
- Blueprint export JSON/PDF/HTML: belum ada.

## Masalah yang sudah dikerjakan

- FAB blank page: sudah ditangani dengan guard navigasi dan state safety.
- Voice category: sudah ditangani, kategori masuk ke intent dan save.
- Confirm sebelum save: sudah ada.
- Voice-to-activity flow: sudah bisa membuat aktivitas valid.
- Regression test: sudah ditambahkan dan lulus.

## File penting

- [lib/main.dart](lib/main.dart)
- [lib/features/activity/domain/activity_voice.dart](lib/features/activity/domain/activity_voice.dart)
- [lib/features/activity/presentation/bloc/activity_bloc.dart](lib/features/activity/presentation/bloc/activity_bloc.dart)
- [lib/features/activity/presentation/pages/activity_page.dart](lib/features/activity/presentation/pages/activity_page.dart)
- [lib/features/activity/domain/entities/activity_entity.dart](lib/features/activity/domain/entities/activity_entity.dart)
- [lib/features/assistant/domain/ffm_assistant_form_prefill.dart](lib/features/assistant/domain/ffm_assistant_form_prefill.dart)
- [lib/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart](lib/features/assistant/presentation/widgets/ffm_assistant_draft_edit_dialog.dart)
- [lib/features/settings/presentation/pages/supabase_setup_page.dart](lib/features/settings/presentation/pages/supabase_setup_page.dart)
- [test/activity_test.dart](test/activity_test.dart)
- [test/activity_voice_test.dart](test/activity_voice_test.dart)

## Yang masih belum final

- Aktivitas banyak dalam satu hari: butuh uji manual di device.
- Parent/child activity: butuh visual jelas dan validasi arah nesting.
- Edit riwayat tanggal: belum umum di semua halaman.
- Draft AI coverage semua halaman: belum seragam.
- Export blueprint JSON/PDF/HTML: belum ada.
- Supabase: masih perlu input manual URL + anon key.

## Prioritas berikutnya

1. Validasi real device untuk aktivitas dan voice.
2. Uji multi-activity + parent-child flow.
3. Audit draft AI ke halaman lain.
4. Buat editor riwayat tanggal umum.
5. Buat generator blueprint file JSON/HTML/PDF.
6. Review setup Supabase manual.

## Kondisi selesai

Sebuah item dianggap selesai kalau:

- ada implementasi pada file yang relevan,
- ada validasi/tes atau pengecekan yang jelas,
- UI/device test sudah benar,
- status update tercatat di blueprint,
- AI lain bisa lanjut tanpa baca seluruh repo.

## Catatan akhir

- Code level untuk aktivitas dan voice sudah beres.
- Yang belum final adalah validasi device, UX multi-activity, dan blueprint export file.
- File ini dipakai sebagai master handoff untuk AI atau manusia berikutnya.
