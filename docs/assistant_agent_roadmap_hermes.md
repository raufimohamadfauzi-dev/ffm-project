# FFM — Roadmap Agent Proaktif Berbasis Data Internal

> Dokumen kerja untuk coding agent: Astra/OpenCode, VS Code Agent, Codex, dan agent pengembangan lain.
> Sumber perbandingan: Hermes Agent dari Nous Research, dokumentasi resmi, serta inspeksi kode FFM.
> Fokus: fitur assistant yang realistis untuk Android, online/offline, foreground/background.

## 0. Status dan cara mulai

| Field | Nilai saat ini |
|---|---|
| Dibuat | 2026-09-11 |
| Pembaruan terakhir | 2026-09-11 — penyusunan roadmap + reverifikasi data kode |
| Status | PLANNED — implementasi roadmap belum dimulai |
| Fase aktif | F0 — verifikasi baseline dan kontrak |
| Langkah berikutnya | F0.1: periksa instruksi repo, working tree, dan perubahan sejak audit |
| Blocker awal | Kontrak capability cloud di AGENTS.md berbeda dengan kode; selesaikan F0.3 sebelum perubahan perilaku cloud |
| Batas pembuktian | Inspeksi kode/dokumentasi; belum menjalankan test, build, atau uji perangkat untuk roadmap ini |

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

- [ ] **F0.1** Baca instruksi repo, `docs/PROJECT_CONTEXT.md`, status/diff working tree, serta log terakhir dokumen ini. Catat branch/HEAD dan file terkait yang sudah berubah tanpa menyalin diff sensitif.
- [ ] **F0.2** Verifikasi tabel baseline terhadap implementasi terbaru dan call site produksi. Tandai temuan sebagai wired, service-only, test-only, atau belum ditemukan.
- [ ] **F0.3** Selesaikan konflik kontrak cloud yang berlapis: AGENTS.md menyebut dua read capability; kode memakai `allowedCapabilityIds` 18 ID (dengan executor lengkap) dan `canonicalToolChoices` 11 ID; pesan galat parser di `ffm_assistant_proposal_json_service.dart:48` masih mengklaim dua. Tetapkan kontrak resmi, lalu selaraskan kode, test, dan instruksi repo secara konsisten. Jangan menghapus batas instruksi repo secara sepihak.
- [ ] **F0.4** Verifikasi routing mode, active-draft `draftReview`, executor, policy biaya/token, cancellation, dan household scope. Tetapkan regression yang harus tetap hijau.
- [ ] **F0.5** Jalankan `flutter analyze lib test` dan `flutter test` untuk baseline. Catat kegagalan yang sudah ada; jangan mengklaim disebabkan roadmap tanpa bukti.
- [ ] **F0.6** Isi catatan keputusan awal, blocker, dan langkah implementasi pertama beserta test pemilik modul.

**Selesai jika:** kontrak implementasi jelas, baseline aktual tercatat, dan setiap blocker memiliki dampak/dependensi yang jelas. Fase tidak dianggap selesai bila konflik kontrak wajib masih terbuka.

## F1 — Runtime durable, recovery, dan observability

**Reuse:** autonomy repository/worker/background handler, action plan/executor, circuit breaker, execution limits, policy, Telegram delivery, monitor page.

- [ ] **F1.1** Petakan event → claim → resolve plan → execute → verify → persist → deliver. Periksa atomic claim/lease yang sudah ada sebelum menambah kolom/tabel.
- [ ] **F1.2** Lengkapi pencegahan race foreground/background, lease kedaluwarsa, retry terbatas/backoff, dan cancellation. Satu kejadian terjadwal harus punya identitas stabil.
- [ ] **F1.3** Simpan checkpoint dan outcome terstruktur. Bedakan gagal eksekusi, menunggu konfirmasi, menunggu jaringan, diblokir konfigurasi, dan gagal delivery; adaptasikan model status yang ada.
- [ ] **F1.4** Terapkan batas waktu, jumlah langkah, token, dan biaya pada jalur yang benar-benar berjalan. Pisahkan estimasi biaya dari usage aktual; jangan tampilkan estimasi sebagai tagihan pasti.
- [ ] **F1.5** Hindari pemanggilan cloud duplikat pada event berdekatan. Coalesce event, lakukan cek deterministik dulu, dan hentikan retry konfigurasi yang tidak mungkin berhasil.
- [ ] **F1.6** Tampilkan sumber pemicu, waktu data, evaluasi terakhir, hasil, dan alasan blocked pada monitor yang ada. Jangan menampilkan hidden chain-of-thought.
- [ ] **F1.7** Verifikasi restart setelah crash pada setiap batas penting; jangan mengulang efek mutasi/delivery secara buta jika hasil sebelumnya ambigu.

**Test awal:** `test/ffm_assistant_autonomy_worker_test.dart`, `test/ffm_assistant_autonomy_repository_test.dart`, `test/ffm_assistant_autonomy_task_execution_host_test.dart`, `test/ffm_assistant_autonomy_policy_test.dart`.

**Kriteria selesai:** dua worker bersamaan tidak mengeksekusi pekerjaan yang sama; task terhenti dapat dipulihkan; batas kerja terbukti; kegagalan eksekusi dan pengiriman dapat dibedakan.

## F2 — Analisis multi-langkah lintas sumber internal

**Dependensi:** F0; gunakan reliability F1 untuk pekerjaan yang dipersistenkan.
**Contoh penerimaan:** “Apakah arus kas saya cukup untuk cicilan dan target bulan ini?”

- [ ] **F2.1** Definisikan kontrak evidence bertipe: source/capability, household scope, periode, waktu snapshot, nilai deterministik, kelengkapan data, dan error. Pertahankan kontrak existing bila sudah memadai.
- [ ] **F2.2** Tentukan allowlist final dari F0.3. Sediakan adapter agregasi lokal yang diperlukan tanpa SQL bebas atau dump semua transaksi.
- [ ] **F2.3** Ubah alur cloud satu-read menjadi loop bounded pada orchestrator yang ada: request → validated read → evidence → langkah berikutnya/jawaban. Nilai awal usulan: maksimal 4 langkah baca; keputusan angka final dicatat dan konsisten dengan policy repo.
- [ ] **F2.4** Tangani tool tidak dikenal, parameter rusak, permintaan berulang identik, output kosong, timeout, quota, cancellation, dan habis budget. Kembalikan hasil parsial dengan sumber yang tersedia bila bermakna.
- [ ] **F2.5** Buat rencana analisis deterministik offline untuk intent lintas data yang jelas. Untuk intent ambigu minta klarifikasi; jangan mengklaim hasil reasoning cloud saat offline.
- [ ] **F2.6** Ground jawaban ke evidence; bila data berubah di tengah analisis, gunakan snapshot konsisten atau tandai/recompute sesuai policy freshness. Persiapan mutasi tetap perlu validasi ulang saat eksekusi.
- [ ] **F2.7** Pertahankan `draftReview` pada mode Gemini Cloud dan routing draft/navigation yang sudah ada. Perubahan read loop tidak boleh menjadi jalur write otomatis.
- [ ] **F2.8** Tambahkan regression multi-source, satu sumber gagal, no-data vs nol, pengulangan tool, perubahan household, offline, dan batas loop. Perbarui test yang memang mengunci perilaku lama dengan kontrak baru yang disetujui, bukan melemahkan proteksi.

**Test awal:** `test/ffm_assistant_orchestrator_read_integration_test.dart`, `test/ffm_gemini_promoted_capability_detail_test.dart`, `test/ffm_agent_harness_test.dart`, test grounding/planner yang ditemukan saat F0.

**Kriteria selesai:** pertanyaan contoh menghasilkan angka yang sama dengan perhitungan fixture; beberapa sumber dapat dibaca; loop selalu berhenti; jalur offline dan cloud dibedakan dengan benar.

## F3 — Otomatisasi yang dibuat melalui percakapan

**Dependensi:** F1; F2 untuk job yang membutuhkan reasoning lintas sumber.
**MVP:** tiga jenis job — evaluasi mingguan, pemantauan kategori anggaran, pemeriksaan tagihan/target. Gunakan preset terstruktur, bukan prompt bebas yang bisa menjalankan apa pun.

- [ ] **F3.1** Definisikan job versioned dengan tujuan, household, jenis pemicu, timezone, schedule/condition, capability scope, delivery channel, status, next run, dan batas biaya. Reuse goal/task/event tables bila sesuai.
- [ ] **F3.2** Dukung create/list/edit/pause/resume/cancel/run-now melalui capability aplikasi. Tampilkan preview jadwal, data yang dipakai, kanal, dan perilaku background sebelum aktivasi.
- [ ] **F3.3** Implementasikan parser offline terbatas untuk template yang terdokumentasi. “Setiap Minggu” harus diklarifikasi bila waktu belum ada; jangan mengarang jadwal tanpa default yang terlihat.
- [ ] **F3.4** Online: Gemini mengusulkan structured job memakai schema yang sama; validasi aplikasi tetap menentukan apakah job dapat diterima.
- [ ] **F3.5** Hubungkan ke Workmanager/event worker. Hitung ulang jadwal setelah perubahan timezone dan restart; gabungkan missed ticks menjadi satu evaluasi terbaru bila sesuai, bukan membanjiri user.
- [ ] **F3.6** Bedakan job baca/analisis dari aksi finansial. Menjalankan job monitoring tidak otomatis menyetujui transfer, pengeluaran, pengubahan anggaran, atau transaksi lain.
- [ ] **F3.7** Gunakan delivery policy dan antrean yang ada. Jika offline, hasil lokal tersedia di app; kanal internet berstatus pending dengan expiry agar laporan basi tidak dikirim membabi buta.
- [ ] **F3.8** Hubungkan hasil job ke konteks percakapan yang sah agar “kenapa begitu?” merujuk laporan yang benar. Sertakan job/run reference dan waktu data.
- [ ] **F3.9** Uji jadwal sekali/berulang, tanggal akhir, timezone, pause/resume/cancel, duplicate fire, missed tick, offline delivery, serta user mengubah job saat run berjalan.

**Kriteria selesai:** user dapat membuat dan menghentikan tiga job MVP melalui chat; job tetap tersimpan setelah restart; waktu next-run dan batas best-effort terlihat.

## F4 — Goal dan tindak lanjut dengan bukti hasil

**Dependensi:** F1–F3.
**Perbedaan penting:** target finansial user bukan task komputasi yang terus berputar sampai tercapai. Menabung selama sebulan harus menunggu event/waktu berikutnya, bukan memanggil LLM berulang.

- [ ] **F4.1** Definisikan completion contract: metrik hasil, periode, baseline, sumber bukti, kondisi lanjut/selesai/blocked, waktu evaluasi berikutnya, dan alasan berhenti.
- [ ] **F4.2** Hubungkan instruksi user ke goal/task tersimpan. Tunjukkan rencana kecil dan klarifikasi tujuan yang tidak terukur.
- [ ] **F4.3** Lengkapi evaluator deterministik; “semua task selesai” tidak otomatis berarti kondisi finansial user sudah membaik.
- [ ] **F4.4** Tambahkan outcome yang setara dengan `needs_input`, `waiting_for_data`, `waiting_for_time`, `blocked`, dan `completed` pada model existing sesuai kebutuhan, beserta migrasi.
- [ ] **F4.5** Setelah insight ditindaklanjuti, simpan baseline dan jadwal pemeriksaan. Bandingkan data berikutnya tanpa menyimpulkan sebab-akibat yang tidak dapat dibuktikan.
- [ ] **F4.6** Rencanakan langkah lanjutan hanya dari capability yang diizinkan. Batasi replanning dan hentikan siklus tanpa bukti/data baru.
- [ ] **F4.7** Hormati penolakan, snooze, pencabutan monitoring, perubahan prioritas, dan pembatalan user. Dedupe pesan yang tidak membawa informasi baru.
- [ ] **F4.8** Uji goal sampai completion dengan jalur produksi dari chat, bukan hanya task yang dibuat langsung oleh test. Sertakan goal tidak mungkin, missing data, dan user mencabut persetujuan.

**Test awal:** `test/ffm_assistant_agent_task_plan_resolver_test.dart`, `test/ffm_assistant_agent_task_event_handler_test.dart`, `test/ffm_assistant_autonomy_e2e_test.dart`, `test/autonomous_evaluation_coordinator_test.dart`.

**Kriteria selesai:** assistant bisa memantau tujuan, menunggu secara tepat, menjelaskan progres dari angka aktual, dan berhenti/jeda tanpa meminta user terus mengetik “lanjut”.

## F5 — Pencarian riwayat percakapan lokal

**Dependensi:** F0; dapat didahulukan jika menjadi blocker konteks F2/F4.
**Keputusan arah:** migrasi history SharedPreferences ke Drift/SQLite dan indeks pencarian lokal yang didukung runtime Android ARM64.

- [ ] **F5.1** Inventarisasi format history, export/import, backup, clear/delete, batas retensi, dan perubahan data-retention yang sedang berlangsung. Tentukan ownership household untuk history lama; jangan menebak dan mengekspos antar akun.
- [ ] **F5.2** Catat evaluasi SharedPreferences vs Drift/SQLite: maintainability, reliability, performance, biaya, keamanan, ergonomi agent, dan kesesuaian produk. Verifikasi dukungan FTS pada build SQLite yang dipakai (`sqlite3mc` di pubspec saat audit).
- [ ] **F5.3** Buat migrasi idempotent, transactional, dengan verifikasi jumlah/isi yang aman dan recovery. Hapus key legacy hanya setelah hasil migrasi diverifikasi; pertahankan import format lama bila diperlukan.
- [ ] **F5.4** Implementasikan pencarian dengan filter household, conversation, waktu, dan limit. Gunakan parameterized query dan batas panjang pencarian; bedakan no result dengan storage failure.
- [ ] **F5.5** Tambahkan read capability pencarian percakapan internal; bukti berisi referensi pesan, tanggal, dan cuplikan minimum. Penyajian ke cloud mengikuti keputusan scope F0.3, bukan otomatis dibuka.
- [ ] **F5.6** Pertahankan provenance: ucapan user, jawaban assistant, proposal, dan hasil eksekusi tidak boleh dianggap sama. Klaim finansial lama harus dicek ulang ke data saat ini.
- [ ] **F5.7** Pastikan delete conversation/forget/retention menghapus indeks terkait dan konteks cache; historical retrieval bukan izin menyimpan inferred personal memory tanpa approval.
- [ ] **F5.8** Uji migrasi ulang, data legacy rusak, backup round-trip, pencarian Indonesia, household isolation, deletion, dan performa dengan dataset sintetis yang mencerminkan retensi sasaran.

**Kriteria selesai:** pertanyaan “apa alasan saya menunda target yang pernah kita bahas?” dapat mengambil bukti percakapan yang benar; data terhapus tidak muncul kembali; history lama tidak hilang akibat migrasi.

## F6 — Workflow pembelajaran yang dapat dipakai ulang

**Dependensi:** F1–F4; manfaat tambahan dari F5.
**MVP:** prosedur analisis mingguan dan preferensi kategorisasi yang disetujui. Bukan arbitrary script atau instalasi skill dari internet.

- [ ] **F6.1** Audit workflow candidate yang sudah ada: asal, scope household, ID, status approval, langkah, dan capability yang dirujuk. Kandidat `system.set_merchant_category` harus dicek ke registry/executor; jangan menganggap capability valid hanya karena tersimpan.
- [ ] **F6.2** Definisikan schema workflow versioned dengan trigger, precondition, langkah allowlisted, parameter, hasil yang diharapkan, provenance, dan kebijakan konfirmasi.
- [ ] **F6.3** Lengkapi review/approve/reject/edit/archive. Kandidat pending tidak menjadi instruksi aktif. Perubahan versi yang memperluas tindakan harus melalui review lagi.
- [ ] **F6.4** Hubungkan workflow approved ke planner/executor yang ada. Validasi ulang capability, entitas, izin, dan kondisi saat replay; jangan langsung menjalankan JSON tersimpan.
- [ ] **F6.5** Catat keberhasilan, kegagalan, dan koreksi terstruktur. Usulkan revisi yang spesifik; jangan otomatis menyimpulkan preferensi pribadi dari satu kejadian.
- [ ] **F6.6** Online boleh membantu mengusulkan prosedur; offline tetap dapat mengamati pola deterministik dan menjalankan prosedur approved yang valid. Batasi frekuensi background learning.
- [ ] **F6.7** Tambahkan regression pending tidak aktif, revoked tidak replay, unknown capability ditolak, versi berubah, data entitas dihapus, dan mutasi tetap meminta konfirmasi.

**Test awal:** `test/ffm_assistant_learning_candidate_service_test.dart`, `test/ffm_assistant_capability_executor_test.dart`, `test/ffm_assistant_autonomy_worker_test.dart`.

**Kriteria selesai:** satu prosedur approved benar-benar dipakai ulang melalui jalur produksi dan dapat dicabut; “learning” terbukti berdampak pada perilaku, bukan hanya menyimpan kandidat.

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
| Inspeksi baseline | SELESAI dan direverifikasi 2026-09-11; daftar capability diperbaiki ke data aktual | Sumber kode pada bagian 3 + grep ke file dirujuk | Working tree 2026-09-11 | B01 disempurnakan menjadi 3 lapis; cakupan B04/B05 diperluas berdasarkan baris aktual |
| Analyzer | BELUM DIJALANKAN untuk roadmap | — | — | F0/F7 |
| Full suite | BELUM DIJALANKAN untuk roadmap | — | — | F0/F7 |
| Multi-step offline/cloud | BELUM DIUJI | — | — | F2 |
| Migrasi history | BELUM DIIMPLEMENTASIKAN | — | — | F5 |
| Background Android/lifecycle | BELUM DIUJI | — | — | F7 |
| Gemini/Telegram sungguhan | BELUM DIUJI | — | — | F7 |
| ARM64 release | BELUM DIBUILD untuk roadmap | — | — | F7 |
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
| B01 | Kontrak cloud berlapis tidak selaras: AGENTS.md menyebut `read.summary`/`read.transactions` (baris 51, 258); `allowedCapabilityIds` di `ffm_gemini_read_capability_service.dart` berisi 18 ID dengan executor lengkap; `canonicalToolChoices` 11 ID dipaparkan ke model; pesan galat `ffm_assistant_proposal_json_service.dart:48` masih mengklaim dua | Konflik kontrak terverifikasi dari kode | F0.3: tetapkan kontrak resmi dan selaraskan kode+test+instruksi repo; setiap capability tambahan wajib punya evidence bounded setara |
| B02 | Workflow approved belum ditemukan dipakai ulang oleh call site produksi | Gap dari inspeksi | F0.2/F6: cari ulang dan lengkapi replay jika benar belum ada |
| B03 | API goal/task tersedia; test e2e yang dibaca membuat goal langsung secara programatis | Batas pembuktian | F3/F4: buktikan jalur user/chat menuju task produksi |
| B04 | Sejumlah generator ID memakai timestamp mikrodetik tunggal tanpa counter/random: `ffm_assistant_learning_candidate_service.dart:45` (`assistant-workflow-…`), `ffm_assistant_learning_repository.dart:128` (`assistant-learning-…`), `ffm_assistant_unanswered_question_repository.dart:101` (`assistant-unanswered-…`), `ffm_assistant_capability_adapters.dart:1969` (`checkpoint-…`). File lain sudah memakai pola aman (Uuid().v4() atau timestamp+suffix random) | Risiko collision terverifikasi pada kode | Saat modul terkait disentuh, selaraskan ke Uuid().v4() atau timestamp+counter/random; tambahkan regression ID unik sesuai tuntutan AGENTS.md |
| B05 | Beberapa jalur background/learning/trigger menelan error tanpa pencatatan yang dapat diaudit, contoh `ffm_assistant_autonomy_trigger_service.dart:77` (`catchError((_) {})`), `ffm_assistant_autonomy_worker.dart:143` dan `autonomous_activity_repository.dart` (`catch (_) {}`), `ffm_memory_learning_service.dart:140` | Observasi kode terverifikasi, dampak runtime belum diuji | F1: pastikan pelaporan kegagalan terstruktur tanpa menutup masalah; bedakan unexpected error dari cancellation/expected deny |
| B06 | Folder deployment `supabase/` tidak ditemukan pada lokasi root yang diperiksa | Batas inventaris, bukan bukti tidak ada backend eksternal | F8.1: inventarisasi deployment aktual bila fase dipilih |

### Pertanyaan yang perlu keputusan user bila fase terkait dikerjakan

- Kontrak read capability cloud mana yang sah untuk baseline terbaru? (F0.3)
- Apakah monitoring harus tetap berjalan saat perangkat mati/force-stop, atau Android best-effort sudah cukup untuk rilis awal? (F8)
- Jika memakai server, snapshot apa yang boleh disinkronkan dan berapa anggaran operasionalnya? (F8)
- Berapa retensi percakapan dan apakah riwayat lama lintas sesi boleh dicari assistant secara default? (F5; gunakan kebijakan existing sampai diputuskan)

Pertanyaan ini tidak menghalangi inspeksi, test baseline, atau perbaikan runtime yang independen. Catat jawaban aktual di tabel keputusan, jangan menebak preferensi user.

## 10. Log pekerjaan dan handoff

Tambahkan entri per sesi/increment. Jangan mengganti riwayat lama dengan rangkuman yang menghilangkan kegagalan atau keputusan.

### 2026-09-11 — Astra/OpenCode — penyusunan roadmap

- Status: `VERIFIED` untuk penyusunan dan peninjauan dokumen; implementasi fitur `PLANNED`.
- Permintaan: roadmap Markdown untuk coding agent, checklist, update wajib, fitur internal online/offline dan foreground/background.
- Pekerjaan: membandingkan dokumentasi Hermes dan kode FFM; menulis fase, acceptance, dependensi, lifecycle, serta protokol pembaruan.
- File: `docs/assistant_agent_roadmap_hermes.md`.
- Validasi dokumen: ditinjau untuk konsistensi baseline, dependensi, dan batas lifecycle; 70 checklist ber-ID F0.1–F8.8 ditemukan. `git diff --no-index --check -- /dev/null "docs/assistant_agent_roadmap_hermes.md"` tidak melaporkan masalah whitespace.
- Catatan lingkungan: executable `rg` tidak tersedia pada PATH sesi ini; pencarian/penghitungan checklist menggunakan tool Grep harness.
- Validasi aplikasi: belum dijalankan; sesi ini perubahan dokumentasi.
- Keputusan penting: runtime FFM dipertahankan; perluas kemampuan bertahap; backend always-on opsional.
- Blocker yang diwariskan: B01 untuk perubahan kontrak cloud; keputusan backend untuk F8.
- Langkah berikutnya: F0.1, kemudian verifikasi wired/service-only/test-only pada F0.2.

### 2026-09-11 — Astra/OpenCode — reverifikasi dan penyempurnaan dokumen

- Status: `VERIFIED` untuk revisi dokumen; implementasi fitur tetap `PLANNED`.
- Permintaan: fokus menyempurnakan file MD berbasis data kode, tanpa mengubah kode aplikasi.
- Pekerjaan: verifikasi klaim dokumen terhadap implementasi aktual (test file, pubspec, orchestrator, read capability service, scheduler/foreground di `main.dart`, pola error handling, generator ID); memperbaiki tabel baseline, F0.3, B01, B04, B05, dan matriks validasi.
- Perubahan data penting: `allowedCapabilityIds` = 18 ID, `canonicalToolChoices` = 11 ID, pesan galat parser klaim 2 ID; foreground service diaktifkan kondisional; pola swallow-error dan ID mikrodetik tunggal terverifikasi di beberapa file.
- Validasi aplikasi: tidak dijalankan; sesi ini hanya revisi dokumentasi, sehingga `flutter analyze lib test`/`flutter test` tidak dijalankan untuk perubahan ini.
- Blocker yang diwariskan: B01 (kontrak cloud 3 lapis); keputusan backend untuk F8; keputusan retensi/pencarian untuk F5.
- Langkah berikutnya: F0.1 mulai implementasi; keputusan kontrak cloud (F0.3) diperlukan sebelum perubahan cloud.

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
