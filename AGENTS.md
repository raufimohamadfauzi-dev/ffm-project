# AGENTS.md

# FFM Project — Agent Operating Instructions

## 1. Purpose

FFM (Family Finance Manager) is a Flutter Android application whose primary product direction is an **AI financial assistant/agent**.

The assistant is the highest-priority capability of the product. Other application features should primarily support the assistant, provide trustworthy financial data, or execute actions initiated through the assistant.

The target product experience is:

> A financial application whose central intelligence layer is an AI assistant/agent, backed by application data, Supabase services, and Gemini reasoning via orchestrator.

Do not treat FFM as a traditional finance application with a chatbot attached to it.

---

## 2. Priority Order

When deciding what to build, fix, refactor, test, or optimize, use this order:

1. AI assistant / agent
2. Agent orchestration, reasoning, planning, tools, and capabilities
3. Gemini API and orchestrator routing
4. Assistant context, memory, personalization, and follow-up behavior
5. Action validation, confirmation, execution, verification, and recovery
6. Supabase/backend integration required by the assistant
7. Assistant UI and conversation UX
8. Financial features required by the assistant
9. Core non-assistant application features
10. Non-essential UI polish

When priorities conflict, prefer the higher-priority item.

Do not spend significant effort on unrelated UI or secondary features while the assistant has known functional, reasoning, reliability, data, or integration problems.

---

## 3. Core Architecture Principle

FFM uses a **hybrid AI architecture**.

Do not enforce an offline-first or cloud-only ideology.

The assistant may use (via orchestrator):

- deterministic application logic,
- local application/database context,
- Supabase services and persistence,
- Gemini Cloud for reasoning (bounded read capabilities `read.summary`/`read.transactions`),
- existing assistant tools and capability executors.

Choose the correct layer for the task instead of forcing every task through one model or one provider.

The application remains authoritative for financial state and business rules.

---

## 4. AI Assistant Is P0

Treat the assistant as the primary product surface.

The assistant should be capable of:

- understanding natural Indonesian language,
- maintaining conversational context,
- understanding financial context,
- answering questions about the user's finances,
- performing deterministic financial analysis,
- generating useful explanations and summaries,
- asking useful follow-up questions,
- proposing actions,
- creating structured action plans,
- requesting confirmation when required,
- executing approved capabilities,
- verifying execution results,
- handling errors and partial failures,
- using approved personal memory,
- providing proactive read-only insights when appropriate.

The assistant should feel integrated with FFM, not like a generic chat screen.

---

## 5. Existing Assistant Architecture

Prefer the existing assistant architecture and abstractions.

Before creating new infrastructure, inspect and reuse the existing implementation in areas such as:

- `lib/features/assistant/`
- assistant domain models and services
- assistant data sources and repositories
- assistant presentation/UI
- `ffm_agent_harness`
- assistant action plans
- assistant action planner
- assistant action tools
- assistant capability registry/executor
- Gemini Cloud orchestrator (`FfmGeminiCloudOrchestrator`)
- reasoning context
- memory services
- learning candidate services
- proactive assistant services
- proposal/draft validation
- assistant query tools
- assistant integration and test harnesses
- `FamilyProfilePage` (`lib/features/settings/presentation/pages/family_profile_page.dart`) — family profile and assistant identity, intentionally **separate** from Master Data (the combined page replaced the old header card in `master_data_page.dart`)
- assistant destination catalog and page-context mapping (`familyProfile` destination, alias `profil keluarga`/`data keluarga`)

Do not create a parallel orchestrator, planner, capability system, or AI framework unless there is a clear architectural reason and the existing abstraction cannot support the requirement. See section 26 for the standing rule when a clearly better tool/framework exists.

---

## 6. Agent Execution Boundary

The AI model must not directly mutate application state.

The model may generate:

- intent,
- structured output,
- query parameters,
- proposal,
- draft,
- action plan,
- reasoning result,
- user-facing explanation.

The application must remain responsible for:

1. validation,
2. permissions and authorization,
3. business rules,
4. confirmation policy,
5. capability execution,
6. persistence,
7. post-execution verification.

For mutations, prefer this flow:

```text
User Request
    ↓
Assistant Understanding
    ↓
Reasoning / Planning
    ↓
Structured Action Plan / Proposal
    ↓
Validation
    ↓
Confirmation when required
    ↓
Capability Executor
    ↓
Application / Database Mutation
    ↓
Verification
    ↓
Assistant Result
```

Never bypass the validation/confirmation/executor boundary merely to make the assistant appear faster.

Respect existing idempotency, duplicate-execution protection, authorization, and partial-failure handling.

---

## 7. Deterministic Financial Logic

Financial values must be authoritative from application code and data, not from model imagination.

Use deterministic application logic for:

- arithmetic,
- totals,
- balances,
- budgets,
- transaction aggregation,
- percentage calculations,
- financial projections where formulas are defined,
- validation rules,
- business constraints.

The AI should interpret, explain, summarize, and reason over authoritative values.

If deterministic computation is available, do not trust an LLM-generated number as the source of truth.

---

## 8. Gemini API

Gemini is a supported AI provider and may be used for advanced cloud reasoning and generation.

Use the existing Gemini integration/abstractions before creating a new client or provider layer.

Good Gemini use cases include:

- natural-language understanding,
- complex reasoning,
- conversational generation,
- explanation,
- summarization,
- planning assistance,
- tasks that benefit from stronger cloud reasoning,
- multimodal capabilities when already supported by the project.

Do not:

- hard-code API keys,
- expose secrets in source control,
- duplicate Gemini client implementations,
- bypass existing assistant context construction,
- bypass response validation,
- allow Gemini to directly mutate application state.

All financial claims generated by Gemini must be grounded in authoritative application data.

---

## 9. Supabase

Supabase is a first-class backend dependency where the existing application architecture requires it.

Use Supabase for the responsibilities already assigned to the backend, including where applicable:

- authentication,
- cloud persistence,
- synchronization,
- backend services,
- shared user/application data,
- server-side capabilities.

Do not replace Supabase with a local-only implementation merely to satisfy an offline-first philosophy.

When modifying Supabase-related code:

- preserve existing data contracts,
- preserve authentication behavior,
- preserve authorization assumptions,
- preserve row-level security expectations,
- handle network failures explicitly,
- handle authentication failures explicitly,
- handle timeouts explicitly,
- avoid unnecessary network calls,
- do not leak privileged credentials into the Android application.

The application should degrade gracefully when network services are unavailable, but cloud functionality is part of the intended architecture.

---

## 10. Orchestrator + Gemini Cloud

The primary reasoning path is **orkestrator → deterministic logic → Gemini Cloud (bounded)**.

The orchestrator assembles bounded context (conversation, financial snapshot, page context, approved memory) and decides routing. Gemini Cloud is used via `FfmGeminiCloudOrchestrator` with allowlisted read capabilities `read.summary`/`read.transactions` (max 8 items, no merchant/category/account detail). Supabase is used for backend persistence where required. The application remains authoritative for financial truth.

Do not let the model fabricate financial numbers; all claims must be grounded in authoritative application data. Do not let the model directly mutate state — it may only propose a draft/action plan that passes validation/confirmation/executor.

Active-draft corrections follow the routing mode. In `geminiCloud` mode they are delegated to Gemini as `requestClass: draftReview` (Gemini is the primary conversational layer even for draft revision). In Agent mode they use the deterministic multi-turn draft revision (Module 2), grounded to the database, so "bukan 50rb tapi 75rb", account/category changes, and cancellation are handled instantly without a cloud round trip. Do not intercept active-draft corrections deterministically in Gemini Cloud mode; do not bypass Gemini draftReview when an active draft exists and the route is `geminiCloud`.

---

## 11. AI Provider Routing

Do not hard-wire business logic to one AI provider.

Prefer a routing architecture conceptually similar to:

```text
User Request
    ↓
Assistant Orchestrator
    ↓
Context Assembly
    ↓
Task / Capability Routing
    ├── Deterministic Application Logic
    ├── Gemini API
    └── Supabase-backed Data / Capability
    ↓
Structured Result / Action Plan
    ↓
Validation
    ↓
Confirmation when required
    ↓
Capability Executor
    ↓
Verification
    ↓
User Response
```

Provider-specific implementation details should stay behind appropriate assistant/domain/data abstractions instead of leaking throughout widgets and UI code.

---

## 12. Assistant Context

Assistant context must be relevant, bounded, and structured.

Use existing mechanisms for:

- conversation history,
- current page/screen context,
- financial snapshots,
- capability context,
- approved user context,
- memory,
- model/provider readiness,
- active filters,
- previous action results.

Do not dump the entire database or unnecessary application state into model prompts.

Only provide the context required for the current task.

Never expose:

- passwords,
- private API keys,
- access tokens,
- service-role credentials,
- unrelated secrets,
- unnecessary sensitive internal data.

---

## 13. Personal Memory

Personal assistant memory must remain explicit and user-controlled.

New personal facts should follow the existing memory/approval architecture.

Do not silently persist inferred personal information merely because a model inferred it.

Memory should remain:

- local or securely stored according to project architecture,
- reviewable,
- removable,
- bounded to useful assistant context.

---

## 14. Reasoning Transparency

The UI may expose safe execution metadata such as:

- assistant mode,
- model/provider used,
- readiness state,
- capability/tool used,
- execution status,
- action-plan status,
- elapsed time,
- high-level reason for a result.

Do not fabricate reasoning traces.

Do not expose hidden chain-of-thought.

Provide concise user-safe explanations instead.

---

## 15. Error Handling and Graceful Degradation

The assistant must distinguish between different failure classes, including:

- Gemini/provider unavailable,
- Supabase unavailable,
- authentication failure,
- network timeout,
- invalid model output,
- invalid or missing application data,
- validation failure,
- capability execution failure,
- partial execution failure,
- cancellation.

Do not fabricate an answer when authoritative data or required reasoning is unavailable.

Return useful, honest fallback behavior.

Do not silently switch to a less trustworthy path when doing so could change the meaning of a financial result or action.

---

## 16. Assistant UX

The assistant UI should prioritize:

- fast time-to-first-useful-response,
- natural Indonesian conversation,
- clear responses,
- concise answers with optional detail,
- useful follow-up suggestions,
- strong contextual awareness,
- action previews,
- explicit confirmation where required,
- clear execution state,
- understandable success/failure states,
- recovery after failure.

Avoid over-designing decorative chatbot UI while core assistant functionality is incomplete.

---

## 17. Testing Priority

When changing assistant behavior, prioritize testing in this order:

1. Agent harness
2. Orchestration/planner
3. Capability executor
4. Proposal/action validation
5. Assistant query/data adapters
6. Mutation integration
7. Gemini/provider routing
8. Memory/learning
9. Cancellation/concurrency
10. Assistant UI/integration

A change affecting assistant behavior should include relevant tests where practical.

Never delete or weaken tests merely to make the suite pass.

---

## 18. Build Target — Android ARM64 Release Only

The only release build target for this project is:

```bash
flutter build apk --target-platform android-arm64 --release
```

The release deliverable must target:

`arm64-v8a`

Do not create release deliverables for:

- iOS,
- web,
- Windows,
- macOS,
- Linux,
- Android x86,
- Android x86_64,
- multi-ABI Android release APKs,
- other APK architectures.

Do not broaden ABI support unless explicitly requested.

---

## 19. Build and Validation Workflow

For normal Dart/Flutter validation, use the project's existing test/lint strategy and prefer:

```bash
flutter analyze lib test
```

Run relevant assistant tests before completing assistant-related work. Before any commit, both `flutter analyze lib test` **and** the full suite (`flutter test`, currently ~1,104 tests, ~2–3 minutes) must pass. Use the default reporter for speed; if the final status is truncated, re-run with `--reporter expanded`. Do not use `--concurrency=1` for the full suite (several minutes slower) unless isolating a hang.

For release validation, the canonical command is:

```bash
flutter build apk --target-platform android-arm64 --release
```

Verify the output is an ARM64 Android APK and does not contain unintended release ABIs.

Do not claim real-device AI inference validation unless inference was actually tested on a physical Android device or appropriate emulator.

A successful Flutter build is not proof of successful Gemini calls or Supabase connectivity.

---

## 20. Android Release Scope

When the request is specifically for a release APK, optimize for:

- Android,
- ARM64,
- release mode,
- stable assistant behavior,
- native AI runtime compatibility,
- correct API/backend configuration,
- production-safe secret handling.

Do not spend release work on unrelated platform targets.

---

## 21. Security

Never commit or embed privileged secrets such as:

- Supabase service-role keys,
- production database admin credentials,
- private backend secrets,
- long-lived access tokens,
- private certificates/keys.

Treat Gemini credentials according to the project's existing security architecture.

Do not move secrets into source code simply to make a build succeed.

Do not mint unique IDs from a bare `DateTime.now().microsecondsSinceEpoch` — rapid same-microsecond inserts collide (observed with recurring transactions). Use `Uuid().v4()` or timestamp + counter/random suffix in every new ID generator.

---

## 22. Change Strategy

Before modifying code:

1. inspect the existing implementation,
2. identify the owning module and contract,
3. inspect relevant tests,
4. reuse existing abstractions,
5. make the smallest coherent change,
6. update/add relevant tests,
7. run analyzer/tests,
8. build the ARM64 release when the change is release-relevant.

Do not rewrite functioning architecture without evidence that a rewrite is necessary. The existence of a genuinely better, proven tool/framework is valid evidence (see section 26).

Prefer incremental changes that improve the current assistant system, but replace a component when a clearly better option exists (see section 26).

---

## 23. Scope Discipline

When a request is ambiguous, ask internally:

> Does this directly improve the AI assistant, its supporting data/capabilities, or the Android release needed to ship it?

If yes, prioritize it.

If no, only implement it when it is necessary for correctness, stability, security, or an essential user flow.

Avoid unrelated feature expansion.

---

## 24. Definition of Done

A change is complete when applicable conditions are met:

- the AI assistant is improved or preserved,
- existing architecture is respected,
- financial calculations remain deterministic and authoritative,
- Gemini/Supabase/local-AI responsibilities remain clear,
- mutation safety and confirmation boundaries are preserved,
- relevant tests pass,
- the full test suite (`flutter test`) is green,
- analyzer is clean,
- error states are handled honestly,
- secrets are not exposed,
- generated IDs are collision-safe (UUID or timestamp + counter/random),
- the Android ARM64 release remains buildable.

---

## 25. Final Product Direction

The highest-level rule for all agents working on this repository is:

> **Make FFM's AI assistant/agent the best part of the product.**
>
> Use deterministic application logic for financial truth, Supabase for backend capabilities and data, and Gemini for strong cloud reasoning via orchestrator.
>
> Ship only the Android ARM64 release target unless the user explicitly requests another platform.

---

## 26. Tool & Framework Replacement Policy (Mandatory When Better)

For the long-term health of the project, FFM must not remain locked to an inferior tool or framework merely because it already exists in the codebase.

When deciding between the current implementation and an alternative framework, tool, library, or service, apply this rule:

1. **Evaluate the alternative honestly.** If a proven framework/tool exists that is genuinely better than the current one for the task (better long-term maintainability, reliability, performance, cost, security, or fit for FFM's AI-assistant direction), it **must replace the current implementation**.
2. **"Better" is judged for the whole project life**, not just the current task. Prefer options that reduce long-term burden, dependency risk, and architectural debt, even if the swap takes extra effort now.
3. **Migration is expected, not avoided.** Do not keep a known-inferior component only because it is already wired up. Plan and execute a clean migration (data, tests, call sites) with the old implementation removed afterward.
4. **Evidence required for the upgrade decision**: compare both options against maintainability, reliability, performance, cost, security, team/AI-agent ergonomics, and fit with the AI-assistant direction. Record the decision and the reason.
5. **Still respect the guardrails.** Replacements must preserve: deterministic financial truth, the validation/confirmation/executor boundary, secrets handling, Android ARM64-only release build, and existing tests (migrated, not weakened).
6. **Do not replace for its own sake.** If no clearly better option exists, keep the current implementation. Do not churn architecture without a genuine improvement.

When this rule conflicts with an older "prefer/reuse existing" instruction, **this section wins** — the goal is the best long-term tool, not loyalty to whatever is already there.

Proactively flag, in your final report to the user, any component where you believe a clearly better alternative exists, even if swapping it is not part of the current request.

---

## 27. Git Operations & Interactive Commands (The Devin Workflow Standard)

When executing version control and interactive terminal operations:

1. **Do not prematurely kill interactive commands**: When executing operations like `git push`, `git fetch`, or other network/credential-sensitive commands, do NOT cancel or kill the task prematurely with a short timeout. Systems like Windows Git Credential Manager (GCM) often open an interactive GUI modal (e.g. *"Select an account"*) for user confirmation.
2. **Support the complete Git lifecycle**: The agent must confidently handle full Git workflows — inspecting status (`git status`), staging relevant files (`git add`), crafting clear conventional commits (`git commit`), and publishing to remote (`git push`) directly, instead of claiming it can only work on the local filesystem.
3. **Notify and allow time for user authorization**: When a command triggers an external modal or browser authentication, keep the command active, inform the user that an account selection or sign-in prompt is visible on their screen, and wait patiently for the user to complete the interaction.
4. **Clean commit hygiene**: Ensure all changes pass static analysis (`flutter analyze lib test`) and the full test suite (`flutter test`, currently ~1,104 tests) before committing, with informative conventional commit messages (`feat:`, `fix:`, `refactor:`, `test:`).

