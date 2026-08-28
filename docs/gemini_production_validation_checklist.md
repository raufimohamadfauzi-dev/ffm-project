# Checklist Lanjutan: Gemini-first Assistant

**Status:** siap dilanjutkan tanpa build APK terlebih dahulu.
**Diperbarui:** 28 Agustus 2026 (Asia/Jakarta).
**Baca juga:** `AGENTS.md` dan `docs/gemini_first_agent_handoff.md`.

Dokumen ini memisahkan pekerjaan yang masih perlu dilakukan setelah arsitektur Gemini-first selesai. Jangan menambah akses mutasi langsung kepada Gemini.

## Kondisi saat ini

| Area | Status | Bukti/keterangan |
|---|---|---|
| Gemini sebagai lawan bicara mode Gemini Cloud | Selesai | Interpreter memakai `FfmGeminiCloudOrchestrator`. |
| Agent sebagai pemilik data, validasi, draft, dan eksekusi | Selesai | Tidak ada mutasi langsung dari model. |
| Capability baca bounded | Selesai | `read.summary` dan `read.transactions`. |
| Filter tanggal transaksi | Selesai | `startDate` + `endDate`, berpasangan, maksimal 14 hari, bulan berjalan. |
| Privasi hasil transaksi | Selesai | Maksimal 8 item tanpa merchant, kategori, rekening, catatan, atau ID. |
| Status sumber jawaban di UI | Selesai | Gemini Cloud, Data lokal FFM, Agent lokal, dan error Gemini dibedakan. |
| Test routing Gemini | Selesai | Test khusus `ffm_gemini_routing_test.dart` lulus. |
| Test kegagalan capability lengkap | Selesai | `ffm_gemini_first_integration_test.dart` 4 kasus Tahap A lulus + `ffm_gemini_cloud_orchestrator.dart` try/catch. |
| Uji Gemini API produksi | Belum | Memerlukan key yang sudah diverifikasi pengguna. |
| Uji perangkat Android nyata | Belum | Perlu perangkat/emulator yang tersedia. |
| Full test dan APK ARM64 release | Belum | Jangan dikerjakan kecuali diminta. |

## Tahap A — Lengkapi test keamanan dan kegagalan

- [x] Tambah test: executor capability melempar error → tidak ada panggilan Gemini kedua dan tidak ada mutasi.
- [x] Tambah test: Gemini gagal pada panggilan kedua → respons jujur `cloudError`, tanpa fallback yang menyamar sebagai Gemini.
- [x] Tambah test: JSON capability rusak/argumen tidak dikenal → ditolak sebelum executor.
- [x] Tambah test: filter tanggal lintas bulan → executor menolak.
- [x] Jalankan test fokus dan `dart analyze` untuk file yang berubah.

Kriteria selesai: semua kasus gagal berhenti aman, tidak menyimpan data, dan menyampaikan status yang benar.

## Tahap B — Rapikan UX eksekusi

- [x] Pastikan semua draft dari Gemini terlihat sebagai **Menunggu konfirmasi**.
- [x] Tampilkan capability yang dipakai hanya sebagai metadata aman, misalnya "Membaca ringkasan bulan ini".
- [x] Pastikan error Gemini memiliki aksi yang sesuai: coba lagi atau buka Setup Gemini.
- [x] Pastikan UI tidak menyebut Gemini ketika jawaban sebenarnya berasal dari data lokal/Agent.
- [x] Tambah atau perbarui widget test yang relevan.

Kriteria selesai: pengguna dapat membedakan jawaban, draft, pembacaan data, dan kegagalan tanpa melihat detail reasoning internal.

## Tahap C — Validasi produksi (butuh kondisi eksternal)

- [ ] Gunakan API key Gemini yang telah diuji lewat Pengaturan aplikasi.
- [ ] Uji percakapan bebas dalam mode Gemini Cloud.
- [ ] Uji pertanyaan ringkasan, transaksi, serta rentang tanggal dalam bulan berjalan.
- [ ] Uji permintaan mutasi: pastikan hanya menghasilkan draft dan meminta konfirmasi.
- [ ] Uji jaringan putus, timeout, key ditolak, dan model tidak tersedia.
- [ ] Catat hasil nyata tanpa menyimpan key atau token di repository.

Kriteria selesai: setiap kegagalan cloud ditampilkan jujur dan tidak mengubah data.

## Tahap D — Validasi rilis Android (hanya saat diminta)

- [ ] Jalankan seluruh test proyek.
- [ ] Jalankan `flutter analyze lib test`.
- [ ] Jalankan `flutter build apk --target-platform android-arm64 --release`.
- [ ] Verifikasi APK hanya berisi `arm64-v8a`.
- [ ] Uji alur Gemini-first pada perangkat Android atau emulator.

Kriteria selesai: APK ARM64 release berhasil dan perilaku Gemini-first tervalidasi pada perangkat.

## Batas yang tidak boleh dilanggar

1. Jangan memberi Gemini akses SQL, repository, executor, token, atau credential.
2. Jangan menambah capability mutasi ke kontrak Gemini.
3. Jangan menambah filter merchant, kategori, rekening, atau catatan tanpa desain minimisasi data dan persetujuan eksplisit.
4. Semua angka keuangan harus berasal dari query/perhitungan FFM.
5. Semua perubahan data harus tetap: proposal → validasi → draft → konfirmasi → executor → verifikasi.
