# Rencana Maksimalisasi FFM Offline Agent Orchestrator — Tanpa Build

## Tujuan utama

Mengembangkan FFM Offline Agent agar benar-benar berfungsi sebagai **asisten aplikasi**, bukan sekadar chatbot atau parser perintah. Agent harus mampu memahami bahasa alami, mengenali konteks aplikasi dan kebiasaan user, membaca halaman, merencanakan pekerjaan, mengoperasikan seluruh fitur FFM, dan memberikan saran yang relevan secara lokal.

Seluruh pekerjaan pada tahap ini dilakukan pada source code, database schema, contract, test, dan dokumentasi. **Tidak ada build APK debug maupun release, tidak ada signing, dan tidak ada proses packaging** sampai user memberikan perintah build secara eksplisit.

## Definisi “pintar” untuk FFM

“Pintar” tidak berarti agent bebas mengubah database atau bertindak tanpa kendali. Dalam konteks FFM, agent dianggap pintar jika dapat:

1. Memahami maksud dan konteks perintah yang tidak selalu memakai kata kunci persis.
2. Mengingat preferensi, alias, kebiasaan, dan koreksi user secara lokal setelah persetujuan.
3. Mengetahui halaman, data, form, dan capability aplikasi yang sedang tersedia.
4. Memecah perintah kompleks menjadi langkah yang logis dan berurutan.
5. Mengetahui informasi yang kurang, lalu bertanya secara tepat.
6. Memeriksa hasil setiap langkah dan memperbaiki rencana bila diperlukan.
7. Mengenali pola penggunaan user dan menawarkan bantuan proaktif yang relevan.
8. Tidak membuat transaksi atau perubahan permanen tanpa preview dan konfirmasi akhir.

## Prinsip arsitektur

| Komponen | Tanggung jawab |
|---|---|
| **Qwen2-VL lokal** | Pemahaman bahasa, analisis gambar, ekstraksi informasi, peringkasan, dan usulan rencana. |
| **Agent orchestrator FFM** | Menentukan tujuan, membaca context, memilih capability, mengurutkan langkah, mengelola state, dan memverifikasi hasil. |
| **Knowledge base FFM** | Pengetahuan tetap mengenai identitas aplikasi, fitur, istilah, alur transaksi, dan aturan kerja. |
| **User model lokal** | Profil, preferensi, alias, kebiasaan, koreksi, dan tingkat keyakinan yang dipelajari secara terkontrol. |
| **Capability registry** | Daftar aksi aplikasi yang sah, parameter, prasyarat, risiko, dan hasil yang dijanjikan. |
| **Local data layer** | SQLite/Drift untuk transaksi, agregasi, knowledge agent, user model, workflow, dan audit. |
| **Confirmation layer** | Preview, persetujuan akhir, idempotensi, dan perlindungan terhadap mutation ganda. |

SLM tidak diberi akses SQL mentah, tidak boleh memilih tabel secara bebas, tidak boleh menulis database secara langsung, dan tidak boleh mengubah aturan keamanan atau capability registry sendiri.

## Fase 1 — Kontrak perilaku agent

Definisikan state dan kontrak agent dari awal sampai akhir:

> **Observe → Understand → Plan → Ask → Prepare → Validate → Preview → Confirm → Execute → Verify → Explain → Learn candidate**

Setiap state memiliki input, output, kondisi transisi, timeout, error, dan aturan pembatalan. Agent tidak boleh melompat dari Understand langsung ke Execute untuk mutation.

Kontrak harus membedakan:

- pertanyaan umum;
- pembacaan data;
- navigasi;
- pembuatan draft;
- perubahan data;
- tindakan destruktif;
- permintaan yang memerlukan PIN atau konfirmasi;
- saran proaktif;
- pembelajaran user.

## Fase 2 — Knowledge base internal FFM

Ubah dokumen knowledge dasar menjadi sumber pengetahuan terstruktur yang dapat dipakai orchestrator dan SLM. Isinya mencakup nama dan tujuan FFM, model data, seluruh halaman, fungsi setiap menu, istilah finansial, jenis transaksi, field transaksi, urutan input, validasi, alur recurring, budget, target, utang/piutang, aset, activity, report, backup, privacy, dan offline mode.

Knowledge base juga harus menjelaskan alur setelah setiap tahap, misalnya setelah data ditemukan agent merangkum, setelah form lengkap agent membuat preview, setelah confirm agent mengeksekusi, setelah execute agent memverifikasi, dan setelah error agent melaporkan langkah yang gagal.

Knowledge base bersifat versioned dan read-only dari perspektif SLM. Perubahan terhadapnya dilakukan melalui pembaruan aplikasi, bukan pembelajaran bebas.

## Fase 3 — User model agar agent mengenal user

Buat model user lokal yang terpisah dari database transaksi mentah. Data yang dapat dipelajari setelah approval meliputi:

| Jenis pengetahuan | Contoh |
|---|---|
| Identitas panggilan | Nama panggilan yang user pilih. |
| Alias | “rekening utama” berarti rekening tertentu. |
| Preferensi | Kategori default atau format ringkasan. |
| Kebiasaan | Waktu atau pola pencatatan yang sering dilakukan. |
| Koreksi | Koreksi user terhadap interpretasi agent. |
| Konteks keluarga | Istilah anggota keluarga atau sumber pemasukan. |
| Gaya interaksi | Jawaban singkat, detail, suara, atau teks. |

Setiap memory memiliki source, scope, confidence, createdAt, updatedAt, approval status, version, dan rollback metadata. Informasi sensitif tidak boleh disimpan sebagai memory hanya karena muncul dalam percakapan; user harus dapat melihat, mengedit, menonaktifkan, dan menghapusnya.

## Fase 4 — Page context dan pemahaman situasional

Lengkapi seluruh halaman FFM dengan context dinamis. Context minimal berisi destination, tujuan halaman, data ringkas yang sedang terlihat, filter, item terpilih, form field, validation state, available capabilities, loading/error state, dan timestamp/version.

Agent harus dapat menjawab “apa yang sedang saya lihat?”, “apa yang bisa dilakukan di halaman ini?”, dan “langkah berikutnya apa?” tanpa menebak dari nama route saja.

Context harus diminimalkan sebelum dikirim ke SLM. Hanya data yang relevan dengan perintah yang boleh masuk ke prompt; PIN, token, dan data sensitif yang tidak diperlukan harus dikeluarkan.

## Fase 5 — Capability registry dan full app control

Seluruh fitur penting FFM harus memiliki capability nyata, bukan hanya label navigasi. Setiap capability harus memiliki schema parameter, resolver entity lokal, precondition, executor, result verifier, risk class, confirmation policy, dan idempotency key.

Prioritas adapter:

1. Baca dan cari Summary, Transactions, Accounts, Categories, Budget, dan Analysis.
2. Draft dan execute pemasukan, pengeluaran, transfer, serta recurring transaction.
3. Draft dan execute target, asset, liability, receivable, dan budget.
4. Data Utama, activity, reminders, reports, backup/restore, privacy, diagnostics, dan model setup.
5. Workflow lintas halaman dengan dependency dan hasil antar langkah.

Full access berarti agent boleh menggunakan seluruh capability yang terdaftar pada level aplikasi. Namun mutation, delete, dan perubahan sensitif tetap melalui final confirmation.

## Fase 6 — Planner dan executor multi-langkah

Action Plan harus menjadi state machine runtime, bukan hanya objek katalog. Plan memiliki planId, versi, intent, langkah, dependency, parameter, risk, preview, confirmation token, status, hasil, dan error.

Contoh alur:

> “Cari pengeluaran restoran bulan ini, rangkum, lalu siapkan transaksi baru dari struk.”

Agent harus melakukan read query, merangkum hasil, membaca gambar secara lokal, membuat draft, memvalidasi, lalu berhenti di preview. Jika user mengatakan confirm, executor menjalankan mutation sekali dan memverifikasi hasil.

Plan harus mendukung pause, resume, cancel, expiry, retry aman, partial failure, dan recovery. Tidak boleh ada duplicate execution jika callback, retry, atau response SLM datang dua kali.

## Fase 7 — SLM sebagai reasoning engine

SLM diberi system context yang terdiri dari knowledge base FFM, user memory yang relevan, page context, daftar capability aktif, dan schema output. SLM hanya mengusulkan intent atau plan terstruktur.

Orchestrator melakukan:

1. validasi schema;
2. validasi capability allowlist;
3. validasi entity lokal;
4. validasi parameter dan field wajib;
5. klasifikasi risiko;
6. pembuatan preview;
7. confirmation gate;
8. eksekusi dan verifikasi.

Jika SLM tidak tersedia, agent tetap dapat melakukan subset deterministic yang aman dan harus menyatakan mode aktual. Tidak ada cloud fallback.

## Fase 8 — Proaktif tetapi tetap terkendali

Agent dapat “mengerti tanpa disuruh” dalam arti **mengamati konteks aplikasi dan menawarkan bantuan**, bukan mengambil tindakan finansial sendiri.

Contoh bantuan proaktif yang aman:

- ketika user membuka halaman transaksi, menawarkan membaca filter atau merangkum periode;
- ketika recurring transaction mendekati tanggal, menampilkan pengingat lokal;
- ketika data anggaran menunjukkan pola, menawarkan analisis;
- ketika user berulang kali mengoreksi kategori, mengusulkan preference candidate;
- ketika model belum siap, menawarkan setup SLM tanpa mengunduh otomatis.

Saran proaktif harus memiliki opt-in/opt-out, frequency limit, alasan yang dapat dijelaskan, dan tidak boleh mengubah data. Notification background hanya dipakai jika user mengaktifkannya dan seluruh analisis tetap lokal.

## Fase 9 — Controlled learning berkelanjutan

Saat aplikasi idle, sistem boleh memproses log lokal yang telah disanitasi untuk menemukan pola. SLM dapat membantu mengelompokkan koreksi dan menyusun candidate memory atau candidate workflow.

Alur wajib:

> **Log lokal → analisis pola → candidate → preview alasan → user approval → validasi/replay → versioned activation → rollback tersedia**

Tidak boleh ada autonomous self-modification. Agent tidak boleh belajar untuk melewati confirmation, PIN, permission, atau validation. True fine-tuning bobot Qwen2-VL tidak termasuk fase ini.

## Fase 10 — Migrasi pengetahuan dan pengenalan user antarperangkat

Backup JSON harus memisahkan dan membawa:

- finance data;
- user profile dan preferences;
- approved memories;
- approved learning examples;
- approved workflows/skills;
- corrections dan aliases;
- unanswered questions;
- optional chat history;
- knowledge schema/version.

Import harus mendukung preview, validation, merge/replace, conflict resolution, status pending/rejected, dan rollback. Workflow yang belum disetujui tidak boleh aktif setelah restore.

Bundle SLM tetap dipindahkan terpisah melalui `.ffmbundle`. Agent tetap dapat memulihkan knowledge dasar dan user model meskipun model belum tersedia; setelah model diverifikasi, reasoning lokal dapat digunakan kembali.

## Fase 11 — UI pendukung agent

UI chat ditingkatkan setelah kontrak agent stabil. UI harus menunjukkan:

- agent sedang membaca, merencanakan, atau menunggu konfirmasi;
- langkah plan yang sedang berjalan;
- sumber jawaban: SLM lokal atau deterministic local capability;
- memory yang digunakan, tanpa menampilkan data sensitif berlebihan;
- candidate learning yang menunggu approval;
- preview mutation;
- hasil dan error per langkah;
- history persisten;
- gambar inline dengan thumbnail dan tampilan besar;
- tombol setup SLM yang jelas.

UI tidak boleh menyamarkan draft sebagai transaksi tersimpan atau membuat agent terlihat berhasil ketika langkah gagal.

## Fase 12 — Pengujian tanpa build

Sebelum user memerintahkan build, seluruh validasi berikut dijalankan tanpa packaging APK:

- unit test registry, schema, planner, state machine, confirmation, idempotency, retry, expiry, dan recovery;
- test knowledge base dan user memory scope/approval/rollback;
- test page context stale data dan minimization;
- test semua resolver entity lokal;
- integration test read → draft → preview → confirm → execute → verify dengan database in-memory;
- negative test SLM invalid output, unknown capability, SQL injection-like text, duplicate callback, dan stale response;
- test controlled learning candidate dan rejection;
- test JSON/Agent Knowledge Pack round-trip antar database;
- test chat history dan image metadata round-trip;
- full `flutter analyze` dan full `flutter test`;
- audit manual bahwa tidak ada key, model GGUF, atau data sensitif dalam source archive.

Tidak ada `flutter build`, Gradle assemble, signing, atau packaging pada fase ini.

## Kriteria selesai sebelum meminta build

Fokus agent dianggap selesai hanya jika:

1. Agent dapat menjelaskan dan membaca seluruh halaman penting FFM.
2. Agent dapat memilih capability dan membuat rencana multi-langkah.
3. Minimal seluruh domain prioritas memiliki read, draft, preview, execute, dan verify adapter.
4. Semua mutation berhenti pada konfirmasi akhir.
5. Duplicate confirmation dan duplicate execution ditolak.
6. Error dan partial failure dilaporkan secara jujur.
7. User model dan controlled learning dapat disetujui, diedit, dinonaktifkan, dihapus, dan di-rollback.
8. Knowledge agent dapat dipindahkan antarperangkat melalui JSON/Agent Knowledge Pack.
9. Proactive assistance memiliki opt-in/opt-out dan tidak melakukan mutation otomatis.
10. Full analyzer dan test suite lulus.
11. Tidak ada klaim inference perangkat nyata sebelum benar-benar diuji.
12. **Baru setelah semua poin di atas selesai, user dapat memberikan perintah terpisah untuk build.**

## Risiko terbuka

1. Tidak semua halaman mungkin memiliki use case/domain API yang seragam; adapter harus mengikuti API aktual.
2. Full app control dapat membutuhkan perubahan lintas banyak feature dan perlu dilakukan per-domain agar regresi mudah dilacak.
3. SLM lokal pada HP tertentu dapat lambat atau kekurangan RAM; orchestrator harus mendukung antrean serial, context pendek, dan fallback aman.
4. Pengenalan user harus dibatasi pada data yang disetujui dan tidak boleh berubah menjadi profiling tersembunyi.
5. Chat history dapat mengandung data finansial sensitif; ekspor perlu pilihan jelas dan proteksi yang memadai.
6. “Belajar sendiri” tetap dibatasi menjadi analisis lokal dan candidate generation; agent tidak boleh mengubah dirinya sendiri tanpa approval.
7. Tidak ada build atau APK release pada rencana ini sampai user memerintahkan tahap tersebut secara eksplisit.
