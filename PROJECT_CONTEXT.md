# FFM Project Context

## Current Status

Family Finance Manager (FFM) is a Flutter Android application focused on an AI financial assistant for family finance workflows.

- Application version: `0.1.90+90`
- Package ID: `com.ffm_manager`
- Minimum Android version: API 26
- Release target: Android ARM64 (`arm64-v8a`)
- Primary AI path: deterministic local application logic plus bounded Gemini Cloud orchestration
- Financial source of truth: local SQLite database through Drift

## Assistant Architecture

The assistant may read bounded application context, calculate financial values deterministically, explain results through Gemini Cloud, propose drafts or action plans, and request confirmation. The model never mutates application state directly. Validation, confirmation, execution, persistence, and verification remain application responsibilities.

Supabase is optional and is used only for configured cloud services such as assistant memory. Cloud reasoning and fresh external data require network access; core financial workflows remain local.

The former local SLM/Qwen/llama.cpp feature has been removed from the active source, Android native build, tests, and release tree. Speech-to-text remains a separate device capability and must not be confused with the removed conversational SLM.

## Main Capabilities

- Transactions, accounts, budgets, goals, assets, liabilities, receivables, reminders, recurring transactions, and activity journaling.
- Deterministic financial analysis, smart budgeting, autonomous read-only insights, and structured action plans.
- Android NFC bridge, payment notification detection, Quick Settings tile, local notifications, and CalendarProvider integration.
- JSON backup/restore, PDF and Excel reporting, audit logging, Hijri calendar support, and optional Telegram delivery.

## Validation

Use the repository validation commands:

```bash
flutter analyze lib test
flutter test
flutter build apk --target-platform android-arm64 --release
```

Analyzer and focused regression tests must pass before publishing. Hardware-dependent NFC, notification background delivery, CalendarProvider, wearable synchronization, Gemini connectivity, and physical-device behavior require device-level validation and are not proven by static analysis alone.

Release signing requires a local, ignored `android/key.properties`. Never commit signing credentials, API keys, or service-role secrets.
