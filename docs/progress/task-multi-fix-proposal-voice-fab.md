# Task: Perbaikan Multi-Issue — Proposal, Draft Execution, Voice, FAB, Kalender

**Completed:** 2026-08-31

## Status
- [x] Sudah selesai

---

## Issue 1: Proposal Parser Gak Support `type: goal` dan `type: budget` ✅

### Masalah
Saat user bilang "buat target liburan 10 juta", Gemini return proposal JSON dengan `type: "goal"`, tapi parser di `ffm_assistant_proposal_json_service.dart` cuma support:
- `master_data`
- `transaction`
- `activity`
- `memory`

Goal dan budget masuk ke case `_` → error "Jenis proposal belum didukung".

### File yang Perlu Diubah
**`lib/features/assistant/data/ffm_assistant_proposal_json_service.dart`**

### Solusi
Tambah `type: 'goal'` dan `type: 'budget'` di switch statement:

```dart
// Line 159 (parse single)
return switch (proposal['type']?.toString()) {
  'master_data' => _parseMasterData(proposal, createdAt),
  'transaction' => _parseTransaction(proposal, createdAt),
  'activity' => _parseActivity(proposal, createdAt),
  'memory' => _parseMemory(proposal),
  'goal' => _parseGoal(proposal, createdAt),       // ← TAMBAH
  'budget' => _parseBudget(proposal, createdAt),   // ← TAMBAH
  _ => const FfmAssistantProposalParseResult.invalid(
    'Jenis proposal belum didukung...',
  ),
};

// Line 204 (parseMultiple) — tambah juga di sini
```

Tambah method baru `_parseGoal`:

```dart
static FfmAssistantProposalParseResult _parseGoal(
  Map<String, dynamic> proposal,
  DateTime createdAt,
) {
  final title = _boundedText(proposal['title'] ?? proposal['name'], 100);
  if (title == null) {
    return const FfmAssistantProposalParseResult.invalid(
      'Target keuangan wajib punya nama/judul.',
    );
  }
  final amount = _positiveInt(proposal['amount'] ?? proposal['targetAmount']);
  final note = _boundedText(proposal['note'], 200);
  final date = _dateOr(proposal['targetDate'], createdAt.add(const Duration(days: 30)));

  return FfmAssistantProposalParseResult.draft(FfmAssistantDraft(
    kind: FfmAssistantDraftKind.goal,
    createdAt: createdAt,
    title: title,
    amount: amount,
    note: note,
    date: date,
  ));
}
```

Tambah method baru `_parseBudget`:

```dart
static FfmAssistantProposalParseResult _parseBudget(
  Map<String, dynamic> proposal,
  DateTime createdAt,
) {
  final title = _boundedText(proposal['title'] ?? proposal['category'] ?? proposal['name'], 100);
  if (title == null) {
    return const FfmAssistantProposalParseResult.invalid(
      'Anggaran wajib punya nama/kategori.',
    );
  }
  final amount = _positiveInt(proposal['amount'] ?? proposal['limit'] ?? proposal['budgetAmount']);
  final note = _boundedText(proposal['note'], 200);

  return FfmAssistantProposalParseResult.draft(FfmAssistantDraft(
    kind: FfmAssistantDraftKind.budget,
    createdAt: createdAt,
    title: title,
    amount: amount,
    categoryName: title,
    note: note,
    date: createdAt,
  ));
}
```

### Update Gemini Orchestrator Instructions
**`lib/features/assistant/data/ffm_gemini_cloud_orchestrator.dart`**

Line 246, ubah:
```dart
// SEBELUM:
- KELUARKAN proposal JSON dengan formatVersion "ffm-assistant-proposal-v1" dan type transaction, master_data, activity, atau memory.

// SESUDAH:
- KELUARKAN proposal JSON dengan formatVersion "ffm-assistant-proposal-v1" dan type transaction, master_data, activity, goal, budget, atau memory.
```

Tambah instruksi goal/budget:
```dart
ATURAN TARGET KEUANGAN:
- Untuk membuat target baru, gunakan proposal JSON dengan type "goal", field: title, amount (angka tanpa Rp), targetDate (YYYY-MM-DD), note.
- Contoh: {"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"goal","title":"Liburan ke Jepang","amount":15000000,"targetDate":"2026-12-31","note":"Tabungan bulanan Rp 1.5jt"}}

ATURAN ANGGARAN:
- Untuk membuat anggaran baru, gunakan proposal JSON dengan type "budget", field: title/kategori, amount (limit), note.
- Contoh: {"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"budget","title":"Makanan","amount":500000,"note":"Budget bulanan makan"}}
```

---

## Issue 2: LLM Gak Bisa Eksekusi Draft / Buka Halaman ✅

### Masalah
Ketika user klik "Tinjau & konfirmasi" pada draft card, halaman form gak terbuka. Atau setelah Gemini return proposal, draft gak bisa dieksekusi.

### Kemungkinan Penyebab
1. **Missing review**: `intent.review` null → draft card gak muncul tombol "Buka & cek"
2. **`_confirmDraftInChat` bermasalah**: Dialog konfirmasi gak muncul atau review null
3. **`_handleIntent` early return**: Ada guard yang return sebelum navigate

### File yang Perlu Diperiksa
- `lib/features/assistant/presentation/widgets/ffm_assistant_sheet.dart` — `_handleIntent()` line 1451
- `lib/features/assistant/data/ffm_assistant_interpreter.dart` — `_intentForDraft()` method

### Solusi
Periksa flow `_intentForDraft` — pastikan `FfmAssistantDraftReview` selalu di-create untuk setiap draft:

```dart
// Cari method _intentForDraft di ffm_assistant_interpreter.dart
// Pastikan review di-generate:
FfmAssistantIntent _intentForDraft(String rawText, String normalized, FfmAssistantDraft draft) {
  final review = FfmAssistantDraftReview(draft: draft);  // ← Pastikan ini ada
  return FfmAssistantIntent(
    rawText: rawText,
    normalizedText: normalized,
    type: FfmAssistantIntentType.confirm,
    confidence: .85,
    draft: draft,
    review: review,  // ← Pastikan ini di-pass
    response: _draftResponse(draft),
  );
}
```

Kalau review sudah ada tapi form gak buka, periksa `_confirmDraftInChat` di sheet:
```dart
// Pastikan dialog konfirmasi return true dan navigasi jalan
// Cek _handleIntent line 1497-1503:
if (intent.draft != null && !directMutation) {
  final confirmed = await _confirmDraftInChat(intent.draft!);
  if (!confirmed) { return; }
}
// Pastikan shouldNavigate = true setelah confirmed
```

---

## Issue 3: Voice Aktivitas Kategori Bermasalah — Gak Bisa Mulai ✅

### Masalah
User bilang "buat aktivitas ke kebun" via VN, tapi gak bisa mulai karena kategori bermasalah.

### Root Cause
Di `_startConversation()` (activity_page.dart line 426), kategori hardcode:
```dart
final categories = ['Perjalanan', 'Belanja', 'Pekerjaan', 'Keluarga', 'Lainnya'];
```

Tapi kategori yang dipakai di `_SessionForm` (line 1234) diambil dari database via `_categoryRepository.readActive('local-household', type: 'activity')`.

Kalau user gak punya kategori "Perjalanan/Belanja/Pekerjaan/Keluarga" di database, voice conversation pilih kategori yang gak ada → gagal.

### File yang Perlu Diubah
**`lib/features/assistant/presentation/pages/activity_page.dart`**

### Solusi
Ubah `_startConversation` supaya ambil kategori dari database:

```dart
void _startConversation(String title) async {
  _voiceConversation = _VoiceConversation(
    title: title,
    category: 'Lainnya',
  );
  setState(() {
    _voiceText = title;
    _voiceStatus = 'Pilih kategori';
    _voiceError = null;
  });

  // Ambil kategori dari database
  final repo = getIt<CategoryRepository>();
  final cats = await repo.readActive('local-household', type: 'activity');
  final categories = cats.isEmpty
      ? ['Lainnya']
      : [...cats.map((c) => c.name), 'Lainnya'];

  if (!mounted) return;
  _speechService.speak(
    'Aktivitas $title. Pilih kategori: ${categories.join(", ")}. Atau bilang "lewati" untuk pakai kategori pertama.',
  );
}
```

Dan di `_handleConversationResponse`, pastikan kategori yang dipilih valid di database, atau fallback ke kategori pertama yang tersedia.

---

## Issue 4: FAB Aktivitas Masih Abu-Abu ✅

### Masalah
FAB (FloatingActionButton) di halaman aktivitas warnanya abu-abu, bukan mengikuti theme teal.

### File yang Perlu Diubah
**`lib/features/activity/presentation/pages/activity_page.dart`**

### Solusi
Tambah `backgroundColor` dan `foregroundColor` ke FAB:

```dart
// Line 812
floatingActionButton: FloatingActionButton.extended(
  heroTag: 'activity_add_fab',
  onPressed: _startSession,
  tooltip: 'Mulai sesi aktivitas',
  backgroundColor: Theme.of(context).colorScheme.primary,       // ← TAMBAH
  foregroundColor: Theme.of(context).colorScheme.onPrimary,     // ← TAMBAH
  icon: const Icon(Icons.add),
  label: const Text('Tambah'),
),
```

---

## Issue 5: Kalender Hijri (SUDAH SELESAI ✅)

### Masalah
LLM gak bisa akses kalender lokal Hijriah.

### Root Cause
Cek Hijri di `ffm_assistant_interpreter.dart` dilakukan SETELAH Gemini-first guard, jadi query Hijri dikirim ke Gemini (yang gak punya akses kalender lokal).

### Solusi (SUDAH DIPERBAIKI)
Pindahkan cek Hijri SEBELUM Gemini-first guard.

**File**: `lib/features/assistant/data/ffm_assistant_interpreter.dart`

```dart
// ✅ SUDAH DIPERBAIKI: Hijri check sebelum Gemini-first
if (_isHijriDateRequest(normalized)) { ... }
if (isGeminiConversationMode) { ... }
```

---

## Execution Order

```
1. Proposal Parser (goal + budget)     ← KRITIS, semua fitur terpengaruh
2. Gemini Orchestrator Instructions     ← Agar Gemini tau format goal/budget
3. Draft Execution Review Check         ← Pastikan review selalu ada
4. Voice Kategori dari Database         ← Agar voice conversation jalan
5. FAB Color Fix                       ← UI polish
6. Flutter Analyze + Commit
```

---

## File Changes Summary

| File | Issue | Changes |
|---|---|---|
| `ffm_assistant_proposal_json_service.dart` | #1 | +`_parseGoal`, +`_parseBudget`, tambah case di switch |
| `ffm_gemini_cloud_orchestrator.dart` | #1 | +instruksi goal/budget, update type list |
| `ffm_assistant_interpreter.dart` | #2 | Pastikan review di-generate untuk semua draft |
| `ffm_assistant_sheet.dart` | #2 | Debug flow `_handleIntent` → navigate |
| `activity_page.dart` | #3, #4 | Kategori dari DB, FAB color fix |
| `activity_voice.dart` | #3 | Validasi kategori terhadap DB |

---

## Testing Checklist

### Proposal
- [ ] "buat target liburan 10 juta" → draft goal muncul
- [ ] "buat anggaran makan 500rb" → draft budget muncul
- [ ] "catat pengeluaran makan 50rb" → draft expense tetap jalan
- [ ] Multi-proposal: "buat target A dan anggaran B" → 2 draft

### Draft Execution
- [ ] Klik "Tinjau & konfirmasi" → form terbuka
- [ ] Setelah confirm → data tersimpan
- [ ] Draft dari Gemini bisa dieksekusi

### Voice Activity
- [ ] "buat aktivitas ke kebun" → tanya kategori
- [ ] Kategori yang dipilih valid di database
- [ ] "lewati" → pakai kategori default
- [ ] Flow complete: judul → kategori → catatan → konfirmasi → simpan

### UI
- [ ] FAB Aktivitas warna teal (bukan abu-abu)
- [ ] Quick-action buttons muncul di card aktivitas

### Kalender
- [ ] "tanggal hijriah hari ini" → jawab lokal (bukan Gemini)
- [ ] "besok tanggal berapa hijriah" → jawab lokal
