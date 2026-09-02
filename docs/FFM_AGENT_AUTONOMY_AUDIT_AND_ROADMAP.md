# FFM Agent Autonomy Audit And Delivery Roadmap

Status: active implementation checklist

Last audited: 2026-09-02

Scope: AI assistant, orchestrator, Gemini routing, autonomous/proactive work,
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
data, recognize meaningful conditions, prioritize them, and deliver the right
next step to the user.

Target loop:

```text
Durable event / scheduled evaluation
  -> bounded sensing
  -> deterministic financial analysis
  -> confidence and priority scoring
  -> insight, question, or action draft
  -> user approval when required
  -> capability execution
  -> verification and durable outcome
  -> approved-memory / feedback learning
```

Autonomy is permitted for read-only sensing, deterministic analysis, ranking,
and delivery of low-noise insights. It is not permission for an LLM to change
financial state. Gemini may interpret and explain facts or propose a draft; it
cannot bypass the application validation, confirmation, capability executor,
or verification boundary.

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
  `ffm_assistant_analysis_engine.dart` provide verified and analyzed facts.
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

### Memory and user control

- Personal-memory extraction, approval, learning candidates, decay, and
  approved-memory persistence were inspected under `lib/features/assistant`.
- The design correctly requires approval before saving personal facts, but the
  chat flow must visibly surface pending candidates for review.

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
autonomy loop. Proactive behavior is fragmented: budget warnings are appended
to chat history, activity warnings only change launcher state, and scheduled
tasks can resolve into plans that may be impossible to execute safely.

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

- [ ] Remove the duplicate `FfmAssistantChatHistoryRepository` GetIt
  registration in `lib/core/di/injection.dart`.
  Acceptance: `configureDependencies()` can run once in a clean process without
  duplicate-registration failure; add a DI startup test.

- [ ] Define and enforce a background-task capability policy.
  Current issue: `ffm_assistant_agent_task_plan_resolver.dart` creates a
  one-step plan, while mutation plans require confirmation and a later
  verification step. The task host does not confirm plans.
  Acceptance: background tasks are restricted to `readOnly` and safe `prepare`
  work, or mutation-capable tasks always produce a persisted proposal awaiting
  explicit user approval. No task can silently mutate financial state.

- [ ] Carry actual Gemini read-capability output into response grounding.
  Current issue: after `read_data`, the second Gemini response may be checked
  against rebuilt facts rather than the exact capability evidence it consumed.
  Acceptance: the cloud-turn result includes immutable capability evidence and
  ID; the interpreter validates output against it; a test rejects a claim that
  is absent from returned tool evidence.

- [ ] Define an explicit multi-function-call policy for Gemini.
  Current issue: only the first returned function call is used by
  `ffm_gemini_cloud_orchestrator.dart`.
  Acceptance: either process a bounded, allowlisted sequence deterministically
  or reject multiple calls with an honest retry response. Never silently ignore
  a tool call.

- [ ] Align cloud read capability allowlist with the documented privacy
  contract.
  Acceptance: one named policy is used by instruction generation, function-call
  validation, read service, tests, and user-visible privacy explanation.

### P1 - Establish A Durable Agent Insight Lifecycle

- [ ] Create a domain model for `FfmAssistantInsight` or equivalent.
  Required fields: stable ID, household ID, type, severity, priority,
  confidence, deterministic evidence JSON/version, user-facing summary,
  optional Gemini explanation, suggested action/draft reference, source event,
  created/expiry time, dedupe key, cooldown key, status, and delivery status.
  Acceptance: insights survive process restart and are queryable without calling
  Gemini.

- [ ] Create durable storage/repository and migration for insights.
  Status values: `new`, `seen`, `dismissed`, `snoozed`, `acted`, `expired`,
  `failedDelivery`.
  Acceptance: duplicate detector runs cannot create duplicate active insights;
  state transitions are auditable and household-scoped.

- [ ] Build one `AutonomousEvaluationCoordinator` under the existing assistant
  architecture rather than adding a parallel agent framework.
  Responsibilities: claim event, obtain bounded sensor data, run deterministic
  detectors, deduplicate, score, persist insight/proposal, request optional
  explanation, and request delivery.
  Acceptance: every background event has one durable terminal outcome:
  completed, deferred, ignored due to cooldown, or failed with retry metadata.

- [ ] Implement deterministic detectors before LLM copywriting.
  Initial detector set: budget burn-rate, budget overrun, upcoming bill/reminder,
  projected cash shortfall, unusual transaction compared with historical range,
  goal progress risk, and long-running activity.
  Acceptance: each detector emits structured evidence, confidence, and a
  user-safe fallback statement without Gemini.

- [ ] Add a deterministic priority/ranking policy.
  Rank by severity, estimated financial impact, urgency, confidence, user goal
  relevance, cooldown, recent dismissals, and daily notification budget.
  Acceptance: at most one interruptive notification is selected per evaluation
  unless the user has opted into a higher frequency; lower priority insights
  remain in the inbox.

- [ ] Add feedback handling for `helpful`, `not helpful`, `dismiss`, and
  `snooze`.
  Acceptance: feedback adjusts future delivery preference only after a bounded,
  explainable rule; it does not silently store sensitive inferred personal data.

### P1 - Add Agent Inbox And Notification Delivery

- [ ] Add an in-app **Agent Inbox / Laporan Asisten** page.
  Decision: yes, this page should be added. It is the durable source of truth
  for autonomous work, whereas the Android notification is only a delivery
  surface.
  Acceptance: user can see unread insights, active proposals awaiting review,
  history, evidence summary, actions, and status without needing to search chat.

- [ ] Make each report inspectable but concise.
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

- [ ] Keep the inbox local-first and sync only where current Supabase contracts
  require it.
  Acceptance: an offline user can receive and review locally generated insights;
  failed sync is explicit and does not duplicate delivery or lose local state.

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

1. Complete every P0 item and their regression tests.
2. Implement the insight model, repository, dedupe, status lifecycle, and
   deterministic detector contract without any new UI or Gemini generation.
3. Add the autonomous coordinator and convert existing budget/activity proactive
   logic to emit durable insights.
4. Build the Agent Inbox, report detail, and action routes.
5. Connect local Android notification delivery and preference controls.
6. Add optional Gemini explanation strictly after structured evidence is stored.
7. Expand detectors, ranking, feedback learning, and operational metrics.
8. Complete P3 test coverage and ARM64 release validation.

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

- Gemini function-calling documentation was requested but the official page was
  temporarily unavailable to the audit fetcher. The implementation plan above
  therefore relies on the repository's existing Gemini boundary and requires
  direct function-call integration tests before expanding tool scope.

## Non-Negotiable Guardrails

- No Gemini or LLM direct writes to app/Supabase financial state.
- No financial number, period, trend, or "saved" claim without deterministic
  evidence and validation.
- No sensitive transaction detail in notification payloads or lock-screen text
  by default.
- No silently persisted personal memory or inference.
- No automatic mutation from a background event without a previously approved,
  constrained policy and the existing execution/verification protections.
- No replacement framework is currently justified. The existing architecture is
  capable of this roadmap; complete and unify it rather than create a parallel
  agent framework.
