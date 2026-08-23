# Rencana Peningkatan Agent Orchestrator FFM

## Tujuan

Meningkatkan Agent Orchestrator agar tidak sekadar selalu memberikan jawaban, tetapi selalu menghasilkan respons yang **logis, relevan, transparan, berbasis data lokal bila tersedia, dan aman untuk ditindaklanjuti**. Agen harus mampu memahami pertanyaan pengguna, menentukan apakah data FFM diperlukan, membaca agregat yang aman dari database, membedakan fakta dari estimasi, mengajukan klarifikasi jika informasi penting belum ada, serta memberikan saran finansial keluarga yang sesuai dengan konteks FFM.

Peningkatan ini dilakukan sepenuhnya offline pada runtime aplikasi. Tidak ada cloud fallback, pengiriman raw database ke SLM, autosave, atau build APK/debug/release/signing pada fase ini.

## Prinsip keputusan agen

Setiap pertanyaan akan melewati urutan berikut:

1. **Deteksi domain dan maksud.** Agen membedakan perintah aplikasi, pertanyaan data FFM, literasi/manajemen keuangan keluarga, dan topik di luar domain.
2. **Tentukan kebutuhan data.** Pertanyaan faktual atau rekomendasi personal seperti kemampuan cicilan, kondisi cashflow, target tabungan, atau penghematan harus memicu pembacaan agregat lokal. Pertanyaan edukasi umum dapat dijawab tanpa database.
3. **Ambil data paling minimal.** Orkestrator hanya mengambil ringkasan terstruktur—periode, pemasukan, pengeluaran, cicilan aktif, target, aset kas, dan indikator kualitas data—bukan raw rows atau seluruh isi database.
4. **Validasi kecukupan dan kualitas data.** Agen memeriksa apakah periode cukup, apakah pemasukan/pengeluaran kosong, apakah transaksi berulang atau transfer berpotensi terhitung ganda, dan apakah kewajiban aktif memiliki cicilan bulanan.
5. **Hitung dengan kode lokal.** Rasio, cashflow, ruang cicilan, target tabungan, dan skenario konservatif dihitung deterministik oleh aplikasi. SLM tidak menjadi sumber angka utama.
6. **Gunakan SLM sebagai penalaran dan narasi terkontrol.** SLM menerima ringkasan aman, asumsi, batasan, serta hasil kalkulasi; outputnya harus terstruktur dan divalidasi sebelum ditampilkan.
7. **Berikan saran bertingkat.** Respons memuat kesimpulan singkat, angka/fakta, alasan, risiko, asumsi, dan langkah berikutnya yang bersifat read-only atau navigasi. Mutation tetap melalui draft → preview → konfirmasi → execute sekali → verify.
8. **Jujur saat tidak tahu.** Jika data kurang, agen menyatakan data yang hilang, memberikan jawaban edukatif yang masuk akal tanpa mengarang kondisi pengguna, lalu meminta data atau menawarkan halaman FFM yang relevan.

## Fase implementasi

### Fase 1 — Reasoning contract dan kualitas data

Membuat model domain untuk `FfmAssistantEvidence`, `FfmAssistantDataQuality`, `FfmAssistantRecommendation`, `FfmAssistantAssumption`, `FfmAssistantRisk`, dan `FfmAssistantNextAction`. Kontrak ini akan membedakan:

| Jenis hasil | Sumber | Perlakuan |
|---|---|---|
| Fakta angka | Agregator database lokal | Ditampilkan sebagai data aktual dengan periode jelas |
| Perhitungan | Fungsi deterministik aplikasi | Menampilkan formula/threshold yang digunakan |
| Insight | SLM atau rule lokal | Harus merujuk fakta dan tidak boleh mengubah angka |
| Edukasi | Knowledge registry/rule/SLM | Boleh tanpa data pribadi, tetapi dikaitkan ke FFM bila relevan |
| Rekomendasi | Rule konservatif + narasi SLM | Memuat risiko, asumsi, dan confidence |
| Next action | Navigasi/read-only | Tidak langsung menyimpan atau mengubah transaksi |

Menentukan status kualitas data minimal: `sufficient`, `partial`, `empty`, `staleOrInsufficientPeriod`, dan `conflicting`. Agen tidak boleh menyebutkan rekomendasi personal sebagai pasti jika status bukan `sufficient`.

### Fase 2 — Data context dan analisis finansial lokal

Memperluas agregator read-only agar dapat menghitung secara konsisten:

- pemasukan dan pengeluaran bulan berjalan serta rata-rata beberapa bulan bila tersedia;
- cashflow bersih dan rasio pengeluaran terhadap pemasukan;
- cicilan aktif, saldo kewajiban, dan ruang cicilan konservatif;
- target tabungan dan kontribusi yang masih dibutuhkan;
- aset kas/dana darurat bila tersedia;
- recurring income/expense dan indikator transaksi tidak rutin;
- piutang yang diharapkan, dengan perlakuan konservatif agar tidak dianggap sebagai kas pasti;
- indikator data kosong, periode terlalu pendek, dan anomali.

Untuk kemampuan pinjaman, hasil lokal minimal memuat pemasukan, pengeluaran, cicilan berjalan, cashflow setelah cicilan, batas cicilan konservatif, ruang cicilan baru, dan peringatan bila cashflow negatif atau data belum memadai. Threshold 30% digunakan sebagai default konservatif yang dapat dijelaskan, bukan sebagai persetujuan kredit dan bukan jaminan dari lembaga pemberi pinjaman.

Analisis skenario akan dipisahkan dari keputusan final: pengguna dapat menanyakan simulasi nominal pinjaman, tenor, dan cicilan, tetapi agen hanya menghitung skenario yang diberikan atau meminta parameter yang hilang. Agen tidak mengarang bunga, biaya, tenor, atau kelayakan bank.

### Fase 3 — Router intent dan SLM terstruktur

Menambah routing intent/handler untuk pertanyaan `financialAdvice`, atau memakai `help/queryData` dengan metadata recommendation yang eksplisit bila perubahan enum tidak diperlukan. Router harus:

- memprioritaskan guard deterministik untuk pertanyaan yang jelas;
- memblokir topik benar-benar tidak terkait;
- mengizinkan literasi keuangan keluarga dan menghubungkannya ke fitur FFM;
- memilih `read-only financial analysis` sebelum SLM untuk pertanyaan berbasis kondisi pengguna;
- meminta klarifikasi terarah untuk periode, nominal, tujuan, atau parameter yang hilang;
- tidak menganggap jawaban SLM yang bebas sebagai fakta database.

Proposal SLM akan diperketat dengan schema terstruktur yang berisi `intent`, `answerStyle`, `dataNeeded`, `claims`, `calculationsToExplain`, `risks`, `assumptions`, `clarificationQuestion`, dan `nextActions`. Validator lokal menolak output yang memasukkan angka yang tidak ada pada evidence, menyatakan persetujuan pinjaman, atau menyarankan mutation tanpa confirmation.

SLM digunakan untuk memahami variasi bahasa, menyusun penjelasan, membandingkan skenario yang sudah dihitung lokal, dan memberi narasi. Semua angka dan status database tetap berasal dari aggregator/rule engine lokal.

### Fase 4 — Recommendation engine dan pengalaman chat

Menghubungkan recommendation engine ke query adapter dan chat UI. Format jawaban yang ditargetkan:

1. **Kesimpulan:** misalnya ruang cicilan konservatif atau kondisi cashflow.
2. **Dasar:** periode data, pemasukan, pengeluaran, cicilan, dan formula yang digunakan.
3. **Saran:** langkah yang paling masuk akal, misalnya menunda pinjaman, menurunkan pengeluaran, mengisi data, atau meninjau target.
4. **Risiko dan asumsi:** data belum lengkap, pemasukan tidak rutin, piutang belum tentu tertagih, bunga/biaya pinjaman belum diketahui.
5. **Langkah berikutnya:** buka Ringkasan, Anggaran, Goals, Liabilities, atau buat simulasi—semuanya read-only kecuali pengguna memilih mutation dan melewati confirmation gate.

Saran proaktif tetap hanya muncul dari fakta yang telah dihitung lokal, dapat disembunyikan/dismiss, memiliki expiry, dan tidak menjalankan perubahan otomatis. Riwayat percakapan tidak dipakai sebagai fakta finansial tanpa persetujuan dan tanpa evidence database.

### Fase 5 — Validasi, dokumentasi, dan arsip source

Menambahkan pengujian untuk:

- database kosong: jawaban edukatif tanpa angka palsu;
- hanya pemasukan: ruang cicilan dihitung tetapi keterbatasan pengeluaran dinyatakan;
- pemasukan dan pengeluaran: cashflow serta rasio benar;
- cicilan aktif: cicilan lama mengurangi ruang cicilan baru;
- cashflow negatif atau rasio tinggi: rekomendasi menunda pinjaman;
- transaksi transfer tidak dihitung sebagai income/expense;
- recurring dan piutang tidak membuat hasil terlalu optimistis;
- data satu minggu atau periode tidak lengkap menghasilkan confidence rendah/permintaan klarifikasi;
- SLM mengembalikan angka yang tidak ada pada evidence: ditolak atau disanitasi;
- SLM tidak tersedia: rule lokal tetap memberi respons yang berguna;
- topik budidaya ikan/politik/cuaca: ditolak;
- cara menabung, budgeting, cashflow, utang, dan target: diterima serta dikaitkan ke FFM;
- saran tidak membuat draft atau mutation otomatis;
- semua mutation yang kelak ditawarkan tetap mengikuti preview–confirmation–execute–verify.

Menjalankan `dart format`, `flutter analyze lib test`, targeted tests, dan full `flutter test`. Tidak menjalankan build APK, Gradle assemble, signing, atau inspeksi APK.

Memperbarui `PROJECT_CONTEXT.md` dan `docs/implementation_status.md` dengan status nyata, termasuk batas bahwa inference Android fisik belum diuji dan agent belum menjadi operator 100% untuk semua form. Setelah milestone selesai, membuat ZIP source baru yang bersih dan memverifikasi tidak ada APK/AAB, model GGUF, bundle model, key, credential, build, atau cache. Arsip asli tidak boleh ditimpa.

## Asumsi dan batas risiko

Rencana ini mengasumsikan tabel transaksi dan kewajiban yang sudah ada tetap menjadi sumber utama. Jika aplikasi belum menyimpan informasi bunga, tenor, biaya, atau pendapatan bersih secara konsisten, agen hanya menghitung ruang cicilan bulanan dan tidak mengubahnya menjadi estimasi plafon pinjaman. Pengeluaran satu bulan dapat menyesatkan jika pendapatan bersifat musiman; karena itu jumlah periode dan kualitas data harus ditampilkan.

Hasil fitur adalah **analisis dan edukasi finansial berbasis data lokal**, bukan persetujuan kredit, penilaian resmi bank, nasihat hukum/pajak, atau jaminan bahwa pinjaman aman. Untuk keputusan besar, pengguna tetap perlu memeriksa syarat resmi pemberi pinjaman atau berkonsultasi dengan profesional yang sesuai.

## Definition of Done

Fitur dianggap selesai hanya jika agen dapat memilih antara menjawab, membaca data, meminta klarifikasi, atau menolak dengan alasan yang benar; angka dapat ditelusuri ke agregat lokal; SLM tidak dapat mengarang fakta; data kosong menghasilkan fallback yang jujur; saran memiliki risiko dan next action; test suite lulus; dokumentasi sesuai implementasi; dan source ZIP bersih dibuat tanpa build APK.
