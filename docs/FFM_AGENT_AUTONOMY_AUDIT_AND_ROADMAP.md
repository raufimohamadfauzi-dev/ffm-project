# FFM Agent Autonomy Audit And Delivery Roadmap

Status: active implementation checklist

Last audited: 2026-09-02
Last updated: 2026-09-03 (Intelligence & Autonomy Expansion)

Scope: AI assistant, orchestrator, Gemini routing, autonomous/proactive work,
financial reasoning engines, multi-turn dialogue, multimodal ingestion,
capabilities, action execution, grounding, memory, notifications, and tests.

## How To Use This Document

- Treat each checkbox as an implementation contract, not a suggestion.
- Check a box only after its acceptance criteria and relevant tests pass.
- Keep unchecked items when a change is partial; add a short progress note under
  the item rather than marking it done.
- Do not weaken safety boundaries to finish a checkbox. Financial facts remain
  deterministic and all mutations still require validation, confirmation,
  execution through an allowlisted capability, and post-execution verification.
- Work in priority order. Do not begin P2 or P3 while an unresolved P0 item
  can cause startup failure, unsafe behavior, or ungrounded financial claims.

## Product Definition

FFM Agent is not a chatbot with access to finance features. It is a bounded,
goal-oriented financial system which can independently observe trustworthy app
data, recognize meaningful conditions, forecast financial trajectories, prioritize
insights, and deliver the right next step to the user.

Target loop:

```text
Durable event / scheduled evaluation / user message / multimodal intake
  -> bounded sensing & multi-source intake (cashflow, calendar, receipts, alerts)
  -> deterministic financial analysis & forward projection (runway, rebalancing)
  -> conversational slot-filling & intent disambiguation (when input is partial)
  -> confidence, priority, and relevance scoring
  -> structured insight, question, next best action (NBFA), or action draft
  -> user confirmation & plan dry-run preview when mutation is proposed
  -> capability execution (allowlisted, serial, circuit-broken)
  -> verification with before/after state delta & durable outcome
  -> approved-memory synthesis / feedback reinforcement learning
```

Autonomy is permitted for read-only sensing, deterministic analysis, ranking,
and delivery of low-noise insights. It is not permission for an LLM to change
financial state. Gemini may interpret and explain facts or propose a draft; it
cannot bypass the application validation, confirmation, capability executor,
or verification boundary.

### Pillars Of Advanced Financial Intelligence In FFM

To make FFM Agent genuinely smarter than a traditional rule engine or generic LLM wrapper,
the architecture combines deterministic computation with empathetic contextual reasoning:

1. **Predictive Foresight (Not Merely Reactive)**:
   Forecasting cashflow runway, calculating safe daily spending limits, and predicting
   cashout dates ahead of time rather than alerting only after budget depletion.
2. **Algorithmic Envelope Optimization (Zero-Sum Rebalancing)**:
   Proactively detecting when category deficits can be safely offset by surplus categories
   without increasing total net expenses.
3. **Conversational Fluency & Multi-Turn Slot Filling**:
   Gracefully handling incomplete, colloquial, or ambiguous user requests by asking targeted,
   single-slot clarification questions in natural Indonesian, without losing conversational context.
4. **Multimodal Grounded Ingestion (Nota/Struk & Banking Alerts)**:
   Ingesting receipts and push notifications with deterministic mathematical reconciliation
   (`sum(lineItems) + tax == totalAmount`) before presenting 1-tap actionable drafts.
5. **Closed-Loop Verification & State-Delta Transparency**:
   Demonstrating the exact before-and-after financial delta (`balanceBefore` vs `balanceAfter`)
   and offering dry-run previews so users retain complete trust and control.
6. **Indonesian Financial Nuances & Lifestyle Rhythms**:
   Deep grounding in Indonesian financial realities: gajian (25th/end-of-month) cashflow cycles,
   THR (Tunjangan Hari Raya) allocations, arisan schedules, cicilan/paylater debt burden (DSR),
   and empathetic "Tanggal Tua / Boncos" guidance.

## What Was Inspected

### Main request path

- `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart`
  assembles chat/page context, sends turns to the interpreter, renders plans,
  previews drafts, and triggers memory learning.
- `lib/features/assistant/data/ffm_assistant_interpreter.dart` is the current
  central routing layer for deterministic logic, local harness, Gemini,
  verified facts, drafts, and fallback behavior.
- `lib/features/assistant/data/ffm_gemini_cloud_orchestrator.dart` is the
  Gemini boundary. It can request local read data and then issue a grounded
  second Gemini call.

### Financial truth and grounding

- `ffm_assistant_financial_snapshot_service.dart` creates deterministic month
  snapshots and a transaction digest bounded to eight items.
- `ffm_assistant_verified_fact_service.dart` and
  `ffm_assistant_analysis_engine.dart` provide verified and analyzed facts
  (frequency, trend, comparison, pattern, and period analysis).
- `ffm_assistant_grounding_validator.dart` blocks unsupported save claims and
  performs lightweight checks on financial numbers and dates.

### Planning and execution

- `ffm_assistant_action_planner.dart` turns intent/drafts into plans with
  prerequisite reads, one mutation maximum, confirmation, and verification.
- `ffm_assistant_capability_executor.dart` enforces allowlists, policy,
  confirmation, serial execution, timeouts, read retries, circuit breaking,
  auditing, and execution records.
- `ffm_assistant_capability_adapters.dart` maps allowed capabilities to the
  application's actual repositories/use cases.

### Autonomous and proactive behavior

- `ffm_assistant_autonomy_trigger_service.dart` creates sanitized durable
  events.
- `ffm_assistant_autonomy_worker.dart`, background scheduler, and dispatcher
  run due work through Workmanager.
- `ffm_assistant_agent_task_plan_resolver.dart` and task execution host resolve
  persisted agent tasks into action plans.
- `ffm_assistant_proactive_evaluation_task.dart` currently checks budget
  overruns and writes a message to chat history.
- `ffm_assistant_proactive_monitor.dart` currently detects activity sessions
  active for at least twelve hours and changes launcher state.

### Memory, recommendation, and multimodal foundations

- Personal-memory extraction, approval, learning candidates, decay, and
  approved-memory persistence were inspected under `lib/features/assistant`.
- `ffm_assistant_follow_up_suggestions.dart` and `ffm_assistant_recommendation.dart`
  contain initial follow-up and recommendation domain models.
- `ffm_qwen2vl_gateway.dart` and `receipt_import_test.dart` provide vision/OCR
  foundation for receipt processing.
- `lib/core/services/hijri_calendar_service.dart` supports Islamic date calculations
  for Ramadhan and Qurban seasonal planning.
- `ffm_category_suggestion_service.dart` and `ffm_draft_correction_learning_test.dart`
  contain category suggestion and draft correction learning primitives.

### Tests and validation executed

- `flutter analyze lib test` completed with no errors. It reported 16 existing
  deprecation infos in transaction UI files, unrelated to the agent.
- 53 focused assistant, plan, executor, autonomy, Gemini, and grounding tests
  passed.
- The passing suite is useful but does not yet cover several critical autonomy,
  notification, Gemini-function-call, and concurrency paths listed below.

## Current Strengths To Preserve

- [x] Financial snapshots and most calculations are deterministic application
  logic rather than LLM-generated values.
- [x] Gemini has no direct database write/executor access.
- [x] Mutations use a plan, explicit confirmation, allowlisted executor, and
  verification step.
- [x] Capability execution has circuit-breaker, retry, timeout, serial, and
  audit mechanisms.
- [x] Transaction context is bounded and redacts merchant, account, category,
  note, and identifiers in the cloud digest.
- [x] Durable autonomy events are sanitized before persistence.
- [x] Personal-memory persistence has an explicit approval model.

## Architecture Gaps

The app has robust pieces of an agent, but it does not yet have one coherent
autonomy loop or forward-looking intelligence:

1. **Fragmented Proactive Insights**:
   Budget warnings are appended directly to chat history, activity warnings only
   change launcher state, and scheduled tasks can resolve into plans that cannot
   be executed safely in the background.
2. **Backward-Looking vs. Forward-Looking Predictive Analysis**:
   The current analysis engine computes historical frequency, past trends, and
   previous period comparisons, but lacks forward-looking projections: runway
   calculation until payday, burn-rate trajectory, and safe daily spend limits.
3. **Rigid Single-Turn Conversational Interaction**:
   When user input is partial (e.g. "catat makan siang", "transfer ke tabungan",
   "mau nabung buat liburan"), the assistant either errors or attempts single-shot
   guessing instead of engaging in structured, single-slot conversational clarification.
4. **Missing Closed-Loop Before/After State-Delta Verification**:
   Capability execution records boolean success/failure, but does not calculate and
   report the exact state delta (e.g., `Kas: Rp 1.500.000 -> Rp 1.450.000`,
   `Pos Makan: Tersisa Rp 200.000 -> Rp 150.000`), reducing transparency and trust.
5. **Siloed Multimodal and Mutation Capture Pipeline**:
   Receipt scanning and potential bank notification parsing exist in separate tests
   or gateways, disconnected from the Agent Inbox and proposal lifecycle.
6. **Calendar Month Bias vs. Real-World Payday Cadence**:
   Evaluation tasks assume a 1st-to-end-of-month cadence, causing misaligned insights
   for users whose real cashflow cycle is anchored to the 25th or a weekly rhythm.

The desired end state is one durable `Agent Insight / Proposal` lifecycle:

```text
detector -> evidence -> ranked candidate -> persisted insight/proposal
         -> in-app inbox + optional Android notification
         -> open / dismiss / snooze / review action
         -> draft or confirmed execution -> verified outcome
```

LLM-generated wording is optional and must be attached to the deterministic
evidence that justified the insight. The evidence and deterministic summary are
the source of truth.

## Delivery Checklist

### P0 - Fix Correctness And Safety First

- [x] Remove the duplicate `FfmAssistantChatHistoryRepository` GetIt
  registration in `lib/core/di/injection.dart`.
  Acceptance: `configureDependencies()` can run once in a clean process without
  duplicate-registration failure; add a DI startup test.

- [x] Define and enforce a background-task capability policy.
  Current issue: `ffm_assistant_agent_task_plan_resolver.dart` creates a
  one-step plan, while mutation plans require confirmation and a later
  verification step. The task host does not confirm plans.
  Acceptance: background tasks are restricted to `readOnly` and safe `prepare`
  work, or mutation-capable tasks always produce a persisted proposal awaiting
  explicit user approval. No task can silently mutate financial state.

- [x] Carry actual Gemini read-capability output into response grounding.
  Current issue: after `read_data`, the second Gemini response may be checked
  against rebuilt facts rather than the exact capability evidence it consumed.
  Acceptance: the cloud-turn result includes immutable capability evidence and
  ID; the interpreter validates output against it; a test rejects a claim that
  is absent from returned tool evidence.

- [x] Define an explicit multi-function-call policy for Gemini.
  Current issue: only the first returned function call is used by
  `ffm_gemini_cloud_orchestrator.dart`.
  Acceptance: either process a bounded, allowlisted sequence deterministically
  or reject multiple calls with an honest retry response. Never silently ignore
  a tool call.

- [x] Align cloud read capability allowlist with the documented privacy
  contract.
  Acceptance: one named policy is used by instruction generation, function-call
  validation, read service, tests, and user-visible privacy explanation.

### P1 - Establish A Durable Agent Insight Lifecycle

- [x] Create a domain model for `FfmAssistantInsight` or equivalent.
  Required fields: stable ID, household ID, type, severity, priority,
  confidence, deterministic evidence JSON/version, user-facing summary,
  optional Gemini explanation, suggested action/draft reference, source event,
  created/expiry time, dedupe key, cooldown key, status, and delivery status.
  Acceptance: insights survive process restart and are queryable without calling
  Gemini.

- [x] Create durable storage/repository and migration for insights.
  Status values: `new`, `seen`, `dismissed`, `snoozed`, `acted`, `expired`,
  `failedDelivery`.
  Acceptance: duplicate detector runs cannot create duplicate active insights;
  state transitions are auditable and household-scoped.

- [x] Build one `AutonomousEvaluationCoordinator` under the existing assistant
  architecture rather than adding a parallel agent framework.
  Responsibilities: claim event, obtain bounded sensor data, run deterministic
  detectors, deduplicate, score, persist insight/proposal, request optional
  explanation, and request delivery.
  Acceptance: every background event has one durable terminal outcome:
  completed, deferred, ignored due to cooldown, or failed with retry metadata.

- [x] Implement advanced deterministic detectors before LLM copywriting.
  Detector specifications:
  1. **Predictive Runway & Payday Burn-Rate Detector**:
     Formula: `DaysToPayday = (PaydayDate - Today).inDays`,
     `SafeDailySpend = (LiquidCash - UpcomingFixedBills) / DaysToPayday`.
     Trigger warning when `CurrentAverageDailyBurn > SafeDailySpend * 1.25`.
     Output: estimated cashout date, safe daily spend limit, and required reduction.
  2. **Intelligent Envelope / Budget Rebalancing Detector**:
     Compare category burn rates. If Category A is in deficit (>90% spent before 75%
     of period elapsed) and Category B has excess surplus (>40% unspent), calculate
     exact zero-sum transfer amount: `RebalanceAmount = min(DeficitNeeded, SurplusAvailable * 0.5)`.
     Propose 1-tap rebalancing plan without increasing overall monthly budget.
  3. **Duplicate Transaction & Anomaly Spike Detector**:
     Sliding 15-minute duplicate check: identical amount and merchant/account.
     Statistical spike check: transaction amount > `Q3 + 1.5 * IQR` (or > 3x median)
     against the specific category's 90-day baseline.
  4. **Silent Leakage & Micro-Expense ("Latte Factor") Detector**:
     Aggregate transactions under Rp 30.000 across a 14-day window. If cumulative
     micro-expenses exceed 15% of discretionary income, generate an awareness insight
     itemizing frequency and cumulative monthly impact.
  5. **Debt Service Ratio & Cicilan Commitment Monitor**:
     Evaluate total monthly installment obligations (cicilan, paylater, loans) against
     net income: `DSR = TotalMonthlyDebt / MonthlyNetIncome`. Alert if DSR exceeds
     safe thresholds (>30% caution, >40% critical), with snowball/avalanche payoff simulations.
  6. **Goal Progress Risk Detector**:
     Evaluate active goal deadlines against current savings velocity. If monthly contribution
     rate is insufficient to meet target date, compute the required monthly delta:
     `RequiredDelta = (TargetAmount - CurrentAmount) / MonthsRemaining - CurrentMonthlyContribution`.
  Acceptance: each detector emits structured evidence, confidence, and a
  user-safe fallback statement without Gemini.

- [x] Add a deterministic priority/ranking policy.
  Rank by severity, estimated financial impact, urgency, confidence, user goal
  relevance, cooldown, recent dismissals, and daily notification budget.
  Acceptance: at most one interruptive notification is selected per evaluation
  unless the user has opted into a higher frequency; lower priority insights
  remain in the inbox.

- [x] Add feedback handling for `helpful`, `not helpful`, `dismiss`, and
  `snooze`.
  Acceptance: feedback adjusts future delivery preference only after a bounded,
  explainable rule; it does not silently store sensitive inferred personal data.

### P1 - Add Agent Inbox And Notification Delivery

- [x] Add an in-app **Agent Inbox / Laporan Asisten** page.
  Decision: yes, this page should be added. It is the durable source of truth
  for autonomous work, whereas the Android notification is only a delivery
  surface.
  Acceptance: user can see unread insights, active proposals awaiting review,
  history, evidence summary, actions, and status without needing to search chat.

- [x] Make each report inspectable but concise.
  Report view must show: what changed, deterministic numbers/period used, why it
  matters, confidence/source label, proposed next action, and timestamp.
  Do not expose hidden model chain-of-thought. Offer "lihat data pendukung" with
  safe deterministic aggregates or deep links to the relevant FFM page.

- [ ] Add Android local notification delivery through the existing
  `flutter_local_notifications` dependency and reminder notification service.
  Use channels such as `agent_urgent`, `agent_action_needed`, and `agent_digest`.
  Acceptance: notification payload contains only insight ID/type, tap deep-links
  to the inbox detail, and no sensitive financial amount is shown on the lock
  screen unless the user enables it.

- [ ] Request Android notification permission contextually.
  Acceptance: explain the value after the user enables proactive insights or
  when the first useful report is ready. Gracefully retain the inbox when
  permission is denied.

- [ ] Add notification controls.
  Controls: global enablement, urgency categories, quiet hours, daily limit,
  privacy-on-lock-screen, detector categories, and per-insight snooze/dismiss.
  Acceptance: policy is enforced before local notification scheduling/delivery,
  including within Workmanager background execution.

- [x] Keep the inbox local-first and sync only where current Supabase contracts
  require it.
  Acceptance: an offline user can receive and review locally generated insights;
  failed sync is explicit and does not duplicate delivery or lose local state.

### P2 - Advanced Conversational Intelligence & Multi-Turn Reasoning

- [ ] Implement a deterministic Conversational Slot-Filling Engine.
  Current issue: partial requests (e.g. "Catat bensin kemarin", "Transfer ke tabungan",
  "Nabung 500 ribu") either fail validation or trigger hallucinations.
  Architecture: create a stateful, transient `FfmSlotFillingSession` containing required
  slots per intent (e.g., for `record_transaction`: amount, category, account, date).
  When slots are missing, the assistant prompts specifically for the missing slot in
  natural Indonesian: "Berapa nominal bensin kemarin dan dibayar pakai apa?"
  Acceptance: missing attributes are gathered across turns without losing original intent;
  session expires cleanly after timeout or explicit cancellation.

- [ ] Cross-Turn Coreference & Entity Chaining.
  Enable referential reasoning across turns (e.g. Turn 1: "Berapa sisa pos Makan?",
  Turn 2: "Kalau kopi tadi sudah masuk situ?", Turn 3: "Iya, kurangi 35 ribu").
  Maintain a bounded working context of the last 3 discussed financial entities
  (amounts, categories, accounts) without exposing full transaction tables to the model.
  Acceptance: assistant resolves pronouns and relative references ("itu", "tadi", "sisanya")
  reliably in Indonesian.

- [ ] Contextual "Next Best Financial Action" (NBFA) Follow-Up Generator.
  Enrich `ffm_assistant_follow_up_suggestions.dart` with deterministic follow-up chips
  attached to every turn:
  - After balance inquiry: `[Lihat Pengeluaran Terbesar]`, `[Simulasi Tabungan Gajian]`.
  - After transaction recording: `[Cek Sisa Pos Terkait]`, `[Unggah Foto Struk]`.
  - After budget alert: `[Geser Saldo Pos Lain]`, `[Koreksi Transaksi Terakhir]`.
  Acceptance: follow-up chips are deterministic, 1-tap actionable, and context-relevant.

- [ ] Calibrate Indonesian Vernacular & Cultural Financial Tone.
  Ground natural Indonesian financial terminology: "boncos", "nombok", "tanggal tua",
  "uang dingin", "dana darurat", "gajian", "THR".
  Tone adapts dynamically: encouraging during savings milestones, calm and actionable
  during "tanggal tua" austerity (providing daily survival spend limits rather than shaming).

### P2 - Multimodal & Real-World Ingestion Intelligence

- [ ] Receipt / Nota OCR Parsing with Deterministic Math Reconciliation.
  Integrate visual intake (using local Qwen2-VL or bounded Gemini Vision) for shopping
  receipts and paper bills.
  Crucial safety guard: before creating a draft proposal, the engine must deterministically
  verify:
  `sum(lineItems.amount) + taxAmount + serviceCharge == totalAmount`.
  If reconciled: generates an itemized transaction draft with high confidence.
  If discrepancy detected: flags the math discrepancy explicitly and presents a prefilled
  review dialog for user correction.
  Acceptance: receipt photos convert into confirmed transactions in under 2 taps with zero math errors.

- [ ] Indonesian Bank & E-Wallet Mutation Notification Capture.
  Implement a local Android notification listener service to capture financial transaction
  alerts from Indonesian banks and e-wallets (BCA, Mandiri, BRI, BNI, GoPay, OVO, ShopeePay, Dana).
  Parsing pipeline:
  1. Deterministic regex extracts amount, transaction type (debit/credit), merchant, and source.
  2. Creates a pending draft transaction in the Agent Inbox (tagged as `unconfirmed_alert`).
  3. Never mutates database automatically; user confirms with 1-tap in the inbox.
  Acceptance: incoming transaction push notifications appear as ready-to-approve drafts
  in the Agent Inbox within 2 seconds.

### P2 - Hyper-Personalization & Financial Persona Rhythms

- [ ] Payday Cycle Auto-Discovery & Dynamic Rhythm Anchoring.
  Automatically detect recurring income spikes (e.g. 25th of month or 1st of month)
  and prompt user to anchor budget periods, burn-rate calculations, and proactive
  summaries to their real cashflow cadence rather than rigid calendar months.
  Acceptance: all runway calculations and budget alerts align with the user's real payday cycle.

- [ ] Vendor-to-Category Rule Learning from User Edits.
  When the user manually edits a transaction's category (e.g., reclassifies "Indomaret"
  from "Makanan" to "Kebutuhan Rumah"), generate a memory learning candidate:
  `"Ingat bahwa belanja di Indomaret biasanya masuk Kebutuhan Rumah?"`.
  Upon approval, persist as an active rule for future autofill.
  Acceptance: user corrections continuously improve future categorization accuracy with explicit consent.

- [ ] Indonesian Seasonal & Cultural Financial Models.
  Implement dedicated deterministic seasonal modules:
  - *THR (Tunjangan Hari Raya) Planner*: Automatic 4-bucket allocation formula
    (Mudik/Transport 25%, Zakat/Infaq 10%, Angpao Keluarga 35%, Tabungan Pasca-Lebaran 30%).
  - *Arisan Cadence Tracker*: Managing group draw dates and incoming/outgoing cashflow obligations.
  - *Qurban Savings Cadence*: Monthly savings projection linked to Hijri calendar countdown
    via `hijri_calendar_service.dart`.
  Acceptance: seasonal events trigger tailored financial preparation plans well in advance.

### P2 - Improve Orchestration And Grounded Reasoning

- [ ] Introduce a typed orchestration result that carries intent, deterministic
  facts, analysis facts, tool evidence, provider metadata, confidence, and
  user-safe explanation separately.
  Acceptance: UI never has to parse model prose to determine truth, plan state,
  or source of a financial claim.

- [ ] Strengthen claim-level grounding.
  Validate financial values, dates, periods, category/account claims,
  comparisons, and recommendation premises against typed evidence. Reject or
  soften only unsupported clauses, not necessarily the whole answer.
  Acceptance: test cases cover fabricated small numbers, incorrect period,
  unsupported comparison, false save claim, and grounded mixed responses.

- [ ] Add an abstention/clarification policy.
  Acceptance: insufficient evidence yields a concise Indonesian clarification or
  an honest unavailability message, never a confident fabricated answer.

- [ ] Separate deterministic routing from language generation in the
  interpreter.
  Acceptance: a provider outage cannot change financial truth, action policy, or
  query results; only explanation quality may degrade.

- [ ] Add Closed-Loop Before/After State-Delta in Capability Execution.
  Before executing any mutation, capture pre-state; after execution, capture post-state.
  The execution result must emit a typed state delta:
  `accountDelta: {id: "bca", before: 2000000, after: 1950000, diff: -50000}`,
  `budgetDelta: {category: "makan", beforeRemaining: 300000, afterRemaining: 250000}`.
  The UI and assistant response state the verified impact explicitly:
  "Tercatat Rp 50.000 untuk Makan Siang. Sisa pagu pos Makan sekarang Rp 250.000."
  Acceptance: every mutation returns a verified before-and-after financial delta.

- [ ] Add Plan Dry-Run Impact Simulation.
  For high-impact mutations (budget changes, bulk transfers, loan payoff proposals),
  generate a dry-run preview before asking for confirmation:
  "Jika disetujui, saldo Kas akan menjadi Rp 1.200.000 dan pos Hiburan akan berkurang Rp 150.000."
  Acceptance: user sees exact mathematical consequences before giving confirmation.

- [ ] Enable Bounded Two-Way Tool Calling on Second Gemini Turn.
  Currently, after `read_data`, the second Gemini turn only returns plain text.
  Allow the second turn to return structured proposals (`create_draft`) or navigation (`navigate`)
  grounded in the fetched local data.
  Acceptance: Gemini can read data and propose a grounded action plan within a single user turn.

- [ ] Add operational metrics without sensitive content.
  Metrics: detector candidates, persisted insights, delivered/opened/dismissed/
  acted rates, grounding rejections, tool failures, retries, provider failure,
  and time-to-insight.
  Acceptance: metrics use IDs/types/counts only and do not log transaction
  details, prompts, access tokens, or personal memory text.

### P2 - Repair Memory Review Flow

- [ ] Surface pending memory candidates in the assistant and inbox/profile.
  Current issue: candidate extraction exists but the returned candidate is not
  visibly used by the chat flow.
  Acceptance: user can approve, edit, reject, and delete every candidate; no
  pending candidate becomes active memory automatically.

- [ ] Show the source and effect of approved memory.
  Acceptance: the user can tell which preference changed agent prioritization or
  wording and can revoke it immediately.

### P3 - Reliability, Tests, And Release Gates

- [ ] Add Gemini function-call tests.
  Cover navigation, clarification, draft, read-data, malformed arguments,
  unknown capability, second-call failure, executor failure, and multiple calls.

- [ ] Add end-to-end grounding tests after `read_data`.
  Acceptance: the test captures the actual tool evidence, verifies valid claims,
  and rejects invalid numeric/date/period claims in the second model response.

- [ ] Add autonomy worker durability tests.
  Cover concurrent claims, duplicate events, partial persistence failure,
  handler crash, retry exhaustion, policy block, cooldown, and batch limit.

- [ ] Add Workmanager scheduler/dispatcher tests or an injectable platform
  boundary with integration coverage.
  Acceptance: task registration, dispatcher task filtering, database lifecycle,
  retry result, and notification delivery request are verifiable.

- [ ] Add executor resilience tests.
  Cover read retry success/exhaustion, timeout, handler throw, mutation
  non-retry, listener/audit failure, policy budget rejection, and concurrent
  `execute()` calls.

- [ ] Add table-driven planner tests for every draft type.
  Acceptance: all draft kinds are checked for prerequisites, mutation mapping,
  confirmation, verification, and idempotency behavior.

- [ ] Add advanced financial detector tests.
  Cover predictive runway calculation, envelope rebalancing math, duplicate transaction
  sliding-window detection, statistical anomaly spike thresholding, and DSR calculations.

- [ ] Add conversational slot-filling and coreference tests.
  Cover partial input clarification, slot cancellation, session timeout, and Indonesian
  pronoun/relative reference resolution across 3 consecutive turns.

- [ ] Add receipt OCR math reconciliation tests.
  Verify that itemized transactions match total amounts, and mismatching totals trigger
  review flags rather than erroneous draft creation.

- [ ] Add before/after state-delta verification tests.
  Ensure every capability adapter returns verified pre-mutation and post-mutation deltas.

- [ ] Add inbox and full assistant flow widget/integration tests.
  Cover insight rendering, read/unread state, deep link, dismiss/snooze,
  draft review, confirmation, execution, verification, and honest provider
  failure state.

- [ ] Run release validation after each release-relevant phase.
  Commands:

  ```bash
  flutter analyze lib test
  flutter test <relevant test files>
  flutter build apk --target-platform android-arm64 --release
  ```

  Acceptance: release APK is ARM64-only and notification/deep-link behavior is
  manually verified on an Android device or emulator.

## Recommended Implementation Order

1. **Stage 1: P0 Safety & Correctness Gates**:
   - Fix duplicate DI registration in `injection.dart`.
   - Enforce background-task capability policy (no silent mutations).
   - Carry actual Gemini read-capability evidence into response grounding.
   - Define explicit multi-function-call policy and cloud read privacy contracts.
2. **Stage 2: Core Insight Lifecycle & Storage**:
   - Implement `FfmAssistantInsight` domain model, SQLite repository, status lifecycle,
     and deduplication keys.
   - Implement `AutonomousEvaluationCoordinator` claiming events and persisting insights.
3. **Stage 3: Advanced Deterministic Detectors**:
   - Implement Predictive Runway & Burn-Rate Detector.
   - Implement Intelligent Envelope Rebalancing Detector.
   - Implement Duplicate & Anomaly Spike Detector.
   - Implement Silent Leakage & Micro-Expense Detector.
   - Implement Debt Service Ratio & Cicilan Commitment Monitor.
4. **Stage 4: Agent Inbox & Notification Delivery**:
   - Build in-app Agent Inbox page (`Laporan Asisten`) with evidence inspection and action buttons.
   - Wire Android local notification delivery via `flutter_local_notifications`.
   - Implement notification preference controls (quiet hours, lock-screen privacy, daily limits).
5. **Stage 5: Conversational Multi-Turn Intelligence**:
   - Implement stateful conversational slot-filling engine for partial inputs.
   - Implement cross-turn coreference and entity chaining.
   - Add contextual "Next Best Financial Action" follow-up suggestion chips.
   - Calibrate Indonesian vernacular tone ("boncos", "tanggal tua", empathetic guidance).
6. **Stage 6: Multimodal & Real-World Ingestion**:
   - Build receipt/nota OCR pipeline with deterministic math reconciliation (`sum == total`).
   - Implement Android bank & e-wallet mutation notification parser into Agent Inbox drafts.
7. **Stage 7: Hyper-Personalization & Closed-Loop Verification**:
   - Implement payday cycle auto-discovery and dynamic cadence anchoring.
   - Implement vendor-to-category memory learning candidates from user edits.
   - Implement closed-loop before/after state-delta calculation in capability executor.
   - Implement plan dry-run impact simulation.
   - Connect Indonesian seasonal models (THR, Arisan, Qurban).
8. **Stage 8: Comprehensive Testing & ARM64 Release Gate**:
   - Complete P3 test suites (runway tests, slot-filling tests, math reconciliation tests, executor tests).
   - Run `flutter analyze lib test`.
   - Build and verify release APK: `flutter build apk --target-platform android-arm64 --release`.

## Notification And LLM Report Decision

Create the page, but do not make it a free-form "LLM report feed." A report
must begin as a structured insight backed by deterministic evidence. Gemini may
generate a short Indonesian explanation and follow-up question, but the detail
screen must keep the source, relevant period, values, confidence, and action
separate from generated prose.

This prevents hallucinated reports, lets the app work offline, supports audits,
and gives users a reliable place to review missed notifications. It also lets
the notification contain only safe text and an insight ID for deep linking.

## External References Checked

- Flutter local notifications package documentation:
  <https://pub.dev/packages/flutter_local_notifications>
  The project already depends on version `^22.3.0`. The package supports local
  display, channels, actions, deep-link handling, scheduling, grouping, and
  Android notification permission handling. It also documents Android OEM
  background-delivery limitations and Android 13+ permission requirements.

- Firebase Cloud Messaging Flutter documentation:
  <https://firebase.google.com/docs/cloud-messaging/flutter/client>
  FCM is appropriate only if FFM later needs server-originated cross-device
  delivery when the app cannot run locally. It requires Firebase setup, token
  lifecycle, permission handling, and secure server-side sending. Do not add it
  for the first inbox/local-proactive phase because the existing local
  notification and Workmanager stack is sufficient and lower complexity.

- Gemini function-calling documentation:
  Tool use must follow strict JSON schemas. Function call arguments must be validated
  against allowlisted parameter ranges. Grounding requires passing tool execution results
  back in the multi-turn context before generating user-facing claims.

## Non-Negotiable Guardrails

- No Gemini or LLM direct writes to app/Supabase financial state.
- No financial number, period, trend, runway projection, or "saved" claim without
  deterministic evidence and validation.
- All mathematical calculations (runway burn rates, budget rebalancing amounts,
  receipt line-item totals, state deltas) must be computed in deterministic Dart code;
  Gemini is strictly restricted to contextual interpretation, explanation, and empathetic framing.
- No sensitive transaction detail in notification payloads or lock-screen text
  by default.
- No silently persisted personal memory or inference without explicit user review.
- No automatic mutation from a background event or notification listener without
  an approved user confirmation and the existing execution/verification protections.
- No replacement framework is currently justified. The existing architecture is
  capable of this roadmap; complete, deepen, and unify it rather than creating a parallel
  agent framework.
