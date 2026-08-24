# Audit Baseline Agent FFM v84

Tanggal audit: 24 Agustus 2026. Dokumen ini memakai source aktif `main` v84 dan menjadi matriks fakta untuk roadmap Personal Manager. Status **tersedia** berarti class/kontrak ditemukan; status **terhubung** berarti ada jalur registry → planner → executor/adaptor yang terlihat; status **tervalidasi** baru boleh dipakai setelah regresi yang relevan lulus pada checkpoint fase terkait.

## Ringkasan fakta utama

| Area | Fakta source v84 | Status audit | Implikasi fase berikutnya |
|---|---|---|---|
| SLM dan keamanan | SLM mengembalikan proposal; executor hanya memakai handler allowlist. Mutasi ditahan sampai plan berstatus executing setelah konfirmasi. | Terhubung secara arsitektur | Pertahankan sebagai batas keras. Tidak ada SLM/SQL write langsung. |
| Executor | Eksekusi serial; read-only dapat memakai snapshot transaksi dan retry; mutation tidak diretry; timeout per langkah dan pelacakan step dieksekusi tersedia. | Terhubung | Belum memiliki branching, group read, atau recovery plan yang dapat dijelaskan. |
| Context | `FfmAssistantReasoningContext` sudah membawa halaman, ringkasan tersanitasi, filter, allowlist, user context disetujui, personalisasi, step result, dan transaksi terbatas. | Tersedia dan terhubung | Masih berupa blok string agregat; perlu builder adaptif berbasis capability dan budget yang lebih ketat. |
| Planner | Planner membuat read → navigate → draft → save → verify pada satu intent/draft. | Terhubung | Belum ada multi-draft, kondisi, parallel-read, atau state recovery. |
| Learning | Memori, contoh belajar, pertanyaan belum terjawab, ekspor/impor knowledge pack, edit, archive, dan reminder pagi tersedia pada Pusat Pengetahuan. | Tersedia dan terhubung | Belum ada observasi event yang menghasilkan kandidat otomatis, approval provenance, atau rollback versioned. |
| Saran proaktif | Ada service saran halaman berbasis destination/model-ready/conversation-empty. | Tersedia | Belum membaca fakta finansial atau lifecycle saran; tidak boleh ditingkatkan menjadi auto-action. |
| Visi | Jalur gambar ke Qwen2-VL tersedia; v84 menyimpan diagnosis aman untuk file model, native init, inference, respons, proposal, dan timeout. | Terhubung secara source | Inference nyata pada perangkat belum boleh diklaim. |

## Matriks capability yang benar-benar terdaftar

| Kelompok | Capability yang terdaftar | Adapter eksekusi | Jalur yang masih perlu ditutup |
|---|---|---|---|
| Navigasi | Seluruh `navigate.{destination}` dari katalog halaman | Ditangani sebagai handoff AppShell/UI dan ditandai skipped di executor | Uji deep-link/cold-start dan konteks setelah navigasi. |
| Read-only | `read.summary`, transactions, accounts, categories, analysis, activity, budget, goals, assets, liabilities, receivable, recurring, reminders, model status | Handler untuk seluruh item ini terdaftar di adapter registry | Filter/query belum seragam; beberapa ringkasan masih dangkal dan tidak memiliki provenance per fakta. |
| Draft create | Income, expense, transfer, profil, aktivitas, pengingat, Data Utama, target, aset, hutang, piutang, anggaran, setoran/pemakaian target | Draft handler generik dan `mutate.save_draft` memilih adapter domain | Perlu audit per-domain atas field wajib, ambiguity, preview yang terbaca, dan verifier yang tepat. |
| Update / archive / delete | Update/archive/delete transaksi; archive/delete aktivitas | Adapter dan verifier khusus transaksi/aktivitas tersedia | Update/arsip/hapus setara untuk target, aset, hutang, piutang, anggaran, pengingat, Data Utama, dan profil belum terdaftar sebagai draft kind/intent khusus. |
| Verify | `verify.saved_draft`, transaksi, aktivitas | Ada di registry | `verify.saved_draft` harus diaudit karena implementasi transaksi tidak dapat otomatis membuktikan seluruh domain non-transaksi. |
| Sensitif | `sensitive.delete` | Dialihkan ke delete transaksi/aktivitas saat ini | PIN/risk policy dan pilihan entitas harus diperluas secara eksplisit sebelum domain lain memiliki hapus. |

## Pemetaan intent dan keterbatasan sebenarnya

Interpreter mengenali draft untuk profil, aktivitas, pengingat, Data Utama, target, aset, hutang, piutang, anggaran, serta transaksi. Planner juga memetakan seluruh `FfmAssistantDraftKind` tersebut ke capability draft, save, dan verify. Ini membantah asumsi bahwa semua adapter domain non-transaksi belum ada.

Namun, model proposal Qwen2-VL saat ini hanya memetakan proposal create secara eksplisit untuk **expense, income, dan transfer**, serta navigation/read/help. Artinya, domain lain dapat dijangkau oleh rule parser deterministik, tetapi belum tentu tercapai andal dari proposal SLM. Pada Fase 1 dan Fase 2, peta proposal, validator, dan capability harus disatukan tanpa menurunkan guard deterministik.

## Gap yang disetujui untuk ditangani berurutan

| Prioritas | Gap faktual | Risiko bila tidak ditutup | Arah penyelesaian |
|---|---|---|---|
| P0 | Verifikasi simpan non-transaksi belum dibuktikan per domain. | Agent dapat menyatakan berhasil tanpa readback yang spesifik. | Buat verifier dan test per domain sebelum menambah mutasi baru. |
| P0 | Update/archive/delete baru jelas untuk transaksi dan aktivitas. | Personal manager tidak dapat mengoreksi data domain lain dengan jalur aman. | Tambahkan satu domain per perubahan dengan draft, preview, PIN bila perlu, audit, dan verify. |
| P0 | Context masih agregat dan salah satu jalur proposal SLM terbatas. | Jawaban SLM kurang tepat atau menerima konteks berlebih. | Capability-aware context builder dan parser proposal yang tervalidasi. |
| P1 | Planner hanya mendukung satu draft dan langkah linear. | Perintah lintas-domain tidak dapat dijelaskan/ditangani secara konsisten. | Workflow deklaratif terbatas dengan read grouping, kondisi lokal, serial write, dan recovery. |
| P1 | Learning belum membentuk kandidat dari koreksi/pola. | Knowledge center tetap manual dan tidak cukup membantu personalisasi. | Event observasi tersanitasi → kandidat lokal → review/approve/rollback. |
| P1 | Saran proaktif tidak berbasis fakta lokal. | Saran terlalu generik dan berpotensi mengganggu. | Evaluator read-only, alasan/evidence, cadence, dismiss/snooze, tanpa auto-action. |
| P2 | Catatan, Tugas, Rutinitas, dan Jadwal belum ada secara faktual pada skema. | Klaim Personal Life Manager melebihi source. | Domain baru dikerjakan satu per satu: Catatan → Tugas → Rutinitas → Jadwal. |
| P2 | Inference visi belum diuji perangkat. | Kesiapan file salah ditafsir sebagai fungsi vision. | Pertahankan diagnosis v84; lakukan uji fisik hanya pada fase validasi perangkat yang diizinkan. |

## Invarian pengembangan

1. Tidak ada perubahan database tanpa migrasi Drift, repository, test migrasi, backup/restore bila perlu, dan audit dampak context Agent.
2. Tidak ada mutasi yang melewati draft, preview/edit, konfirmasi eksplisit, executor allowlist, pembacaan ulang, serta audit lokal.
3. Tidak ada fitur yang diklaim tersedia hanya karena capability terdaftar; status harus membedakan registry, jalur terhubung, test, dan bukti perangkat.
4. Tidak ada build APK atau signing selama roadmap ini belum selesai. Checkpoint source GitHub diperbolehkan setelah quality gate fase yang relevan lulus.
