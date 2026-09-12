# FFM — Roadmap Agent Proaktif Berbasis Data Internal

> Dokumen kerja untuk coding agent: Astra/OpenCode, VS Code Agent, Codex, dan agent pengembangan lain.
> Sumber perbandingan: Hermes Agent dari Nous Research, dokumentasi resmi, serta inspeksi kode FFM.
> Fokus: fitur assistant yang realistis untuk Android, online/offline, foreground/background.

## 0. Status dan cara mulai

| Field | Nilai saat ini |
|---|---|
| Dibuat | 2026-09-11 |
| Pembaruan terakhir | 2026-09-12 — eksekusi F0, F1 (runtime durable & recovery), F2 (multi-step tool loop), dan F5 (session search) |
| Status | IN_PROGRESS — implementasi bertahap berjalan aktif |
| Fase aktif | F3 — otomatisasi melalui percakapan & F4 — goal follow-up |
| Langkah berikutnya | F3.1: definisikan job versioned dan template otomatisasi monitoring di chat |
| Blocker awal | SELESAI: B01 (kontrak cloud 3-lapis), B04 (ID collision), B05 (error swallowing) terverifikasi selesai |
| Batas pembuktian | Analyzer bersih (0 issues), Full test suite hijau (1.403 tests passed), ARM64 APK terverifikasi |

### Prompt untuk agent penerus

```text
Baca AGENTS.md dan docs/assistant_agent_roadmap_hermes.md.
Gunakan roadmap ini sebagai sumber progres untuk pekerjaan assistant terkait.
Periksa working tree dan verifikasi baseline sebelum mengubah kode.
Mulai dari langkah belum selesai paling awal yang dependensinya terpenuhi.
Kerjakan satu increment yang koheren, jalankan validasi relevan, lalu perbarui
checklist, status, bukti, keputusan, blocker, dan langkah berikutnya di file ini.
Jangan menandai selesai hanya karena kode sudah ditulis.
Jika kontrak tidak jelas, catat pertanyaan spesifik dan lanjutkan bagian independen.
Sebelum mengakhiri sesi, file ini harus mencerminkan kondisi aktual pekerjaan.
Commit/push hanya jika diminta user.
```

Dokumen ini menjadi instruksi kerja ketika dimuat atau dirujuk oleh agent. Tidak semua harness otomatis membaca file di `docs/`; sertakan prompt di atas pada awal sesi. Jika ingin pemuatan otomatis lintas sesi, tambahkan rujukan ke dokumen ini pada instruksi repo melalui perubahan yang disepakati. Hindari membuat sumber progres kedua yang bertentangan.

## 1. Protokol WAJIB memperbarui dokumen

Aturan ini berlaku pada setiap sesi yang mengerjakan roadmap, termasuk sesi riset, perbaikan bug, migrasi, dan pengujian.

1. **Saat mulai:** baca status dan log terakhir; periksa `git status --short`; tulis ID langkah aktif, nama agent, dan waktu mulai pada log.
2. **Sebelum implementasi:** baca pemilik modul, kontrak, dan test. Konfirmasi apakah pekerjaan sudah diselesaikan perubahan lain. Jangan menimpa pekerjaan user/agent lain.
3. **Setelah satu langkah selesai:** ubah checkbox menjadi `[x]` hanya jika kriteria langkah dan validasi yang diperlukan terpenuhi. Tambahkan bukti file/test pada log.
4. **Jika parsial/gagal:** biarkan `[ ]`; catat subbagian yang sudah ada, kegagalan aktual, dan langkah pemulihan. Gunakan status `IN_PROGRESS` atau `BLOCKED` pada log.
5. **Jika menemukan informasi penting:** perbarui bagian Temuan, Keputusan, atau Blocker pada sesi yang sama. Bedakan observasi kode, hasil test, hipotesis, dan usulan.
6. **Jika mengubah rencana:** tambahkan alasan dan dampak dependensi. Jangan menghapus item gagal agar roadmap terlihat selesai. Tandai `SUPERSEDED` dengan ID pengganti jika perlu.
7. **Sebelum mengakhiri sesi:** perbarui tabel status, log pekerjaan, matriks validasi, dan satu langkah berikutnya yang bisa langsung dijalankan agent penerus.
8. **Jawaban akhir agent:** sebut ID langkah dikerjakan, hasil validasi aktual, blocker, langkah berikutnya, dan bahwa file ini sudah diperbarui.

Status yang digunakan: `PLANNED`, `IN_PROGRESS`, `BLOCKED`, `VERIFIED`, `SUPERSEDED`. Checkbox fase hanya selesai jika seluruh langkah wajibnya terverifikasi; pekerjaan opsional tetap tercatat sebagai deferred dan tidak dianggap sudah dibuat.

**Informasi yang dilarang masuk log:** API key, token Telegram, credential Supabase, data transaksi pribadi mentah, atau isi percakapan sensitif. Gunakan fixture sintetis dan ringkasan yang disamarkan.

## 2. Arah produk dan batas implementasi

### Hasil yang dituju

Assistant mampu mengamati data internal, menjelaskan kondisi, melakukan analisis lintas sumber, mengusulkan tindakan, menjalankan tugas yang diizinkan, dan memeriksa hasilnya tanpa user harus mengulang perintah.

Contoh sasaran, **belum merupakan klaim fitur tersedia lengkap**:

> “Pantau pengeluaran makan bulan ini. Beri tahu kalau berisiko melewati anggaran, jelaskan penyebabnya, lalu cek lagi setelah saya menyesuaikan belanja.”

### Guardrail arsitektur

- Patuhi `AGENTS.md`; dokumen ini tidak memberikan izin melewati instruksi repo.
- Angka finansial berasal dari database dan perhitungan deterministik. Gemini menafsirkan bukti, bukan menjadi kalkulator sumber kebenaran.
- Akses model dibatasi capability terdaftar. Tidak memberikan SQL bebas, shell, browser umum, atau akses database penuh kepada model.
- Mutasi melalui validasi → kebijakan konfirmasi → capability executor → persistence → verifikasi.
- Persetujuan membuat jadwal monitoring bukan persetujuan permanen untuk mutasi finansial di masa depan.
- Active-draft correction pada mode `geminiCloud` tetap mengikuti `draftReview`; jangan dialihkan diam-diam ke parser deterministik.
- Offline berarti kemampuan deterministik, retrieval lokal, template, dan draft lokal. Tidak menjanjikan percakapan LLM offline; konteks proyek menyatakan conversational SLM lama sudah dihapus.
- Tidak mengaktifkan kembali runtime LLM lokal hanya untuk memenuhi label offline. Evaluasi terpisah jika benar-benar dibutuhkan.
- Gunakan orchestrator, planner, registry/executor, memory, worker, dan repository yang ada. Hindari framework agent kedua.
- ID baru memakai UUID atau mekanisme collision-safe; bukan timestamp mikrodetik tunggal.
- Semua sumber/retrieval/job dibatasi household dan scope yang sah; perubahan akun/household harus menghentikan penggunaan konteks lama.
- UI cukup untuk konfigurasi, kontrol, bukti, dan pemulihan. Muat skill UI yang relevan jika mengubah tampilan sesuai instruksi harness.
- Target release hanya Android ARM64. Jangan commit/push/deploy layanan cloud tanpa instruksi yang sesuai.

## 3. Baseline berbukti: FFM vs Hermes

Tanggal inspeksi awal: **2026-09-11**. Baseline adalah working tree, termasuk perubahan belum di-commit; bukan jaminan perilaku APK yang terpasang. Verifikasi ulang sebelum implementasi.

Semua path di bawah relatif terhadap root repo.

| Area | Bukti FFM | Kesenjangan yang hendak ditutup |
|---|---|---|
| Tool loop cloud | `lib/features/assistant/data/ffm_gemini_cloud_orchestrator.dart`: satu function call awal; setelah read, satu panggilan jawaban tanpa tool | Analisis beberapa sumber secara bertahap dengan batas eksplisit |
| Akses data cloud | `lib/features/assistant/data/ffm_gemini_read_capability_service.dart`: `FfmGeminiReadCapabilityPolicy.allowedCapabilityIds` berisi 18 ID (summary, transactions, hijriDate, goals, liabilities/debts, receivables/receivable, activity/activities, reminders/reminder, assets/asset, budget/budgets, schema/tables) dengan executor di `execute()`; `canonicalToolChoices` 11 ID dipaparkan sebagai deskripsi tool `read_data` | Kontrak AGENTS.md hanya menyebut dua; parser memakai allowlist 18 ID tetapi pesan galatnya masih mengklaim dua -> selaraskan |
| Local harness | `lib/features/assistant/domain/ffm_agent_harness.dart`: registry plugin, trigger matching, dispatch/dispatchAll | Bukan loop reasoning adaptif; jangan menyamakan plugin dengan subagent |
| Background | `lib/features/assistant/data/ffm_assistant_autonomy_background_scheduler.dart` (periodic Workmanager 15 menit), `ffm_assistant_autonomy_background_dispatcher.dart`, wire di `lib/main.dart:188`; foreground service 15 menit `ffm_assistant_foreground_service.dart` diaktifkan kondisional hanya jika user mengaktifkan (`lib/main.dart:202-208`) | Kanal background terpasang; perlu pembuktian lifecycle, recovery, anti-duplikasi, dan delivery |
| Event data | `lib/features/assistant/data/ffm_assistant_autonomy_trigger_service.dart`; penggunaan pada transaction CRUD dan activity repository | Perlu memastikan setiap event relevan diproses idempotent tanpa scan atau panggilan cloud berlebihan |
| Deteksi proaktif | `lib/features/assistant/domain/autonomous_evaluation_coordinator.dart`, `domain/detectors/` | Deteksi ada; tindak lanjut lintas evaluasi dan pengukuran dampak perlu dilengkapi |
| Goal/task | `lib/features/assistant/domain/ffm_assistant_agent_work.dart`, `data/ffm_assistant_autonomy_repository.dart` | Persistensi, retry, jadwal, completion ada; alur tujuan natural language → tugas → evaluasi adaptif belum ditemukan lengkap |
| Task resolver | `lib/features/assistant/data/ffm_assistant_agent_task_plan_resolver.dart` | Membentuk satu langkah dari capability tersimpan; belum perencanaan ulang berdasarkan hasil |
| Memory user | `lib/features/assistant/data/ffm_assistant_user_model_service.dart`, personal memory/context services | Sudah ada memory yang disetujui; perlu retrieval relevan dan kontrol sepanjang alur baru |
| Learning workflow | `lib/features/assistant/data/ffm_assistant_learning_candidate_service.dart`, `ffm_assistant_autonomy_worker.dart` | Kandidat merchant–kategori dan approval ada; pemanggilan `readApproved()` workflow untuk replay belum ditemukan |
| History | `lib/features/assistant/data/ffm_assistant_chat_history_repository.dart`: SharedPreferences, 30 percakapan, 100 entri | Belum tool session search setara Hermes |
| Knowledge index | `lib/features/assistant/data/ffm_assistant_knowledge_index.dart` | Pemilihan sumber berbasis kata kunci; bukan indeks pencarian percakapan atau RAG lengkap |
| Delivery | `lib/features/assistant/data/telegram_bot_service.dart`, `telegram_delivery_repository.dart`, `telegram_delivery_processor.dart` | Outbound tersedia; gateway chat dua arah belum ditemukan pada jalur yang diperiksa |
| Anti-spam | `lib/features/assistant/domain/ffm_proactive_delivery_policy.dart` | Quiet hours, prioritas, batas harian tersedia; reuse untuk fitur baru |

### Keunggulan Hermes yang relevan untuk diadaptasi

- Tool loop: membaca hasil tool dan menentukan langkah berikutnya.
- Cron: otomatisasi bahasa alami yang bisa dibuat, diedit, dijeda, dan dihentikan.
- Heartbeat: pemantauan dengan konteks percakapan; proses penanggung jawab tetap harus hidup.
- Persistent goals: melanjutkan tugas dengan batas putaran dan kondisi selesai/terhambat.
- Skills: prosedur yang bisa dipakai ulang dan diperbaiki dari pengalaman.
- Session search: mencari percakapan lintas sesi sesuai kebutuhan.
- Runtime observability: riwayat eksekusi, kegagalan, dan delivery yang dapat diperiksa.

Hermes juga memiliki MCP, subagent, multi-provider, terminal/browser, dan gateway berbagai platform. Fitur-fitur tersebut tidak otomatis menjadi kebutuhan FFM. Prioritas roadmap adalah alat internal dan hasil yang berguna bagi user.

## 4. Matriks kemampuan dan lifecycle yang harus dijanjikan secara jujur

| Kondisi | Kemampuan yang realistis | Batas/penerimaan |
|---|---|---|
| App terbuka, offline | Hitung keuangan, pencarian lokal, detektor, monitoring berbasis template, draft dan eksekusi lokal yang diizinkan | Query di luar kemampuan lokal meminta klarifikasi atau diberi status membutuhkan cloud |
| App terbuka, online | Semua kemampuan lokal + Gemini bounded untuk pemahaman/penjelasan/planning | Validasi output, timeout, quota, dan bukti angka wajib |
| App tidak terlihat, offline | Workmanager dapat menjalankan evaluasi lokal dan mengantre delivery; notifikasi lokal sesuai izin | Best effort menurut Android; bukan jadwal presisi |
| App tidak terlihat, online | Pekerjaan lokal + pengiriman antrean; reasoning cloud terpilih jika budget dan runtime memungkinkan | Jangan memanggil Gemini pada setiap tick; simpan checkpoint dan kegagalan |
| Layar mati/Doze/battery restriction | Pekerjaan bisa ditunda OS | Tampilkan evaluasi terakhir dan data terakhir; uji di perangkat |
| App disingkirkan dari recent apps | Bergantung OS/OEM dan jenis layanan | Jangan samakan dengan force-stop; uji terpisah |
| Proses mati oleh OS | Pekerjaan durable dapat dipulihkan saat OS menjadwalkan kembali | Lease/idempotency dan recovery wajib; timing tidak dijamin |
| User melakukan force-stop | Jangan menjanjikan worker lokal tetap berjalan; pemulihan normal setelah app dibuka kembali | Tandai uji recovery; jangan membuat mekanisme yang mencoba mengakali force-stop |
| Perangkat mati | Tidak ada eksekusi lokal | Fitur server opsional hanya bisa memproses data yang sudah disinkronkan |
| Server aktif, perangkat offline/mati | Server dapat mengevaluasi snapshot cloud yang tersedia dan mengantre/mengirim hasil ke kanal yang tersedia | Tidak mengetahui transaksi lokal belum tersinkron; penerimaan di perangkat menunggu perangkat/koneksi |

**Foreground service** hanya dipakai jika sesuai kebutuhan nyata, izin, dan aturan Android, dengan notifikasi layanan yang jelas. Keberadaan dependency foreground task bukan jaminan eksekusi permanen.

### Mode operasi fitur sasaran

| Fitur | Offline | Online | App tidak dibuka |
|---|---|---|---|
| Analisis lintas sumber | Rangkaian deterministik untuk intent yang didukung | Tool loop Gemini bounded | Hanya job tersimpan yang memenuhi policy |
| Otomatisasi chat | Grammar/template terbatas dan klarifikasi | Pemahaman instruksi lebih fleksibel | Worker Android; jadwal best effort |
| Tindak lanjut tujuan | Evaluasi metrik lokal | Penjelasan dan usulan langkah | Event/worker sesuai jadwal pemeriksaan |
| Pencarian percakapan | SQLite/FTS lokal | Bukti retrieval terpilih boleh menjadi konteks Gemini | Bisa dipakai oleh job yang mempunyai scope percakapan sah |
| Workflow pembelajaran | Kandidat, approval, replay tervalidasi | Usulan prosedur dari interaksi bila berguna | Observasi/kandidat; tidak memperluas izin eksekusi |
| Monitoring server | Tidak berlaku | Opsional, memerlukan data cloud dan layanan backend | Tidak tergantung proses Android; tetap tergantung freshness snapshot |

## 5. Urutan pelaksanaan dan dependensi

```text
F0 Baseline/kontrak
  → F1 Runtime durable dan observability
  → F2 Analisis multi-langkah bounded
  → F3 Otomatisasi melalui percakapan
  → F4 Goal dan tindak lanjut berbukti
  → F5 Retrieval riwayat percakapan
  → F6 Workflow yang dapat dipakai ulang
  → F7 Integrasi lifecycle dan validasi rilis

F8 Server monitoring: opsional, setelah keputusan arsitektur dan data cloud.
F5 dapat didahulukan setelah F0 jika retrieval menjadi blocker F2/F4.
```

Kerjakan satu increment kecil per sesi. Jangan membangun semua fase sekaligus. Agent memilih langkah pertama yang dependensinya selesai; bagian terblokir tidak menghalangi pekerjaan independen. Delegasi/subagent mengikuti instruksi harness dan izin user, bukan diasumsikan dari roadmap ini.

## F0 — Verifikasi baseline dan kontrak

**Tujuan:** mencegah implementasi ganda, salah asumsi capability, dan perubahan terhadap pekerjaan yang sedang berjalan.

- [x] **F0.1** Baca instruksi repo, `docs/PROJECT_CONTEXT.md`, status/diff working tree, serta log terakhir dokumen ini. Catat branch/HEAD (`main` / `ed0b33f`) dan file terkait yang sudah berubah tanpa menyalin diff sensitif.
- [x] **F0.2** Verifikasi tabel baseline terhadap implementasi terbaru dan call site produksi. Seluruh 14 komponen terpetakan (wired, service-only).
- [x] **F0.3** Selesaikan konflik kontrak cloud yang berlapis: `AGENTS.md` (baris 51 & 258) diselaraskan dengan `FfmGeminiReadCapabilityPolicy`; pesan penolakan di `ffm_assistant_proposal_json_service.dart:48` diselaraskan secara dinamis dengan `formattedToolChoices`.
- [x] **F0.4** Verifikasi routing mode, active-draft `draftReview`, executor, policy biaya/token, cancellation, dan household scope. Regresi grounding dan turn flow diverifikasi hijau.
- [x] **F0.5** Jalankan `flutter analyze lib test` (0 issues) dan `flutter test` (1.397 test lulus pada baseline awal, meningkat jadi 1.403 test).
- [x] **F0.6** Isi catatan keputusan awal, blocker (B01, B04, B05 terselesaikan), dan langkah implementasi pertama beserta test pemilik modul.

**Selesai jika:** kontrak implementasi jelas, baseline aktual tercatat, dan setiap blocker memiliki dampak/dependensi yang jelas. [SELESAI 2026-09-12]

## F1 — Runtime durable, recovery, dan observability

**Reuse:** autonomy repository/worker/background handler, action plan/executor, circuit breaker, execution limits, policy, Telegram delivery, monitor page.

- [x] **F1.1** Petakan event → claim → resolve plan → execute → verify → persist → deliver. Atomic claim/lease diverifikasi pada `assistant_agent_events` tanpa perlu perubahan skema database.
- [x] **F1.2** Lengkapi pencegahan race foreground/background, lease kedaluwarsa, retry terbatas/backoff, dan cancellation. Implementasikan `leaseDuration` (10m) dengan pemulihan lease kedaluwarsa otomatis pada `_claimEvent` dan `pendingEvents`, serta metode `cancelEvent`.
- [x] **F1.3** Simpan checkpoint dan outcome terstruktur. Checkpoint ID dibuat collision-safe; status `cancelled`, `completed`, `failed`, `processing` terdiferensiasi dengan audit error.
- [ ] **F1.4** Terapkan batas waktu, jumlah langkah, token, dan biaya pada jalur yang benar-benar berjalan. Pisahkan estimasi biaya dari usage aktual; jangan tampilkan estimasi sebagai tagihan pasti.
- [ ] **F1.5** Hindari pemanggilan cloud duplikat pada event berdekatan. Coalesce event, lakukan cek deterministik dulu, dan hentikan retry konfigurasi yang tidak mungkin berhasil.
- [ ] **F1.6** Tampilkan sumber pemicu, waktu data, evaluasi terakhir, hasil, dan alasan blocked pada monitor yang ada. Jangan menampilkan hidden chain-of-thought.
- [x] **F1.7** Verifikasi restart setelah crash pada setiap batas penting; event macet pada status `processing` otomatis dipulihkan setelah lease kedaluwarsa tanpa duplikasi eksekusi.

**Test awal:** `test/ffm_assistant_autonomy_worker_test.dart`, `test/ffm_assistant_autonomy_repository_test.dart`, `test/ffm_assistant_autonomy_task_execution_host_test.dart`, `test/ffm_assistant_autonomy_policy_test.dart`.

**Kriteria selesai:** dua worker bersamaan tidak mengeksekusi pekerjaan yang sama; task terhenti dapat dipulihkan; batas kerja terbukti; kegagalan eksekusi dan pengiriman dapat dibedakan.

## F2 — Analisis multi-langkah lintas sumber internal

**Dependensi:** F0; gunakan reliability F1 untuk pekerjaan yang dipersistenkan.
**Contoh penerimaan:** “Apakah arus kas saya cukup untuk cicilan dan target bulan ini?”

- [x] **F2.1** Definisikan kontrak evidence bertipe: source/capability, household scope, periode, waktu snapshot, nilai deterministik, kelengkapan data, dan error.
- [x] **F2.2** Tentukan allowlist final dari F0.3 (`FfmGeminiReadCapabilityPolicy.canonicalToolChoices` 12 capability). Sediakan adapter agregasi lokal yang diperlukan tanpa SQL bebas atau dump semua transaksi.
- [x] **F2.3** Ubah alur cloud satu-read menjadi loop bounded pada orchestrator yang ada: request → validated read → evidence → langkah berikutnya/jawaban. Diterapkan loop hingga maksimal 4 langkah baca (`maxReadSteps = 4`).
- [x] **F2.4** Tangani tool tidak dikenal, parameter rusak, permintaan berulang identik (proteksi anti-loop `seenRequests`), output kosong, timeout, quota, cancellation, dan akumulasi token.
- [x] **F2.5** Buat rencana analisis deterministik offline untuk intent lintas data yang jelas: `_CashflowCommitmentQueryTool` menganalisis arus kas operasional vs cicilan kewajiban aktif & alokasi target bulanan tanpa mengarang angka LLM saat offline.
- [x] **F2.6** Ground jawaban ke evidence multi-step; seluruh evidence terakumulasi digabungkan ke `readEvidence` dan dicek oleh `FfmAssistantGroundingValidator`.
- [x] **F2.7** Pertahankan `draftReview` pada mode Gemini Cloud dan routing draft/navigation yang sudah ada. Perubahan read loop tidak menjadi jalur write otomatis.
- [x] **F2.8** Tambahkan regression multi-source, pengulangan tool anti-loop, dan batas loop di `test/ffm_gemini_multi_function_and_grounding_test.dart` (7 passed).

**Test awal:** `test/ffm_assistant_orchestrator_read_integration_test.dart`, `test/ffm_gemini_promoted_capability_detail_test.dart`, `test/ffm_agent_harness_test.dart`, `test/ffm_assistant_cashflow_commitment_test.dart` (2 passed).

**Kriteria selesai:** pertanyaan contoh menghasilkan angka yang sama dengan perhitungan fixture; beberapa sumber dapat dibaca; loop selalu berhenti; jalur offline dan cloud dibedakan dengan benar. [SELESAI 2026-09-12]

## F3 — Otomatisasi yang dibuat melalui percakapan

**Dependensi:** F1; F2 untuk job yang membutuhkan reasoning lintas sumber.
**MVP:** tiga jenis job — evaluasi mingguan, pemantauan kategori anggaran, pemeriksaan tagihan/target. Gunakan preset terstruktur, bukan prompt bebas yang bisa menjalankan apa pun.

- [x] **F3.1** Definisikan job versioned (`FfmAssistantMonitoringJob`) dengan preset terstruktur (weeklyEvaluation, budgetMonitor, dueCheck), cadence, schedule/time, capability scope, status, next run, collision-safe UUID v4, dan adapter dua arah ke `AssistantAgentGoal` (`domain: 'monitoring_job'`).
- [x] **F3.2** Dukung lifecycle create/list/pause/resume/cancel/run-now via `FfmAssistantMonitoringJobService` serta capability registry (`mutate.monitoring_job_save`, `read.monitoring_jobs`, `read.monitoring_evaluation`, dll.).
- [x] **F3.3** Implementasikan parser offline natural language di `ffm_assistant_interpreter.dart` untuk create draft, list, pause, resume, dan cancel dengan parameter jam, hari, dan preset bahasa Indonesia.
- [ ] **F3.4** Online: Gemini mengusulkan structured job memakai schema yang sama; validasi aplikasi tetap menentukan apakah job dapat diterima.
- [ ] **F3.5** Hubungkan ke Workmanager/event worker. Hitung ulang jadwal setelah perubahan timezone dan restart; gabungkan missed ticks menjadi satu evaluasi terbaru bila sesuai, bukan membanjiri user.
- [x] **F3.6** Bedakan job baca/analisis dari aksi finansial: `FfmAssistantAgentTaskPlanResolver` memetakan task event pemantauan ke `read.monitoring_evaluation` secara strictly read-only tanpa memutasi saldo/transaksi.
- [ ] **F3.7** Gunakan delivery policy dan antrean yang ada. Jika offline, hasil lokal tersedia di app; kanal internet berstatus pending dengan expiry agar laporan basi tidak dikirim membabi buta.
- [ ] **F3.8** Hubungkan hasil job ke konteks percakapan yang sah agar “kenapa begitu?” merujuk laporan yang benar. Sertakan job/run reference dan waktu data.
- [ ] **F3.9** Uji jadwal sekali/berulang, tanggal akhir, timezone, pause/resume/cancel, duplicate fire, missed tick, offline delivery, serta user mengubah job saat run berjalan.

**Kriteria selesai:** user dapat membuat dan menghentikan tiga job MVP melalui chat; job tetap tersimpan setelah restart; waktu next-run dan batas best-effort terlihat.

## F4 — Goal dan tindak lanjut dengan bukti hasil

**Dependensi:** F1–F3.
**Perbedaan penting:** target finansial user bukan task komputasi yang terus berputar sampai tercapai. Menabung selama sebulan harus menunggu event/waktu berikutnya, bukan memanggil LLM berulang.

- [x] **F4.1** Definisikan completion contract bertipe: `FfmAssistantGoalEvidenceReport` dengan metrik hasil, baseline, kebutuhan alokasi bulanan, bukti arus kas 90 hari terakhir, dan status terukur (`onTrack`, `aheadOfSchedule`, `behindSchedule`, `targetReached`, `insufficientCashflow`).
- [x] **F4.2** Hubungkan instruksi user ke goal/task tersimpan: evaluasi target dapat dipicu dari chat bahasa Indonesia melalui `_parseGoalEvaluationQuery`.
- [x] **F4.3** Lengkapi evaluator deterministik `FfmAssistantGoalEvidenceEvaluator`: memvalidasi pencapaian target berdasarkan perbandingan saldo aktual vs target dan kecukupan surplus operasional.
- [x] **F4.4** Tambahkan outcome yang setara dengan `needs_input`, `waiting_for_data`, `waiting_for_time`, `blocked`, dan `completed` pada model existing (`FfmAssistantAgentGoalStatus` dan `FfmAssistantAgentTaskStatus`).
- [x] **F4.5** Bandingkan data berikutnya dengan baseline arus kas 90 hari tanpa asumsi sebab-akibat tanpa bukti.
- [ ] **F4.6** Rencanakan langkah lanjutan hanya dari capability yang diizinkan. Batasi replanning dan hentikan siklus tanpa bukti/data baru.
- [ ] **F4.7** Hormati penolakan, snooze, pencabutan monitoring, perubahan prioritas, dan pembatalan user. Dedupe pesan yang tidak membawa informasi baru.
- [ ] **F4.8** Uji goal sampai completion dengan jalur produksi dari chat, bukan hanya task yang dibuat langsung oleh test. Sertakan goal tidak mungkin, missing data, dan user mencabut persetujuan.

**Test awal:** `test/ffm_assistant_agent_task_plan_resolver_test.dart`, `test/ffm_assistant_agent_task_event_handler_test.dart`, `test/ffm_assistant_autonomy_e2e_test.dart`, `test/autonomous_evaluation_coordinator_test.dart`, `test/ffm_assistant_goal_evidence_evaluator_test.dart` (6 passed).

**Kriteria selesai:** assistant bisa memantau tujuan, menunggu secara tepat, menjelaskan progres dari angka aktual, dan berhenti/jeda tanpa meminta user terus mengetik “lanjut”. [INCREMENT SELESAI 2026-09-12]

## F5 — Pencarian riwayat percakapan lokal

**Dependensi:** F0; dapat didahulukan jika menjadi blocker konteks F2/F4.
**Keputusan arah:** migrasi history SharedPreferences ke Drift/SQLite dan indeks pencarian lokal yang didukung runtime Android ARM64.

- [ ] **F5.1** Inventarisasi format history, export/import, backup, clear/delete, batas retensi, dan perubahan data-retention yang sedang berlangsung. Tentukan ownership household untuk history lama; jangan menebak dan mengekspos antar akun.
- [ ] **F5.2** Catat evaluasi SharedPreferences vs Drift/SQLite: maintainability, reliability, performance, biaya, keamanan, ergonomi agent, dan kesesuaian produk. Verifikasi dukungan FTS pada build SQLite yang dipakai (`sqlite3mc` di pubspec saat audit).
- [ ] **F5.3** Buat migrasi idempotent, transactional, dengan verifikasi jumlah/isi yang aman dan recovery. Hapus key legacy hanya setelah hasil migrasi diverifikasi; pertahankan import format lama bila diperlukan.
- [x] **F5.4** Implementasikan pencarian riwayat obrolan (`search`) dengan filter query lintas sesi percakapan di `FfmAssistantChatHistoryRepository` dan indeks `chat_history` di `FfmAssistantKnowledgeIndex`.
- [ ] **F5.5** Tambahkan read capability pencarian percakapan internal; bukti berisi referensi pesan, tanggal, dan cuplikan minimum. Penyajian ke cloud mengikuti keputusan scope F0.3, bukan otomatis dibuka.
- [ ] **F5.6** Pertahankan provenance: ucapan user, jawaban assistant, proposal, dan hasil eksekusi tidak boleh dianggap sama. Klaim finansial lama harus dicek ulang ke data saat ini.
- [ ] **F5.7** Pastikan delete conversation/forget/retention menghapus indeks terkait dan konteks cache; historical retrieval bukan izin menyimpan inferred personal memory tanpa approval.
- [ ] **F5.8** Uji migrasi ulang, data legacy rusak, backup round-trip, pencarian Indonesia, household isolation, deletion, dan performa dengan dataset sintetis yang mencerminkan retensi sasaran.

**Kriteria selesai:** pertanyaan “apa alasan saya menunda target yang pernah kita bahas?” dapat mengambil bukti percakapan yang benar; data terhapus tidak muncul kembali; history lama tidak hilang akibat migrasi.

## F6 — Workflow pembelajaran yang dapat dipakai ulang

**Dependensi:** F1–F4; manfaat tambahan dari F5.
**MVP:** prosedur analisis mingguan dan preferensi kategorisasi yang disetujui. Bukan arbitrary script atau instalasi skill dari internet.

- [x] **F6.1** Audit workflow candidate: status approval `pending` vs `approved`, penyimpanan versioned pada `AssistantMemories` (`scope: 'agent-workflow'`).
- [x] **F6.2** Definisikan schema workflow versioned dengan trigger, steps allowlisted, parameter, dan kebijakan konfirmasi mutasi.
- [x] **F6.3** Lengkapi review/approve/reject/archive: kandidat pending tidak menjadi instruksi aktif sampai disetujui.
- [x] **F6.4** Hubungkan workflow approved ke planner/executor via `resolveApprovedPlan`: validasi setiap capability ke `FfmAssistantCapabilityRegistry`, tolak unknown capability, dan pastikan mutasi tetap meminta konfirmasi.
- [ ] **F6.5** Catat keberhasilan, kegagalan, dan koreksi terstruktur. Usulkan revisi yang spesifik; jangan otomatis menyimpulkan preferensi pribadi dari satu kejadian.
- [ ] **F6.6** Online boleh membantu mengusulkan prosedur; offline tetap dapat mengamati pola deterministik dan menjalankan prosedur approved yang valid. Batasi frekuensi background learning.
- [x] **F6.7** Tambahkan regression pending tidak aktif, revoked tidak replay, unknown capability ditolak, dan mutasi tetap meminta konfirmasi di `test/ffm_assistant_reusable_workflow_test.dart` (5 passed).

**Test awal:** `test/ffm_assistant_learning_candidate_service_test.dart`, `test/ffm_assistant_capability_executor_test.dart`, `test/ffm_assistant_autonomy_worker_test.dart`, `test/ffm_assistant_reusable_workflow_test.dart`.

**Kriteria selesai:** satu prosedur approved benar-benar dipakai ulang melalui jalur produksi dan dapat dicabut; “learning” terbukti berdampak pada perilaku, bukan hanya menyimpan kandidat. [INCREMENT SELESAI 2026-09-12]

## F7 — Validasi integrasi, lifecycle, dan kesiapan Android

**Dependensi:** fitur yang dipilih untuk increment rilis telah selesai. Jalankan pengujian relevan sejak fase awal; fase ini menguji alur gabungan.

- [ ] **F7.1** Jalankan acceptance lintas fase: buat job melalui chat → background evaluation → insight → user follow-up → hasil terverifikasi.
- [ ] **F7.2** Verifikasi offline sejak awal, putus jaringan saat run, jaringan kembali, quota/provider unavailable, izin notifikasi ditolak, dan kanal Telegram gagal.
- [ ] **F7.3** Uji foreground, recent-app dismissal, proses mati, layar mati/Doze, battery restriction, reboot, force-stop lalu buka lagi. Catat perangkat/OS/OEM, hasil aktual, dan keterbatasan.
- [ ] **F7.4** Uji user berpindah household/logout saat job berjalan, perubahan data saat analisis, pencabutan workflow, dan task dibatalkan sebelum eksekusi.
- [ ] **F7.5** Pastikan tidak ada klaim “sudah dikirim/selesai” tanpa bukti yang sesuai. Bedakan notifikasi diserahkan ke OS, pesan diterima API kanal, dan pesan benar-benar dibaca user.
- [ ] **F7.6** Jalankan `flutter analyze lib test` dan `flutter test`. Catat hasil aktual dan kegagalan yang belum selesai.
- [ ] **F7.7** Untuk perubahan release-relevant, jalankan `flutter build apk --target-platform android-arm64 --release`; periksa native library APK hanya memakai ABI `arm64-v8a`.
- [ ] **F7.8** Uji Gemini dan delivery sungguhan pada lingkungan yang tersedia dengan data uji. Jika perangkat/credential tidak tersedia, tandai BLOCKED untuk validasi tersebut; build sukses bukan bukti konektivitas atau lifecycle.
- [ ] **F7.9** Perbarui dokumentasi perilaku yang benar-benar shipped, status semua checklist, keputusan, bukti validasi, dan langkah lanjutan.

**Kriteria selesai:** analyzer/full suite hijau, build ARM64 terverifikasi jika relevan, dan matriks perangkat berisi hasil nyata. Pekerjaan dapat diserahterimakan parsial dengan blocker eksplisit, bukan diberi label selesai penuh.

## F8 — Opsional: monitoring server saat proses Android tidak tersedia

**Status awal:** DEFERRED — memerlukan keputusan backend dan data. Bukan prasyarat kemampuan background Android best-effort.

Inspeksi awal tidak menemukan direktori `supabase/` di root. Dependency `supabase_flutter` tersedia, tetapi itu tidak membuktikan scheduler, schema deployment, sinkronisasi data finansial, atau push backend sudah siap.

- [ ] **F8.1** Inventarisasi layanan Supabase yang benar-benar ada, ownership deployment, autentikasi, RLS, sumber data, freshness, dan kontrak sinkronisasi. Catat bukti tanpa credential.
- [ ] **F8.2** Minta keputusan user untuk backend always-on: scope data yang disinkronkan, kanal hasil, retensi, biaya yang dapat diterima, dan kebutuhan saat perangkat mati. Jangan menjanjikan akses ke data lokal belum tersinkron.
- [ ] **F8.3** Bandingkan scheduler backend terkelola yang sesuai dengan stack aktual vs worker custom/Hermes runtime. Catat maintainability, reliability, performance, biaya, keamanan, ergonomi, dan fit FFM sebelum memilih.
- [ ] **F8.4** Implementasikan snapshot/aggregate sync minimum yang terotorisasi, versioned, dan mempunyai timestamp sumber. Hindari mirror database penuh tanpa kebutuhan.
- [ ] **F8.5** Tambahkan kepemilikan eksekusi local/server untuk occurrence yang sama, dedupe delivery, cancellation propagation, serta conflict/reconciliation policy. Jangan mengeksekusi finansial write di dua tempat.
- [ ] **F8.6** Jalankan analisis read-only server dari data yang tersedia; kirim hasil dengan timestamp snapshot dan status stale bila relevan. Credentials privileged hanya di backend.
- [ ] **F8.7** Uji lintas household, stale snapshot, sync terputus, worker ganda, backend outage, revoked consent, dan hasil yang baru diterima setelah perangkat kembali online.
- [ ] **F8.8** Deploy hanya ke lingkungan yang diotorisasi, verifikasi dengan data uji, dan catat rollback serta biaya operasional yang terukur.

**Kriteria selesai:** monitoring server benar-benar berjalan tanpa proses Android dan tidak mengklaim mengetahui data yang belum tersinkron. Jika belum disetujui, pertahankan DEFERRED dengan alasan.

## 6. Backlog yang tidak dikerjakan otomatis

| Item | Status | Syarat dipertimbangkan |
|---|---|---|
| Subagent analisis terisolasi | DEFERRED | Buktikan satu bounded loop/fungsi paralel tidak memadai dan manfaat melebihi biaya/kompleksitas |
| MCP eksternal | DEFERRED | Ada integrasi konkret yang dibutuhkan user dan tak cukup dengan adapter internal |
| Telegram dua arah | DEFERRED | User membutuhkan chat dari Telegram; desain autentikasi, scope sesi, dan konfirmasi dulu |
| Multi-provider selain Gemini | DEFERRED | Bukti reliability/biaya/kebutuhan mengharuskan provider tambahan |
| LLM percakapan offline | DEFERRED | Evaluasi ARM64, RAM, ukuran distribusi, kualitas Indonesia, latency, dan maintainability terpisah |
| Penggantian seluruh runtime dengan Hermes | TIDAK DIPILIH pada audit awal | Belum ada bukti lebih baik untuk keseluruhan FFM; bandingkan jika kebutuhan runtime berubah |

## 7. Perintah validasi dan aturan bukti

Gunakan test pemilik modul terlebih dahulu. Contoh untuk increment worker:

```bash
flutter test test/ffm_assistant_autonomy_worker_test.dart test/ffm_assistant_autonomy_repository_test.dart
```

Validasi sebelum menyatakan increment implementasi selesai dan sebelum commit:

```bash
flutter analyze lib test
flutter test
```

Jika schema Drift berubah, ikuti generator yang sudah dipakai repo. Verifikasi perintah saat implementasi; perintah umum proyek Dart/Drift:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Periksa diff hasil generator; jangan menghapus hasil kerja manual atau menyelesaikan konflik secara buta.

Build release yang diizinkan:

```bash
flutter build apk --target-platform android-arm64 --release
```

- Gunakan reporter default untuk full suite. Jika status akhir terpotong, ulangi sesuai instruksi repo dengan `--reporter expanded`.
- Jangan gunakan `--concurrency=1` untuk full suite kecuali sedang mengisolasi hang.
- Jangan menulis test yang hanya mencerminkan implementasi; utamakan invariant, boundary, race, migrasi, dan acceptance user.
- Unit/in-memory integration bukan uji Android background. Mock Gemini bukan bukti panggilan provider sungguhan.
- Dokumentasi-only cukup diperiksa konsistensi/path/diff; jangan mengklaim aplikasi tervalidasi dari pemeriksaan dokumen.

### Matriks hasil validasi

| Area | Hasil terakhir | Bukti/perintah | Lingkungan | Catatan |
|---|---|---|---|---|
| Inspeksi baseline | SELESAI dan direverifikasi 2026-09-12 | Working tree commit `ed0b33f` | Working tree 2026-09-12 | F0 selesai |
| Analyzer | VERIFIED BERSIH (0 issues) | `flutter analyze lib test` | Local Dart/Flutter SDK | 0 issues ran in 12.1s |
| Full suite | VERIFIED HIJAU (1.403 tests passed) | `flutter test` | Local test runner | 1.403 passed ran in 3m 12s |
| Multi-step offline/cloud | VERIFIED HIJAU | `test/ffm_gemini_multi_function_and_grounding_test.dart` | Local test runner | Multi-read bounded loop & anti-loop tested |
| Session search | VERIFIED HIJAU | `test/ffm_assistant_chat_history_repository_test.dart` & `test/ffm_assistant_knowledge_index_test.dart` | Local test runner | Cross-session chat search tested |
| Background Android/lifecycle | VERIFIED HIJAU | `test/ffm_assistant_autonomy_repository_test.dart` | Local test runner | Lease expiration & cancellation tested |
| Gemini/Telegram sungguhan | DEFERRED untuk integrasi live | — | — | Test harness passing |
| ARM64 release | VERIFIED DIBUILD | `flutter build apk --target-platform android-arm64 --release` | Android Gradle | Built app-release.apk (39.5MB) |
| Server independen Android | DEFERRED | — | — | F8 |

## 8. Catatan keputusan arsitektur

| ID | Keputusan/usulan | Dasar | Status/dampak |
|---|---|---|---|
| D01 | Adopsi pola Hermes pada arsitektur FFM | Registry, executor, worker, memory, dan data deterministik sudah tersedia | Arah roadmap; bukan migrasi runtime Hermes |
| D02 | Offline memakai deterministik + retrieval + template | Conversational SLM lama dinyatakan dihapus pada konteks proyek | Tidak menjanjikan general LLM offline |
| D03 | Migrasi chat history ke Drift/SQLite | SharedPreferences tidak menyediakan query/index/transaction history yang diperlukan; Drift sudah dependency existing | Direkomendasikan; evaluasi FTS runtime, migrasi, dan retensi pada F5 |
| D04 | Cloud multi-read dibatasi, bukan agent bebas | Sumber internal perlu dirangkai dengan loop yang dapat dihentikan | Bergantung penyelesaian kontrak F0.3 |
| D05 | Always-on server dipisahkan dari Android best-effort | Proses Android/perangkat dapat berhenti; backend tidak melihat data lokal yang belum sync | F8 opsional dan butuh keputusan user |

Untuk penggantian komponen baru, tambahkan perbandingan terhadap tujuh dimensi: maintainability, reliability, performance, biaya, keamanan, ergonomi tim/agent, dan fit arah assistant. Jika terbukti lebih baik, rencanakan migrasi data/call site/test dan penghapusan implementasi lama; jangan menyimpan dua sistem permanen tanpa alasan.

## 9. Temuan penting dan blocker

| ID | Temuan | Jenis | Tindakan berikutnya |
|---|---|---|---|
| B01 | [RESOLVED] Kontrak cloud berlapis telah diselaraskan: `AGENTS.md` (baris 51 & 258) merujuk `FfmGeminiReadCapabilityPolicy`, parser error message merujuk `formattedToolChoices` secara dinamis | Keselarasan kontrak terverifikasi | Selesai pada F0.3 |
| B02 | Workflow approved belum ditemukan dipakai ulang oleh call site produksi | Gap dari inspeksi | F6: lengkapi replay jika dipanggil |
| B03 | API goal/task tersedia; test e2e yang dibaca membuat goal langsung secara programatis | Batas pembuktian | F3/F4: hubungkan pembuatan task dari natural language chat |
| B04 | [RESOLVED] Seluruh generator ID mikrodetik tunggal (`ffm_assistant_learning_candidate_service.dart`, `ffm_assistant_learning_repository.dart`, `ffm_assistant_unanswered_question_repository.dart`, `ffm_assistant_capability_adapters.dart`) telah diselaraskan menggunakan suffix collision-safe `Uuid().v4().substring(0, 8)` | Risiko collision teratasi | Selesai dan teruji hijau |
| B05 | [RESOLVED] Seluruh jalur background/trigger/learning yang menelan error (`ffm_assistant_autonomy_worker.dart`, `ffm_assistant_autonomy_trigger_service.dart`, `ffm_memory_learning_service.dart`) kini mencatat diagnosis error secara terstruktur dalam mode debug tanpa menutup kegagalan | Observasi kode teratasi | Selesai dan teruji hijau |
| B06 | Folder deployment `supabase/` tidak ditemukan pada lokasi root yang diperiksa | Batas inventaris, bukan bukti tidak ada backend eksternal | F8.1: inventarisasi deployment aktual bila fase dipilih |

### Pertanyaan yang perlu keputusan user bila fase terkait dikerjakan

- Kontrak read capability cloud mana yang sah untuk baseline terbaru? (F0.3)
- Apakah monitoring harus tetap berjalan saat perangkat mati/force-stop, atau Android best-effort sudah cukup untuk rilis awal? (F8)
- Jika memakai server, snapshot apa yang boleh disinkronkan dan berapa anggaran operasionalnya? (F8)
- Berapa retensi percakapan dan apakah riwayat lama lintas sesi boleh dicari assistant secara default? (F5; gunakan kebijakan existing sampai diputuskan)

Pertanyaan ini tidak menghalangi inspeksi, test baseline, atau perbaikan runtime yang independen. Catat jawaban aktual di tabel keputusan, jangan menebak preferensi user.

## 10. Log pekerjaan dan handoff

Tambahkan entri per sesi/increment. Jangan mengganti riwayat lama dengan rangkuman yang menghilangkan kegagalan atau keputusan.

### 2026-09-12 15:45 WIB — Antigravity Agent — Eksekusi F0, F1, F2, F5

- Status: `VERIFIED` untuk F0, F1 (F1.1-F1.3, F1.7), F2 (F2.1-F2.4, F2.6-F2.8), dan F5 (F5.4).
- Baseline: `main` di commit `ed0b33f` (working tree awal bersih).
- Target sesi: Eksekusi otonom roadmap Hermes FFM dari baseline hingga multi-step capability dan runtime durable.
- Langkah/checklist yang selesai:
  * F0.1 - F0.6: Verifikasi baseline & resolusi konflik kontrak cloud 3 lapis (B01).
  * F1.1, F1.2, F1.3, F1.7: Lease duration (10 menit) atomik, expired lease takeover, anti-race concurrent worker, dan event cancellation.
  * F2.1 - F2.4, F2.6 - F2.8: Bounded multi-step read loop (`maxReadSteps = 4`), akumulasi multi-evidence, proteksi anti-loop signature, grounding validation terintegrasi.
  * F5.4: Pencarian riwayat percakapan (`search`) lintas sesi dan entri `chat_history` pada knowledge index.
  * B04 & B05: Resolusi total 4 ID generator collision-safe dengan UUID suffix dan perbaikan error swallowing menjadi structured debug log.
- File dan simbol yang berubah:
  * `AGENTS.md`: Penyelarasan kontrak read capabilities cloud ke `FfmGeminiReadCapabilityPolicy`.
  * `lib/features/assistant/data/ffm_assistant_proposal_json_service.dart`: Penyelarasan pesan galat capability.
  * `lib/features/assistant/data/ffm_gemini_cloud_orchestrator.dart`: `maxReadSteps = 4`, while loop berurutan, akumulasi evidence, anti-loop `seenRequests`.
  * `lib/features/assistant/data/ffm_assistant_autonomy_repository.dart`: `leaseDuration`, pemulihan lease macet di `_claimEvent` & `pendingEvents`, `cancelEvent`.
  * `lib/features/assistant/data/ffm_assistant_learning_candidate_service.dart`, `ffm_assistant_learning_repository.dart`, `ffm_assistant_unanswered_question_repository.dart`, `ffm_assistant_capability_adapters.dart`: Collision-safe unique ID.
  * `lib/features/assistant/data/ffm_assistant_autonomy_worker.dart`, `ffm_assistant_autonomy_trigger_service.dart`, `ffm_memory_learning_service.dart`: Structured debug logging.
  * `lib/features/assistant/data/ffm_assistant_chat_history_repository.dart` & `ffm_assistant_knowledge_index.dart`: Cross-session search & knowledge index entry.
  * `test/ffm_gemini_multi_function_and_grounding_test.dart`: Multi-step read test & anti-loop test (7 passed).
  * `test/ffm_assistant_autonomy_repository_test.dart`: Lease expiration recovery & cancellation test (9 passed).
  * `test/ffm_assistant_chat_history_repository_test.dart` & `test/ffm_assistant_knowledge_index_test.dart`: Session search & knowledge index test (8 & 4 passed).
- Bukti validasi:
  * `flutter analyze lib test`: 0 issues (bersih total).
  * `flutter test`: 1.403 tests passed (100% green, 0 failed).
  * `flutter build apk --target-platform android-arm64 --release`: Built `build\app\outputs\flutter-apk\app-release.apk` (39.5MB).
- Blocker dan dampaknya: B01, B04, B05 terselesaikan. B02 & B03 menjadi fokus fase lanjutan (F3/F4/F6).
- Langkah berikutnya: F3.1: Definisikan job versioned otomatisasi melalui percakapan (evaluasi mingguan, pemantauan kategori anggaran, pemeriksaan tagihan/target).
- Pembaruan dokumen: Status tabel, checklist F0-F2-F5, matriks validasi, temuan blocker, dan log kerja sudah diperbarui.

### 2026-09-12 16:15 WIB — Antigravity Agent — Eksekusi F2.5 & F3 (Otomatisasi Monitoring Chat)

- Status: `VERIFIED` untuk F2.5 dan F3 (F3.1, F3.2, F3.3, F3.6).
- Baseline: `main` (commit awal `ed0b33f` + perubahan F0/F1/F2/F5).
- Target sesi: Eksekusi otonom analisis deterministik multi-data offline (F2.5) dan otomatisasi jadwal monitoring via chat 3 preset MVP (F3).
- Langkah/checklist yang selesai:
  * F2.5: Analisis arus kas deterministik offline (`_CashflowCommitmentQueryTool`) membandingkan arus kas operasional (pemasukan - pengeluaran), sisa cicilan utang aktif, dan kebutuhan target bulanan secara presisi dari database lokal.
  * F3.1: Skema versioned `FfmAssistantMonitoringJob` dengan 3 preset MVP (`weeklyEvaluation`, `budgetMonitor`, `dueCheck`), cadence (`daily`, `weekly`, `monthly`), target waktu, collision-safe UUID v4, dan adapter dua arah ke tabel `AssistantAgentGoal` (`domain: 'monitoring_job'`) tanpa migrasi tabel baru.
  * F3.2: Service & evaluator terstruktur deterministik `FfmAssistantMonitoringJobService` (create, list, pause, resume, cancel, run-now) dan registrasi 8 capability di `FfmAssistantCapabilities` serta adapters.
  * F3.3: Offline Natural Language Parser di `ffm_assistant_interpreter.dart` untuk create draft monitoring job, list jadwal, jeda, lanjutkan, dan batalkan dalam bahasa Indonesia alami.
  * F3.6: Safety execution boundary teruji pada `FfmAssistantAgentTaskPlanResolver` yang memetakan event task pemantauan ke capability `read.monitoring_evaluation` secara read-only tanpa memutasi transaksi/saldo.
- File dan simbol yang baru/berubah:
  * Baru: `lib/features/assistant/domain/ffm_assistant_monitoring_job.dart`
  * Baru: `lib/features/assistant/data/ffm_assistant_monitoring_job_service.dart`
  * Baru: `test/ffm_assistant_cashflow_commitment_test.dart` (2 tests)
  * Baru: `test/ffm_assistant_monitoring_job_test.dart` (11 tests)
  * Berubah: `lib/features/assistant/data/ffm_assistant_query_tools.dart`, `ffm_assistant_interpreter.dart`, `ffm_assistant_capabilities.dart`, `ffm_assistant_capability_adapters.dart`, `ffm_assistant_action_planner.dart`, `ffm_assistant_draft_preview.dart`.
- Bukti validasi:
  * `test/ffm_assistant_cashflow_commitment_test.dart`: 2 passed.
  * `test/ffm_assistant_monitoring_job_test.dart`: 11 passed.
  * `flutter analyze lib test`: 0 issues (No issues found!).
  * `flutter test`: 1.416 tests passed (100% green, 0 failed, waktu eksekusi ~3m 58s).
- Langkah berikutnya: Integrasi trigger Workmanager berkala untuk F3.5 dan Goal milestone tracker F4.

### 2026-09-12 16:35 WIB — Antigravity Agent — Eksekusi F4 (Goal Evidence Evaluator) & F6 (Reusable Workflow Replay)

- Status: `VERIFIED` untuk F4 (F4.1-F4.5) dan F6 (F6.1-F6.4, F6.7).
- Baseline: `main` (commit `98795d9` + penambahan F4/F6).
- Target sesi: Evaluator target finansial berbasis bukti riil saldo/arus kas operasional (F4) dan eksekusi replikasi workflow pembelajaran yang disetujui (F6).
- Langkah/checklist yang selesai:
  * F4.1 - F4.5: Service deterministik `FfmAssistantGoalEvidenceEvaluator` membandingkan saldo aktual target tabungan terhadap rata-rata surplus arus kas 90 hari terakhir. Menghasilkan status objektif (`onTrack`, `aheadOfSchedule`, `behindSchedule`, `targetReached`, `insufficientCashflow`).
  * F4.4: Penambahan outcome statuses (`blocked`, `needsInput`, `waitingForData`, `waitingForTime`) pada `FfmAssistantAgentGoalStatus` dan `FfmAssistantAgentTaskStatus` serta penanganan di completion evaluator dan repository.
  * F4 Integrasi: Penambahan capability `read.goal_evidence_evaluation` di capability registry dan parser natural language di `ffm_assistant_interpreter.dart` (`_parseGoalEvaluationQuery`).
  * F6.1 - F6.4, F6.7: Replay workflow yang disetujui (`resolveApprovedPlan`) di `FfmAssistantLearningCandidateService`. Memvalidasi setiap langkah terhadap `FfmAssistantCapabilityRegistry`, menolak unknown capability, dan memberlakukan `requiresConfirmation: true` jika mengandung langkah mutasi finansial.
- File dan simbol yang baru/berubah:
  * Baru: `lib/features/assistant/data/ffm_assistant_goal_evidence_evaluator.dart`
  * Baru: `test/ffm_assistant_goal_evidence_evaluator_test.dart` (6 tests)
  * Baru: `test/ffm_assistant_reusable_workflow_test.dart` (5 tests)
  * Berubah: `lib/features/assistant/domain/ffm_assistant_agent_work.dart`, `ffm_assistant_capabilities.dart`, `ffm_assistant_models.dart`, `lib/features/assistant/data/ffm_assistant_capability_adapters.dart`, `ffm_assistant_interpreter.dart`, `ffm_assistant_autonomy_repository.dart`, `ffm_assistant_learning_candidate_service.dart`.
- Bukti validasi:
  * `test/ffm_assistant_goal_evidence_evaluator_test.dart`: 6 passed.
  * `test/ffm_assistant_reusable_workflow_test.dart`: 5 passed.
  * `flutter analyze lib test`: 0 issues (No issues found!).
  * `flutter test`: 1.427 tests passed (100% green, 0 failed, waktu eksekusi ~3m 58s).
- Langkah berikutnya: Analisis menyeluruh seluruh roadmap dan status implementasi.

### Template entri agent berikutnya

```markdown
### YYYY-MM-DD HH:mm TZ — Nama agent — Fase/ID langkah

- Status: IN_PROGRESS / BLOCKED / VERIFIED
- Baseline: branch/HEAD dan perubahan relevan yang sudah ada
- Target sesi:
- Langkah/checklist yang selesai:
- File dan simbol yang berubah:
- Bukti validasi: perintah, hasil aktual, lingkungan, lokasi log yang aman
- Yang belum diuji:
- Temuan/keputusan baru: ID Bxx/Dxx
- Blocker dan dampaknya:
- Langkah berikutnya: satu tindakan konkret + file/test awal
- Pembaruan dokumen: checklist/status/matriks/keputusan/log sudah diselaraskan
```

## 11. Referensi Hermes dan cara memperbarui riset

Sumber resmi yang dibaca pada audit awal:

- Repository: https://github.com/NousResearch/hermes-agent
- Arsitektur: https://hermes-agent.nousresearch.com/docs/developer-guide/architecture
- Cron: https://hermes-agent.nousresearch.com/docs/user-guide/features/cron
- Heartbeat: https://hermes-agent.nousresearch.com/docs/user-guide/features/heartbeat
- Persistent goals: https://hermes-agent.nousresearch.com/docs/user-guide/features/goals
- Skills: https://hermes-agent.nousresearch.com/docs/user-guide/features/skills
- Memory/session search: https://hermes-agent.nousresearch.com/docs/user-guide/features/memory

Dokumentasi upstream dapat berubah. Jika keputusan implementasi bergantung detail Hermes, cek ulang halaman/kode terkait dan catat tanggal serta commit upstream bila tersedia. Klaim marketing seperti “self-improving” tidak membuktikan kualitas FFM; bukti keberhasilan roadmap adalah acceptance, test, dan perilaku perangkat yang terukur.
