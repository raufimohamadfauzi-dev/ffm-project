# Assistant / Agent Execution Plan

> Dokumen kerja aktif. Setiap tahap hanya ditandai selesai setelah kode, test
> relevan, dan bukti verifikasi dicatat. Rujukan arsitektur lengkap ada di
> `docs/assistant_agent_roadmap.md`.

## Batas Arsitektur yang Tidak Boleh Dilanggar

- Gemini/LLM memahami permintaan dan menyusun bahasa natural, bukan sumber
  nilai finansial atau pelaksana mutasi data.
- Data dan analisis berasal dari capability/query deterministik.
- Aksi write selalu melalui draft terstruktur, validasi, konfirmasi bila
  diwajibkan, executor, dan verifikasi hasil.
- Context LLM harus terbatas, relevan, dan tidak memuat secret.

## Status Keseluruhan

- [ ] Tahap 0 — Audit baseline dan peta alur runtime
- [ ] Tahap 1 — Stabilkan routing dan fallback assistant
- [ ] Tahap 2 — Standarkan tool contract dan registry
- [ ] Tahap 3 — Analysis tools dan verified-fact context
- [ ] Tahap 4 — Hardening draft, validasi, konfirmasi, eksekusi, verifikasi
- [ ] Tahap 5 — Multi-turn conversation, memory, dan clarification
- [ ] Tahap 6 — Debug trace dan replay yang aman
- [ ] Tahap 7 — Test harness, golden conversation, dan regresi
- [ ] Tahap 8 — Validasi akhir dan handoff ke roadmap Activity Intelligence

---

## Tahap 0 — Audit Baseline dan Peta Alur Runtime

Status: **sedang dikerjakan**

- [x] Petakan jalur: UI → interpreter/orchestrator → tool/capability →
  repository/backend → verified result → respons.
- [ ] Petakan jalur Gemini dan pastikan hanya menggunakan context/capability
  yang diizinkan.
- [x] Inventarisasi jalur jawaban fallback dan kondisi yang berisiko memberi
  jawaban tanpa data.
- [ ] Inventarisasi test assistant yang sudah ada dan gap prioritas.
- [ ] Catat temuan serta file pemilik setiap kontrak sebelum mengubah kode.

Kriteria selesai: diagram/peta ringkas, daftar gap terurut P0/P1, dan tidak
ada asumsi membuat arsitektur paralel.

## Tahap 1 — Routing dan Fallback

Status: belum mulai

- [ ] Klasifikasikan percakapan, read/query, analysis, action, clarification,
  confirmation, cancellation, dan multi-step secara konsisten.
- [ ] Pastikan pertanyaan yang memerlukan data tidak menjawab seolah data ada
  saat tool/data gagal.
- [ ] Pastikan kegagalan provider, backend, autentikasi, timeout, dan output
  model tidak valid memiliki respons jujur serta dapat dipulihkan.
- [ ] Tambah/ubah test routing yang menutup temuan Tahap 0.

## Tahap 2 — Tool Contract dan Registry

Status: belum mulai

- [ ] Pastikan setiap capability menyatakan input, output, read/write,
  confirmation, error, dan batas datanya.
- [ ] Hilangkan kontrak duplikat atau jalur tool yang bypass validator/executor.
- [ ] Pastikan Gemini hanya dapat memakai capability read yang diizinkan.
- [ ] Tambahkan test kontrak/registry untuk capability kritis.

## Tahap 3 — Analysis dan Verified Facts

Status: belum mulai

- [ ] Identifikasi analisis yang sudah deterministik dan gap capability-nya.
- [ ] Bentuk output fakta terstruktur: periode, filter, metrik, sumber, dan
  fakta terverifikasi.
- [ ] Pastikan LLM hanya menjelaskan fakta itu, tidak membuat angka sendiri.
- [ ] Tambahkan test empty data, data besar, periode, dan grounding.

## Tahap 4 — Action Draft Flow

Status: belum mulai

- [ ] Semua write action menghasilkan draft/JSON terstruktur lebih dahulu.
- [ ] Validasi field, otorisasi, idempotensi, serta confirmation policy berada
  di aplikasi, bukan pada model.
- [ ] Hasil eksekusi diverifikasi sebelum respons sukses dikirim.
- [ ] Tangani pembatalan dan kegagalan parsial secara eksplisit.
- [ ] Tambahkan test koreksi draft, konfirmasi, eksekusi ganda, dan verifikasi.

## Tahap 5 — Percakapan, Memory, dan Clarification

Status: belum mulai

- [ ] Follow-up merujuk draft/konteks yang tepat.
- [ ] Ambiguitas meminta klarifikasi, bukan memilih data sendiri.
- [ ] Memory bersifat eksplisit, dapat direview/dihapus, serta tidak tersimpan
  tanpa persetujuan.
- [ ] Tambahkan test multi-turn Indonesia untuk correction dan cancellation.

## Tahap 6 — Debug Trace dan Replay

Status: belum mulai

- [ ] Trace aman menampilkan intent, planner, tool, parameter tersaring,
  result, facts, dan status akhir tanpa chain-of-thought atau secret.
- [ ] Siapkan format replay untuk percakapan gagal yang sudah disanitasi.
- [ ] Tambah test trace agar kegagalan bisa dilokalisasi.

## Tahap 7 — Test Harness dan Regresi

Status: belum mulai

- [ ] Lengkapi harness: routing, tool, draft, validation, executor,
  Gemini-routing, memory, concurrency, dan UI integration.
- [ ] Tambahkan golden conversation: greeting, read, analysis, create/update,
  correction, confirm, cancel, failure, dan multi-tool.
- [ ] Jalankan analyzer serta test relevan dan catat hasil nyata.

## Tahap 8 — Validasi Akhir dan Handoff Activity Intelligence

Status: belum mulai

- [ ] Audit ulang semua batas arsitektur di atas.
- [ ] Pastikan tidak ada klaim sukses palsu atau angka finansial dari LLM.
- [ ] Dokumentasikan capability/fact contract yang dapat dipakai Activity
  Intelligence.
- [ ] Mulai roadmap `activity_intelligence_upgrade.md` hanya setelah
  prerequisite query, analysis, dan verified facts telah siap.

## Log Verifikasi

Tambahkan entri singkat setelah tiap tahap selesai:

| Tanggal | Tahap | Bukti (test/analyzer/review) | Catatan |
| --- | --- | --- | --- |
| - | - | - | - |
| 2026-08-31 | 0 | Review `FfmAssistantInterpreter`, Gemini orchestrator, proposal parser, read capability service, executor, dan test routing | P0 ditemukan: instruksi Gemini menawarkan capability di luar batas bounded; `read.activity` bahkan tidak memiliki adapter cloud. Kontrak kini disempitkan ke `read.summary`/`read.transactions`. Test fokus dijalankan tetapi runner tidak mengembalikan exit code/output; ulangi pada sesi terminal bersih. |
