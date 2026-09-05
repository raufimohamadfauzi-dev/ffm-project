# Roadmap Fitur Asisten Otonom FFM (Autonomous Financial Agent)

Dokumen perencanaan dan panduan implementasi 6 pilar kecerdasan otonom Asisten FFM. Setiap pilar membedakan status fondasi di kode (`[x]`) dan penyempurnaan fitur mutakhir yang **akan dikerjakan** (`[ ]`).

---

## 1. Autonomous Budget Rebalancing (Penyeimbang Anggaran Universal)
> Berfungsi untuk **semua tipe pengguna** (petani, pedagang, karyawan, keluarga), apa pun nama dan jumlah pos anggarannya.

- [x] **Algoritma Deteksi Anggaran Dinamis**: `IntelligentEnvelopeRebalanceDetector` membaca seluruh anggaran aktif secara dinamis dari database (tanpa hardcode nama kategori), mendeteksi pos minus dan pos surplus aman.
- [x] **Evaluasi Penyeimbangan**: `SmartEnvelopeRebalance` menghitung batas transfer aman (maks 50% surplus).
- [x] **Tampilan Notifikasi di Kotak Masuk**: Kartu insight `FfmAssistantInsightType.envelopeRebalance` di `AgentInboxPage`.
- [x] **Eksekusi 1-Ketukan ("Terapkan Pergeseran Sekarang")**:
  - Tombol pada kartu insight di `AgentInboxPage` yang langsung mengeksekusi pergeseran plafon anggaran di SQLite (`db.envelopeTransfers`) dan menyesuaikan saldo anggaran tanpa form manual.
- [ ] **Interaksi Percakapan Asisten**:
  - Pengguna cukup mengetik di chat: *"Seimbangkan anggaran saya"* ➔ Asisten membaca anggaran aktif apa saja milik pengguna yang minus, mencari pos yang surplus, dan menyajikan draft pergeseran untuk disetujui.

---

## 2. Cash-Flow Runway & Proactive Work/Farm Interview (Wawancara Proaktif & Memori Transparan)
> Asisten aktif bertanya kondisi usaha/kebun pengguna, menampilkan bukti memori yang diserap secara transparan di UI, dan menghitung ketahanan kas nyata.

- [x] **Deteksi Laju Belanja Harian (*Daily Burn Rate*)**: `PredictiveRunwayDetector` menghitung pengeluaran rata-rata 14 hari terakhir dan membandingkannya dengan saldo kas likuid.
- [x] **Peringatan Defisit Sebelum Gajian**: Menghitung tanggal kas habis jika pengeluaran harian melebihi batas aman (`safeDailySpend`).
- [ ] **Wawancara Proaktif Status Usaha/Tani (*Proactive Check-In*)**:
  - Asisten membuka percakapan di awal minggu atau saat aplikasi dibuka:
    > *"Selamat pagi Pak Budi! Bagaimana perkembangan kebun/usaha minggu ini? Apakah ada belanja pupuk/bibit tak terduga, dan berapa hari lagi kira-kira panen?"*
- [x] **Transparansi Penyerapan Memori di UI Chat**:
  - Saat pengguna menyebutkan fakta penting (*"Baru beli pupuk 3 karung, kira-kira 20 hari lagi panen"* atau nomor meteran), asisten **menampilkan kartu konfirmasi memori di chat** (`FfmMemoryNudgeCard`) dengan tombol `[Simpan]` dan `[Nanti]`.
  - Saat disimpan, chat bubble menampilkan badge hijau transparan:
    > *✨ Memori Terserap: "Pertanian & Komoditas"*
  - Memori ini langsung masuk ke `FfmPersonalMemoryService` dan profil siklus kas (`CashFlowProfileRepository`), dapat dilihat/diedit pengguna di halaman Profil Keluarga.
- [x] **Integrasi Kas Runway ke Tanggal Panen/Usaha**:
  - Menghitung sisa hari kas bertahan langsung terhadap estimasi tanggal panen di profil kas pertanian (`targetHarvestDate`), bukan asumsi kaku gajian tanggal 25.

---

## 3. Autonomous Habit Discovery & Pendaftaran Langsung (Deteksi & Daftarkan Kebiasaan)
> Pengguna bisa mendaftarkan kebiasaan rutinnya secara langsung, atau membiarkan asisten mempelajarinya sendiri. Desain UI sopan tanpa pop-up aneh.

- [x] **Pencatatan Transaksi Berulang Manual**: Tabel `recurring_transactions` dan runner jadwal otomatis.
- [x] **Infrastruktur Pembelajaran Pola**: `FfmAssistantLearningCandidateService` untuk alur kerja dan kebiasaan yang disetujui.
- [ ] **Daftarkan Kebiasaan Langsung via Obrolan**:
  - Pengguna bisa langsung bilang ke Asisten:
    > *"Saya punya kebiasaan tiap Jumat jam 16:00 tarik tunai jajan anak 200rb"*
  - Asisten langsung mencatatnya sebagai jadwal kebiasaan aktif tanpa harus menunggu observasi 30 hari.
- [ ] **Mesin Penambang Pola (*Pattern Miner Engine*)**:
  - Menganalisis riwayat transaksi 30–60 hari untuk mendeteksi klaster hari, jam, dan toko berulang secara otomatis.
- [ ] **Desain Penempatan UI yang Nyaman & Tidak Aneh**:
  - **Bukan pop-up liar**: Tidak akan muncul tiba-tiba menutupi layar saat pengguna membuka menu lain.
  - **Di Lembar Chat Asisten**: Kartu santun:
    > *"💡 Saran Rutin: Biasanya hari Jumat sore ada penarikan jajan anak Rp 200rb. Mau dicatat sekarang?"*
  - **Opsi Kontrol Pengguna**:
    * `[+ Simpan Catatan]` (1 ketukan).
    * `[Lewati Minggu Ini]` (bukan menghapus kebiasaan, hanya menunda hari ini).
    * `[Ubah / Matikan Kebiasaan]` (jika kebiasaan sudah berubah).

---

## 4. Silent Utility & Manajemen Meteran Listrik (Multi-Meteran, Riwayat Khusus & Koreksi Otonom)
> Menyimpan nomor meteran/ID pelanggan di aplikasi (Rumah, Ruko, Pompa Ladang), memindai foto nota via LLM, dan menyediakan UI pantau/koreksi otonom.

- [x] **Deteksi Lonjakan Belanja Umum**: `AnomalySpikeDetector` mendeteksi transaksi yang melebihi 3.5x median kategori 90 hari.
- [x] **Pencegahan Transaksi Ganda**: Mendeteksi ketidaksengajaan double-input dalam rentang 15 menit.
- [x] **Katalog Meteran / ID Pelanggan di Aplikasi ("Buku Saku Meteran & Token Listrik PLN")**:
  - Menyimpan daftar nomor meteran dengan label/lokasi khusus (*"Listrik Rumah Utama"*, *"Listrik Ruko"*, *"Pompa Sawah Barat"*).
  - Berfungsi sebagai buku saku: saat ingin beli token di minimarket/m-banking, pengguna tinggal 1-ketuk untuk menyalin nomor meteran atau nomor token 20-digit.
  - Halaman `UtilityMeterPage` terdaftar di menu Pengaturan dan Asisten (`FfmAssistantDestination.utilityMeter`).
  - Setiap meteran memiliki riwayat pembelian token tersendiri (`TokenHistoryEntry`).
- [ ] **Pemindaian Foto Nota Cerdas via LLM**:
  - Pengguna mengirim/memfoto struk pembelian token. LLM memindai nomor token 20-digit, nominal rupiah, dan nomor meteran.
  - **Auto-Matching**: Jika nomor meteran sudah ada, draft diarahkan ke meteran tersebut.
  - **Auto-Register Baru**: Jika meteran belum pernah terdaftar, asisten secara otomatis mengusulkan draft untuk mendaftarkan meteran baru tersebut sekaligus mencatat pengeluarannya.
- [ ] **UI Pantau & Koreksi Otonom**:
  - Menambahkan panel *"Aktivitas Otonom Terkini"* di dalam `AgentInboxPage` atau `AutonomyMonitorPage`.
  - Pengguna dapat melihat apa saja yang baru diproses oleh sistem otonom dengan tombol `[Koreksi]` atau `[Batalkan]` jika ada data yang kurang tepat.

---

## 5. Executive Audio Morning Briefing & Onboarding Adaptif Berjenjang
> Briefing audio pagi berbasis data riil, tahan pembunuhan baterai saver OS, dan memandu pengguna secara adaptif dari data kosong hingga mahir.

- [x] **Pembuat Ringkasan Data Finansial**: `FfmAssistantFinancialSnapshotService` merangkum saldo dan aktivitas.
- [ ] **Onboarding Adaptif Berjenjang (Pemandu Bertahap)**:
  - **Kunjungan ke-1 (Data Kosong)**: Jika Data Utama atau rekening masih kosong, asisten menyapa ramah dan membimbing langkah pertama: *"Selamat datang Pak! Mari kita mulai dengan melengkapi nama profil keluarga dan membuat rekening/dompet pertama Anda."*
  - **Kunjungan ke-2 (Ada Rekening, Belum Ada Transaksi)**: Mengarahkan pencatatan transaksi perdana (misal scan kartu NFC atau catat belanja dapur).
  - **Kunjungan ke-3+ (Ada Transaksi, Belum Ada Anggaran)**: Menyarankan pembuatan pagu anggaran agar pengeluaran terkendali.
  - Memperkenalkan fitur-fitur baru secara bertahap saat data terkait sudah mulai terbentuk tanpa membebani pengguna di awal.
- [ ] **Arsitektur Tahan Baterai & Anti-Kill Android**:
  - Dipicu saat aplikasi dibuka pertama kali di pagi hari (jam 06:00 – 09:00). Tidak memakai service background yang dibunuh Android OS.
- [ ] **Kendali Penuh Audio & Teks**:
  - Tersedia tombol `[🔊 Putar Suara]` / `[⏸️ Pause]` / `[🔇 Bisu]`. Jika di tempat umum, pengguna dapat membaca ringkasan dalam format kartu teks yang bersih.

---

## 6. Debt Payoff Strategist (Strategi Pelunasan Hutang & Cicilan Cerdas)
> Mengubah modul hutang dari sekadar daftar catatan pasif menjadi simulator percepatan bebas hutang berbasis cicilan bulanan.

- [x] **Pencatatan Hutang & Piutang Lengkap**: `liability_pages.dart` dan `liability_detail_page.dart` (pokok hutang, cicilan bulanan `monthlyInstallment`, bunga `interestRate`, jatuh tempo).
- [x] **Pencatatan Pembayaran Cicilan**: `DebtPaymentDialog` mencatat mutasi cicilan (`liability_payment`) dan otomatis memotong sisa pokok hutang.
- [x] **Pengawasan Rasio Beban Hutang (DSR)**: `DebtServiceRatioDetector` memantau beban cicilan terhadap total pemasukan (standar sehat <= 30%).
- [ ] **Input Cicilan Bulanan yang Adaptif**:
  - Jika pengguna mengisi kolom `monthlyInstallment` di form hutang: kalkulasi simulasi bunga dan waktu lunas menjadi **100% presisi**.
  - Jika tidak diisi: sistem membaca rata-rata pembayaran aktual dari riwayat transaksi `liability_payment`.
- [ ] **Simulasi Otonom Snowball vs Avalanche**:
  - Menghitung penghematan bunga jika ada kelebihan uang belanja:
    > *"Jika sisa uang belanja bulan ini Rp 300.000 dialokasikan untuk melunasi hutang pupuk bunga tertinggi lebih dulu, Anda akan menghemat bunga Rp 120.000 dan lunas 1 bulan lebih cepat."*
