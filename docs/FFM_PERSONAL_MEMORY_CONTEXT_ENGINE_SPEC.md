# FFM Personal Memory & Context Engine

## Spesifikasi Implementasi --- Personalization v2

**Status:** Draft implementasi\
**Target:** `ffm-project` pada branch `main`\
**Scope:** 100% internal FFM / offline-first\
**Tujuan utama:** membuat setiap jawaban Assistant FFM semakin personal
karena sistem secara aktif memilih konteks pengguna yang relevan sebelum
jawaban dibuat.

------------------------------------------------------------------------

## 1. Ringkasan Eksekutif

FFM sudah memiliki fondasi personal memory dan controlled learning.
Repository saat ini sudah mempunyai:

-   `FfmAssistantMemoryRepository`
-   `FfmAssistantPersonalizationRepository`
-   `FfmAssistantUserModelService`
-   `FfmPersonalMemoryService`
-   learning repository/candidate service
-   knowledge base/knowledge pack
-   chat history repository
-   feedback context/repository
-   fuzzy matcher
-   typo normalizer
-   local model gateway
-   action planner/harness/capability executor

Dokumentasi FFM juga sudah menetapkan bahwa data pribadi tetap lokal,
fakta personal baru disimpan setelah persetujuan pengguna, dan model
tidak boleh langsung mengubah database. citeturn2view0turn2view1

Masalah yang ingin diselesaikan spesifikasi ini bukan kekurangan jumlah
memory. Masalahnya adalah **memory yang sudah ada belum menjadi satu
Context Engine yang secara konsisten memilih memory paling relevan untuk
setiap pertanyaan**.

Target akhir:

> Sebelum Assistant menjawab pertanyaan pengguna, FFM harus dapat
> menentukan konteks apa yang relevan dari percakapan saat ini, memory
> personal, tujuan aktif, pola penggunaan, riwayat percakapan, dan
> konteks halaman FFM; kemudian hanya konteks yang relevan tersebut yang
> diberikan ke reasoning/response layer.

Jangan membuat SLM menjadi tempat penyimpanan memory.\
Jangan memasukkan seluruh database ke prompt.\
Jangan mengganti sistem memory yang sudah ada secara membabi buta.

Bangun lapisan **Personal Context Engine** di atas fondasi yang sudah
ada.

------------------------------------------------------------------------

# 2. Kondisi Repository yang Harus Dijadikan Baseline

Implementasi harus dimulai dari kode terbaru di branch `main`, bukan
dari asumsi versi lama.

Repository memiliki struktur
`lib/features/assistant/{data,domain,presentation}` dan branch `main`
saat spesifikasi ini dibuat memiliki 23 commits. Assistant data layer
saat ini sudah memiliki file khusus untuk memory, personalization, user
model, personal memory, learning, chat history, feedback, knowledge,
local model, query tools, dan reminder. citeturn3view2turn3view0

Komponen yang paling relevan:

### Data layer

-   `lib/features/assistant/data/ffm_assistant_memory_repository.dart`
-   `lib/features/assistant/data/ffm_assistant_personalization_repository.dart`
-   `lib/features/assistant/data/ffm_assistant_user_model_service.dart`
-   `lib/features/assistant/data/ffm_personal_memory_service.dart`
-   `lib/features/assistant/data/ffm_assistant_learning_repository.dart`
-   `lib/features/assistant/data/ffm_assistant_learning_candidate_service.dart`
-   `lib/features/assistant/data/ffm_assistant_chat_history_repository.dart`
-   `lib/features/assistant/data/ffm_assistant_response_feedback_repository.dart`
-   `lib/features/assistant/data/ffm_assistant_knowledge_base.dart`
-   `lib/features/assistant/data/ffm_assistant_knowledge_pack_service.dart`
-   `lib/features/assistant/data/ffm_assistant_fuzzy_matcher.dart`
-   `lib/features/assistant/data/ffm_assistant_typo_normalizer.dart`

### Domain layer

-   `lib/features/assistant/domain/ffm_assistant_reasoning_context.dart`
-   `lib/features/assistant/domain/ffm_assistant_runtime_knowledge.dart`
-   `lib/features/assistant/domain/ffm_assistant_feedback_context.dart`
-   `lib/features/assistant/domain/ffm_assistant_action_plan.dart`
-   `lib/features/assistant/domain/ffm_agent_harness.dart`
-   `lib/features/assistant/domain/ffm_assistant_capabilities.dart`

Daftar tersebut berasal dari struktur repository `main` yang diperiksa
sebelum dokumen ini dibuat. citeturn3view0turn3view1

------------------------------------------------------------------------

# 3. Kondisi Memory Saat Ini

`FfmAssistantMemoryRepository` saat ini menyimpan memory lokal sebagai
record dengan:

-   `id`
-   `householdId`
-   `kind`
-   `triggerText`
-   `valueText`
-   `metadata`
-   `source`
-   `isArchived`
-   `createdAt`
-   `updatedAt`

Repository sudah mendukung:

-   membaca active/all memory,
-   save,
-   archive,
-   update,
-   alias application,
-   fuzzy answer.

Memory juga sengaja dipisahkan dari chat history. citeturn4view0

`FfmAssistantUserModelService` menggunakan tabel memory yang sama untuk
menyimpan user model dengan prefix `user_`, confidence, approval, dan
scope `user-model`. Namun `buildContext()` saat ini masih menggunakan
pencocokan teks sederhana antara query dan `key/value`, lalu mengambil
sampai 24 entry. citeturn5view1

`FfmPersonalMemoryService` saat ini sudah memiliki kategori:

-   `preference`
-   `habitChat`
-   `habitData`

dan mendeteksi beberapa fakta melalui pola/regex. Penyimpanan tetap
membutuhkan persetujuan eksplisit pengguna. citeturn5view2

`FfmAssistantPersonalizationRepository` juga sudah memiliki controlled
pattern learning. Contoh pattern saat ini berfokus pada merchant dan
field seperti `category`, `account`, dan `amount`, dengan ambang
`sampleCount >= 5` dan `confidenceScore >= 0.8` untuk dianggap kuat.
Repository tersebut secara eksplisit tidak memasukkan transaksi mentah
ke prompt dan tidak melatih ulang model secara langsung.
citeturn5view0

**Kesimpulan baseline: jangan membuat memory system kedua yang
duplikatif.**

------------------------------------------------------------------------

# 4. Masalah yang Harus Diselesaikan

Contoh masalah saat ini:

Pengguna pernah mengatakan:

> "Saya ingin mengurangi pengeluaran makan menjadi maksimal satu juta
> per bulan."

Kemudian beberapa hari kemudian:

> "Bulan ini gimana?"

Assistant seharusnya dapat memahami bahwa:

-   "bulan ini" mengacu pada periode aktif,
-   pengguna memiliki target pengeluaran makan,
-   pertanyaan kemungkinan berkaitan dengan kondisi pengeluaran,
-   transaksi aktual harus diambil melalui query tool/database,
-   target pengguna adalah konteks personal,
-   jawaban harus membandingkan kondisi aktual dengan target.

Jangan mengandalkan substring matching saja.

Memory:

> `target_makan = Rp1.000.000`

harus dapat relevan dengan pertanyaan:

-   "bulan ini gimana?"
-   "aku masih aman?"
-   "pengeluaran makan kebanyakan nggak?"
-   "kayaknya mulai boros"
-   "target makan saya masih kejaga?"

------------------------------------------------------------------------

# 5. Sasaran Produk

Setelah implementasi, Assistant harus memiliki perilaku berikut.

### 5.1 Personal

Jawaban mempertimbangkan fakta dan preferensi pengguna yang relevan.

### 5.2 Context-aware

Pertanyaan lanjutan dapat merujuk pada percakapan sebelumnya tanpa
pengguna mengulang konteks.

### 5.3 Goal-aware

Assistant mengetahui tujuan aktif pengguna ketika tujuan tersebut
relevan.

### 5.4 Behavior-aware

Assistant dapat menggunakan pola yang telah cukup kuat, tetapi tidak
menganggap pola lemah sebagai fakta.

### 5.5 Evidence-bound

Assistant tidak boleh mengklaim sesuatu hanya karena memory mengatakan
demikian jika data aktual FFM menunjukkan hal berbeda.

### 5.6 Editable

Pengguna dapat melihat, mengubah, mengarsipkan, dan menghapus memory.

### 5.7 Offline

Tidak ada cloud dependency.

### 5.8 Model-independent

Memory harus tetap tersedia walaupun model lokal diganti.

------------------------------------------------------------------------

# 6. Prinsip Arsitektur

Arsitektur yang diwajibkan:

``` text
User Query
   |
   v
Input Normalization
   |
   v
Intent / Entity Understanding
   |
   v
Personal Context Engine
   |
   +--> Working Conversation Context
   +--> Personal Memory
   +--> User Preferences
   +--> Goals
   +--> Behavioral Patterns
   +--> Relevant History
   +--> Page Context
   +--> Current FFM Data
   |
   v
Context Pack
   |
   v
SLM / Reasoning Layer
   |
   v
Response / Action Proposal
```

Memory Engine dan Context Engine **bukan SLM**.

SLM hanya menerima konteks yang telah dipilih.

------------------------------------------------------------------------

# 7. Komponen Baru yang Direkomendasikan

Buat satu orchestrator context baru:

``` text
lib/features/assistant/domain/ffm_personal_context_engine.dart
```

Jika project convention mengharuskan service berada di data layer, boleh
gunakan:

``` text
lib/features/assistant/data/ffm_personal_context_engine.dart
```

Tetapi domain contract harus tetap bersih.

Komponen pendukung yang disarankan:

``` text
lib/features/assistant/domain/
  ffm_personal_context_engine.dart
  ffm_personal_context.dart
  ffm_memory_candidate.dart
  ffm_memory_type.dart
  ffm_memory_evidence.dart
  ffm_context_relevance.dart
```

Nama boleh disesuaikan dengan convention repository yang terbaru. Jangan
membuat file baru jika fungsi yang sama sudah tersedia di branch
terbaru.

------------------------------------------------------------------------

# 8. Model Memory Baru

Jangan langsung menghapus struktur `kind/triggerText/valueText`. Gunakan
struktur tersebut sebagai compatibility layer.

Memory harus secara konseptual mempunyai tipe berikut:

## 8.1 Identity

Fakta relatif stabil.

Contoh:

``` text
preferred_name
occupation
language
currency
household_role
```

Jangan menyimpan data sensitif secara otomatis tanpa approval.

------------------------------------------------------------------------

## 8.2 Preference

Cara pengguna ingin Assistant bekerja.

Contoh:

``` text
response_style = concise
currency_format = rupiah_no_decimal
preferred_language = Indonesian
clarification_style = minimal
```

Preference boleh memengaruhi jawaban.

------------------------------------------------------------------------

## 8.3 Explicit Fact

Fakta yang pengguna sendiri nyatakan dan setujui.

Contoh:

``` text
payday = tanggal 25
monthly_food_limit = 1000000
preferred_account = BCA
```

------------------------------------------------------------------------

## 8.4 Goal

Tujuan aktif.

Contoh:

``` text
goal = menabung 10 juta
target_date = 2026-12-31
```

Goal harus memiliki lifecycle:

``` text
active
paused
completed
cancelled
```

------------------------------------------------------------------------

## 8.5 Habit

Kebiasaan yang disimpulkan dari pola.

Contoh:

``` text
user biasanya mencatat transaksi malam hari
```

Habit tidak boleh dianggap sebagai fakta mutlak.

Gunakan confidence dan evidence.

------------------------------------------------------------------------

## 8.6 Behavioral Pattern

Pola data.

Contoh:

``` text
merchant "Indomaret"
biasanya category = kebutuhan rumah
```

Ini berbeda dari preference.

------------------------------------------------------------------------

## 8.7 Episodic Memory

Ringkasan kejadian yang mungkin relevan di masa depan.

Contoh:

``` text
Pada 2026-08-20 pengguna meminta bantuan menurunkan
pengeluaran makan karena melebihi target bulanan.
```

Episodic memory harus memiliki tanggal dan relevance decay.

------------------------------------------------------------------------

## 8.8 Working Memory

Konteks percakapan aktif.

Contoh:

``` text
Topik aktif: pengeluaran makan
Periode: Agustus 2026
Target: Rp1.000.000
Pertanyaan sebelumnya: "Bulan ini gimana?"
```

Working memory tidak harus menjadi long-term memory.

------------------------------------------------------------------------

## 8.9 Correction Memory

Koreksi eksplisit pengguna.

Contoh:

``` text
User: "Indomaret jangan masukkan ke belanja pribadi,
itu biasanya kebutuhan rumah."
```

Koreksi mempunyai bobot tinggi.

------------------------------------------------------------------------

## 8.10 Assistant Decision / Recommendation Memory

Boleh disimpan jika memang berguna untuk kontinuitas.

Contoh:

``` text
Assistant pernah menyarankan user membatasi makan di luar.
```

Jangan menyamakan rekomendasi Assistant dengan fakta pengguna.

------------------------------------------------------------------------

# 9. Evidence Model

Setiap memory yang digunakan harus memiliki evidence metadata.

Minimal:

``` text
source
sourceId
sourceType
createdAt
updatedAt
confidence
approval
lastUsedAt
useCount
```

Contoh source:

``` text
user_explicit
user_correction
approved_pattern
inferred_pattern
conversation
transaction_pattern
goal
system
assistant_recommendation
```

Aturan:

-   `user_explicit` lebih kuat daripada `inferred_pattern`.
-   `user_correction` lebih kuat daripada pattern statistik.
-   `approved_pattern` lebih kuat daripada pattern yang belum
    dikonfirmasi.
-   `assistant_recommendation` tidak boleh diperlakukan sebagai fakta
    pengguna.
-   Memory tanpa evidence tidak boleh mendapatkan confidence tinggi.

------------------------------------------------------------------------

# 10. Confidence

Gunakan confidence 0.0--1.0.

Contoh:

``` text
1.00 = explicit user-approved fact
0.95 = explicit correction
0.90 = repeated confirmed pattern
0.80 = strong observed pattern
0.60 = weak observed pattern
0.40 = tentative inference
```

Tetapi confidence tidak boleh menjadi satu-satunya faktor retrieval.

Gunakan:

``` text
relevance
confidence
recency
importance
source reliability
usage frequency
current goal relevance
```

------------------------------------------------------------------------

# 11. Memory Extraction

Setelah percakapan selesai, sistem dapat melakukan memory candidate
extraction.

Pipeline:

``` text
Conversation Turn
      |
      v
Candidate Extractor
      |
      v
Candidate Memory
      |
      +--> duplicate?
      +--> contradiction?
      +--> sensitive?
      +--> explicit?
      +--> useful?
      |
      v
Approval / Promotion
      |
      v
Persistent Memory
```

### Jangan menyimpan semua percakapan.

Kalimat seperti:

> "oke"

tidak menjadi memory.

Kalimat seperti:

> "Mulai sekarang panggil saya Rafi."

menjadi candidate preference/identity.

Kalimat seperti:

> "Saya sedang berusaha menekan pengeluaran makan."

menjadi candidate goal/preference/plan, tetapi harus ditentukan dengan
benar apakah pengguna sedang menyatakan target atau hanya komentar.

------------------------------------------------------------------------

# 12. Jangan Memaksa Semua Memory Harus Di-Approve

Aturan lama FFM menyatakan fakta personal baru harus dikonfirmasi
sebelum disimpan. Pertahankan aturan tersebut untuk **durable personal
memory**. citeturn2view0turn3view2

Namun bedakan:

### Persistent personal memory

Perlu approval:

``` text
nama
pekerjaan
preferensi
goal
kebiasaan personal
fakta keluarga
```

### Working memory

Tidak perlu kartu approval.

Contoh:

``` text
"Pada percakapan ini kita sedang membahas pengeluaran makan."
```

### Query context

Tidak disimpan sebagai memory.

Contoh:

``` text
user sedang berada di halaman budget.
```

### Data-derived context

Tidak perlu disimpan sebagai personal memory.

Contoh:

``` text
bulan ini pengeluaran makan Rp1.200.000.
```

Data tersebut dibaca dari database saat diperlukan.

------------------------------------------------------------------------

# 13. Context Retrieval

Ini inti pekerjaan.

Buat method konseptual:

``` dart
Future<FfmPersonalContext> buildContext({
  required String query,
  required FfmAssistantPageContext? pageContext,
  required FfmAssistantReasoningContext? reasoningContext,
});
```

Nama type boleh mengikuti model terbaru repository.

Context Engine harus mengambil kandidat dari beberapa sumber:

``` text
A. Working memory
B. User model
C. Personal memory
D. Preferences
E. Goals
F. Behavioral patterns
G. Approved corrections
H. Relevant recent conversation
I. Page context
J. Current FFM data
K. Knowledge/answer memory
```

------------------------------------------------------------------------

# 14. Retrieval Harus Multi-Stage

Jangan langsung melakukan semantic search ke semuanya.

Gunakan:

``` text
Stage 1: Normalize
Stage 2: Detect entities/time/topic
Stage 3: Cheap lexical retrieval
Stage 4: Structured filtering
Stage 5: Relevance scoring
Stage 6: Deduplication
Stage 7: Conflict resolution
Stage 8: Context budget
Stage 9: Context Pack
```

------------------------------------------------------------------------

# 15. Stage 1 --- Normalization

Gunakan komponen yang sudah ada:

-   typo normalizer
-   fuzzy matcher
-   alias memory

Jangan mengganti komponen tersebut jika masih kompatibel.

Contoh:

``` text
"bulan ini gue boros gak ya?"
        |
        v
normalized:
"bulan ini saya boros tidak"
```

Jangan mengubah maksud pengguna.

------------------------------------------------------------------------

# 16. Stage 2 --- Entity & Topic Extraction

Ambil:

``` text
time:
  bulan ini

topic:
  pengeluaran

entity:
  tidak spesifik

intent:
  financial_analysis
```

Untuk:

> "target makan saya masih aman?"

hasilkan:

``` text
topic = food spending
entity = target
intent = financial_analysis
```

------------------------------------------------------------------------

# 17. Stage 3 --- Cheap Retrieval

Cari kandidat berdasarkan:

-   exact token
-   normalized token
-   alias
-   kind
-   key
-   value
-   merchant
-   category
-   goal
-   date
-   recent conversation

Target awal:

``` text
10–50 candidates
```

Jangan mengirim semua ke SLM.

------------------------------------------------------------------------

# 18. Stage 4 --- Structured Filtering

Filter berdasarkan konteks.

Contoh query:

> "bulan ini saya aman nggak?"

Prioritaskan:

``` text
current month
active goals
recent spending
budget
user targets
relevant preferences
```

Kurangi:

``` text
memory 2 tahun lalu
merchant yang tidak relevan
old completed goals
unrelated identity facts
```

------------------------------------------------------------------------

# 19. Stage 5 --- Relevance Scoring

Gunakan formula awal yang deterministic.

Contoh:

``` text
score =
    0.30 * semanticOrLexicalMatch
  + 0.20 * topicMatch
  + 0.15 * entityMatch
  + 0.10 * recency
  + 0.10 * importance
  + 0.05 * confidence
  + 0.05 * goalRelevance
  + 0.05 * usageFrequency
```

Bobot boleh dituning setelah evaluasi.

Jangan menganggap formula ini final.

------------------------------------------------------------------------

# 20. Recency

Gunakan decay.

Contoh:

``` text
recency = exp(-ageDays / halfLife)
```

Gunakan half-life berbeda per jenis:

``` text
Identity       = sangat lambat
Preference     = lambat
Goal           = berdasarkan status
Habit          = sedang
Episodic       = sedang/cepat
Working        = sangat cepat
```

Goal aktif tidak boleh hilang hanya karena sudah beberapa hari tidak
digunakan.

------------------------------------------------------------------------

# 21. Importance

Importance berbeda dari confidence.

Contoh:

``` text
Nama panggilan:
confidence 1.0
importance 0.4

Target menabung aktif:
confidence 1.0
importance 1.0

Komentar "saya suka kopi":
confidence 0.8
importance 0.2
```

------------------------------------------------------------------------

# 22. Goal Relevance

Jika pengguna memiliki goal aktif:

``` text
"menabung Rp10 juta sebelum Desember"
```

maka pertanyaan:

> "Boleh beli HP ini?"

harus membuat goal tersebut mendapat boost.

Namun Assistant tidak boleh memaksakan goal ke pertanyaan yang tidak
relevan.

------------------------------------------------------------------------

# 23. Context Budget

Context Engine harus memiliki batas.

Contoh awal:

``` text
Working memory: max 8 items
Personal facts: max 8
Preferences: max 5
Goals: max 5
Behavior patterns: max 8
Episodes: max 5
Corrections: max 5
```

Target context pack harus kecil.

Untuk model lokal di Android, **lebih baik 10 memory yang sangat relevan
daripada 100 memory yang kebetulan cocok.**

------------------------------------------------------------------------

# 24. Context Pack

Buat object terstruktur.

Contoh konseptual:

``` json
{
  "query": "bulan ini saya boros gak?",
  "normalizedQuery": "bulan ini saya boros tidak",
  "topic": "spending_analysis",
  "workingContext": [],
  "personalFacts": [],
  "preferences": [],
  "goals": [
    {
      "text": "User ingin membatasi pengeluaran makan maksimal Rp1.000.000 per bulan",
      "confidence": 1.0,
      "relevance": 0.94
    }
  ],
  "behaviorPatterns": [],
  "episodes": [],
  "corrections": [],
  "dataContext": {
    "period": "current_month"
  }
}
```

Jangan memasukkan data yang tidak relevan.

------------------------------------------------------------------------

# 25. Context Pack Bukan Prompt Final

Context Engine hanya menghasilkan structured context.

Response layer yang menentukan bagaimana context dimasukkan ke prompt
model.

Ini penting supaya:

-   SLM dapat diganti,
-   prompt dapat berubah,
-   context retrieval dapat diuji tanpa model,
-   unit test tidak tergantung inference.

------------------------------------------------------------------------

# 26. Conflict Resolution

Contoh:

Memory lama:

``` text
payday = tanggal 25
```

Memory baru:

``` text
payday = tanggal 28
```

Jangan mengirim keduanya sebagai fakta tanpa penjelasan.

Gunakan:

``` text
newer explicit user statement
        >
older explicit user statement
        >
approved pattern
        >
inferred pattern
```

Jika konflik tidak dapat diselesaikan:

> "Dulu Anda menyebut tanggal gajian tanggal 25, tetapi baru-baru ini
> tanggal 28. Yang mana yang harus saya gunakan?"

Jangan menebak.

------------------------------------------------------------------------

# 27. Contradiction Detection

Minimal deteksi contradiction berdasarkan:

``` text
same kind
same key
different value
```

Contoh:

``` text
user_preference:
response_style = singkat

user_preference:
response_style = detail
```

Simpan histori perubahan jika dibutuhkan, tetapi hanya satu nilai aktif
yang digunakan.

------------------------------------------------------------------------

# 28. Memory Deduplication

Jangan menyimpan:

``` text
"User suka jawaban singkat."
"Pengguna lebih suka jawaban yang singkat."
"Saya lebih nyaman dengan jawaban singkat."
```

sebagai tiga memory.

Gunakan canonical key:

``` text
response_style = concise
```

Lalu metadata dapat menyimpan evidence count.

------------------------------------------------------------------------

# 29. Memory Promotion

Pattern tidak langsung menjadi personal memory kuat.

Contoh:

``` text
observed 1x
  -> weak

observed 3x
  -> candidate

observed 5x + confidence >= threshold
  -> strong pattern

user confirms
  -> approved personal preference/pattern
```

Gunakan sistem existing `minimumSampleCount = 5` dan
`minimumConfidenceScore = 0.8` sebagai baseline untuk pattern yang sudah
dianggap kuat, bukan sebagai aturan universal untuk semua memory.
citeturn5view0

------------------------------------------------------------------------

# 30. Memory Decay

Memory tidak harus dihapus otomatis.

Gunakan status:

``` text
active
stale
archived
```

Contoh:

Goal selesai:

``` text
active -> completed
```

Habit lama:

``` text
active -> stale
```

Stale memory boleh tetap ada untuk audit/history tetapi tidak masuk
context normal.

------------------------------------------------------------------------

# 31. Memory Usage Tracking

Setiap memory yang dipakai dapat mencatat:

``` text
lastUsedAt
useCount
```

Namun jangan menulis database untuk setiap token atau setiap operasi
kecil.

Gunakan batch/debounced write.

Contoh:

``` text
chat turn selesai
   |
   v
memory usage buffer
   |
   v
flush
```

------------------------------------------------------------------------

# 32. Personal Context Engine Tidak Boleh Membaca Semua Transaksi Mentah

Data transaksi tetap dibaca melalui query/service yang sesuai.

Contoh:

Pertanyaan:

> "Bulan ini saya boros?"

Context Engine dapat meminta:

``` text
financial analysis:
  current month total
  previous period total
  category breakdown
  active budget
```

Bukan:

``` text
ambil 2.000 transaksi
masukkan semuanya ke prompt
```

Ini penting untuk performa dan privasi.

------------------------------------------------------------------------

# 33. Integrasi Dengan Page Context

Dokumentasi FFM sudah menetapkan bahwa Orchestrator bekerja dengan page
context yang berisi destination ID, data penting, aksi yang tersedia,
dan filter aktif. citeturn2view1

Gunakan itu.

Contoh:

User sedang di halaman Budget lalu berkata:

> "Yang ini kebanyakan nggak?"

Assistant harus dapat menggunakan:

``` text
current page = budget
current filter = food
visible budget = ...
```

tanpa meminta user menjelaskan ulang.

------------------------------------------------------------------------

# 34. Integrasi Dengan Conversation Memory

Working memory harus menyimpan:

``` text
last user intent
last referenced entity
current topic
current period
current goal
pending clarification
last action result
```

Contoh:

User:

> "Pengeluaran makan bulan ini berapa?"

Assistant menjawab.

User:

> "Kalau minggu lalu?"

"kalau minggu lalu" harus merujuk ke:

``` text
topic = pengeluaran
entity = makan
```

bukan memulai query baru dari nol.

------------------------------------------------------------------------

# 35. Integrasi Dengan Feedback

Gunakan `ffm_assistant_response_feedback_repository.dart` dan
`ffm_assistant_feedback_context.dart` yang sudah ada.

Feedback dapat memberi sinyal:

``` text
answer useful
answer not useful
user correction
wrong interpretation
wrong category
too verbose
too short
```

Jangan langsung mengubah personality berdasarkan satu feedback.

Gunakan akumulasi.

------------------------------------------------------------------------

# 36. Personality vs Memory

Pisahkan dua konsep.

### Memory

> "User ingin jawaban singkat."

### Response policy

> "Jawaban berikut sebaiknya singkat."

Jangan membuat SLM membaca raw memory lalu menebak personality setiap
kali.

Context Engine dapat menghasilkan:

``` text
responsePreferences:
  concise = true
  useIndonesian = true
  showRupiah = true
```

------------------------------------------------------------------------

# 37. Jangan Membuat Vector Database Dulu

Tahap pertama harus tetap sederhana dan offline.

Prioritas:

``` text
SQLite/Drift
+
structured filters
+
lexical/fuzzy matching
+
relevance scoring
+
recency
+
confidence
```

Embedding/vector retrieval boleh menjadi fase berikutnya jika evaluasi
menunjukkan lexical retrieval tidak cukup.

Jangan menambah dependency besar hanya untuk mengejar semantic search
sebelum baseline diukur.

------------------------------------------------------------------------

# 38. Semantic Retrieval Fase 2

Jika diperlukan, tambahkan:

``` text
query embedding
memory embedding
cosine similarity
reranker
```

Tetapi embedding harus lokal/offline.

Model embedding harus dapat diganti tanpa mengubah schema memory utama.

------------------------------------------------------------------------

# 39. SLM Sebagai Memory Extractor

Jika local SLM sudah stabil, SLM boleh digunakan untuk menghasilkan
**candidate** memory.

SLM tidak boleh:

-   menyimpan sendiri,
-   menghapus sendiri,
-   mengubah memory aktif,
-   mengubah transaksi,
-   menganggap inferensi sebagai fakta,
-   menulis langsung ke database.

Output model:

``` json
{
  "candidates": [
    {
      "kind": "preference",
      "key": "response_style",
      "value": "concise",
      "confidence": 0.91,
      "reason": "user explicitly requested short answers"
    }
  ]
}
```

Kemudian deterministic validator memutuskan apakah candidate valid.

------------------------------------------------------------------------

# 40. Candidate Validation

Validator harus memeriksa:

``` text
valid JSON
known kind
known key
non-empty value
confidence 0..1
source available
no sensitive auto-save
no destructive instruction
no database command
```

Jika gagal:

``` text
discard candidate
```

Jangan fallback ke auto-save.

------------------------------------------------------------------------

# 41. Sensitive Data

Jangan membuat automatic extraction untuk data sensitif.

Jika model mendeteksi sesuatu yang sensitif:

``` text
candidate -> blocked or explicit confirmation
```

Default aman:

``` text
tidak disimpan
```

------------------------------------------------------------------------

# 42. Memory UI

UI memory yang sudah ada harus tetap dipertahankan.

Tambahkan jika perlu:

``` text
Memory
├── Semua
├── Preferensi
├── Fakta
├── Kebiasaan
├── Tujuan
├── Koreksi
├── Pola
└── Arsip
```

Setiap memory dapat menampilkan:

``` text
Apa yang diingat
Mengapa diingat
Sumber
Tanggal
Confidence
Status
```

Contoh:

> "Anda lebih suka jawaban singkat."

Detail:

``` text
Sumber: Anda mengonfirmasi
Dibuat: 25 Agustus 2026
Confidence: 1.0
Status: Aktif
```

------------------------------------------------------------------------

# 43. Auditability

Untuk setiap memory penting, sistem harus bisa menjawab:

> "Kenapa Assistant mengingat ini?"

Jawaban harus berasal dari metadata.

Contoh:

``` text
Source:
user-approved

Evidence:
"Mulai sekarang jawab singkat saja."

Approved:
true
```

Jangan membuat memory yang tidak dapat dijelaskan asalnya.

------------------------------------------------------------------------

# 44. Backup

Memory harus ikut dalam mekanisme backup profile yang sudah ada.

Pertahankan compatibility dengan
`ffm_assistant_profile_export_service.dart`.

Backup harus dapat memuat:

``` text
memory
user model
preferences
approved patterns
goals/context metadata yang memang termasuk profile
```

Jangan memasukkan working memory sementara kecuali format backup memang
membutuhkan conversation continuity.

------------------------------------------------------------------------

# 45. Testing Strategy

Buat test unit untuk Context Engine.

## A. Exact relevance

Input:

``` text
"tanggal gajian saya kapan?"
```

Harus memilih:

``` text
payday
```

dan bukan memory lain.

## B. Paraphrase

Input:

``` text
"aku biasanya terima gaji tanggal berapa?"
```

Harus menemukan `payday`.

## C. Typo

Input:

``` text
"tnggal gajian ku kpan?"
```

Harus tetap menemukan `payday`.

## D. Follow-up

Turn 1:

``` text
"pengeluaran makan bulan ini berapa?"
```

Turn 2:

``` text
"kalau minggu lalu?"
```

Harus mempertahankan topic/entity.

## E. Goal relevance

Jika ada goal menabung, pertanyaan yang relevan harus mendapat goal
context.

## F. Unrelated memory

Memory tentang nama panggilan tidak boleh mendominasi pertanyaan
transaksi.

## G. Conflict

Dua nilai payday berbeda harus memicu conflict handling.

## H. Stale memory

Goal completed tidak boleh muncul sebagai active goal.

## I. Correction

User correction harus mengalahkan pattern lama.

## J. No-memory fallback

Jika tidak ada memory relevan, Assistant tetap menjawab secara normal.

------------------------------------------------------------------------

# 46. Evaluation Dataset

Buat dataset internal aman berisi pertanyaan seperti:

``` text
"gaji saya tanggal berapa?"
"kapan saya biasanya gajian?"
"bulan ini boros gak?"
"target nabung saya apa?"
"yang tadi maksud saya apa?"
"kalau minggu lalu?"
"aku masih aman sama budget?"
"kok kamu tahu saya suka jawaban singkat?"
"jangan ingat itu"
"yang tadi salah, koreksi ya"
```

Untuk setiap test, tentukan:

``` text
expected memory IDs
expected memory types
expected exclusions
expected answer style
```

Jangan menggunakan data finansial nyata pengguna sebagai fixture test.

------------------------------------------------------------------------

# 47. Acceptance Criteria

Implementasi dianggap berhasil jika:

### Retrieval

-   [ ] Query dapat mengambil memory relevan tanpa query exact match.
-   [ ] Typo dan paraphrase tetap dapat menemukan memory.
-   [ ] Memory tidak relevan tidak memenuhi context budget.
-   [ ] Memory lama memiliki decay.
-   [ ] Goal aktif mendapat relevance boost jika relevan.
-   [ ] Correction memiliki prioritas tinggi.

### Personalization

-   [ ] Preference memengaruhi response policy.
-   [ ] User model dipakai dalam context.
-   [ ] Personal memory dipakai secara selektif.
-   [ ] Working memory mempertahankan referensi antar-turn.
-   [ ] Assistant tidak meminta ulang informasi yang sudah ada dan
    relevan.

### Safety

-   [ ] Model tidak menulis memory langsung.
-   [ ] Durable personal memory tetap membutuhkan approval.
-   [ ] Sensitive candidate tidak auto-save.
-   [ ] Conflict tidak diselesaikan dengan tebakan.
-   [ ] Memory dapat dihapus/diarsipkan.

### Offline

-   [ ] Tidak ada network request untuk retrieval.
-   [ ] Context Engine berjalan tanpa SLM.
-   [ ] Assistant tetap berfungsi jika model lokal tidak tersedia.
-   [ ] Tidak ada cloud dependency baru.

### Regression

-   [ ] Existing tests tetap lulus.
-   [ ] Parser deterministik tetap menjadi authority.
-   [ ] Action planner tetap bekerja.
-   [ ] Existing memory UI tetap bekerja.
-   [ ] Backup profile tetap kompatibel.

------------------------------------------------------------------------

# 48. Performance Target Android

Target awal:

``` text
cheap retrieval: < 20 ms
structured scoring: < 20 ms
context composition: < 20 ms
database reads: batched
```

Target total Personal Context Engine:

``` text
< 100 ms
```

tidak termasuk inference SLM.

Jika memory jumlahnya masih kecil, jangan optimasi berlebihan.

------------------------------------------------------------------------

# 49. Fallback Behavior

Jika Context Engine error:

``` text
Context Engine
    |
    X
    |
    v
fallback:
  current query
  current page context
  deterministic parser
```

Assistant tetap berjalan.

Jangan membuat memory failure menyebabkan seluruh Assistant gagal.

------------------------------------------------------------------------

# 50. Urutan Implementasi

## Phase 1 --- Contract

-   [ ] Buat `FfmPersonalContext`
-   [ ] Buat `FfmMemoryCandidate`
-   [ ] Buat memory type enum/contract
-   [ ] Buat relevance score model
-   [ ] Buat context engine interface

## Phase 2 --- Retrieval

-   [ ] Integrasikan `FfmAssistantMemoryRepository`
-   [ ] Integrasikan `FfmAssistantUserModelService`
-   [ ] Integrasikan `FfmPersonalMemoryService`
-   [ ] Integrasikan personalization patterns
-   [ ] Integrasikan aliases/fuzzy matcher
-   [ ] Implement relevance scoring
-   [ ] Implement deduplication
-   [ ] Implement conflict resolution

## Phase 3 --- Working Context

-   [ ] Integrasikan chat history
-   [ ] Current topic
-   [ ] Current entity
-   [ ] Current period
-   [ ] Last user reference
-   [ ] Pending clarification

## Phase 4 --- FFM Context

-   [ ] Integrasikan page context
-   [ ] Integrasikan reasoning context
-   [ ] Integrasikan query tools
-   [ ] Jangan memasukkan raw database rows ke prompt

## Phase 5 --- Response Integration

-   [ ] Context Engine dipanggil sebelum response generation
-   [ ] Context Pack diteruskan ke reasoning layer
-   [ ] Response policy dibangun dari preference
-   [ ] Pastikan SLM tidak mengakses database langsung

## Phase 6 --- Learning

-   [ ] Candidate extraction
-   [ ] Validation
-   [ ] Approval
-   [ ] Promotion
-   [ ] Correction
-   [ ] Decay
-   [ ] Usage tracking

## Phase 7 --- Tests

-   [ ] Unit test
-   [ ] Retrieval test
-   [ ] Conflict test
-   [ ] Follow-up test
-   [ ] Typo test
-   [ ] Regression test
-   [ ] Performance test

------------------------------------------------------------------------

# 51. Jangan Lakukan Hal Berikut

Jangan:

1.  membuat database memory kedua jika `assistant_memories` masih dapat
    dikembangkan;
2.  mengganti `FfmAssistantMemoryRepository` tanpa migration plan;
3.  memasukkan seluruh memory ke setiap prompt;
4.  memasukkan seluruh transaksi ke prompt;
5.  menjadikan SLM sebagai authority;
6.  membiarkan SLM menulis database;
7.  menganggap semua inference sebagai fakta;
8.  menyimpan semua chat sebagai memory;
9.  menghapus approval untuk durable personal memory;
10. menambahkan vector DB sebelum baseline retrieval diuji;
11. membuat autonomous action sebagai bagian pekerjaan memory;
12. mengubah UI besar-besaran sebelum engine stabil.

------------------------------------------------------------------------

# 52. Contoh End-to-End

## Skenario 1 --- Preferensi

User:

> "Jawab singkat aja ya."

Pipeline:

``` text
candidate:
kind = preference
key = response_style
value = concise
```

UI:

> "Boleh saya ingat bahwa Anda lebih suka jawaban singkat?"

User:

> "Boleh."

Persist:

``` text
response_style = concise
approved = true
confidence = 1.0
```

Pertanyaan berikutnya:

> "Berapa pengeluaran bulan ini?"

Context Engine:

``` text
preference:
response_style = concise
```

Response:

> "Rp4,8 juta. Naik 12% dari bulan lalu."

------------------------------------------------------------------------

# 53. Contoh End-to-End --- Goal

User:

> "Saya mau nabung 10 juta sebelum Desember."

Setelah approval:

``` text
goal:
type = savings
target = 10000000
deadline = 2026-12-31
status = active
```

Kemudian:

> "Saya masih aman?"

Context Engine mendeteksi:

``` text
current financial state
+
active savings goal
```

Assistant dapat menjawab berdasarkan data aktual.

------------------------------------------------------------------------

# 54. Contoh End-to-End --- Follow-up

User:

> "Pengeluaran makan bulan ini berapa?"

Assistant:

> "Rp1,2 juta."

User:

> "Kalau minggu lalu?"

Working memory:

``` text
topic = spending
category = food
period = current_month
```

Query kedua otomatis:

``` text
category = food
period = previous_week
```

Tidak perlu bertanya:

> "Minggu lalu untuk apa?"

------------------------------------------------------------------------

# 55. Contoh End-to-End --- Correction

Assistant:

> "Indomaret biasanya masuk Belanja Pribadi."

User:

> "Salah. Kalau saya, Indomaret biasanya kebutuhan rumah."

Sistem:

``` text
correction candidate
merchant = Indomaret
category = kebutuhan rumah
source = user_correction
```

Setelah approval/promotion:

``` text
correction weight = high
```

Pattern lama tidak langsung dihapus dari histori, tetapi tidak boleh
mengalahkan correction baru.

------------------------------------------------------------------------

# 56. Contoh End-to-End --- Konflik

Memory:

``` text
payday = 25
```

User kemudian mengatakan:

> "Sekarang gajian tanggal 28."

Jangan membuat:

``` text
payday = 25
payday = 28
```

sebagai dua fakta aktif.

Update:

``` text
old:
payday = 25
status = superseded

new:
payday = 28
status = active
```

Jika sistem tidak yakin apakah user sedang berbicara tentang perubahan
sementara atau permanen, minta klarifikasi.

------------------------------------------------------------------------

# 57. Contoh Context Pack yang Baik

Query:

> "Kayaknya bulan ini saya boros deh."

Context:

``` text
QUERY
"Kayaknya bulan ini saya boros deh."

INTERPRETATION
topic = spending_analysis
period = current_month
tone = concern

PERSONAL CONTEXT
- User ingin mengontrol pengeluaran.
- User memiliki target pengeluaran makan Rp1.000.000/bulan.

GOALS
- Menabung Rp10.000.000 sebelum Desember.

CURRENT DATA REQUEST
- total current month
- previous month comparison
- category variance
- active budget

RELEVANT PATTERNS
- Pengeluaran makan biasanya menjadi kategori yang paling sering melewati target.

RESPONSE PREFERENCE
- concise
- Indonesian
```

Model kemudian menghasilkan jawaban yang grounded pada data aktual.

------------------------------------------------------------------------

# 58. Definisi "Personal" yang Benar

Personal bukan berarti:

> Assistant selalu menyebut nama pengguna.

Personal berarti:

> Assistant menggunakan pengetahuan yang benar-benar relevan tentang
> pengguna untuk meningkatkan ketepatan jawaban.

Contoh buruk:

> "Rafi, pengeluaran Anda Rp5 juta."

Contoh lebih baik:

> "Bulan ini pengeluaran Anda Rp5 juta, sekitar 15% di atas rata-rata
> tiga bulan terakhir. Yang paling meningkat adalah makan, padahal
> target makan Anda Rp1 juta."

Personalisasi harus **berguna**, bukan sekadar kosmetik.

------------------------------------------------------------------------

# 59. Prinsip Utama Untuk Human/AI Developer

Developer yang mengerjakan spesifikasi ini harus memahami:

> **Memory bukan database fakta biasa. Memory adalah sumber konteks yang
> dipilih berdasarkan relevansi.**

Maka pekerjaan utama bukan:

``` text
"buat lebih banyak memory"
```

tetapi:

``` text
"buat memory yang ada dapat ditemukan,
dinilai, diprioritaskan, dikonflikkan,
dan dimasukkan ke context secara tepat."
```

------------------------------------------------------------------------

# 60. Definition of Done

Fitur Personal Memory & Context Engine dianggap selesai jika demonstrasi
berikut berhasil:

### Demo A

User mengajarkan preference.

Tutup/restart aplikasi.

Tanya ulang.

Assistant tetap menggunakan preference.

### Demo B

User membuat goal.

Beberapa turn kemudian bertanya dengan bahasa berbeda.

Goal tetap ditemukan.

### Demo C

User menggunakan typo.

Memory tetap ditemukan.

### Demo D

User bertanya dengan follow-up pendek.

Assistant memahami referensi percakapan sebelumnya.

### Demo E

Ada dua memory yang konflik.

Assistant tidak menebak.

### Demo F

Memory tidak relevan.

Memory tersebut tidak masuk context.

### Demo G

SLM dimatikan.

Deterministic context retrieval tetap bekerja.

### Demo H

Memory dihapus dari UI.

Memory tidak lagi muncul di context.

### Demo I

Data finansial berubah.

Assistant menggunakan data terbaru, bukan memory lama sebagai angka
aktual.

### Demo J

Tidak ada network.

Semua fitur memory dan personalization tetap bekerja.

------------------------------------------------------------------------

# 61. Prinsip Akhir

FFM tidak perlu menjadi chatbot yang "hafal semuanya".

FFM harus menjadi assistant yang:

``` text
mengingat hal yang penting
        +
mengerti konteks sekarang
        +
tahu mana yang relevan
        +
tahu mana yang sudah usang
        +
tahu mana yang hanya dugaan
        +
tahu kapan harus bertanya
        +
menggunakan data aktual FFM
        +
tetap sepenuhnya lokal
```

Arsitektur target:

``` text
                    USER
                     |
                     v
              Query Understanding
                     |
                     v
           +----------------------+
           | Personal Context     |
           | Engine               |
           +----------+-----------+
                      |
       +--------------+---------------+
       |              |               |
       v              v               v
  Working Memory  Long-term       Current FFM
                  Memory             Data
       |              |               |
       +--------------+---------------+
                      |
                      v
                Context Pack
                      |
                      v
                Local SLM
                      |
                      v
              Response / Plan
```

**Satu kalimat untuk developer:**

> Jangan membuat model lebih pintar dulu; buat FFM lebih pintar dalam
> memilih konteks yang diberikan kepada model.

------------------------------------------------------------------------

# 62. Referensi Repository Saat Spesifikasi Dibuat

Baseline diperiksa langsung pada branch `main` repository FFM:

-   Repository: `raufimohamadfauzi-dev/ffm-project`
-   Assistant data layer: `lib/features/assistant/data`
-   Assistant domain layer: `lib/features/assistant/domain`
-   Existing personal memory repository
-   Existing personalization repository
-   Existing user model service
-   Existing personal memory service
-   Existing controlled-learning documentation
-   Existing offline-agent knowledge-base documentation

Repository saat diperiksa menyatakan FFM sebagai aplikasi offline-first
dengan personal memory yang transparan dan local AI. citeturn3view2

Dokumentasi existing menegaskan prinsip bahwa classifier/SLM hanya
memberi dugaan, sementara parser/orchestrator tetap menentukan data,
draft, pertanyaan balik, dan eksekusi. Prinsip ini **wajib
dipertahankan**. citeturn2view0turn2view1

------------------------------------------------------------------------

## Catatan Implementasi

Sebelum coding:

1.  Pull/rebase branch `main`.
2.  Baca file yang disebut dalam spesifikasi menggunakan versi terbaru.
3.  Cari apakah ada perubahan schema/service sejak dokumen ini dibuat.
4.  Jangan mengasumsikan nama method masih sama.
5.  Jika ada konflik dengan implementasi terbaru, prioritaskan
    architecture contract dan buat migration kecil.
6.  Setelah perubahan, jalankan analyzer dan test.
7.  Tambahkan regression test sebelum mengubah behavior existing.

**Dokumen ini adalah spesifikasi implementasi, bukan instruksi untuk
melakukan rewrite total terhadap assistant FFM.**
