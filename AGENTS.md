# AGENTS.md

# FFM Project — Agent Operating Instructions

## 1. Purpose

FFM (Family Finance Manager) is a Flutter Android application whose primary product direction is an **AI financial assistant/agent**.

The assistant is the highest-priority capability of the product. Other application features should primarily support the assistant, provide trustworthy financial data, or execute actions initiated through the assistant.

The target product experience is:

> A financial application whose central intelligence layer is an AI assistant/agent, backed by application data, Supabase services, Gemini reasoning, and optional local AI runtimes.

Do not treat FFM as a traditional finance application with a chatbot attached to it.

---

## 2. Priority Order

When deciding what to build, fix, refactor, test, or optimize, use this order:

1. AI assistant / agent
2. Agent orchestration, reasoning, planning, tools, and capabilities
3. Gemini API and local-model routing
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

The assistant may use:

- deterministic application logic,
- local application/database context,
- Supabase services and persistence,
- Gemini API for cloud AI reasoning,
- optional on-device SLM/native inference,
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
- local-model gateway/runtime integration
- reasoning context
- memory services
- learning candidate services
- proactive assistant services
- proposal/draft validation
- assistant query tools
- assistant integration and test harnesses

Do not create a parallel orchestrator, planner, capability system, or AI framework unless there is a clear architectural reason and the existing abstraction cannot support the requirement.

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

## 10. Optional On-Device AI

The project may contain local SLM/native inference capabilities.

Treat them as an **optional AI runtime**, not as a requirement that defines the whole application architecture.

Use local inference when it is appropriate for:

- supported on-device tasks,
- low-latency local processing,
- local multimodal workloads,
- privacy-sensitive flows intentionally designed for local inference,
- fallback or specialized workflows already supported by the architecture.

Do not remove Gemini/Supabase integration just to make a feature local.

Do not add a local model dependency when the task is better handled by deterministic code, Supabase, or Gemini.

Respect existing native runtime boundaries, model readiness checks, cancellation, and concurrency controls.

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
    ├── On-Device SLM
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
- local model unavailable,
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
8. Local-model routing
9. Memory/learning
10. Cancellation/concurrency
11. Assistant UI/integration

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

Run relevant assistant tests before completing assistant-related work.

For release validation, the canonical command is:

```bash
flutter build apk --target-platform android-arm64 --release
```

Verify the output is an ARM64 Android APK and does not contain unintended release ABIs.

Do not claim real-device AI inference validation unless inference was actually tested on a physical Android device or appropriate emulator.

A successful Flutter build is not proof of successful Gemini calls, Supabase connectivity, or on-device inference.

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

Do not rewrite functioning architecture without evidence that a rewrite is necessary.

Prefer incremental changes that improve the current assistant system.

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
- analyzer is clean,
- error states are handled honestly,
- secrets are not exposed,
- the Android ARM64 release remains buildable.

---

## 25. Final Product Direction

The highest-level rule for all agents working on this repository is:

> **Make FFM's AI assistant/agent the best part of the product.**
>
> Use deterministic application logic for financial truth, Supabase for backend capabilities and data, Gemini for strong cloud reasoning, and local AI only where it provides a meaningful advantage.
>
> Ship only the Android ARM64 release target unless the user explicitly requests another platform.
