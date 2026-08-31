# FFM — Agent Autonomy Implementation Checklist

> Dokumen kerja untuk AI coding agent seperti Codex, OpenCode, Devin, Claude Code, Cursor Agent, dan agent sejenis.
>
> Tujuan: meng-upgrade agent FFM agar tidak hanya merespons chat, tetapi dapat bekerja semi-otonom/otonom dengan aman, terukur, murah, dan dapat diaudit.

---

## Aturan untuk AI Coding Agent

- [x] Baca dokumen ini seluruhnya sebelum mengubah kode.
- [x] Audit repository sebelum implementasi.
- [x] Jangan membuat ulang fitur yang sudah ada.
- [x] Gunakan komponen existing jika masih layak.
- [x] Jangan menghapus fitur existing tanpa alasan teknis jelas.
- [x] Prioritaskan solusi open-source/gratis.
- [x] Ganti dengan framework/tool yang jelas lebih baik jika ada, demi jangka panjang (lihat AGENTS.md section 26); jangan menambah framework tanpa kebutuhan jelas.
- [ ] Checklist hanya boleh diubah menjadi `[x]` setelah implementasi selesai dan diverifikasi.
- [ ] Jika baru sebagian, tetap `[ ]` dan beri catatan `PARTIAL`.
- [x] Update **Progress Summary** dan **Progress Log** setelah setiap sesi pengerjaan.

---

# 0. Repository Audit

- [x] Petakan struktur folder utama.
- [x] Temukan implementasi agent/assistant saat ini.
- [x] Temukan harness/plugin/tool yang sudah tersedia.
- [x] Temukan struktur database lokal.
- [x] Temukan integrasi Supabase/PostgreSQL.
- [x] Temukan sistem Activity/Aktivitas.
- [x] Temukan transaksi, anggaran, hutang-piutang, aset, target, reminder, dan laporan.
- [x] Temukan sistem notifikasi.
- [x] Temukan background service/job yang sudah ada.
- [x] Temukan provider/model LLM yang sedang digunakan.
- [x] Temukan structured output/tool calling yang sudah ada.
- [x] Catat komponen yang bisa dipakai ulang.

### Status
- [x] Repository Audit selesai.

### Catatan Audit
```text
Flutter utama berada di `lib/`, test di `test/`, dan database Drift lokal di
`lib/core/database/`. Assistant existing memakai `FfmAssistantInterpreter`,
`FfmAgentHarness`, capability registry, planner, executor, validator draft,
bounded Gemini orchestrator, serta personal memory approval. Mutasi sudah melalui
draft -> validator -> confirmation -> executor -> verification. Activity, transaksi,
anggaran, hutang-piutang, aset, target, reminder, laporan, dan notifikasi berada pada
feature masing-masing. Supabase dikonfigurasi runtime melalui `SupabaseService`; tidak
ada migrasi Supabase dalam repository. Android punya notification boot receiver dan
reminder callback, tetapi belum punya worker agent yang berjalan tanpa Flutter.
Komponen reuse utama: registry/executor/risk policy, AuditLogger, idempotency executor,
memory approval, activity query/analysis, serta Gemini read allowlist.
```

---

# 1. Agent Orchestrator

Tujuan: mengubah pola `prompt -> LLM -> jawaban` menjadi workflow agent terstruktur.

```text
User / Trigger
      ↓
Context Builder
      ↓
Intent / Domain Router
      ↓
Planner
      ↓
Tool Selection
      ↓
Tool Execution
      ↓
Validation
      ↓
Decision
      ↓
Action / Response
```

- [x] Audit orchestrator existing.
- [x] Tentukan apakah orchestrator existing cukup atau perlu LangGraph.
- [ ] Jika memakai LangGraph, gunakan versi open-source/self-hostable.
- [ ] Buat state object utama agent.
- [ ] State mendukung `user_id`.
- [ ] State mendukung `activity_id`.
- [ ] State mendukung `domain`.
- [ ] State mendukung `entity_id`.
- [ ] State mendukung `field_id/lahan_id` jika relevan.
- [ ] State mendukung history/context.
- [ ] State mendukung pending action.
- [ ] State mendukung tool result.
- [ ] State mendukung approval state.
- [ ] Buat routing berdasarkan domain.
- [ ] Buat loop tool-call dengan batas maksimum.
- [ ] Cegah infinite reasoning/tool loop.
- [ ] Tambahkan timeout/failure handling.
- [ ] Tambahkan fallback jika LLM gagal.

### Status
- [ ] Agent Orchestrator selesai.

---

# 2. Trigger & Background Worker

Tujuan: agent dapat aktif tanpa user harus membuka chat.

- [ ] Trigger dari input user.
- [x] Trigger berdasarkan waktu/jadwal.
- [ ] Trigger berdasarkan perubahan database.
- [x] Trigger berdasarkan event aplikasi.
- [ ] Trigger berdasarkan kondisi tertentu.
- [x] Trigger dari reminder.
- [ ] Trigger dari aktivitas pertanian.
- [ ] Trigger dari target jatuh tempo.
- [ ] Audit background worker existing.
- [ ] Pilih mekanisme paling ringan dan gratis/open-source.
- [ ] Job dapat berjalan dari backend/server.
- [x] Job tidak bergantung pada Flutter sedang dibuka.
- [x] Job memiliki retry.
- [x] Job memiliki deduplication.
- [x] Job memiliki idempotency.
- [ ] Job mencatat waktu dan hasil eksekusi terakhir.
- [ ] Jangan panggil LLM jika rule/SQL sederhana sudah cukup.

### Status
- [ ] Trigger & Background Worker selesai.

---

# 3. Autonomy Engine

Tujuan: mengatur tindakan apa yang boleh dilakukan agent secara otomatis.

```text
LEVEL 0 = read only
LEVEL 1 = analyze
LEVEL 2 = suggest
LEVEL 3 = create draft
LEVEL 4 = execute low-risk action
LEVEL 5 = explicit approval required
```

- [x] Buat model permission/autonomy.
- [x] Setiap tool memiliki risk level.
- [x] Setiap tool memiliki `requires_approval`.
- [x] Setiap autonomous run memiliki action limit.
- [x] Setiap autonomous run memiliki token/cost limit.
- [x] Agent dilarang menghapus data penting tanpa approval.
- [x] Agent dilarang mengubah nominal transaksi sensitif tanpa approval.
- [x] Agent boleh membaca data sesuai izin.
- [ ] Agent boleh melakukan analisis otomatis.
- [ ] Agent boleh membuat rekomendasi otomatis.
- [ ] Agent boleh membuat draft tindakan.
- [x] Agent dapat meminta approval user.
- [x] Approval tersimpan dan dapat diaudit.
- [x] Semua tool execution melewati permission check.

### Status
- [ ] Autonomy Engine selesai. `PARTIAL` — policy level/allowlist, action limit, estimasi token/cost,
  approval guard, dan persistence policy per household sudah terhubung; analisis/rekomendasi
  otomatis masih belum, sedangkan konfigurasi policy dasar sudah tersedia di Monitoring Agent.

---

# 4. Goal & Task System

Tujuan: agent dapat memiliki tujuan berkelanjutan, bukan hanya satu prompt.

Contoh:
```text
Goal: Pantau budidaya Timun Lahan A sampai panen.
```

Data minimal:
```text
goal_id
user_id
domain
entity_id
activity_id
title
objective
status
priority
created_at
updated_at
last_run_at
next_run_at
completion_condition
```

- [x] Buat model Goal.
- [x] Buat model Task.
- [x] Goal dapat memiliki beberapa task.
- [x] Goal dapat pause/resume.
- [x] Goal dapat selesai berdasarkan condition.
- [x] Goal memiliki priority.
- [x] Goal dapat dikaitkan ke Activity.
- [ ] Goal dapat dikaitkan ke lahan.
- [ ] Goal dapat dikaitkan ke transaksi/aset/target.
- [x] Task memiliki status.
- [x] Task memiliki retry count.
- [x] Task memiliki execution history.
- [x] Agent dapat membuat task dari goal.
- [x] Batasi jumlah task yang boleh dibuat otomatis.

### Status
- [ ] Goal & Task System selesai. `PARTIAL` — model, state durable, evaluator
  completion-condition, dan batch task creation sudah ada; scheduler/task planner
  integration belum.

---

# 5. State & Memory

```text
Short-term memory = konteks run/percakapan saat ini
Operational state = posisi workflow/task
Long-term memory = fakta penting yang perlu diingat
Domain memory = aktivitas, pertanian, transaksi, aset, target, dll.
```

- [x] Audit memory existing.
- [ ] Gunakan Supabase/PostgreSQL jika sudah menjadi memory utama.
- [ ] Jangan menyimpan semua percakapan sebagai memory permanen.
- [ ] Buat klasifikasi memory.
- [ ] Memory memiliki source.
- [ ] Memory memiliki timestamp.
- [ ] Memory memiliki confidence jika berasal dari inference.
- [ ] Memory dapat dikaitkan ke Activity.
- [ ] Memory dapat dikaitkan ke entity.
- [ ] Memory dapat diperbarui/dihapus.
- [ ] Hindari duplicate memory.
- [ ] Retrieval mendukung relevance.
- [ ] Retrieval mendukung recency.
- [ ] Retrieval mendukung domain.
- [ ] Retrieval mendukung entity/activity.
- [ ] Pisahkan memory user dari data transaksi mentah.

### Status
- [ ] State & Memory selesai.

---

# 6. Tool Registry

Tujuan: kemampuan FFM tersedia sebagai tools yang kecil, jelas, tervalidasi, dan dapat diaudit.

## Sense / Read
- [ ] `activity.search`
- [ ] `activity.get_detail`
- [ ] `transaction.search`
- [ ] `budget.read`
- [ ] `debt.read`
- [ ] `asset.read`
- [ ] `goal.read`
- [ ] `reminder.read`
- [ ] `farm.history`
- [ ] `memory.search`

## Logic / Analysis
- [ ] `financial_health.analyze`
- [ ] `budget_guard.analyze`
- [ ] `loan_affordability.analyze`
- [ ] `activity_context.resolve`
- [ ] `farm_activity.analyze`
- [ ] `goal_progress.analyze`

## Actuator / Action
- [ ] `transaction.create_draft`
- [ ] `activity.create_draft`
- [ ] `activity.link`
- [ ] `goal.create_draft`
- [ ] `reminder.create`
- [ ] `notification.send`
- [ ] `report.generate`

## Standar Tool
- [ ] Semua tool memiliki input schema.
- [ ] Semua tool memiliki output schema.
- [ ] Semua tool memiliki validation.
- [ ] Semua tool memiliki permission level.
- [ ] Semua tool memiliki audit log.
- [ ] Semua tool memiliki error handling.
- [ ] Hindari tool yang terlalu luas.
- [ ] Tool mutasi melewati policy check.
- [ ] Naming tool konsisten.
- [ ] Tool dapat dipanggil melalui structured tool calling.

### Status
- [ ] Tool Registry selesai.

---

# 7. Event System

Event minimal:
```text
activity.created
activity.updated
transaction.created
transaction.updated
goal.created
goal.overdue
reminder.due
asset.updated
debt.due
farm.activity_created
farm.no_activity_detected
agent.task_failed
agent.approval_required
```

- [x] Buat standard event envelope.
- [x] Event memiliki `event_id`.
- [x] Event memiliki `event_type`.
- [x] Event memiliki `user_id` (householdId).
- [x] Event memiliki `entity_id`.
- [x] Event memiliki `activity_id` jika relevan.
- [x] Event memiliki timestamp.
- [x] Event memiliki payload.
- [x] Event processing idempotent.
- [x] Event tidak diproses dua kali.
- [x] Event dapat diproses oleh worker batch satu siklus.
- [ ] Event dapat memicu agent.
- [ ] Event sederhana diproses tanpa LLM jika memungkinkan.
- [ ] Event penting dapat menghasilkan notification.

### Status
- [ ] Event System selesai. `PARTIAL` — envelope, tabel durable `assistant_agent_events`,
  enqueue/claim/retry idempoten, dan worker batch sudah ada; trigger Flutter-tertutup
  serta notifikasi masih belum.

---

# 8. Audit, Safety & Observability

Audit minimal:
```text
run_id
goal_id
task_id
user_id
trigger
model
tool_name
tool_input
tool_output
decision
approval_status
started_at
finished_at
error
```

- [x] Buat AgentRun log.
- [x] Buat ToolExecution log.
- [x] Buat Approval log.
- [x] Buat error log.
- [x] Catat model/provider.
- [x] Catat tool yang dipanggil.
- [x] Catat hasil tool.
- [x] Simpan structured decision summary.
- [ ] Jangan simpan chain-of-thought mentah.
- [x] Batasi jumlah tool-call per run.
- [x] Batasi retry.
- [x] Tambahkan timeout.
- [x] Tambahkan circuit breaker.
- [x] Tambahkan duplicate-action protection.
- [x] Tambahkan loop protection.
- [x] Tambahkan monitoring autonomous run.
- [x] Riwayat action agent dapat diperiksa dari debug/admin UI atau log.

### Status
- [ ] Audit, Safety & Observability selesai. `PARTIAL` — AgentRun, Approval, ToolExecution,
  error log, circuit breaker, monitoring, dan UI inspeksi sudah ada; hardening lanjutan
  serta integrasi admin terpisah masih belum.

---

# 9. Autonomous Farming E2E

Contoh:
```text
Goal: Pantau Timun Lahan A sampai panen.
```

Flow:
```text
Scheduler/Event
↓
resolve activity_id Timun Lahan A
↓
ambil umur tanaman + histori
↓
jalankan rule sederhana
↓
LLM reasoning hanya jika perlu
↓
ambil tool/data tambahan
↓
hasilkan rekomendasi
↓
cek autonomy permission
↓
simpan hasil
↓
notifikasi hanya jika penting
```

- [ ] Agent dapat membedakan dua lahan dengan komoditas sama.
- [ ] Aktivitas terhubung ke `activity_id/entity_id` yang benar.
- [ ] Agent tidak mencampur dua siklus tanam.
- [ ] Agent dapat mendeteksi tidak adanya aktivitas.
- [ ] Agent dapat menghasilkan analisis berdasarkan histori.
- [ ] Agent hanya memanggil LLM saat diperlukan.
- [ ] Agent dapat diam jika tidak ada hal penting.
- [ ] Agent dapat mengirim notifikasi jika ditemukan kondisi penting.

### Status
- [ ] Autonomous Farming E2E berhasil.

---

# 10. Autonomous Finance E2E

Contoh:
```text
User: Beli pupuk NPK Rp300.000 untuk Timun Lahan A.
```

Flow:
```text
Intent
↓
resolve Timun Lahan A
↓
resolve activity_id
↓
buat draft transaksi
↓
hubungkan ke aktivitas
↓
validasi
↓
approval jika perlu
↓
simpan
↓
update activity context
```

- [ ] Agent memahami transaksi terkait aktivitas.
- [ ] Agent resolve entity/activity yang benar.
- [ ] Agent membuat structured draft.
- [ ] Nominal tervalidasi.
- [ ] Kategori tervalidasi.
- [ ] Link activity tersimpan.
- [ ] Action mengikuti Autonomy Engine.
- [ ] Semua tool-call tercatat.
- [ ] Hasil dapat dilacak dari Activity.

### Status
- [ ] Autonomous Finance E2E berhasil.

---

# 11. Cost Control

- [ ] Rule sederhana tidak memakai LLM.
- [ ] SQL/filter dipakai sebelum semantic/LLM search.
- [ ] Gunakan model kecil untuk classification/routing jika cukup.
- [ ] Model reasoning besar hanya dipakai saat diperlukan.
- [ ] Cache hasil yang aman untuk di-cache.
- [ ] Hindari context terlalu besar.
- [ ] Batasi autonomous token budget.
- [ ] Batasi jumlah autonomous run.
- [ ] Gunakan framework open-source/gratis jika memungkinkan.
- [ ] Jangan menambahkan SaaS berbayar tanpa kebutuhan jelas.

### Status
- [ ] Cost Control selesai.

---

# 12. Testing

- [ ] Unit test Tool Registry.
- [ ] Unit test permission rules.
- [ ] Unit test event processing.
- [ ] Unit test activity resolution.
- [ ] Unit test goal/task state.
- [ ] Test dua lahan dengan komoditas sama.
- [ ] Test dua siklus tanam berbeda.
- [ ] Test duplicate event.
- [ ] Test duplicate transaction.
- [ ] Test failed tool.
- [ ] Test LLM timeout.
- [ ] Test invalid structured output.
- [ ] Test autonomous run limit.
- [ ] Test approval-required action.
- [ ] Test server restart/recovery.
- [ ] Test notification flow.
- [ ] Regression test fitur existing FFM.

### Status
- [ ] Testing selesai.

---

# 13. Definition of Done

Upgrade dianggap selesai jika:

- [ ] Agent dapat dipicu user.
- [ ] Agent dapat dipicu event.
- [x] Agent dapat dipicu scheduler.
- [ ] Agent memahami activity/entity yang benar.
- [ ] Agent memiliki persistent state.
- [ ] Agent memiliki goal/task.
- [ ] Agent dapat memilih tool.
- [ ] Agent dapat melakukan loop secara terbatas.
- [ ] Agent tidak melakukan tindakan berisiko tanpa izin.
- [ ] Agent dapat bekerja tanpa Flutter sedang dibuka.
- [ ] Agent dapat mengirim notifikasi penting.
- [ ] Agent tidak spam notifikasi.
- [ ] Agent memiliki audit trail.
- [ ] Agent memiliki error recovery.
- [ ] Agent memiliki cost/token guard.
- [ ] Fitur existing utama tetap berjalan.
- [ ] Semua test kritis lulus.

---

# Progress Summary

> Wajib diperbarui oleh AI coding agent setiap selesai bekerja.

```text
Repository Audit       : DONE
Agent Orchestrator     : PARTIAL
Background Worker      : PARTIAL
Autonomy Engine        : PARTIAL
Goal & Task            : PARTIAL
State & Memory         : PARTIAL
Tool Registry          : PARTIAL
Event System           : PARTIAL
Audit & Safety         : PARTIAL
Farming E2E            : PARTIAL
Finance E2E            : PARTIAL
Cost Control           : PARTIAL
Testing                : PARTIAL
```

Status yang diperbolehkan:
```text
NOT STARTED
IN PROGRESS
PARTIAL
BLOCKED
DONE
```

---

# Progress Log

Gunakan template berikut setiap sesi:

```text
Date:
Agent:
Commit:
Status:

Completed:
- ...

Changed:
- ...

Remaining:
- ...

Blocked:
- ...

Tests:
- ...

Important Notes:
- ...
```

```text
Date: 2026-08-31
Agent: OpenCode
Commit: Belum dibuat
Status: PARTIAL

Completed:
- Menutup celah executor (deny-by-default): capability di luar registry diblokir
  sebelum handler/navigasi dapat dipanggil; alasan plan diblokir disimpan.
- Menambahkan registry untuk verify.asset_mutation / liability_mutation /
  budget_mutation (adapter sudah punya handler, registry belum; regresi diperbaiki).
- Menambahkan `FfmAssistantAutonomyPolicy` dengan level autonomy, allowlist capability,
  batas action/token/cost, dan approval guard pada setiap tool execution.
- Menyimpan policy autonomy sebagai preference JSON versioned per household dan memuatnya
  saat Assistant Sheet dibuka; konfigurasi invalid kembali ke default aman.
- Menambahkan approval audit log durable (request/approved/rejected) pada schema 47
  dan menghubungkannya ke lifecycle konfirmasi draft di Assistant Sheet.
- Menambahkan durable ToolExecution log pada schema 48; executor mencatat status
  started/completed/failed/blocked per run dan step tanpa parameter mentah.
- Menambahkan circuit breaker per capability dengan threshold kegagalan dan cooldown;
  executor mencatat blokir sementara tanpa memanggil handler.
- Menambahkan query bounded `recentRuns` dan halaman Monitoring Agent read-only di menu
  Lainnya untuk memeriksa status run serta detail ToolExecution yang aman.
- Durability event/state: schemaVersion 45 -> 46; tabel assistant_agent_runs +
  assistant_agent_events; migrasi `from < 46` + index.
- Repository autonomy: enqueueEvent (insertOrIgnore idempoten), processEvent (claim
  atomik + attempt_count + retry failed + tolak completed), recordPlan (serial queue,
  insertOnConflictUpdate, decisionSummary "N langkah selesai, M gagal").
- Wiring recordPlan dari validator/executor ke repository via onPlanRecorded +
  sheet; registrasi di injection (LazySingleton).
- Katalog database structure service untuk tabel autonomy baru.
- Perkecil cakupan routing navigasi interpreter: permintaan daftar Menu Lainnya
  dikembalikan sebelum knowledge-base/query struktur; navigasi eksplisit (buka/
  tampilkan) diputuskan lebih awal; frasa "mulai aktivitas" tidak diambil alih navigasi.

Changed:
- lib/features/assistant/domain/ffm_assistant_capability_executor.dart + test
- lib/features/assistant/domain/ffm_assistant_autonomy_policy.dart + test
- lib/features/assistant/domain/ffm_assistant_tool_execution.dart
- lib/features/assistant/domain/ffm_assistant_circuit_breaker.dart
- lib/features/assistant/presentation/pages/ffm_assistant_autonomy_monitor_page.dart
- lib/features/assistant/domain/ffm_assistant_execution_limits.dart
- lib/features/assistant/domain/ffm_assistant_capabilities.dart
- lib/features/assistant/data/ffm_assistant_capability_adapters.dart
- lib/core/database/tables.dart, app_database.dart, app_database.g.dart
- lib/core/database/ffm_database_structure_service.dart
- lib/features/assistant/data/ffm_assistant_autonomy_repository.dart (baru)
- lib/core/di/injection.dart
- lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart
- lib/features/settings/presentation/pages/other_menu_page.dart
- lib/features/assistant/data/ffm_assistant_interpreter.dart
- test/ffm_assistant_autonomy_repository_test.dart,
  test/ffm_assistant_capability_executor_test.dart,
  test/ffm_assistant_autonomy_policy_test.dart,
  test/ffm_assistant_autonomy_monitor_page_test.dart,
  test/database_migration_v64_test.dart,
  test/database_structure_v64_test.dart,
  test/ffm_assistant_destination_coverage_test.dart
- docs/AGENT_AUTONOMY_IMPLEMENTATION.md

Remaining:
- Background worker dan trigger (waktu/event/database/reminder) agar agent berjalan
  saat Flutter tertutup.
- Konfigurasi policy dari UI dan agent goal/task.
- E2E farming/finance dan cost control.
- Routing navigasi interpreter belum penuh hijau: 1 test destination coverage gagal
  (kata "struktur" diharapkan openPage, saat ini unknown); ditunda sesuai arahan user.

Blocked:
- Tidak ada blocker teknis. Autonomous background membutuhkan keputusan arsitektur
  backend/worker agar dapat berjalan saat Flutter tertutup.
- ffm_assistant_interpreter.dart sedang ditulis proses paralel; hasil test routing
  bisa berubah antar-jalankan.

Tests:
- flutter test test/ffm_assistant_autonomy_policy_test.dart (5 lulus)
- flutter test test/ffm_assistant_autonomy_repository_test.dart (7 lulus, termasuk approval/tool audit dan monitoring query)
- flutter test test/ffm_assistant_capability_executor_test.dart (8 lulus, termasuk circuit breaker)
- flutter test test/database_migration_v64_test.dart (version 48 lulus)
- flutter test test/database_structure_v64_test.dart
- asset/budget/liability mutation test
- flutter analyze lib test: 0 issues
- Destinasi menu interpreter: sebagian lulus; 1 test navigasi ditunda (lihat Remaining).

Important Notes:
- Semua mutasi tetap melalui validator, confirmation, executor, dan verification.
- Registry adalah allowlist wajib; adanya handler tidak memberi izin capability baru.
- Decision summary yang disimpan adalah ringkasan eksekusi, bukan chain-of-thought.

Date: 2026-09-01
Agent: OpenCode
Commit: Belum dibuat
Status: PARTIAL

Completed:
- Menambahkan durable ToolExecution log pada schema 48.
- Executor mencatat `started`, `completed`, `failed`, dan `blocked` per run/step.
- Audit tool hanya menyimpan metadata terstruktur dan ringkasan aman, bukan parameter mentah.
- Menghubungkan listener ToolExecution ke repository autonomy dan Assistant Sheet.
- Menambahkan circuit breaker per capability dengan threshold kegagalan dan cooldown.
- Menambahkan query `recentRuns` bounded dan halaman Monitoring Agent read-only di menu Lainnya.
- Menambahkan widget test untuk memastikan run terbaru tampil tanpa membuka data sensitif.
- Menambahkan Goal/Task Agent durable pada schema 49, dengan relasi domain/entity/
  activity, status pause/resume, retry count, batas 20 task per goal, dan execution history.

Changed:
- lib/features/assistant/domain/ffm_assistant_tool_execution.dart
- lib/features/assistant/domain/ffm_assistant_agent_work.dart
- lib/features/assistant/domain/ffm_assistant_capability_executor.dart
- lib/features/assistant/domain/ffm_assistant_circuit_breaker.dart
- lib/features/assistant/data/ffm_assistant_autonomy_repository.dart
- lib/features/assistant/presentation/pages/ffm_assistant_autonomy_monitor_page.dart
- lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart
- lib/features/settings/presentation/pages/other_menu_page.dart
- lib/core/database/tables.dart, app_database.dart, app_database.g.dart
- lib/core/database/ffm_database_structure_service.dart
- test/ffm_assistant_autonomy_repository_test.dart
- test/ffm_assistant_capability_executor_test.dart
- test/ffm_assistant_autonomy_monitor_page_test.dart
- test/ffm_assistant_agent_work_test.dart
- test/database_migration_v64_test.dart
- docs/AGENT_AUTONOMY_IMPLEMENTATION.md

Remaining:
- Konfigurasi policy dari UI, scheduler/agent task creation, dan completion-condition evaluator.
- Hardening monitoring untuk admin terpisah.
- Background worker/trigger saat Flutter tertutup.

Blocked:
- Tidak ada blocker teknis untuk monitoring Agent.

Tests:
- flutter analyze lib test: 0 issues
- Test monitoring/repository/executor/Goal-Task/migrasi/struktur: seluruhnya lulus
- database migration: schema 49 lulus

Important Notes:
- Log tidak menyimpan chain-of-thought atau parameter tool mentah.
- Kegagalan pencatatan audit tidak membatalkan eksekusi capability; dicatat melalui error logger.

Date: 2026-09-01
Agent: OpenCode
Commit: Belum dibuat
Status: PARTIAL

Completed:
- Menambahkan evaluator completion-condition deterministik untuk `all_tasks_completed`,
  `no_pending_tasks`, dan `any_task_completed`; kondisi tidak dikenal atau goal tanpa task
  tidak dianggap selesai.
- Menambahkan `evaluateAndCompleteGoal` yang hanya mengubah goal aktif menjadi completed
  setelah status task dibaca dari database.
- Menambahkan `FfmAssistantAutonomyWorker.runOnce` untuk memproses batch event pending/failed
  dengan batas jumlah event dan maksimum percobaan.
- Worker mengantrekan task `nextRunAt` yang jatuh tempo menjadi event `agent.task.due`
  dengan event ID deterministik, sehingga enqueue tetap idempoten.

Changed:
- lib/features/assistant/domain/ffm_assistant_agent_work.dart
- lib/features/assistant/data/ffm_assistant_autonomy_repository.dart
- lib/features/assistant/data/ffm_assistant_autonomy_worker.dart
- test/ffm_assistant_agent_work_test.dart
- test/ffm_assistant_autonomy_worker_test.dart
- docs/AGENT_AUTONOMY_IMPLEMENTATION.md

Remaining:
- Scheduler/task planner integration dari goal.
- Trigger waktu/event/database/reminder saat Flutter tertutup.
- Konfigurasi policy dari UI, monitoring hardening, dan E2E farming/finance.

Blocked:
- Tidak ada blocker teknis.

Tests:
- flutter test test/ffm_assistant_agent_work_test.dart test/ffm_assistant_autonomy_worker_test.dart test/ffm_assistant_autonomy_repository_test.dart: 15 lulus.
- Validasi mencakup completion condition, worker success, retry, batas attempt, dan event completed.
- Batch task creation memvalidasi goal/household, duplicate ID, dan batas 20 task.

Important Notes:
- Worker hanya memproses event durable; ia belum menjadi Android/backend scheduler.
- Completion condition dievaluasi oleh kode aplikasi, bukan model.

Date: 2026-09-01
Agent: OpenCode
Commit: Belum dibuat
Status: PARTIAL

Completed:
- Menambahkan konfigurasi policy autonomy dasar pada halaman Monitoring Agent.
- UI menggunakan default `explicitApproval`, batas action 1-20, helper text, loading state,
  dan feedback sukses/gagal.
- Policy disimpan melalui repository per household; tidak ada data percakapan atau parameter
  tool yang ditambahkan ke persistence.
- Memperbaiki widget test yang terdampak konten list di luar viewport dan API Flutter deprecated.

Changed:
- lib/features/assistant/presentation/pages/ffm_assistant_autonomy_monitor_page.dart
- test/ffm_assistant_autonomy_monitor_page_test.dart
- docs/AGENT_AUTONOMY_IMPLEMENTATION.md

Remaining:
- Monitoring hardening dan E2E farming/finance.
- Scheduler Android/backend untuk menjalankan worker saat Flutter tertutup.
- Integrasi task planner dengan sumber trigger Agent.

Blocked:
- Tidak ada blocker teknis pada policy UI.

Tests:
- flutter test test/ffm_assistant_autonomy_monitor_page_test.dart test/ffm_assistant_autonomy_policy_test.dart test/ffm_assistant_autonomy_worker_test.dart test/ffm_assistant_agent_work_test.dart: 16 lulus.
- flutter analyze lib test: 0 issues.

Important Notes:
- Scheduler platform belum ditambahkan karena worker task execution membutuhkan resolver
  capability yang aman untuk background isolate; plugin WorkManager belum menjadi dependency.

Date: 2026-09-01
Agent: OpenCode
Commit: Belum dibuat
Status: PARTIAL

Completed:
- Menambahkan `FfmAssistantAutonomyTriggerService` untuk mengubah trigger aplikasi menjadi
  event durable tanpa memanggil LLM atau capability executor.
- Event sekarang menyimpan `householdId` dari trigger, bukan selalu `local-household`.
- Enqueue menggunakan `INSERT OR IGNORE` dengan hasil row count yang akurat untuk deduplication.
- Payload trigger dibatasi metadata scalar, jumlah field, panjang string, dan membuang key
  sensitif seperti prompt, input, token, secret, credential, raw, dan content.
- Mendaftarkan trigger service ke dependency injection.

Changed:
- lib/features/assistant/data/ffm_assistant_autonomy_repository.dart
- lib/features/assistant/data/ffm_assistant_autonomy_trigger_service.dart
- lib/core/di/injection.dart
- test/ffm_assistant_autonomy_trigger_service_test.dart
- docs/AGENT_AUTONOMY_IMPLEMENTATION.md

Remaining:
- Menghubungkan trigger service ke sumber reminder/database/event yang konkret.
- Scheduler Android/backend untuk menjalankan worker saat Flutter tertutup.
- Resolver task planner dan capability execution untuk event `agent.task.due`.

Blocked:
- Tidak ada blocker teknis pada trigger envelope dan deduplication.

Tests:
- Trigger/repository/worker/monitor suite: 14 lulus.
- flutter analyze lib test: 0 issues.

Important Notes:
- Trigger hanya enqueue event; boundary validation, approval, executor, dan verification tetap
  tidak dilewati.

Date: 2026-09-01
Agent: OpenCode
Commit: Belum dibuat
Status: PARTIAL

Completed:
- Menghubungkan `ReminderBloc` ke `FfmAssistantAutonomyTriggerService`.
- Aksi notifikasi reminder mengantrekan event `reminder.due` berdasarkan `history.id` sebagai
  deduplication key, termasuk household, reminder, history, occurrence, dan action metadata.
- Kegagalan persistence autonomy tidak menggagalkan aksi reminder utama.
- Menambahkan test integrasi notification tap dan memastikan event autonomy tetap terbuat.

Changed:
- lib/features/reminder/presentation/bloc/reminder_bloc.dart
- lib/core/di/injection.dart
- test/reminder_test.dart
- docs/AGENT_AUTONOMY_IMPLEMENTATION.md

Remaining:
- Trigger database/app event lain yang konkret.
- Scheduler Android/backend untuk menjalankan worker saat Flutter tertutup.
- Resolver task planner dan capability execution untuk event `agent.task.due`.

Blocked:
- Tidak ada blocker teknis pada reminder trigger.

Tests:
- flutter test test/reminder_test.dart test/ffm_assistant_autonomy_trigger_service_test.dart: 9 lulus.
- flutter analyze lib test: 0 issues.

Important Notes:
- Reminder tetap authoritative terhadap status history; autonomy hanya menerima event terstruktur
  untuk diproses kemudian.

Date: 2026-09-01
Agent: OpenCode
Commit: Belum dibuat
Status: PARTIAL

Completed:
- Menambahkan metadata task `capabilityId` dan `parametersJson` pada schema 50 untuk membuat
  task execution eksplisit dan tidak menebak capability dari judul task.
- Menambahkan migrasi 49 -> 50 dengan guard kolom agar upgrade langsung dari schema lama tetap aman.
- Menambahkan `FfmAssistantAgentTaskPlanResolver` yang memvalidasi event, household, status task,
  JSON parameter, dan capability registry sebelum membentuk plan.
- Menambahkan `FfmAssistantAgentTaskEventHandler` sebagai adapter worker ke executor plan;
  success/failure dicatat ke execution history dan completion goal dievaluasi setelah success.
- Mendaftarkan resolver di dependency injection.

Changed:
- lib/core/database/tables.dart
- lib/core/database/app_database.dart
- lib/core/database/app_database.g.dart
- lib/core/di/injection.dart
- lib/features/assistant/domain/ffm_assistant_agent_work.dart
- lib/features/assistant/data/ffm_assistant_autonomy_repository.dart
- lib/features/assistant/data/ffm_assistant_agent_task_plan_resolver.dart
- lib/features/assistant/data/ffm_assistant_agent_task_event_handler.dart
- test/database_migration_v64_test.dart
- test/ffm_assistant_agent_task_plan_resolver_test.dart
- test/ffm_assistant_agent_task_event_handler_test.dart
- docs/AGENT_AUTONOMY_IMPLEMENTATION.md

Remaining:
- Menyediakan executor callback nyata dari capability executor pada host worker.
- Scheduler Android/backend untuk menjalankan worker saat Flutter tertutup.
- Trigger database/app event lain, monitoring hardening, dan E2E farming/finance.

Blocked:
- Tidak ada blocker pada schema, resolver, atau handler. Background scheduler masih menunggu
  host executor yang aman untuk isolate dan lifecycle Android.

Tests:
- Resolver/handler/Goal-Task/worker/repository/migrasi/struktur/executor: 33 lulus.
- flutter analyze lib test: 0 issues.

Important Notes:
- Resolver hanya membentuk plan. Capability tetap harus melewati executor, policy, confirmation,
  registry, dan verification.

Date: 2026-09-01
Agent: OpenCode
Commit: Belum dibuat
Status: PARTIAL

Completed:
- Menambahkan `FfmAssistantAutonomyTaskExecutionHost` sebagai executor callback nyata untuk
  task Agent menggunakan adapter registry dan `FfmAssistantCapabilityExecutor` existing.
- Host memuat policy per household dan membuat controller plan baru untuk setiap execution.
- Read-only plan berhasil dieksekusi melalui adapter registry; mutation tanpa verification tetap
  diblokir oleh workflow safety sebelum handler.
- Mendaftarkan worker, resolver, host, dan task event handler di dependency injection.

Changed:
- lib/features/assistant/data/ffm_assistant_autonomy_task_execution_host.dart
- lib/core/di/injection.dart
- test/ffm_assistant_autonomy_task_execution_host_test.dart
- docs/AGENT_AUTONOMY_IMPLEMENTATION.md

Remaining:
- Scheduler Android/backend untuk memanggil `worker.runOnce` saat Flutter tertutup.
- Trigger database dan event aplikasi lain.
- E2E farming/finance, monitoring hardening, serta release validation.

Blocked:
- Tidak ada blocker pada executor host.

Tests:
- Host/resolver/handler/executor/policy/migrasi: 21 lulus.
- flutter analyze lib test: 0 issues.

Important Notes:
- Host tidak membuat pengecualian policy; task mutation tetap memerlukan confirmation dan
  verification sesuai executor existing.

Date: 2026-09-01
Agent: OpenCode
Commit: Belum dibuat
Status: PARTIAL

Completed:
- Menambahkan WorkManager `0.10.9` sebagai scheduler Android periodik 15 menit.
- Menambahkan top-level background dispatcher yang menginisialisasi plugin, dependency, database,
  worker, background event handler, lalu mengembalikan status retry/success ke WorkManager.
- Scheduler dijalankan saat startup dengan fallback diagnostik; kegagalan scheduler tidak memblokir
  penggunaan aplikasi foreground.
- Menambahkan background event routing untuk `agent.task.due`, `reminder.due`, dan
  `database.changed` tanpa retry tidak perlu untuk event audit-only.
- Menghubungkan trigger database aman ke Activity Repository dan SaveTransaction batch/single/mixed.
- Menambahkan E2E finance/farming pipeline dari goal, due event, resolver, executor, task history,
  sampai goal completion.
- Monitoring Agent sekarang menerima household scope eksplisit untuk mencegah detail tool lintas
  household terbaca.
- Full test suite lulus dan release APK ARM64 berhasil dibangun.

Changed:
- pubspec.yaml, pubspec.lock
- lib/main.dart
- lib/core/di/injection.dart
- lib/features/assistant/data/ffm_assistant_autonomy_background_handler.dart
- lib/features/assistant/data/ffm_assistant_autonomy_background_scheduler.dart
- lib/features/assistant/data/ffm_assistant_autonomy_background_dispatcher.dart
- lib/features/assistant/data/ffm_assistant_autonomy_task_execution_host.dart
- lib/features/assistant/data/ffm_assistant_autonomy_trigger_service.dart
- lib/features/assistant/data/ffm_assistant_autonomy_repository.dart
- lib/features/assistant/data/ffm_assistant_agent_task_plan_resolver.dart
- lib/features/assistant/data/ffm_assistant_agent_task_event_handler.dart
- lib/features/assistant/domain/ffm_assistant_agent_work.dart
- lib/features/assistant/presentation/pages/ffm_assistant_autonomy_monitor_page.dart
- lib/features/activity/data/repositories/activity_repository.dart
- lib/features/reminder/presentation/bloc/reminder_bloc.dart
- lib/features/transaction/domain/usecases/transaction_crud_usecases.dart
- lib/core/database/tables.dart, app_database.dart, app_database.g.dart
- test/* autonomy, trigger, resolver, handler, E2E, reminder, database migration
- docs/AGENT_AUTONOMY_IMPLEMENTATION.md

Remaining:
- Validasi WorkManager dan notification behavior pada device/emulator Android nyata.
- E2E domain penuh untuk dua lahan, transaksi mutation dengan approval, dan notifikasi penting.
- Trigger database untuk seluruh domain non-activity/transaksi.
- Cost control/cache hardening dan review monitoring admin.
- Verifikasi final APK pada device ARM64.

Blocked:
- Tidak ada blocker build atau test. Validasi background runtime belum dapat diklaim tanpa device.

Tests:
- flutter test: 828 lulus.
- flutter analyze lib test: 0 issues.
- flutter build apk --target-platform android-arm64 --release: berhasil.
- APK: build/app/outputs/flutter-apk/app-release.apk, 38.0 MB.
- Isi native APK hanya `lib/arm64-v8a`.

Important Notes:
- WorkManager adalah scheduler best-effort Android dengan minimum interval sistem sekitar 15 menit;
  ia bukan jaminan eksekusi tepat waktu.
- Build release mengeluarkan warning dependency Kotlin plugin dari `speech_to_text` dan WorkManager,
  tetapi tidak gagal. Ini residual maintenance risk untuk migrasi Built-in Kotlin Flutter berikutnya.
```

---

# Instruksi Terakhir untuk AI Coding Agent

Jangan mencentang checklist hanya karena file/class sudah dibuat.

Item `[x]` berarti:

1. kode benar-benar ada,
2. terhubung dengan sistem existing,
3. dapat dijalankan,
4. sudah diverifikasi,
5. tidak merusak fitur existing,
6. memiliki test atau bukti validasi yang memadai.

Jika belum memenuhi seluruh poin tersebut, jangan tandai selesai.
