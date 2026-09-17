# FFM - Rencana Asisten Anggaran Cerdas dan Otonom

> Dibuat: 2026-09-17
> Status: PLANNED
> Pemilik: `features/assistant` + `features/budget`
> Sumber progres: dokumen ini untuk kemampuan intelligence Anggaran. Kontrak
> create/update/archive dasar tetap mengikuti Phase 4 di
> `docs/assistant_draft_database_ui_audit_plan.md`; jangan menduplikasi atau
> melewati checklist yang belum selesai di sana.

## Tujuan Produk

Asisten harus mampu memahami dan menyelesaikan permintaan anggaran dalam Bahasa
Indonesia berdasarkan data keuangan yang otoritatif, misalnya:

- "Bagaimana kondisi anggaran saya minggu ini?"
- "Pos mana yang berisiko melebihi batas bulan ini?"
- "Tolong atur anggaran bulanan dan mingguan sesuai kebiasaan saya."
- "Naikkan anggaran makan berdasarkan pengeluaran tiga bulan terakhir."
- "Seimbangkan anggaran yang defisit, tapi tunjukkan dulu dampaknya."

Angka, status, prediksi, dan rekomendasi plafon dihitung secara deterministik
dari database FFM. Gemini hanya memahami bahasa pengguna, memilih capability
yang diizinkan, dan menjelaskan fakta yang dikembalikan aplikasi.

## Batas Keselamatan Wajib

- [ ] Semua pembacaan dan perhitungan dibatasi `householdId`, periode, dan data
  minimum yang diperlukan.
- [ ] Model tidak menerima SQL bebas, data rekening mentah, token, atau rahasia.
- [ ] Pembuatan, perubahan, pengarsipan, dan transfer alokasi selalu melalui
  draft -> validator -> preview -> konfirmasi -> executor -> verifier.
- [ ] Secara default, insight otonom hanya membuat notifikasi, recommendation,
  atau draft siap tinjau. Mutasi plafon tanpa konfirmasi per tindakan hanya
  boleh berjalan setelah pengguna memberi delegasi Anggaran yang eksplisit,
  terbatas, dan dapat dicabut.
- [ ] Delegasi otonom wajib menyimpan snapshot sebelum/sesudah, evidence aturan,
  ID job/idempotency, waktu, dan alasan yang dapat ditinjau pengguna.
- [ ] Pengguna dapat membatalkan delegasi serta meminta undo dari riwayat;
  undo hanya boleh mengembalikan state bila pos belum diubah lagi sejak aksi
  otonom, selain itu harus menjadi draft resolusi konflik.
- [ ] Eksekusi batch menggunakan idempotency key collision-safe dan memiliki
  hasil per-pos untuk recovery kegagalan parsial.
- [ ] Koreksi active draft pada mode `geminiCloud` tetap melalui `draftReview`;
  mode Agent boleh memakai revision deterministic yang sudah ada.

## Baseline Terkonfirmasi

- [x] Asisten dapat membuka halaman Anggaran dan membaca daftar anggaran aktif.
- [x] Asisten dapat membuat draft anggaran, mengubah nominal satu pos tertentu,
  serta mengarsipkan satu pos dengan guard.
- [x] Detector rebalance telah dapat menemukan kandidat surplus/defisit dan
  mengirim rekomendasi ke Kotak Masuk Agen.
- [x] `read.budget` mengembalikan realisasi, sisa, persentase, status, dan
  filter periode/kategori/ID pos untuk anggaran aktif pada periode berjalan.
- [ ] Asisten belum dapat membuat paket anggaran mingguan/bulanan berdasarkan
  kebiasaan pengeluaran pengguna.
- [ ] Asisten belum dapat mengubah atribut anggaran selain nominal plafon.
- [ ] Rebalance belum dapat disetujui dan dieksekusi sebagai action plan dari
  percakapan asisten.
- [ ] Halaman Anggaran belum menjadi permukaan utama untuk insight dan review
  rekomendasi otonom.

## Urutan Implementasi

Setiap checkbox hanya boleh ditandai selesai setelah kode, test relevan, dan
validasi yang disebut pada fase tersebut lulus. Jangan mulai fase mutasi paket
sebelum snapshot dan analisis deterministik dapat dibuktikan benar.

### Fase 0 - Audit Kontrak dan Baseline

- [ ] Baca Phase 4 pada `docs/assistant_draft_database_ui_audit_plan.md` dan
  tandai dependency create/update/archive yang masih belum selesai.
- [ ] Audit `EnvelopeBudgets`, repository, kalkulasi pemakaian, transfer
  alokasi, rollover, alert, dan halaman `budget_page.dart` sebagai sumber
  kontrak canonical.
- [ ] Inventarisasi semua periode yang didukung domain, termasuk weekly,
  biweekly, monthly, bimonthly, dan nonrecurring, beserta aturan tanggalnya.
- [ ] Tetapkan kontrak DTO immutable untuk snapshot, analisis kebiasaan,
  rekomendasi, dan paket proposal tanpa membuat framework asisten kedua.
- [ ] Catat keputusan arsitektur dan alasan di bagian Log Keputusan dokumen ini.
- [ ] Tambahkan fixture database sintetis: tanpa anggaran, pos tunggal,
  multi-kategori, rollover, periode lintas bulan, dan data transaksi ambigu.

Kriteria selesai:

- [ ] Tidak ada field UI/database anggaran yang hilang dari kontrak target.
- [ ] Semua angka target memiliki definisi formula yang terdokumentasi.
- [ ] Baseline test khusus anggaran dan analyzer modul terkait lulus.

### Fase 1 - Snapshot Anggaran Otoritatif

- [x] Buat service/query deterministic tunggal untuk menghitung snapshot per
  pos dan agregat; jangan menghitung ulang dengan formula berbeda di widget,
  adapter, atau Gemini context.
- [x] Hitung plafon, realisasi expense yang cocok, sisa, persentase pemakaian,
  status aman/peringatan/over-budget, dan jumlah hari tersisa untuk periode
  aktif.
- [ ] Tentukan dan uji aturan transaksi yang masuk ke pos: kategori tunggal,
  kategori gabungan, transaksi terarah `budgetId`, transaksi sebelum/sesudah
  rentang periode, pembatalan, dan transfer yang bukan pengeluaran.
- [x] Terapkan rollover sesuai kontrak repository/domain yang ada dan jelaskan
  nilainya pada snapshot tanpa mengubah saldo/plafon.
- [x] Dukung filter `period`, `category`, `budgetId`, dan batas hasil pada
  `read.budget`; tolak filter ambigu dengan respons yang dapat ditindaklanjuti.
- [x] Perbarui capability response menjadi data terstruktur/bounded untuk
  orchestrator dan ringkasan yang aman untuk UI/Gemini.
- [ ] Hentikan fallback context yang sengaja melewati data anggaran bila jalur
  tersebut masih digunakan; gunakan snapshot bounded, bukan dump tabel.

Kriteria selesai:

- [ ] Hasil snapshot sama dengan perhitungan repository/halaman untuk fixture
  yang sama.
- [ ] Pertanyaan "sisa anggaran", "berapa persen terpakai", dan "pos mana
  over-budget" menjawab dengan angka deterministik.
- [ ] Test unit formula dan integration test Drift untuk seluruh edge case lulus.

### Fase 2 - Analisis Kebiasaan dan Prediksi Deterministik

- [x] Buat `BudgetHabitAnalyzer` read-only untuk median pengeluaran kategori,
  tren, pembulatan rekomendasi, dan kecukupan minimal dua bulan aktif.
- [ ] Buat `BudgetHabitAnalysisService` di domain/repository yang memakai 4-12
  periode historis sesuai preferensi pengguna atau default yang terdokumentasi.
- [ ] Hitung median dan rata-rata pengeluaran kategori, frekuensi transaksi,
  tren, volatilitas, dan kecukupan data.
- [ ] Gunakan median sebagai baseline rekomendasi ketika terdapat outlier;
  simpan alasan pemilihan metode pada hasil analisis.
- [ ] Hitung laju belanja dan proyeksi akhir periode dari hari berjalan,
  pengeluaran terakumulasi, dan kalender periode. Tandai proyeksi sebagai
  estimasi, bukan fakta transaksi.
- [ ] Tambahkan buffer konfigurabel, misalnya konservatif, seimbang, atau
  fleksibel; nilai rekomendasi tetap dibulatkan dengan aturan rupiah yang
  konsisten.
- [ ] Tandai kategori yang datanya tidak cukup, terlalu tidak stabil, atau belum
  memiliki anggaran; asisten harus meminta/menawarkan pilihan, bukan mengarang.
- [ ] Pastikan analisis tidak memasukkan pemasukan, transfer, transaksi arsip,
  atau transaksi dari household lain.

Kriteria selesai:

- [ ] Analisis yang sama pada database dan waktu acuan yang sama menghasilkan
  rekomendasi yang sama.
- [ ] Outlier tunggal tidak mendominasi rekomendasi tanpa alasan yang terlihat.
- [ ] Prediksi dan rekomendasi menyertakan basis periode, jumlah data, serta
  peringatan keterbatasan data.

### Fase 3 - Pemahaman Bahasa dan Proposal Anggaran Berdasarkan Kebiasaan

- [ ] Tambahkan intent/routing untuk "atur sesuai kebiasaan", "sarankan
  anggaran", "anggaran mingguan", "anggaran bulanan", serta variasi Bahasa
  Indonesia yang umum pada interpreter dan Gemini orchestrator.
- [ ] Gunakan `read.budget`, transaksi bounded, dan service Fase 2 sebelum
  jawaban/proposal. Gemini tidak boleh menentukan nominal tanpa hasil analisis.
- [ ] Jika periode, rentang histori, buffer, atau cakupan kategori tidak jelas,
  ajukan satu pertanyaan klarifikasi yang paling bernilai.
- [ ] Buat proposal yang berisi pos baru, perubahan pos lama, pos yang sengaja
  tidak direkomendasikan, nominal lama/baru, dan alasan per pos.
- [ ] Sediakan perintah analisis saja, misalnya "sarankan dulu, jangan ubah",
  yang tidak membuat draft mutasi.
- [ ] Sediakan revision percakapan: "makan jadikan 900 ribu", "jangan masukkan
  hiburan", "gunakan buffer hemat", dan "batalkan proposal".
- [ ] Tambahkan prompt fixture Gemini dan test schema untuk output proposal
  valid, invalid, ambigu, serta refusal ketika data tidak cukup.

Kriteria selesai:

- [ ] Contoh perintah tujuan menghasilkan proposal yang grounded atau
  klarifikasi, tidak pernah jawaban nominal imajinatif.
- [ ] Proposal tetap berfungsi offline pada jalur deterministic yang tersedia;
  tidak menjanjikan percakapan LLM offline.
- [ ] Active-draft revision mengikuti mode routing yang diwajibkan proyek.

### Fase 4 - Draft Paket, Preview, dan Eksekusi Aman

- [ ] Tambahkan jenis draft/payload paket anggaran tanpa mematahkan draft satu
  pos yang telah ada.
- [ ] Definisikan operasi tiap item: create, update, archive, activate, atau
  tidak diubah; tiap item membawa reference ID canonical yang telah di-resolve.
- [ ] Validator memeriksa nama duplikat, kategori aktif, periode valid, nilai
  positif, konflik kategori/periode, budget gabungan, dan batas kebijakan total
  alokasi bila domain menyediakannya.
- [ ] Preview menampilkan perubahan per pos, alasan rekomendasi, total sebelum
  dan sesudah, status realisasi, serta warning yang tidak dapat disetujui diam-
  diam.
- [ ] Pengguna dapat menyetujui semua, menghapus item, mengedit item, atau
  membatalkan tanpa ada mutasi prematur.
- [ ] Executor menjalankan batch atomik bila kontrak database memungkinkannya;
  jika tidak, simpan outcome per item dan recovery yang jelas.
- [ ] Verifier membaca kembali setiap row, relasi kategori, rentang periode, dan
  snapshot setelah mutasi.
- [ ] Terapkan idempotency untuk retry action plan dan tolak reuse key dengan
  payload berbeda.

Kriteria selesai:

- [ ] "Atur anggaran mingguan dan bulanan sesuai kebiasaan saya" dapat menjadi
  preview paket yang lengkap dan hanya tersimpan setelah konfirmasi eksplisit.
- [ ] Gagal pada satu item tidak menghasilkan klaim sukses palsu.
- [ ] Test integration mencakup retry, cancel, partial failure, dan readback.

### Fase 5 - Mutasi Satu Pos dan Rebalance Lengkap

- [ ] Perluas update anggaran untuk nama, kategori tunggal/gabungan, periode,
  tanggal, rollover, dan ambang alert, sesuai field yang benar-benar didukung
  form/database.
- [ ] Pertahankan guard untuk target ambigu, pos total, pos nonrutin, pos di luar
  periode, transaksi pemakaian, dan transfer alokasi; ubah guard hanya setelah
  aturan bisnisnya ditentukan dan diuji.
- [ ] Ubah rekomendasi rebalance menjadi action plan yang membawa sumber, tujuan,
  nominal, bukti surplus/defisit, dan dampak snapshot sebelum/sesudah.
- [ ] Rebalance dari chat maupun Kotak Masuk Agen harus memakai executor dan
  verifier yang sama.
- [ ] Tambahkan confirmation policy eksplisit untuk semua pergeseran alokasi.
- [ ] Audit agar perubahan plafon tidak memodifikasi transaksi historis.

Kriteria selesai:

- [ ] Semua mutasi yang diekspos preview dapat diverifikasi kembali dari DB.
- [ ] Rebalance tidak dapat dijalankan tanpa persetujuan pengguna.
- [ ] Pos yang tidak memenuhi guard menghasilkan alasan dan langkah pemulihan.

### Fase 6 - Monitoring Otonom Terhubung ke Halaman Anggaran

- [ ] Reuse `AutonomousEvaluationCoordinator`, monitoring job, delivery policy,
  dan detector yang ada; jangan membuat scheduler atau agent paralel.
- [ ] Tambahkan detector laju belanja mingguan dan bulanan terhadap snapshot
  aktual dan proyeksi akhir periode.
- [ ] Tambahkan detector lonjakan kategori terhadap baseline kebiasaan dan
  detector kategori rutin besar yang belum memiliki pos anggaran.
- [ ] Tambahkan detector rekomendasi plafon periode berikutnya, dengan cooldown,
  deduplikasi, quiet hours, batas harian, dan prioritas delivery yang ada.
- [ ] Simpan evidence terstruktur minimum agar insight dapat dijelaskan tanpa
  menyimpan detail transaksi sensitif yang tidak diperlukan.
- [ ] Kirim insight ke Kotak Masuk Agen dan tampilkan ringkasan relevan pada
  halaman Anggaran.
- [ ] Tambahkan pengaturan delegasi per jenis aksi: rekomendasi saja, buat draft,
  atau sesuaikan plafon otomatis. Default adalah rekomendasi saja.
- [ ] Delegasi penyesuaian otomatis membatasi periode, kategori/pos, nilai
  minimum/maksimum, perubahan maksimum per periode, buffer, dan cooldown.
- [ ] Mutasi otonom hanya boleh mengubah plafon pada pos yang telah diizinkan;
  arsip, kategori/periode/tanggal, dan transfer alokasi tetap memerlukan
  konfirmasi eksplisit sampai ada kebijakan terpisah yang tervalidasi.
- [ ] Insight menyediakan tindakan "lihat bukti", "buat draft", "tunda",
  "undo", atau "matikan delegasi". Setiap mutasi otomatis juga tercatat pada
  riwayat Anggaran dan Kotak Masuk Agen.
- [ ] Evaluasi ulang setelah transaksi baru, perubahan anggaran, pergantian
  periode, dan perubahan household secara idempotent.

Kriteria selesai:

- [ ] Pengguna mendapat peringatan sebelum prediksi over-budget bila data cukup.
- [ ] Insight duplikat tidak muncul berulang pada kondisi yang sama.
- [ ] Menyetujui monitoring tidak memberikan otorisasi mutasi anggaran masa
  depan.

### Fase 7 - UX Halaman Anggaran dan Transparansi

- [ ] Muat skill UI/UX yang relevan sebelum mengubah UI halaman Anggaran.
- [ ] Tambahkan ringkasan kondisi minggu/bulan: realisasi, sisa, status, dan
  prediksi dengan label fakta vs estimasi yang jelas.
- [ ] Tambahkan area rekomendasi asisten yang dapat menjelaskan dasar data dan
  membuka preview paket, bukan mengubah data langsung.
- [ ] Tambahkan tindakan cepat: "Buat dari kebiasaan", "Tinjau risiko",
  "Seimbangkan pos", dan "Tanya asisten tentang halaman ini".
- [ ] Pastikan halaman responsif Android ponsel kecil, aksesibel, dan tidak
  menyembunyikan status/error jaringan atau data kosong.
- [ ] Tampilkan metadata aman: data sampai tanggal berapa, periode analisis,
  provider bila digunakan, dan status draft. Jangan tampilkan chain-of-thought.

Kriteria selesai:

- [ ] Pengguna dapat memahami alasan rekomendasi tanpa membaca chat panjang.
- [ ] Semua CTA mutasi membuka preview/konfirmasi yang sama dengan chat.
- [ ] Widget test mencakup loading, data kosong, error, recommendation, dan
  preview entry point.

### Fase 8 - Validasi Rilis

- [ ] Tambahkan unit test untuk snapshot, period boundary, rollover, proyeksi,
  outlier, pembulatan, dan kecukupan data.
- [ ] Tambahkan test interpreter/orchestrator untuk permintaan kebiasaan,
  klarifikasi, data tidak cukup, revision, dan cancellation.
- [ ] Tambahkan test capability/planner/validator/executor/verifier untuk paket,
  batch, idempotency, dan rebalance.
- [ ] Tambahkan test autonomy untuk event trigger, cooldown, deduplikasi, quiet
  hours, household isolation, dan tidak adanya mutasi tanpa konfirmasi.
- [ ] Tambahkan UI/integration test halaman Anggaran dan Kotak Masuk Agen.
- [ ] Jalankan `flutter analyze lib test` tanpa issue.
- [ ] Jalankan `flutter test` penuh tanpa kegagalan.
- [ ] Jalankan `flutter build apk --target-platform android-arm64 --release`.
- [ ] Verifikasi APK rilis hanya memuat ABI `arm64-v8a`.

## Matriks Perintah Acceptance

| Perintah pengguna | Hasil wajib |
| --- | --- |
| "Bagaimana anggaran saya minggu ini?" | Snapshot per pos dengan plafon, realisasi, sisa, status, dan periode. |
| "Pos mana yang akan jebol bulan ini?" | Proyeksi deterministik, evidence ringkas, dan disclaimer estimasi. |
| "Atur anggaran bulanan sesuai kebiasaan saya." | Analisis histori, klarifikasi bila perlu, lalu preview paket tanpa mutasi. |
| "Buat juga versi mingguan dengan buffer hemat." | Paket weekly terpisah dengan baseline, buffer, dan nominal per pos. |
| "Makan jadikan 900 ribu, hiburan jangan ikut." | Revision proposal; item lain tetap utuh dan belum disimpan. |
| "Setujui semua." | Validasi, eksekusi idempotent, verifier, dan ringkasan hasil per pos. |
| "Seimbangkan anggaran." | Kandidat/bukti rebalance dan preview; eksekusi hanya setelah konfirmasi. |
| "Pantau anggaran saya." | Monitoring job dengan cadence, cooldown, dan kontrol pengguna. |

## Log Keputusan

| Tanggal | Keputusan | Alasan |
| --- | --- | --- |
| 2026-09-17 | Mutasi Anggaran otonom memerlukan delegasi eksplisit, bukan konfirmasi per tindakan. | Pengguna meminta akses seperti pengingat, tetapi plafon finansial tetap memerlukan scope, batas nilai, audit, idempotensi, dan undo aman. |
| 2026-09-17 | Nominal rekomendasi berasal dari service deterministic, bukan Gemini. | Menjaga angka finansial tetap otoritatif, repeatable, dan dapat diuji. |
| 2026-09-17 | Paket anggaran memakai draft/action-plan yang ada. | Menghindari orchestrator, planner, atau executor paralel. |
| 2026-09-17 | `BudgetRepository.readSnapshots` menjadi sumber snapshot asisten. | Formula rollover/transfer/pemakaian yang sama dipakai oleh capability lokal dan digest Gemini. Integrasi halaman Anggaran tetap pekerjaan Fase 7. |

## Log Pekerjaan

| Tanggal | Langkah | Status | Bukti / Catatan |
| --- | --- | --- | --- |
| 2026-09-17 | Dokumen rencana dibuat | PLANNED | Baseline berasal dari inspeksi capability, adapter, interpreter, dan detector rebalance. |
| 2026-09-17 | Fase 1, increment snapshot | IN_PROGRESS | `read.budget` dan digest Gemini memakai snapshot deterministic; targeted test 22 lulus. |
| 2026-09-17 | Validasi increment snapshot | IN_PROGRESS | `flutter analyze lib test` lulus. `flutter test` berjalan sampai 1.339 test tanpa failure yang terlihat, tetapi runner menghentikannya pada batas waktu sebelum hasil akhir. |
| 2026-09-17 | Fase 2, increment analyzer | IN_PROGRESS | Analyzer kebiasaan deterministik dan perintah analisis read-only tersedia; test analyzer dan budget mutation targeted lulus. Proposal batch dan delegasi belum dibuat. |
| 2026-09-17 | Fase 3, integrasi Agent lokal proposal kebiasaan | IN_PROGRESS | Interpreter Agent mengenali perintah `atur` bulanan/mingguan sesuai kebiasaan, membangun `FfmAssistantBudgetHabitProposal` maksimal dua item dari `BudgetHabitAnalyzer`, lalu menyertakan `FfmAssistantActionPlanner.planBudgetHabitProposal` yang confirmation-gated pada metadata. Analisis eksplisit/read-only tidak membuat proposal atau plan. Tidak ada mutasi/persistensi. Konsumen UI/executor batch belum diubah pada increment ini karena draft global hanya satu item. |

## Definition of Done

- [ ] Asisten dapat menjawab kondisi Anggaran dengan angka snapshot yang benar.
- [ ] Asisten dapat membuat rekomendasi mingguan/bulanan berdasarkan kebiasaan
  dengan dasar data yang terlihat dan peringatan data tidak cukup.
- [ ] Pengguna dapat merevisi dan menyetujui paket anggaran secara aman.
- [ ] Monitoring otonom mendeteksi risiko/rekomendasi dan terhubung ke halaman
  Anggaran tanpa mutasi mandiri.
- [ ] Semua mutasi tervalidasi, terkonfirmasi, idempotent, dan terverifikasi.
- [ ] Analyzer, suite test penuh, dan build Android ARM64 lulus.
