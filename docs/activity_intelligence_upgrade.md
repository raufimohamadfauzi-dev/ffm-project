# Activity Intelligence Upgrade

## Tujuan

Menjadikan **Aktivitas** sebagai salah satu sumber data utama FFM untuk pencatatan, pencarian, analisis, dan konteks Agent/LLM — bukan sekadar timer/jurnal.

Target utama:

- aktivitas tetap cepat dan natural untuk dicatat dari UI, chat, dan voice;
- aktivitas sederhana **tidak dipaksa mengisi banyak field**;
- setiap kejadian memiliki ID unik yang dibuat otomatis oleh sistem;
- aktivitas yang merupakan bagian dari proses/objek yang sama dapat ditelusuri;
- aktivitas berbeda tetap terpisah walaupun kategori/domain-nya sama;
- aktivitas pertanian dapat memiliki konteks lebih kaya tanpa membuat aktivitas umum menjadi rumit;
- pencarian berdasarkan ID/relasi hanya mengembalikan history yang relevan;
- analisis 7/30/90 hari memakai seluruh data aktivitas yang relevan;
- Agent/LLM memahami aktivitas berdasarkan data terstruktur, bukan hanya judul teks;
- aktivitas dapat dihubungkan dengan transaksi, kebun/komoditas, target, hutang/piutang, aset, dan entitas lain melalui relasi;
- semua hasil analisis dapat ditelusuri ke data sumber.

> Prinsip UX utama: **simple by default, richer when needed**. Struktur internal boleh kompleks, tetapi input pengguna tetap natural.

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

**Jangan membangun ulang fondasi tersebut. Upgrade di atasnya.**

---

# Tahap 1 — Tetapkan Model Identitas Aktivitas

## 1.1 Event ID wajib unik

Pertahankan `ActivitySession.id` sebagai **ID unik setiap sesi/kejadian aktivitas**. ID dibuat otomatis oleh sistem dan tidak perlu diketahui/diisi pengguna.

Contoh:

```text
ACT-001 = Menanam timun
ACT-002 = Memupuk timun
ACT-003 = Menyemprot pepaya
ACT-004 = Jogging
ACT-005 = Belanja pasar
```

Jangan menggunakan kategori atau judul sebagai identitas unik.

## 1.2 Bedakan event, group, dan parent

`parentSessionId` berguna untuk nested activity, tetapi tidak selalu sama dengan satu rangkaian/proses jangka panjang.

Gunakan konsep terpisah bila kebutuhan sudah terbukti:

```text
activity_id        = satu kejadian unik
activity_group_id  = satu rangkaian/proses yang sama
parent_activity_id = hubungan nested bila memang ada
```

Contoh:

```text
BUD-001 — Budidaya Timun Lahan A
  ├─ ACT-001 Menanam timun
  ├─ ACT-002 Memupuk timun
  ├─ ACT-003 Menyiram timun
  └─ ACT-004 Panen timun

BUD-002 — Budidaya Timun Lahan B
  ├─ ACT-005 Menanam timun
  └─ ACT-006 Memupuk timun

ACT-007 — Semprot pepaya
ACT-008 — Jogging
ACT-009 — Belanja pasar
```

**Jangan menyatukan semua aktivitas pertanian menjadi satu ID.**

---

# Tahap 2 — Subject / Entity Linking

Aktivitas dapat menunjuk ke objek yang sedang dikerjakan bila konteks memang membutuhkan pelacakan.

Contoh:

```text
Activity
 ├─ activity_id
 ├─ category/domain: Pertanian
 ├─ group_id: BUD-001
 ├─ subject_type: crop
 ├─ subject_id: timun-01
 └─ location_id: lahan-A
```

Relasi dapat digunakan untuk:

- komoditas/kebun;
- transaksi;
- aset;
- target;
- hutang/piutang;
- lokasi;
- merchant/tempat;
- entitas domain lain yang memang relevan.

**Activity menjadi pusat kejadian; detail domain tetap berada di domain masing-masing.**

---

# Tahap 3 — Progressive Context / Simple by Default

Ini adalah aturan UX penting.

### Aktivitas sederhana

User cukup mengatakan:

```text
"Tadi jogging 5 km."
```

Sistem tidak perlu meminta:

```text
lahan?
komoditas?
group?
subject?
```

Cukup simpan data yang relevan dan buat ID otomatis.

### Aktivitas kontekstual

Jika user mengatakan:

```text
"Tanam timun di Lahan A."
```

Agent dapat menghubungkan aktivitas ke lahan/komoditas/group yang relevan.

### Aktivitas ambigu

Jika ada:

```text
Lahan A → Timun
Lahan B → Timun
```

dan user berkata:

```text
"Besok saya pupuk timun."
```

Agent **tidak boleh menebak**. Jika konteks sebelumnya tidak cukup, tanyakan:

```text
"Timun di Lahan A atau Lahan B?"
```

**Jangan memaksa semua jenis aktivitas memiliki semua field.**

---

# Tahap 4 — Activity Query Layer

LLM tidak membaca tabel aktivitas secara bebas.

Buat capability query khusus yang mendukung filter:

- tanggal/rentang waktu;
- activity ID;
- group ID;
- category/category ID;
- subject/entity;
- lokasi;
- status/kind;
- keyword/title bila diperlukan.

Contoh capability:

```text
activity.history
activity.by_id
activity.by_group
activity.by_subject
activity.by_category
activity.timeline
```

**Filter harus dilakukan di query/data layer, bukan hanya menyembunyikan hasil setelah semua data diambil.**

---

# Tahap 5 — Activity Analysis Engine

Tambahkan lapisan analisis di atas Activity Query Layer.

Minimal mendukung:

- count/frequency;
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
  domain/activity = jogging
  period = 90 hari

Analysis:
  count
  locations
  frequency
  timeline

Result:
  verified facts
```

LLM hanya menyusun hasil menjadi bahasa natural.

---

# Tahap 6 — Verified Fact / Context Layer

Hasil query/analisis harus diubah menjadi context/fact terstruktur sebelum diberikan kepada LLM.

Minimal memiliki konsep:

```text
period
filters
source record IDs/count
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

LLM **tidak boleh mengarang angka/fakta** yang seharusnya berasal dari database.

---

# Tahap 7 — Upgrade Pemahaman LLM terhadap Activity

LLM/Agent harus memahami perbedaan:

```text
category       = klasifikasi
activity_id    = satu kejadian
activity_group = satu rangkaian/proses
subject_id     = objek yang dikerjakan
parent_id      = hubungan nested
checkpoint     = perkembangan di dalam aktivitas
```

Contoh:

> "Kemarin saya pupuk timun."

Agent mencari konteks/subject/group yang relevan dan menghubungkan aktivitas baru bila memang jelas.

Jika ada lebih dari satu kandidat yang valid dan konteks tidak cukup, **minta klarifikasi**.

LLM tidak boleh memilih lahan/komoditas hanya karena nama teksnya kebetulan sama.

---

# Tahap 8 — Satu Halaman Activity dengan Filtering Kuat

Tetap gunakan **satu halaman Activity**, tetapi jadikan sebagai Activity Explorer.

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

Mode ID:

```text
Cari ACT-XXXX / UUID
        ↓
Tampilkan history aktivitas + relasi yang relevan
```

Mode group/process:

```text
Budidaya Timun Lahan A
 ├─ Menanam
 ├─ Memupuk
 ├─ Menyiram
 └─ Panen
```

Mode category:

```text
Pertanian
 ├─ Timun
 ├─ Pepaya
 ├─ Cabai
 └─ dst.
```

**Satu halaman, banyak filter; bukan banyak halaman untuk setiap jenis aktivitas.**

---

# Tahap 9 — Detail Activity sebagai Timeline

Detail satu aktivitas dapat memperlihatkan:

- metadata;
- ID;
- group/process;
- subject/entity;
- parent/child;
- checkpoint;
- notes;
- transaksi terkait;
- hasil/kejadian domain terkait jika memang memiliki relasi;
- timeline.

Contoh:

```text
ACT-001 — Menanam Timun
Group: BUD-001
Subject: Timun
Lokasi: Lahan A

Timeline
09:00 Menanam
12:00 Update
16:00 Menyiram
```

---

# Tahap 10 — Cross-Domain Activity Linking

Jangan menjadikan Activity sebagai pengganti transaksi/aset/target/hutang/piutang.

Gunakan relasi.

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

Contoh pertanyaan:

> "Berapa biaya yang sudah keluar untuk budidaya timun Lahan A?"

Agent:

```text
Activity Group
 → linked transactions
 → analysis
 → verified result
```

---

# Tahap 11 — Upgrade Habit Learning

`FfmActivityHabitLearner` saat ini perlu diperkuat agar pembelajaran habit tidak hanya bergantung pada judul yang sama.

Gunakan konteks terstruktur bila tersedia:

```text
activity type
category
subject
location
frequency
```

Tujuannya:

```text
"Jogging pagi"
"jogging"
"lari pagi"
```

dapat dianalisis sebagai pola yang sama bila memang terbukti relevan.

Sebaliknya:

```text
Menanam timun
Memupuk timun
Semprot pepaya
```

tidak boleh otomatis digabung hanya karena domain/category sama.

---

# Tahap 12 — Activity Testing

Test utama:

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
- kombinasi filter;
- dua objek dengan nama sama tetapi ID berbeda.

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
- aktivitas sederhana tidak meminta field yang tidak diperlukan;
- membuat aktivitas baru;
- menemukan aktivitas lama;
- melanjutkan group yang benar;
- membedakan dua lahan dengan komoditas sama;
- meminta klarifikasi jika ambigu;
- tidak mencampur jogging dengan aktivitas pertanian;
- menjawab berdasarkan verified facts.

### Integration

```text
User
 → Agent
 → Activity Tool
 → Database
 → Query
 → Analysis
 → Facts
 → LLM
 → Answer
```

---

# Tahap 13 — Golden & Regression Scenarios

Gunakan dataset uji yang sengaja memiliki konteks mirip:

```text
Lahan A → Timun
Lahan B → Timun
Lahan A → Pepaya
```

Dan aktivitas umum:

```text
Jogging
Belanja pasar
Belanja toko A
```

Contoh pengujian:

```text
"Riwayat budidaya timun Lahan A?"
→ hanya group/subject Lahan A yang relevan

"3 bulan terakhir saya jogging ke mana saja?"
→ hanya jogging

"Berapa biaya budidaya timun Lahan A?"
→ group/subject + linked transactions

"Apa yang paling sering saya lakukan?"
→ analysis seluruh activity yang relevan

"Besok saya pupuk timun."
→ jika dua timun aktif dan konteks tidak cukup: clarification
```

---

# Urutan Implementasi

```text
1. Model identitas Activity
        ↓
2. Group / Subject linking
        ↓
3. Progressive Context / simple input
        ↓
4. Activity Query Layer
        ↓
5. Activity Analysis Engine
        ↓
6. Verified Fact / Context Layer
        ↓
7. LLM Activity Understanding
        ↓
8. Activity Explorer / Filtering
        ↓
9. Cross-domain Linking
        ↓
10. Habit Learning Upgrade
        ↓
11. Unit + Integration + Golden + Regression Tests
```

---

# Prinsip Utama

- **Satu Activity = satu kejadian dengan ID unik.**
- **ID dibuat otomatis; user tidak perlu mengisinya.**
- **Satu Group = satu rangkaian/proses bila memang ada hubungan.**
- **Category bukan identitas.**
- **Parent-child bukan pengganti group/project.**
- **Subject/entity digunakan bila aktivitas memang perlu dilacak terhadap objek tertentu.**
- **Aktivitas sederhana tetap sederhana.**
- **Konteks ditambahkan secara progresif ketika diperlukan.**
- **Jika identitas objek ambigu, Agent bertanya; jangan menebak.**
- **Filter dilakukan sebelum data masuk ke LLM.**
- **Analisis dihitung oleh engine/tool, bukan ditebak LLM.**
- **LLM menjelaskan verified facts.**
- **Activity menjadi pusat kejadian, bukan tempat menampung seluruh domain data.**
- **Jangan menggabungkan aktivitas hanya karena kategorinya sama.**

---

# Definition of Done

Activity siap menjadi fondasi analisis jika:

- setiap aktivitas dapat diidentifikasi secara unik;
- aktivitas sederhana dapat dicatat tanpa form/field berlebihan;
- rangkaian aktivitas dapat ditelusuri melalui group/subject;
- dua objek dengan nama sama tidak mudah tertukar;
- aktivitas berbeda tetap terisolasi;
- query dapat memfilter secara deterministik;
- analisis 7/30/90 hari menggunakan data lengkap yang relevan;
- Agent dapat membuat dan menemukan relasi aktivitas dengan benar;
- hasil analisis dapat ditelusuri ke record sumber;
- cross-domain analysis dapat memakai relasi Activity tanpa mencampur domain;
- satu halaman Activity dapat menjelajah/filter history dengan cepat;
- unit, integration, golden, dan regression tests mencakup jalur kritis.
