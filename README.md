# 💎 FFM — Family Financial Management

> **Aplikasi pengelola keuangan keluarga dengan AI Assistant/Agent sebagai pusat pengalaman, didukung Gemini API, Supabase, dan optional on-device AI.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Backend](https://img.shields.io/badge/Backend-Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)
[![AI](https://img.shields.io/badge/AI-Gemini%20%2B%20Local%20AI-4285F4?style=for-the-badge&logo=google)](https://ai.google.dev/)
[![Android](https://img.shields.io/badge/Android-ARM64-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#-build-release)

---

## 🎯 Arah Produk

FFM bukan sekadar aplikasi pencatat keuangan dengan chatbot tambahan.

**AI Assistant/Agent adalah prioritas utama produk.**

Assistant dirancang untuk menjadi lapisan kecerdasan utama FFM: memahami konteks finansial pengguna, menganalisis data, menjawab pertanyaan, memberikan insight, mengusulkan tindakan, dan menjalankan aksi melalui capability aplikasi setelah melewati validasi dan konfirmasi yang diperlukan.

Arsitektur FFM bersifat **hybrid**:

- **Gemini API** untuk reasoning dan kemampuan AI cloud yang membutuhkan model lebih kuat.
- **Supabase** untuk authentication, persistence, sinkronisasi, dan layanan backend yang menjadi bagian dari aplikasi.
- **Local database/application logic** sebagai sumber kebenaran data finansial dan business rules.
- **Optional on-device AI/SLM** untuk workload yang memang lebih cocok dijalankan secara lokal.

FFM **bukan** lagi diposisikan sebagai aplikasi “100% Offline-First” atau “Zero Cloud Dependency”. Offline/local capability tetap dapat digunakan pada area yang sesuai, tetapi cloud adalah bagian resmi dari arsitektur produk.

---

## 🤖 AI Assistant / Agent

Assistant adalah fitur P0 dan menjadi fokus utama pengembangan.

### Kemampuan utama

- Percakapan natural dalam bahasa Indonesia.
- Pemahaman konteks finansial pengguna.
- Analisis transaksi, rekening, budget, goals, liabilities, dan data finansial lain yang tersedia.
- Financial insights dan ringkasan yang grounded pada data aplikasi.
- Follow-up questions dan contextual suggestions.
- Personal memory dengan kontrol pengguna.
- Action planning dan proposal untuk perubahan data.
- Capability/tool execution melalui application layer.
- Verifikasi hasil setelah action dijalankan.
- Penanganan error, timeout, cancellation, dan partial failure.
- Optional local/on-device AI untuk capability yang sesuai.

### Batasan eksekusi AI

Model AI tidak boleh langsung melakukan mutasi database atau state aplikasi.

Untuk action yang mengubah data, alur yang digunakan adalah:

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

Perhitungan finansial yang deterministic tetap dilakukan oleh application logic dan database. AI digunakan untuk memahami, menjelaskan, merangkum, dan membantu mengambil keputusan berdasarkan nilai yang authoritative.

---

## 🧠 Gemini + Supabase + Local AI

### Gemini API

Digunakan untuk kebutuhan seperti:

- natural-language understanding,
- reasoning kompleks,
- generation,
- explanation dan summarization,
- planning assistance,
- multimodal/AI workloads yang sesuai dengan provider.

Gunakan abstraksi Gemini yang sudah ada di project. Jangan membuat banyak client/provider terpisah tanpa kebutuhan arsitektural yang jelas.

### Supabase

Digunakan sebagai bagian resmi backend untuk area seperti:

- authentication,
- cloud persistence,
- synchronization,
- shared application data,
- backend services dan capabilities.

### Local / On-Device AI

Local SLM/native inference merupakan capability tambahan, bukan prinsip yang memaksa seluruh aplikasi menjadi offline-only.

Gunakan local AI ketika workload memang membutuhkan atau diuntungkan oleh:

- low latency,
- local processing,
- privacy-sensitive local workload,
- on-device multimodal processing,
- fallback atau specialized runtime yang sudah didukung project.

---

## 📊 Fitur Keuangan

Fitur finansial lainnya tetap penting, tetapi mengikuti prioritas assistant.

- **Multi Rekening & Dompet** — kas, rekening bank, dan e-wallet.
- **Budget Guard & Daily Burn Rate** — pemantauan pengeluaran dan risiko overbudget.
- **Net Worth & Asset Tracker** — estimasi kekayaan bersih dan aset.
- **Hutang & Piutang** — pelacakan jatuh tempo dan sisa pembayaran.
- **Financial Goals** — target tabungan dan alokasi berkala.
- **Transaction Management** — pemasukan, pengeluaran, transfer, dan kategori.
- **Calendar support** — termasuk kebutuhan penanggalan Masehi/Hijriah yang ada di aplikasi.

Fitur-fitur tersebut harus menyediakan data dan capability yang membuat assistant semakin berguna.

---

## 🏗️ Arsitektur Teknologi

```text
lib/
├── core/                  # Database, tema, konfigurasi, dependency injection
├── features/
│   ├── assistant/         # Agent Engine, planner, tools, capabilities, UI, AI providers
│   ├── activity/          # Aktivitas dan rutinitas
│   ├── auth/              # Authentication / local security flow
│   ├── budget/            # Budget dan allocation logic
│   ├── goal/              # Financial goals
│   ├── home/              # Dashboard dan navigasi
│   ├── liability/         # Hutang dan piutang
│   └── transaction/       # Pemasukan, pengeluaran, dan transfer
```

Komponen assistant yang sudah ada harus diprioritaskan untuk dikembangkan sebelum membuat arsitektur AI paralel.

---

## 🔐 Keamanan & Data

- Jangan commit Gemini API keys, Supabase service-role keys, access tokens, atau credential privat ke repository.
- Model AI tidak menjadi sumber kebenaran untuk financial state.
- Authorization, validation, business rules, dan capability execution tetap berada di application/backend layer.
- Personal memory harus tetap user-controlled dan mengikuti approval architecture yang tersedia.
- Hindari mengirim context atau data finansial yang tidak relevan ke provider AI.

---

## 🚀 Local Setup

### Prasyarat

- **Flutter SDK**: sesuai constraint pada `pubspec.yaml`.
- **Dart SDK**: sesuai constraint pada `pubspec.yaml`.
- **Android Studio / VS Code**.
- **JDK**: sesuai konfigurasi Android project.
- Credential/configuration untuk service yang memang digunakan oleh environment aplikasi, termasuk backend/AI sesuai setup project.

### Instalasi

```bash
git clone https://github.com/raufimohamadfauzi-dev/ffm-project.git
cd ffm-project
flutter pub get
```

### Validasi

```bash
flutter analyze lib test
flutter test
```

Jalankan aplikasi untuk development dengan:

```bash
flutter run
```

---

## 📦 Build Release

**Release target resmi FFM adalah Android ARM64 saja.**

Gunakan command canonical:

```bash
flutter build apk --target-platform android-arm64 --release
```

Target native Android release:

```text
arm64-v8a
```

Jangan membuat release deliverable multi-ABI atau target platform lain kecuali diminta secara eksplisit.

---

## 🧪 Testing AI Assistant

Saat mengubah assistant, prioritaskan pengujian untuk:

1. Agent harness/orchestration.
2. Planner dan action plan.
3. Capability executor.
4. Proposal/validation.
5. Query/data adapters.
6. Mutation integration.
7. Gemini/provider routing.
8. Local AI routing.
9. Memory/learning.
10. Cancellation/concurrency.
11. Assistant UI/integration.

Successful Flutter build tidak otomatis berarti Gemini API, Supabase connectivity, atau on-device inference sudah tervalidasi end-to-end.

---

## 👨‍💻 Pengembang

- **Pembuat & Pengembang Utama**: [raufimohamadfauzi-dev](https://github.com/raufimohamadfauzi-dev)
- **Platform Konten Resmi**: YouTube & TikTok Clipsmart

---

## 📄 Dokumentasi Agent

Aturan kerja agent untuk repository ini tersedia di [`AGENTS.md`](AGENTS.md).

`AGENTS.md` adalah acuan untuk menjaga prioritas pengembangan pada AI Assistant/Agent, integrasi Gemini + Supabase, keamanan eksekusi action, serta target Android ARM64 release.

---

## 📄 Lisensi & Hak Cipta

Hak Cipta © 2026 **Rafi Mohamad Fauzi / FFM Project**. Seluruh hak cipta dilindungi undang-undang.
Pustaka pihak ketiga diatur berdasarkan lisensi masing-masing yang tercantum di [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
