# Master Plan Upgrade Agent FFM — Prioritas Tanpa Build

## Tujuan

Mengubah fondasi agent saat ini menjadi asisten/operator FFM offline yang lebih pintar, jujur, kontekstual, dan dapat diandalkan. Agent harus memahami seluruh aplikasi dan user, membaca data melalui adapter aman, membuat laporan, memberi saran berbantuan SLM, menjalankan workflow lintas halaman, serta meminta konfirmasi sebelum setiap mutation final.

Orchestrator tetap menjadi pengendali policy, capability, Action Plan, database, user approval, dan verifikasi. SLM lokal menjadi engine pemahaman bahasa/gambar, extraction, reasoning, narasi, dan insight; SLM tidak menjadi sumber kebenaran angka dan tidak mengakses database/SQL secara bebas.

Tidak ada build APK/debug/release/signing selama seluruh fase plan ini. Setelah setiap milestone besar selesai dan tervalidasi, buat source ZIP bersih tanpa key, model GGUF, APK/AAB, cache, build output, log build, atau arsip source asli.

## Kondisi awal yang harus dipertahankan

Fondasi saat ini meliputi knowledge registry halaman/domain/schema bounded, page context, user model approved, chat history lokal, widget gateway, Action Plan, adapter read summary/transactions/accounts/categories/analysis, adapter mutation income/expense/transfer, report preview service/chat, recommendation read-only, dan SLM gateway lokal. Validasi terakhir adalah 226 test lulus dan analyzer bersih.

Kemampuan yang belum boleh diklaim selesai penuh: adapter semua domain, callback form ke Action Plan, PDF/file final langsung dari chat, narrative SLM recommendation yang lengkap, controlled learning UI dengan rollback penuh, physical Android Qwen inference, dan full app operator.

## Prioritas implementasi

### Prioritas 1 — Orchestrator intelligence core

1. Satukan `FfmAssistantReasoningContext` pada semua jalur model-first, report, recommendation, dan workflow.
2. Perluas planner menjadi goal-oriented: pecah tujuan menjadi langkah, dependencies, required fields, clarification, risk, confirmation policy, expiry, dan verifier.
3. Tambahkan output contract SLM: intent, extracted fields, facts, clarification, suggested capability, insight, confidence, dan source.
4. Validasi hasil SLM dengan schema/allowlist; tolak capability tidak aktif, route asing, angka hasil halusinasi, SQL, secret, dan instruksi bypass confirmation.
5. Tambahkan explainability status: sumber jawaban, confidence, langkah yang dilakukan, preview, awaiting confirmation, executed, verified, failed, atau fallback.
6. Pastikan retry, cancel, timeout, dan duplicate callback idempotent.

**Kriteria:** agent dapat menjelaskan alasan pemilihan capability dan selalu membedakan jawaban, draft, preview, dan aksi final.

### Prioritas 2 — Pengetahuan lengkap tentang FFM

1. Pastikan setiap destination memiliki deskripsi fungsi, input, output, prasyarat, relasi domain, dan capability aktif.
2. Lengkapi adapter read untuk budget, target, aset, utang/piutang, recurring, reminder, aktivitas, audit, privacy, diagnostics, local model, backup, dan training.
3. Buat domain relation map: transaksi ↔ rekening/kategori; budget ↔ kategori/periode; target ↔ setoran/penggunaan; aset/kewajiban ↔ cashflow; recurring/reminder ↔ tanggal.
4. Perluas page context dinamis untuk filter, selected entity, validation state, summary, dan sumber data.
5. Jangan mengirim seluruh row atau SQL mentah; semua adapter menghasilkan bounded summary dengan redaction.

**Kriteria:** agent dapat menjawab fungsi, prasyarat, dan kondisi seluruh halaman serta membaca ringkasan seluruh domain secara aman.

### Prioritas 3 — Laporan dan dokumen

1. Dukung permintaan natural language untuk laporan harian/mingguan/bulanan, cashflow, budget, target, aset/kewajiban, recurring, aktivitas, dan laporan custom.
2. Agent menentukan periode/modul/gaya/anonimisasi lalu membuat preview.
3. Aggregator lokal menjadi sumber angka; SLM hanya menulis narasi dan insight dari JSON bounded.
4. Tampilkan DATA ASLI, PERHITUNGAN, dan INTERPRETASI SLM secara terpisah.
5. Tambahkan exporter file resmi Markdown/HTML/PDF/JSON bila tersedia, dengan nama file aman, lokasi lokal, dan aksi share eksplisit.
6. Jangan mengklaim file sudah dibuat sebelum exporter mengembalikan file yang nyata.

**Kriteria:** perintah laporan dari chat menghasilkan preview benar; ekspor final hanya berjalan setelah aksi eksplisit user.

### Prioritas 4 — Recommendation dan proaktif aman

1. Adapter/aggregator menghasilkan facts deterministic.
2. Rule engine mendeteksi budget mendekati batas, cashflow negatif, target tertinggal, recurring/reminder mendekat, transaksi tidak biasa, kualitas data, dan model belum siap.
3. SLM membuat insight bahasa Indonesia dari facts tanpa mengubah angka.
4. Tambahkan deduplication, expiry, dismiss, snooze, frequency limit, source page, dan audit reason.
5. Saran yang hanya membaca boleh tampil proaktif; saran yang mengubah data harus menjadi draft Action Plan.
6. Widget hanya menampilkan cache aman dan shortcut; tidak menjalankan background mutation.

**Kriteria:** agent memberi saran yang relevan, tidak mengganggu, dapat ditutup, dan tidak pernah mengubah database otomatis.

### Prioritas 5 — Mengenal user dan controlled learning

1. UI Assistant Training/Privacy untuk melihat, mengubah, menghapus, dan melupakan identity, alias, preference, dan approved workflow.
2. Simpan feedback user sebagai event terstruktur.
3. Candidate workflow selalu pending sampai user approve.
4. Tambahkan version, conflict detection, replay validation, archive, rollback, dan import review.
5. Backup/restore mempertahankan status approved/pending/rejected serta scope dan provenance.
6. Jangan melakukan observasi/background learning diam-diam; idle analysis hanya boleh setelah opt-in yang jelas.

**Kriteria:** agent dapat menyesuaikan gaya dan workflow approved, tetapi tidak mengubah perilaku berdasarkan tebakan atau memory pending.

### Prioritas 6 — Workflow operator lintas halaman

1. Pasang adapter mutation untuk target, aset, utang/piutang, budget, recurring, reminder, dan master data.
2. Gunakan flow universal: resolve → validate → prepare → preview → confirmation → execute once → verify → audit.
3. Hubungkan tombol Simpan/Batal pada form resmi dengan Action Plan.
4. Sediakan progress per step dan error yang dapat dipulihkan.
5. Pertahankan seluruh capability sensitif dengan confirmation eksplisit dan audit.

**Kriteria:** agent dapat mengerjakan workflow lintas domain tanpa tap automation palsu dan tanpa status selesai palsu.

## Test plan wajib

Tambahkan unit, integration, dan widget tests untuk:

- semua destination/domain tercakup registry;
- reasoning context bounded, redacted, dan diteruskan ke SLM;
- output SLM invalid/unauthorized/SQL/secret ditolak;
- planner multi-step meminta klarifikasi untuk field wajib;
- report angka konsisten antara aggregator, preview, dan narasi;
- exporter tidak menulis sebelum aksi eksplisit;
- recommendation facts deterministic, insight terpisah, deduplication/expiry/dismiss bekerja;
- user memory approved dipakai, pending tidak dipakai;
- backup/restore mempertahankan status learning dan privacy opt-in;
- mutation preview-confirm-execute-once-verify pada setiap domain;
- form callback menghasilkan status Action Plan yang benar;
- fallback deterministic bekerja ketika SLM belum siap/gagal;
- prompt tidak berisi raw SQL, PIN, token, secret, atau seluruh rows;
- widget tidak memanggil mutation/background save.

## Urutan milestone

1. **M1 Intelligence Core:** reasoning context, output contract, validation, explainability, planner multi-step.
2. **M2 Complete Knowledge/Read:** seluruh domain read adapter dan page context dinamis.
3. **M3 Report/Document:** laporan natural-language, narrative SLM, exporter file lokal.
4. **M4 Proactive Recommendation:** facts engine, SLM insight, UI proactive, widget cache.
5. **M5 User/Learning:** training/privacy UI, feedback, approval, rollback, backup review.
6. **M6 Full Operator:** mutation adapters domain tersisa, form callback, cross-page verification.
7. Setiap milestone: format → analyze → targeted test → full test → dokumentasi → source ZIP.

## Risiko dan keputusan keamanan

SLM offline tidak berarti bebas akses. Semua akses tetap melalui capability allowlist dan adapter. Angka/identitas sensitif diminimalkan. Tidak ada cloud fallback setelah setup offline. Tidak ada autosave, autonomous CRUD, silent background mutation, atau auto-approval learning. Physical Android inference Qwen2-VL harus diuji terpisah pada perangkat sebelum klaim distribusi.

## Kriteria selesai keseluruhan

Agent dapat menjelaskan seluruh kemampuan aktual, memahami konteks FFM dan user approved, membaca seluruh domain melalui summary aman, menyusun laporan/file, memberi saran berbantuan SLM, menjalankan workflow lintas halaman melalui preview-confirm-execute-verify, belajar hanya dengan approval, serta melaporkan sumber/status jawaban secara jujur. Semua test lulus, analyzer bersih, dokumentasi akurat, dan ZIP source setiap milestone tersedia. APK hanya dibuat jika user memberikan perintah build eksplisit.
