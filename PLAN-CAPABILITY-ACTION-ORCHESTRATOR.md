# Rencana Implementasi Registry Capability dan Action Plan Orchestrator

## Tujuan

Meningkatkan asisten FFM dari interpreter yang terutama melakukan routing dan membuat draft dasar menjadi **agent orchestrator yang dapat merencanakan dan mengoperasikan aplikasi secara bertahap**. Agent menggunakan SLM Qwen2-VL lokal untuk memahami perintah, tetapi seluruh akses aplikasi berjalan melalui capability yang terdaftar dan tervalidasi.

Agent memiliki akses penuh pada level aplikasi FFM: dapat membaca page context, berpindah halaman, membaca data yang diizinkan, membuka form, mengisi draft, memeriksa hasil, dan menyiapkan workflow lintas halaman. Perubahan permanen tetap menunggu konfirmasi akhir pengguna.

## Kondisi awal dan batasan

Source sudah memiliki `FfmAssistantIntent`, interpreter model-first/fallback, 24 destination, page context pada halaman akar, handler destination di `main.dart`, draft/preview pada beberapa fitur, serta model manager Qwen2-VL offline. Namun registry capability seragam dan action plan lintas halaman belum menjadi kontrak runtime penuh.

Pekerjaan ini tidak mengubah model GGUF, tidak memasukkan model ke APK, tidak memberi SLM akses SQL mentah, tidak memberi agent akses root perangkat, dan tidak mengizinkan auto-save transaksi atau bypass PIN/validasi.

## Tahap pekerjaan

### 1. Audit kontrak data yang ada

Petakan field dan lifecycle `FfmAssistantIntent`, `FfmAssistantDraft`, `FfmAssistantPageContext`, queued intents, response mode, serta handler navigasi yang sudah ada. Tentukan field mana yang kompatibel dan mana yang perlu diperluas agar action plan dapat membawa plan ID, step ID, risk level, status, preview, dan hasil.

Hasil tahap ini adalah matriks kompatibilitas yang mencegah perubahan baru merusak routing, voice dedupe, draft transaksi, atau fallback rule-based.

### 2. Definisikan model Registry Capability

Buat kontrak capability yang memuat identifier stabil, label pengguna, kategori, parameter schema, prasyarat, tingkat risiko, apakah read-only, apakah dapat dieksekusi langsung, apakah menghasilkan draft, dan apakah wajib konfirmasi.

Kelompok awal capability:

| Kelompok | Contoh capability | Konfirmasi |
|---|---|---:|
| Navigasi | membuka Summary, Transactions, Budget, Analysis, Other Menu, dan seluruh submenu | Tidak |
| Baca | membaca saldo, transaksi, anggaran, aktivitas, target, utang/piutang, recurring, laporan | Tidak |
| Persiapan | membuka form, mengisi draft transaksi/aset/target/aktivitas/reminder/master data | Belum menyimpan; preview wajib |
| Eksekusi | menyimpan, memperbarui, mengarsipkan, menghapus, mengubah pengaturan sensitif | Ya, final confirmation |
| Model/setup | memeriksa status model, membuka download/import SLM, melihat diagnostik | Tidak untuk navigasi; aksi download/import tetap dipilih pengguna |

Registry harus menolak capability yang tidak dikenal dan harus dapat melaporkan alasan ketika sebuah fitur belum didukung.

### 3. Standarkan Page Context

Perluas page context agar setiap halaman menjelaskan destination, judul, tujuan, data yang sedang terlihat, filter/sort aktif, status loading/empty/error, capability yang tersedia pada kondisi tersebut, dan batas data yang boleh dikirim ke SLM.

Page context harus bersifat ringkas dan terstruktur. Data finansial yang tidak dibutuhkan tidak boleh otomatis dimasukkan ke prompt. Saat halaman tidak aktif atau context sudah kedaluwarsa, agent harus membaca ulang context sebelum menjalankan langkah berikutnya.

### 4. Definisikan Action Plan dan state machine

Action plan memiliki `planId`, intent ringkas, daftar langkah berurutan, capability, parameter tervalidasi, risk level, status setiap langkah, draft/preview, timestamp, dan hasil.

Status minimal:

`planned → inspecting → ready → running → awaiting_confirmation → executing → completed`

Status pembatalan dan kegagalan:

`cancelled`, `expired`, `failed`, dan `blocked`.

Navigasi serta pembacaan dapat berjalan langsung. Draft menghentikan plan pada `awaiting_confirmation`. Eksekusi final hanya boleh berjalan satu kali untuk `planId` yang telah dikonfirmasi. Konfirmasi ganda, response stale, atau plan yang sudah completed harus ditolak secara idempotent.

### 5. Hubungkan SLM ke planner secara terstruktur

Prompt SLM harus memberikan knowledge dasar FFM, page context yang relevan, daftar capability yang tersedia, aturan parameter, dan aturan keamanan. Output SLM harus divalidasi sebagai intent atau rencana terstruktur; teks bebas tidak boleh langsung dianggap sebagai perintah database.

Orchestrator memeriksa kelengkapan parameter, melakukan klarifikasi, memvalidasi tipe dan rentang, mencocokkan nama rekening/kategori secara lokal, lalu membentuk action plan. Jika SLM gagal atau model belum siap, fallback lokal tetap tersedia untuk alur terbatas dan status harus terlihat oleh pengguna.

### 6. Implementasikan adapter capability secara bertahap

Urutan implementasi adapter:

1. Navigasi seluruh destination dan submenu.
2. Pembacaan page context dan data read-only.
3. Draft transaksi pemasukan, pengeluaran, dan transfer.
4. Draft budget, target, aset, liability, receivable, activity, reminder, recurring, dan master data.
5. Preview yang seragam.
6. Final confirmation dan eksekusi capability.
7. Verifikasi hasil dan laporan.
8. Workflow lintas halaman.

Capability tidak boleh memanggil widget UI secara rapuh jika layanan/domain use case yang aman tersedia. Jika sebuah fitur hanya memiliki form UI dan belum memiliki adapter teruji, agent harus membuat draft atau membuka halaman, bukan mengklaim data sudah disimpan.

### 7. Rancang confirmation dan recovery

Preview akhir harus menyebut tindakan, objek yang terkena dampak, nilai sebelum/sesudah jika relevan, dan langkah yang akan dieksekusi. Tombol atau perintah konfirmasi, edit, dan batal harus menghasilkan transisi state yang jelas.

Jika langkah gagal sebelum konfirmasi, plan dapat dikoreksi atau dibatalkan. Jika gagal setelah sebagian eksekusi, agent wajib melaporkan langkah yang sudah berhasil dan yang gagal; tidak boleh mengatakan seluruh plan berhasil. Capability yang mendukung rollback harus menyatakan kontraknya secara eksplisit.

### 8. Integrasikan controlled learning setelah workflow stabil

Log yang disanitasi dapat digunakan untuk mengusulkan alias, preferensi, atau workflow. Hasil belajar tidak langsung mengubah registry atau aturan keamanan. Kandidat harus melalui review, approval, versioning, dan rollback. Registry capability tetap ditentukan oleh aplikasi, bukan dibuat bebas oleh SLM.

## Rencana pengujian

Unit test akan mencakup registry lookup, capability schema, parameter validation, risk classification, page-context expiry, action-plan serialization, state transitions, duplicate confirmation, idempotent execution, cancellation, stale response, unsupported capability, dan fallback saat SLM tidak tersedia.

Widget test akan mencakup tampilan plan, progress langkah, preview, confirmation, edit, cancel, status model, dan navigasi tanpa kehilangan session chat. Integration test akan menggunakan database in-memory untuk menguji baca data, pembuatan draft, confirmation, eksekusi satu kali, serta laporan hasil.

Security test akan memastikan SLM tidak dapat mengeksekusi SQL mentah, tidak ada final mutation tanpa confirmation, data sensitif tidak masuk context yang tidak diperlukan, dan capability yang tidak terdaftar tidak dapat dipanggil.

Sebelum fase release, akan dijalankan `dart format`, `flutter analyze lib test`, full `flutter test`, dan debug arm64-only. Tidak ada release build pada tahap implementasi ini.

## Kriteria selesai fase

Fase dianggap selesai jika agent memiliki registry capability terstruktur, page context mampu memberi capability yang tersedia, minimal alur navigasi-read-draft-preview-confirm-execute berjalan end-to-end untuk transaksi utama, action plan idempotent, fallback dan status model jelas, seluruh perubahan permanen melalui konfirmasi, dan seluruh test baru serta regression test lulus.

Fitur yang belum memiliki adapter tidak boleh disamarkan sebagai selesai. Daftar capability yang belum didukung harus didokumentasikan sebelum melanjutkan ke fase berikutnya.

## Risiko dan asumsi

1. Nama use case dan API domain yang ada mungkin berbeda antar fitur sehingga adapter harus mengikuti source aktual, bukan asumsi dari nama halaman.
2. Qwen2-VL belum tervalidasi inference end-to-end pada perangkat Android fisik; fase ini menguji kontrak dan runtime aplikasi, bukan membuktikan performa semua hardware.
3. Action plan multi-langkah dapat memerlukan perubahan pada callback navigasi global agar session dan plan tidak hilang saat berpindah halaman.
4. Operasi yang bersifat destruktif atau sensitif tetap memerlukan konfirmasi tambahan meskipun pengguna sebelumnya memberi instruksi umum.
5. Pengetahuan dasar FFM akan dipaketkan sebagai konteks internal; memori pengguna dan workflow hasil belajar tetap berada di SQLite/knowledge pack.
6. APK release tidak dibangun sampai kriteria fase ini, fase migrasi, UX, dan validasi akhir semuanya lulus.
