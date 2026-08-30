# Assistant / Agent / LLM Roadmap

## Tujuan

Membuat assistant FFM yang:
- menjawab berdasarkan data nyata ketika ditanya;
- menganalisis data ketika diminta analisis;
- menjalankan perintah melalui tool/backend ketika diminta;
- menghasilkan draft/JSON terstruktur sebelum aksi yang perlu dikonfirmasi;
- memverifikasi hasil aksi sebelum menyatakan berhasil;
- tetap natural dalam percakapan multi-turn;
- tidak mengarang data ketika data/tool tidak tersedia;
- memiliki pengujian yang cukup untuk meminimalkan bug dan regresi.

> Catatan: roadmap ini melengkapi fondasi yang sudah ada di project. Jangan membuat ulang Assistant/Agent/LLM dari nol tanpa alasan yang jelas.

---

## Sketsa Arsitektur Target

```text
User
  |
  v
Assistant / LLM Understanding
  |
  v
Agent Planner / Router
  |
  +---- Conversation / Chat ----------------> Natural Answer
  |
  +---- Read Tools --------------------------+
  |                                          |
  +---- Analysis Tools ----------------------+--> Backend / Database
  |                                          |
  +---- Action Tools ------------------------+
                                             |
                                             v
                                  Verified Data / Facts
                                             |
                                             v
                                      Context Layer
                                             |
                                             v
                                            LLM
                                             |
                                             v
                                      Natural Response

Action path:
User -> Intent -> Tool -> Structured Draft/JSON -> Validate
     -> Confirm (jika diperlukan) -> Execute -> Verify -> Report

Testing path:
Input -> Trace -> Intent -> Planner -> Tool -> Data -> LLM -> Answer
          ^
          +-- Debug / Replay / Regression / Evaluation
```

---

# Urutan Pengerjaan

## 1. Audit & Stabilize Assistant Runtime

Perjelas alur utama assistant yang sudah ada: understanding, routing, tool, response, draft, confirmation, dan fallback.

**Target:** tidak ada jalur yang saling tumpang tindih atau membuat LLM menjawab tanpa sumber data ketika pertanyaan membutuhkan data.

---

## 2. Perkuat Tool Contract & Registry

Standarkan setiap tool/plugin agar memiliki:
- nama dan tujuan;
- input/parameter;
- output;
- read atau write;
- aturan konfirmasi;
- error/result yang jelas.

**Target:** Agent tahu tool mana yang tersedia dan kapan tool tersebut layak digunakan.

---

## 3. Bangun Analysis Tools / Analysis Engine

Tambahkan kemampuan analisis di atas data yang sudah ada, bukan meminta LLM menghitung sendiri.

Contoh kemampuan besar:
- frequency/pattern;
- trend;
- comparison;
- summary;
- period analysis (mingguan/bulanan/90 hari);
- activity/financial pattern.

**Target:** pertanyaan seperti "3 bulan terakhir saya paling sering melakukan apa?" menghasilkan angka/pola dari data nyata.

---

## 4. Bangun Verified Fact / Context Layer

Hasil database dan analysis engine diubah menjadi context/fact terstruktur sebelum diberikan kepada LLM.

**Target:** LLM berfungsi sebagai penyusun jawaban natural berdasarkan fakta terverifikasi, bukan sumber fakta utama.

---

## 5. Perkuat Agent Planner

Agent harus dapat menentukan apakah request adalah:
- percakapan biasa;
- read/query;
- analysis;
- action;
- multi-step/multi-tool;
- clarification;
- confirmation;
- cancellation.

**Target:** request kompleks dapat menjalankan capability yang tepat secara berurutan.

---

## 6. Perkuat Action JSON / Draft Flow

Untuk aksi write:

```text
Natural Request
 -> Structured JSON/Draft
 -> Validate
 -> Show to User
 -> Confirm
 -> Execute
 -> Verify
 -> Report
```

**Target:** user dapat melihat data yang akan dibuat/diubah sebelum disimpan dan assistant tidak mengklaim sukses tanpa verifikasi backend.

---

## 7. Perkuat Natural Conversation & Memory

Pastikan follow-up seperti:
- "yang tadi";
- "ubah jadi...";
- "pakai akun itu";
- "bukan yang itu";
- "batalkan";

tetap mengacu pada konteks yang benar.

**Target:** assistant terasa seperti satu percakapan yang berkelanjutan, bukan kumpulan prompt terpisah.

---

## 8. Agent Debug Trace

Kembangkan trace yang sudah ada agar developer dapat melihat:

```text
Input
 -> Intent
 -> Planner
 -> Selected Tool
 -> Parameters
 -> Backend Result
 -> Analysis
 -> Facts
 -> LLM
 -> Final Answer
```

**Target:** setiap jawaban yang salah dapat diketahui salahnya di tahap mana.

---

## 9. Agent Test Suite

Buat test otomatis untuk:
- intent/routing;
- tool selection;
- tool execution;
- JSON/draft validation;
- confirmation;
- clarification;
- fallback/error;
- data grounding.

**Target:** perubahan pada assistant tidak merusak kemampuan yang sudah benar.

---

## 10. Golden Conversation Tests

Sediakan percakapan standar multi-turn dengan hasil yang diharapkan.

Contoh kategori:
- greeting;
- query data;
- analysis 30/90 hari;
- create/update;
- correction;
- confirmation;
- cancellation;
- memory;
- multi-tool;
- tool failure.

**Target:** natural conversation diuji sebagai alur lengkap, bukan hanya satu input.

---

## 11. LLM Evaluation

Uji kualitas jawaban LLM berdasarkan:
- factuality terhadap context;
- tidak hallucination;
- mengikuti intent;
- tidak mengarang hasil aksi;
- naturalness;
- relevansi;
- completeness.

**Target:** LLM dinilai dari hasil yang benar terhadap data project, bukan hanya dari kalimat yang terdengar bagus.

---

## 12. Regression Test

Setiap perubahan pada Assistant/Agent/LLM wajib menjalankan kumpulan test lama + test baru.

**Target:** fitur baru tidak merusak intent, tool, memory, action, atau conversation yang sebelumnya sudah benar.

---

## 13. Analysis / Python Test (Opsional)

Jika analysis engine memakai perhitungan statistik/algoritma yang kompleks, boleh dibuat test independen menggunakan Python untuk memvalidasi hasil analitik.

**Catatan:** Python bukan kewajiban. Test Dart cukup jika seluruh logic analisis tetap di Dart.

---

## 14. Conversation Replay

Simpan contoh percakapan yang gagal dan sediakan mekanisme replay.

**Target:** bug assistant dapat direproduksi tanpa harus mengetik ulang secara manual.

---

# Prinsip Wajib

1. **Data berasal dari backend/database, bukan tebakan LLM.**
2. **Analisis dilakukan oleh analysis capability/engine, bukan LLM secara bebas.**
3. **LLM menyusun bahasa natural dari verified facts.**
4. **Action menggunakan structured draft/JSON dan validation.**
5. **Write action diverifikasi setelah execution.**
6. **Jika data/tool gagal atau tidak tersedia, assistant harus jujur.**
7. **Jangan menambah tool yang duplikatif tanpa kebutuhan nyata.**
8. **Pertahankan fondasi Agent Harness, plugin, Gemini orchestration, draft, memory, dan trace yang sudah ada.**

---

# Definition of Done

Assistant dianggap siap secara arsitektur jika:

- pertanyaan data selalu grounded ke data nyata;
- analisis menghasilkan fakta/pola yang dapat diverifikasi;
- perintah menghasilkan structured draft/JSON yang benar;
- aksi hanya dijalankan melalui tool/backend;
- hasil aksi diverifikasi;
- multi-turn conversation konsisten;
- kegagalan tool tidak menghasilkan klaim sukses palsu;
- trace dapat menunjukkan jalur eksekusi;
- golden conversation lulus;
- regression test lulus;
- LLM evaluation tidak menunjukkan masalah grounding/hallucination yang kritis.

---

## Prioritas Singkat

```text
P0  Stabilize Runtime
P0  Tool Contract + Registry
P0  Analysis Engine / Analysis Tools
P0  Verified Fact / Context Layer
P0  Action JSON + Validation + Verification
P1  Agent Planner
P1  Natural Conversation / Memory hardening
P1  Agent Debug Trace
P1  Agent Test Suite
P1  Golden Conversation Tests
P1  LLM Evaluation
P1  Regression Tests
P2  Conversation Replay
P2  Python/independent Analysis Tests bila diperlukan
```
