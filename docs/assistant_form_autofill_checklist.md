# Checklist: Agent Autofill, Koreksi, dan Pemeriksaan Form

**Status:** fondasi multi-draft, prefill form utama, dan pemulihan antrean sudah diterapkan; audit perangkat Android serta test per form masih terbuka.
**Diperbarui:** 28 Agustus 2026 (Asia/Jakarta).
**Baca juga:** `AGENTS.md`, `docs/gemini_first_agent_handoff.md`, dan `docs/gemini_production_validation_checklist.md`.

## Tujuan produk

Saat pengguna meminta Agent/Gemini membuat data, Agent harus dapat menyiapkan **draft**, mengisi field pada form resmi yang didukung, memperlihatkan nilai yang belum lengkap atau meragukan, dan memberi cara koreksi. Agent tidak boleh menekan Simpan atau memutasi data atas nama pengguna.

```text
Percakapan pengguna
  → pemahaman perintah + klarifikasi bila perlu
  → satu atau beberapa draft tervalidasi dalam antrean terpisah
  → review kekurangan/konflik per draft
  → buka form resmi dengan prefill
  → pengguna koreksi dan konfirmasi simpan
  → form/executor menyimpan dan memverifikasi
```

## Kondisi baseline yang sudah ada

| Area | Status | Keterangan |
|---|---|---|
| Draft dari Agent/Gemini | Selesai | Tetap melalui `FfmAssistantDraft` dan validator. |
| Review kekurangan & konflik | Selesai | `FfmAssistantDraftValidator` dan `FfmAssistantDraftReview` sudah digunakan chat. |
| Koreksi draft dalam chat | Selesai | Ada koreksi teks dan dialog edit draft sebelum melanjutkan. |
| Pemahaman beberapa perintah sekaligus | Selesai | `interpretMany` memecah perintah; chat mengelola antrean draft bernomor dan lintas halaman. |
| Klarifikasi perintah ambigu | Sebagian | Harus dipertegas agar Agent/Gemini tidak menebak nominal, halaman target, atau maksud pengguna. |
| Petunjuk UI untuk draft cepat | Sebagian | Contoh cepat dan ringkasan beberapa draft sudah tersedia; daftar draft bernomor dan saran kontekstual masih dilanjutkan. |
| Prefill transaksi pemasukan/pengeluaran | Selesai | `TransactionListPage` meneruskan nominal, rekening, kategori, catatan, tanggal, merchant, dan field SLM ke `TransactionFormPage`. |
| Prefill transfer | Selesai | Nominal, rekening asal/tujuan, biaya admin, catatan, dan tanggal diteruskan ke form transfer. |
| Prefill setoran/penggunaan target | Selesai | Nominal, target, rekening, catatan, dan tanggal dipetakan bila cocok dengan Data Utama. |
| Prefill anggaran, target, aset, hutang/piutang, Data Utama | Sebagian | Target/rekening hanya dipilih jika cocok dengan Data Utama; anggaran menerima nominal dan kategori; Data Utama mengembalikan hasil buat data ke antrean. Test per form masih diperlukan. |
| Pemeriksaan field form setelah prefill | Sebagian | Validator draft ada, tetapi belum ada kontrak hasil prefill per form. |
| Simpan otomatis oleh Agent | Dilarang | Tidak boleh ditambahkan. |

## Tahap 1 — Pemahaman perintah dan pemecahan pekerjaan

- [x] Tetapkan kontrak hasil pemahaman yang memuat daftar pekerjaan terpisah: maksud, target halaman/form, parameter yang diketahui, parameter yang belum jelas, dan tingkat keyakinan yang aman.
- [x] Gunakan pemecahan multi-perintah pada jalur Agent maupun Gemini, sehingga satu pesan seperti “catat pengeluaran makan lalu buat anggaran” menjadi dua pekerjaan, bukan satu jawaban campur-aduk.
- [x] Minta klarifikasi singkat jika target form, nominal, rekening, tanggal, atau kategori tidak dapat ditentukan dari konteks resmi; validator FFM menjadi sumber kebenaran dan tidak mengarang nilai.
- [x] Pastikan hasil LLM selalu melewati parser/validator yang sama sebelum menjadi draft, dan sediakan fallback jujur bila output tidak valid atau provider tidak siap.
- [x] Sertakan konteks halaman aktif dan kemampuan form yang didukung, tetapi jangan menjadikan halaman aktif sebagai asumsi jika perintah pengguna menunjuk halaman lain.
- [x] Tambahkan test pemahaman: satu perintah, dua perintah lintas halaman, instruksi ambigu, dan output Gemini/Agent tidak valid.

Kriteria selesai: **selesai** — asisten dapat menjelaskan pekerjaan yang dipahami, memisahkan perintah yang berbeda, meminta data yang benar-benar kurang, dan tidak mengklaim form telah diisi bila belum ada draft valid.

## Tahap 2 — UI percakapan untuk draft cepat

### Prinsip layout: lega untuk percakapan, padat untuk kontrol

- Area percakapan memakai lebar layar penuh dan menjadi area terbesar; tidak ada panel samping permanen atau kartu dekoratif yang mengurangi ruang membaca.
- Pengantar dan contoh cepat muncul ringkas saat chat masih kosong, lalu mengecil menjadi satu aksi “Contoh” setelah percakapan dimulai.
- Saran cepat dan status draft memakai chip/baris ringkas yang dapat dibungkus atau digulir horizontal; jangan membuat satu kartu tinggi untuk setiap tombol.
- Ringkasan hasil pemahaman menampilkan informasi inti saja: jumlah draft, tujuan, dan kekurangan. Detail field dibuka hanya saat pengguna memilih draft.
- Satu draft aktif hanya memiliki satu aksi utama sesuai status. Aksi sekunder ditempatkan di menu yang tetap berlabel, sehingga layar tidak dipenuhi tombol yang setara.
- Composer pesan tetap mudah dijangkau di bagian bawah; daftar draft dan form detail tidak boleh menutup input atau mengganggu navigasi balik.
- Gunakan tinggi sentuh minimal 44 dp dan jarak antar-kontrol minimal 8 dp walaupun tampilan dibuat padat.

```text
Chat kosong:  pengantar singkat + 2–3 contoh cepat
Chat aktif:   riwayat percakapan (ruang utama)
              ringkasan “2 draft siap · 1 perlu info”
              [#1 Transaksi] [#2 Anggaran]  ← ringkas, pilih salah satu
              input pesan selalu tersedia di bawah
```

- [x] Tambahkan pengantar singkat yang dapat ditemukan di halaman Asisten: pengguna boleh memberi satu atau beberapa permintaan dalam satu pesan.
- [x] Sediakan contoh yang relevan dan dapat diketuk, misalnya: “Catat makan Rp50.000 hari ini, lalu siapkan anggaran makan bulan ini.” Contoh hanya mengisi kolom chat, tidak langsung membuat data.
- [x] Tambahkan saran cepat kontekstual setelah jawaban, seperti “Buat draft transaksi”, “Buat draft anggaran”, dan “Gabungkan beberapa permintaan”.
- [x] Setelah pesan dikirim, tampilkan ringkasan ringkas saat ada lebih dari satu draft: jumlah draft dan petunjuk memilih draft pada percakapan. Rincian tujuan dan klarifikasi masih tahap berikutnya.
- [x] Jika ada bagian ambigu, tampilkan pertanyaan singkat di chat dengan pilihan yang jelas bila pilihan aman tersedia; jangan menyembunyikannya di dialog teknis.
- [x] Gunakan label yang berorientasi aksi: “Buat 2 draft”, “Tinjau draft #1”, “Buka form transaksi”, “Koreksi”, dan “Batalkan draft”. Hindari istilah internal seperti intent, parser, atau capability.
- [x] Pastikan contoh cepat dan ringkasan draft memiliki label aksesibilitas serta tombol contoh tetap hanya mengisi input; audit seluruh kontrol Android dan status non-warna masih tahap berikutnya.
- [x] Tambahkan widget test untuk contoh cepat, ringkasan pemahaman, klarifikasi, loading, dan error provider. (Sebagian: `test/ffm_assistant_chat_intro_test.dart` sudah menguji contoh cepat, mode compact, aksesibilitas, klarifikasi, dan layar kecil — 8/8 lulus. Ringkasan pemahaman + loading + error provider di `ffm_assistant_action_plan_ui_test.dart` — 9/9 lulus.)
- [ ] Uji layar kecil Android: daftar draft tidak menyebabkan overflow, input tetap terlihat, dan informasi penting dapat dibaca tanpa scroll horizontal. (Sebagian: overflow komponen contoh cepat sudah diuji di layar 320×480@2x; audit daftar draft lintas halaman menyusul Tahap 3.)

Kriteria selesai: **selesai** — pengguna baru dapat mengetahui cara membuat beberapa draft dalam kurang dari satu layar, memahami apa yang akan dibuat sebelum membuka form, serta dapat mengoreksi atau membatalkan tanpa kebingungan—tanpa mengorbankan ruang utama percakapan.

## Tahap 3 — Antrean draft lintas halaman (fondasi wajib)

- [x] Buat model immutable item antrean draft yang memiliki ID unik, draft/intent, target halaman, status, daftar kekurangan/warning, dan waktu dibuat.
- [x] Simpan antrean di sesi chat dan migrasikan penggunaan satu `activeDraftReview` secara aman agar beberapa draft tidak saling menimpa.
- [x] Masukkan setiap hasil valid dari pemecahan perintah ke antrean dengan urutan dan target form yang jelas.
- [x] Tampilkan daftar draft bernomor ringkas di chat dengan status dan pilihan draft aktif. Detail field serta aksi tetap berada pada kartu draft agar layar tidak penuh.
- [x] Pastikan peninjauan, koreksi, dan pembatalan dari kartu chat terlebih dahulu memilih review milik draft tersebut, sehingga draft terakhir tidak menimpa draft yang dipilih pengguna. Isolasi status lintas halaman penuh masih tahap berikutnya.
- [x] Untuk transaksi pemasukan/pengeluaran: saat pengguna kembali dari form tanpa simpan, pulihkan item yang sama ke antrean; tandai selesai hanya sesudah `_saveDrafts` berhasil. Form lain masih tahap berikutnya.
- [x] Tambahkan test minimal dua draft pada halaman berbeda, lalu uji pembatalan dan koreksi salah satu draft tanpa mengubah yang lain.

Kriteria selesai: pengguna dapat menyimpan beberapa draft aktif untuk form berbeda, memilih urutannya sendiri, dan setiap draft tetap terisolasi sampai selesai atau dibatalkan.

## Tahap 4 — Kontrak prefill lintas halaman

- [x] Buat model immutable `FfmAssistantFormPrefill` yang berisi draft, form target, field yang diisi, field wajib yang belum ada, dan warning aman.
- [x] Buat mapper deterministik dari `FfmAssistantDraft` ke prefill form; jangan letakkan mapping di widget chat.
- [x] Buat hasil inspeksi `FfmAssistantFormCheck` untuk required/conflict/warning setelah mapping.
- [x] Pastikan mapper tidak menerima token, PIN, ID rahasia, atau instruksi simpan.
- [x] Tambahkan unit test mapper dan pemeriksaan kekurangan.

Kriteria selesai: **selesai** — chat dapat menyerahkan payload prefill seragam ke halaman tanpa mengetahui controller widget.

## Tahap 5 — Transaksi dan transfer (prioritas pertama)

- [x] Pindahkan mapping prefill income/expense yang ada ke kontrak bersama tanpa mengubah hasilnya.
- [x] Tambahkan prefill transfer: nominal, rekening asal, rekening tujuan, biaya admin, catatan, dan tanggal.
- [x] Tampilkan banner form: "Diisi dari draft Asisten — periksa sebelum simpan".
- [x] Sorot field yang belum lengkap atau tidak cocok dengan Data Utama aktif.
- [x] Beri aksi “Kembali ke chat untuk koreksi” pada form transaksi prefill; koreksi langsung di form tetap tersedia melalui field resmi.
- [x] Tambahkan widget/integration test: nilai prefill benar, field kurang disorot, dan tombol simpan tidak dipicu otomatis.

Kriteria selesai: transaksi dan transfer dapat dibuka dari draft dengan field terisi, dapat dikoreksi, dan tetap memerlukan simpan manual.

## Tahap 6 — Form keuangan utama

- [x] Tambahkan prefill untuk target tabungan dan kontribusinya; target/rekening dipilih hanya jika cocok dengan Data Utama.
- [x] Tambahkan prefill untuk anggaran.
- [x] Tambahkan prefill untuk aset, hutang, dan piutang yang form-nya sudah mendukung initial value eksplisit; status antrean mengikuti hasil simpan resmi.
- [x] Tambahkan prefill Data Utama (rekening, kategori, tag, merchant, sumber pemasukan) hanya bila form target sudah mendukung initial value eksplisit.
- [x] Tambahkan test per form sebelum menandai dukungan selesai.

Kriteria selesai: **selesai** — setiap form yang ditandai didukung dapat menerima draft tanpa mengambil alih simpan pengguna.

## Tahap 7 — UX koreksi dan pemeriksaan lanjutan

- [x] Tampilkan ringkasan: field terisi, perlu dilengkapi, dan warning; jangan menampilkan reasoning internal.
- [x] Saat pengguna kembali dari form tanpa simpan, pertahankan draft agar bisa dikoreksi.
- [x] Saat user menyimpan dari form, tutup/selesaikan draft chat hanya setelah hasil simpan resmi berhasil.
- [x] Tampilkan pesan jujur saat form belum mendukung prefill; jangan membuka halaman kosong seolah data sudah diterapkan.
- [x] Uji pembatalan, navigasi balik, konflik rekening/kategori, dan draft berubah saat form masih terbuka.

Kriteria selesai: **selesai** — alur koreksi dapat dipulihkan, tidak menggandakan data, dan status chat sesuai hasil form resmi.

## Batas keamanan

1. Agent dan Gemini hanya menghasilkan draft/prefill, tidak menyentuh `TextEditingController` secara langsung dari chat.
2. Form resmi tetap menjadi satu-satunya tempat input akhir dan simpan.
3. Tidak ada `auto-submit`, `auto-save`, atau mutasi latar belakang.
4. Semua mapping nominal, tanggal, rekening, kategori, dan validasi tetap deterministik.
5. Jika field referensi tidak cocok dengan Data Utama, tandai warning atau required; jangan membuat entitas baru diam-diam.
6. Antrean draft bersifat data sementara yang eksplisit; jangan menyimpannya sebagai memori personal atau mengeksekusinya kembali setelah sesi tanpa persetujuan pengguna.
