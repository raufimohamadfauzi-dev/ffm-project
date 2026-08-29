# 7. UI Cleanup

## Status: SELESAI ✓

## Deskripsi
Menghapus komponen UI yang tidak perlu dan menyederhanakan chatbot.

## Yang Dihapus
- `FfmAssistantAmbiguousClarification` — klarifikasi ambigu
- `_buildQuickDraftPrompts()` — prompt draft cepat
- `_buildContextualSuggestions()` — saran kontekstual
- `_buildModelSelector()` — pemilih model
- `_safeClarificationChoices()` — pilihan klarifikasi
- `_fillPrompt()` — isi prompt
- `_saveMemoryNudge()` — simpan memory nudge
- `_pendingMemoryNudge` — memory nudge pending
- `_setRoutingMode()` — atur routing mode
- `_OriginBadge` — badge asal (digabung ke disclosure)
- Proactive suggestion card — saran proaktif
- `FfmMemoryNudgeCard` — kartu memory nudge
- "Tersimpan di Pengetahuan Asisten" — notice

## Lokasi Kode
- `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart`
- `lib/features/assistant/presentation/widgets/chat/ffm_assistant_message_card.dart`

## Import yang Dihapus
- `ffm_memory_nudge_card.dart`
- `ffm_assistant_chat_intro.dart`
