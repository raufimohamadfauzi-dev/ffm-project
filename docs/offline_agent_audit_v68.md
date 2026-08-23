# Audit FFM Offline Agent v0.1.68

## Status audit

Audit ini mendokumentasikan kondisi source saat rencana Offline Agent disetujui. Audit tidak mengubah behavior aplikasi.

## Arsitektur yang sudah ada

FFM memiliki global assistant launcher dan satu `FfmAssistantChatSession` yang dimiliki `AppShell`. Session tersebut mempertahankan entry chat selama `AppShell` dan proses aplikasi masih hidup, tetapi belum merupakan riwayat chat persisten.

`FfmAssistantSheet` meneruskan teks dan gambar ke `FfmAssistantInterpreter`. Interpreter telah memiliki jalur model-first dengan guard deterministik dan fallback aturan lokal. SLM Qwen2-VL tetap berjalan melalui local model gateway/native bridge, tanpa akses mentah ke database atau fungsi CRUD.

`FfmAssistantIntent` sudah membedakan respons `localModel` dan `localRules`, membawa destination, draft, clarification, teaching proposal, dan respons. Draft dapat divalidasi dan diarahkan ke halaman form. Perubahan finansial tetap mengikuti preview/konfirmasi yang tersedia.

`FfmAssistantPageContext` telah dipasang pada halaman akar yang diaudit. Context ini menjadi fondasi pembacaan halaman, tetapi belum sama dengan registry capability lengkap yang dapat membaca semua kontrol dan menjalankan rangkaian aksi lintas halaman.

Repository assistant sudah memisahkan memori/ajaran yang disetujui dan pertanyaan yang belum terjawab dari transaksi. Data ini adalah knowledge dinamis, bukan kode orchestrator dan bukan bobot SLM.

Model manager mendukung download terverifikasi dan `.ffmbundle` offline. Model tidak dibundel ke APK atau source archive. APK v0.1.68 telah dibangun arm64-only dan diverifikasi hanya mengandung ABI `arm64-v8a`.

## Keputusan arsitektur yang dibekukan

Agent orchestrator menjadi pengendali pekerjaan FFM. SLM Qwen2-VL menjadi reasoning engine bahasa/visi lokal. Agent boleh mengakses seluruh capability aplikasi yang terdaftar pada level aplikasi, tetapi perubahan final yang permanen harus menunggu konfirmasi pengguna.

Akses penuh tidak berarti akses root atau akses bebas ke perangkat Android. Capability harus tetap tunduk pada permission Android, PIN, validasi, kebijakan privasi, dan status aplikasi.

Agent harus dapat membaca konteks halaman, berpindah halaman, mencari data, membuka form, mengisi draft, memeriksa hasil, menjalankan workflow lintas halaman, serta melaporkan kegagalan. “Membuat halaman” ditafsirkan sebagai membuka halaman yang sudah tersedia dan membuat data/draft di dalamnya; pembuatan struktur halaman aplikasi baru tetap merupakan pekerjaan pengembangan, bukan aksi runtime agent.

Pengetahuan dasar tentang FFM harus tersedia sejak awal. Pengetahuan tersebut mencakup identitas aplikasi, fungsi, halaman, istilah, workflow transaksi, urutan kerja, aturan validasi, dan prosedur konfirmasi. Pengetahuan pengguna, memori, alias, koreksi, dan workflow hasil belajar disimpan terpisah.

Pembelajaran background boleh menganalisis data lokal dan membuat kandidat knowledge/skill, tetapi kandidat harus dapat ditinjau, disetujui, diberi versi, dan di-rollback. Agent tidak boleh belajar untuk melewati konfirmasi, PIN, validasi, permission, atau batas keamanan.

Migrasi harus memisahkan finance data, agent knowledge, chat history, dan SLM bundle. JSON transaksi saja tidak cukup untuk memulihkan pemahaman personal agent.

## Matriks kondisi dan gap

| Area | Kondisi saat ini | Gap menuju Offline Agent penuh | Prioritas |
|---|---|---|---:|
| SLM lokal | Gateway/model manager/native bridge tersedia; model-first sudah ada | Perlu kontrak reasoning/action plan yang lebih eksplisit | Tinggi |
| Orchestrator | Interpreter dan handler destination tersedia | Belum menjadi planner capability lintas halaman yang seragam | Tinggi |
| Navigasi | 24 destination dan page context akar sudah dipetakan | Sebagian handler hanya membuka halaman; belum seluruhnya membaca/menjalankan kontrol halaman | Tinggi |
| Data read | Beberapa query/fitur khusus tersedia | Perlu registry capability read yang konsisten dan aman | Tinggi |
| Draft | Draft transaksi dan preview sudah tersedia pada jalur tertentu | Perlu standar draft lintas fitur dan status plan | Tinggi |
| Konfirmasi | Ada alur konfirmasi untuk draft/aktivitas | Perlu satu confirmation protocol untuk rangkaian aksi | Tinggi |
| Learning | Memori/contoh/pertanyaan tersimpan lokal setelah persetujuan | Belum ada autonomous observation-to-candidate loop yang tervalidasi | Sedang |
| Migrasi | Backup FFM dan bundle model tersedia secara terpisah | Agent knowledge pack dan schema versioning perlu ditetapkan | Tinggi |
| Chat history | Hidup dalam memory session | Belum persisten dengan retensi/hapus/ekspor | Sedang |
| Gambar chat | Diproses melalui imagePath | Belum tampil sebagai thumbnail/media card di entry chat | Sedang |
| Status SLM | Chip dan CTA download/import sudah tersedia | Perlu status agent plan/action yang lebih rinci | Sedang |
| ABI release | APK v0.1.68 arm64-only | Device inference/runtime belum tervalidasi | Tinggi |

## Batas klaim saat ini

Source saat ini sudah memiliki fondasi agent lokal, tetapi belum boleh diklaim sebagai agent yang dapat mengoperasikan seluruh aplikasi secara bebas dan seragam. Build membuktikan compile, link, packaging, dan signature; build tidak membuktikan inference Android end-to-end, lifecycle, latency, temperatur, atau penggunaan RAM pada perangkat.

## Urutan desain setelah audit

Tahap berikutnya adalah menyusun kontrak pengetahuan dasar FFM dan action plan agent. Setelah itu registry capability dan page context akan dirancang berdasarkan kontrak tersebut. Implementasi behavior baru dilakukan setelah kontrak dan matriks akses disetujui melalui checkpoint fase terkait.
