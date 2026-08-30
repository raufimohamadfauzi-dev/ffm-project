# Activity Intelligence Upgrade

## Tujuan

Menjadikan **Aktivitas** sebagai salah satu sumber data utama FFM untuk pencatatan, pencarian, analisis, dan konteks Agent/LLM — bukan sekadar timer/jurnal.

Target utama:

- aktivitas mudah dicatat dari UI, chat, dan voice;
- setiap kejadian memiliki ID unik;
- aktivitas yang merupakan bagian dari proses/objek yang sama dapat ditelusuri kembali;
- aktivitas berbeda tetap terpisah walaupun kategori/domain-nya sama;
- pencarian berdasarkan ID/relasi hanya mengembalikan riwayat yang relevan;
- analisis 7/30/90 hari memakai seluruh data aktivitas yang relevan;
- Agent/LLM memahami aktivitas berdasarkan data terstruktur, bukan hanya judul teks;
- aktivitas dapat dihubungkan dengan transaksi, kebun/komoditas, target, hutang/piutang, aset, dan entitas lain tanpa mencampur data domain tersebut ke dalam satu tabel aktivitas;
- semua hasil analisis dapat ditelusuri ke data sumber.

---

## Kondisi Project Saat Ini

Fondasi sudah tersedia:

- `ActivitySessions` dengan `id`, `householdId`, `title`, `categoryId`, `category`, `kind`, waktu, status, dan `parentSessionId`;
- `ActivityCheckpoints` yang memiliki `id` dan `sessionId`;
- `ActivityEntries`/journal;
- `ActivityNotes` dengan `linkedSessionId`;
- `HarvestEvents` untuk data panen;
- index aktivitas berdasarkan household/tanggal/kategori/session;
- `Transactions.linkedActivityId` untuk hubungan transaksi → aktivitas;
- `ActivityContextBridge` untuk snapshot aktivitas aktif;
- voice parser + Gemini fallback;
- Agent/LLM sudah mendukung operasi aktivitas mulai/update/selesai/edit/arsip/hapus;
- `FfmActivityHabitLearner` sudah membuat memory habit dari aktivitas;
- test aktivitas, nested journey, plugin, dan voice sudah ada.

Referensi utama: `activity_entity.dart`, `activity_repository.dart`, `activity_bloc.dart`, `activity_page.dart`, `activity_voice.dart`, `app_database.dart`, dan task `docs/progress/task-activity-full-llm-support.md`.

**Jangan membangun ulang fondasi tersebut. Upgrade di atasnya.**

---

# Tahap 1 — Tetapkan Model Identitas Aktivitas

## 1.1 Event ID wajib unik

Pertahankan `ActivitySession.id` sebagai **ID unik setiap sesi/kejadian aktivitas**.

Contoh:

```text
activity_id A = menanam timun
activity_id B = memupuk timun
activity_id C = menyemprot pepaya
activity_id D = jogging
```

Jangan menggunakan kategori atau judul sebagai identitas unik.

## 1.2 Tambahkan identitas kelompok/proses bila diperlukan

`parentSessionId` saat ini berguna untuk nested activity, tetapi **parent-child tidak sama dengan identitas satu rangkaian/proyek jangka panjang**.

Jika kebutuhan sudah terbukti, tambahkan konsep terpisah seperti:

```text
activity_id        = satu kejadian unik
activity_group_id  = satu rangkaian/proses yang sama
parent_activity_id = hubungan nested bila memang ada
```

Contoh:

```text
Budidaya Timun #01
  ├─ A: Menanam timun
  ├─ B: Memupuk timun
  ├─ C: Menyiram timun
  └─ D: Panen timun
```

Sedangkan:

```text
Budidaya Pepaya #02
  └─ E: Semprot pepaya
```

**Catatan:** jangan menyamakan semua aktivitas "pertanian" menjadi satu ID.

---

# Tahap 2 — Tambahkan Subject/Entity Linking

Aktivitas perlu dapat menunjuk ke objek yang sedang dikerjakan.

Contoh besar:

```text
Activity
 ├─ category/domain: Pertanian
 ├─ activity_id: UUID
 ├─ group_id: Budidaya Timun #01
 ├─ subject_type: commodity/crop
 ├─ subject_id: timun-01
 └─ location_id: kebun-01
```

Gunakan relasi/ID, bukan hanya teks bebas.

Kemampuan linking harus dapat berkembang untuk:

- komoditas/kebun;
- transaksi;
- aset;
- target;
- hutang/piutang;
- lokasi;
- merchant/tempat;
- entitas domain lain yang memang relevan.

**Prinsip:** Activity menjadi pusat kejadian, sedangkan detail domain tetap berada pada tabel/domain masing-masing.

---

# Tahap 3 — Activity Query Layer

Jangan membuat LLM membaca tabel aktivitas secara bebas.

Buat query capability khusus aktivitas yang dapat menerima:

- tanggal/rentang waktu;
- activity ID;
- group ID;
- category/category ID;
- subject/entity;
- lokasi;
- status/kind;
- keyword/title bila diperlukan.

Contoh:

```text
activity.history
activity.by_id
activity.by_group
activity.by_subject
activity.by_category
activity.timeline
```

**Target:** pertanyaan "riwayat budidaya timun" dan "riwayat jogging" tidak bercampur hanya karena sama-sama masuk Activity.

---

# Tahap 4 — Activity Analysis Engine

Tambahkan lapisan analisis di atas Activity Query Layer.

Minimal mendukung:

- frequency;
- count;
- duration;
- trend;
- comparison;
- timeline;
- location distribution;
- category distribution;
- subject/process history;
- 7/30/90 hari;
- custom date range.

Contoh:

```text
"3 bulan terakhir saya jogging berapa kali dan ke mana saja?"

Query:
  activity domain = olahraga/jogging
  period = 90 hari

Analysis:
  count
  places
  frequency
  timeline

Result:
  verified facts
```

LLM hanya menyusun hasil menjadi bahasa natural.

---

# Tahap 5 — Verified Activity Fact / Context

Setiap hasil query/analisis menghasilkan context terstruktur yang memiliki minimal:

```text
period
filters
source records/count
metrics
facts
```

Contoh konsep:

```json
{
  "period": "90_days",
  "filter": {
    "activity": "jogging"
  },
  "count": 18,
  "locations": ["Padang", "Kota", "Taman"],
  "source_record_ids": ["...", "..."]
}
```

LLM **tidak boleh mengisi angka/fakta sendiri** jika data tersebut seharusnya berasal dari database.

---

# Tahap 6 — Upgrade Pemahaman LLM terhadap Activity

LLM/Agent harus memahami perbedaan:

```text
category      = klasifikasi
activity_id   = satu kejadian
activity_group= satu rangkaian/proses
subject_id    = objek yang dikerjakan
parent_id     = hubungan nested
checkpoint    = perkembangan di dalam aktivitas
```

Contoh:

> "Kemarin saya pupuk timun."

Agent harus dapat mencari apakah ada proses/subject timun yang relevan dan menghubungkan aktivitas baru dengan ID/group yang benar — **bukan sekadar membuat aktivitas baru tanpa relasi**.

Jika identitas tidak cukup jelas, Agent harus meminta klarifikasi.

---

# Tahap 7 — Satu Halaman Activity dengan Filtering Kuat

Tetap gunakan **satu halaman Activity**, tetapi jadikan halaman tersebut sebagai Activity Explorer.

Filter besar:

```text
Tanggal / Range
Kategori
Jenis
Status
Activity ID
Activity Group
Subject/Objek
Lokasi
Source
```

Mode pencarian ID:

```text
Cari: ACT-XXXX / UUID
        ↓
Tampilkan aktivitas + checkpoint + relasi terkait
```

Mode group/process:

```text
Budidaya Timun #01
 ├─ Menanam
 ├─ Memupuk
 ├─ Menyiram
 └─ Panen
```

Mode kategori:

```text
Pertanian
 ├─ Timun
 ├─ Pepaya
 ├─ Cabai
 └─ dst.
```

**Filter harus dilakukan di query/data layer, bukan hanya menyembunyikan card setelah semua data diambil.**

---

# Tahap 8 — Detail Activity yang Menjadi Timeline

Detail satu aktivitas harus dapat memperlihatkan:

- metadata aktivitas;
- ID;
- group/process;
- subject/entity;
- parent/child;
- checkpoint;
- notes;
- transaksi yang terkait;
- hasil/kejadian domain terkait jika memang memiliki relasi;
- timeline.

Contoh:

```text
ACT-001 — Menanam Timun
Group: BUD-001
Subject: Timun
Lokasi: Kebun A

Timeline
09:00 Menanam
12:00 Update
16:00 Menyiram
```

---

# Tahap 9 — Hubungkan Activity dengan Domain Lain

Jangan menjadikan Activity sebagai pengganti transaksi/aset/target/hutang/piutang.

Gunakan relasi.

Contoh:

```text
Activity
  ├── Transaction(s)
  ├── Asset
  ├── Goal
  ├── Liability
  ├── Receivable
  ├── Harvest
  └── Subject/Project
```

Dengan demikian Agent dapat menjawab pertanyaan lintas domain seperti:

> "Berapa biaya yang sudah keluar untuk budidaya timun ini?"

dengan mengambil Activity Group → transaksi terkait → analisis biaya.

---

# Tahap 10 — Perbaiki Habit Learning

`FfmActivityHabitLearner` saat ini mengenali kebiasaan berdasarkan **judul yang sama** dalam window 60 hari.

Upgrade berikutnya harus mempertimbangkan ID/subject/category yang terstruktur agar:

```text
"Jogging pagi"
"jogging pagi"
"lari pagi"
```

tidak selalu dianggap sama atau berbeda secara keliru.

Sebaliknya:

```text
Menanam timun
Memupuk timun
Semprot pepaya
```

tidak boleh otomatis digabung hanya karena domain/category sama.

---

# Tahap 11 — Activity Testing

Test wajib mencakup:

### Database
- unique activity ID;
- group/parent relation;
- checkpoint relation;
- subject relation;
- linked transaction;
- migration/backfill.

### Query
- filter 7/30/90 hari;
- filter category;
- filter subject;
- filter ID;
- filter group;
- kombinasi filter.

### Analysis
- count;
- frequency;
- duration;
- trend;
- location;
- comparison;
- empty data;
- large dataset.

### Agent/LLM
- membuat aktivitas baru;
- menemukan aktivitas lama;
- melanjutkan group yang benar;
- meminta klarifikasi jika ambigu;
- tidak mencampur aktivitas berbeda;
- menjawab berdasarkan verified facts.

### Integration

```text
User
 → Agent
 → Activity Tool
 → SQLite/Drift
 → Query
 → Analysis
 → Facts
 → LLM
 → Answer
```

---

# Tahap 12 — Regression & Golden Scenarios

Buat skenario tetap seperti:

```text
1. Menanam timun
2. Memupuk timun
3. Menyiram timun
4. Semprot pepaya
5. Jogging di taman
6. Belanja ke pasar
7. Belanja ke toko A
```

Lalu uji:

```text
"Riwayat budidaya timun?"
→ hanya rangkaian timun

"3 bulan terakhir saya jogging ke mana saja?"
→ hanya jogging

"Berapa biaya budidaya timun?"
→ activity group + linked transactions

"Apa yang paling sering saya lakukan?"
→ analysis seluruh activity yang relevan
```

---

# Urutan Implementasi

```text
1. Model identitas Activity
        ↓
2. Group / Subject linking
        ↓
3. Activity Query Layer
        ↓
4. Activity Analysis Engine
        ↓
5. Verified Fact / Context
        ↓
6. LLM Activity Understanding
        ↓
7. Activity Explorer / Filtering
        ↓
8. Cross-domain Linking
        ↓
9. Habit Learning Upgrade
        ↓
10. Unit + Integration + Golden + Regression Tests
```

---

# Prinsip Utama

- **Satu Activity = satu kejadian dengan ID unik.**
- **Satu Group = satu rangkaian/proses bila memang ada hubungan.**
- **Category bukan identitas.**
- **Parent-child bukan pengganti group/project.**
- **Subject/entity harus terstruktur jika perlu dilacak lintas waktu.**
- **Filter dilakukan sebelum data masuk ke LLM.**
- **Analisis dihitung oleh engine/tool, bukan ditebak LLM.**
- **LLM menjelaskan verified facts.**
- **Activity menjadi pusat kejadian, bukan tempat menampung seluruh domain data.**
- **Jangan menggabungkan aktivitas hanya karena kategorinya sama.**
- **Jika relasi tidak jelas, Agent harus meminta klarifikasi.**

---

# Definition of Done

Activity siap menjadi fondasi analisis jika:

- setiap aktivitas dapat diidentifikasi secara unik;
- rangkaian aktivitas dapat ditelusuri melalui group/subject;
- aktivitas berbeda tetap terisolasi;
- query dapat memfilter secara deterministik;
- analisis 7/30/90 hari menggunakan data lengkap yang relevan;
- Agent dapat membuat dan menemukan relasi aktivitas dengan benar;
- hasil analisis dapat ditelusuri ke record sumber;
- cross-domain analysis dapat memakai relasi Activity tanpa mencampur tabel domain;
- UI satu halaman dapat menjelajah/filter history dengan cepat;
- unit, integration, golden, dan regression tests mencakup jalur kritis.
