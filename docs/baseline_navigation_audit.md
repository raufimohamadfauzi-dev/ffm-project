# Audit Baseline dan Navigasi Siklus 1

Tanggal: 23 Agustus 2026.

## Baseline

Worktree ini berasal dari `/home/ubuntu/upload/FFM-source-PersonalLifeManager-Siklus1(1).zip`.

- Ukuran arsip: 8.912.647 byte.
- SHA-256: `b88b8a3a7fd20dc0a2869f9e2076c4fd665b7881c82a59c9af44aee95c8a6a14`.
- Worktree: `/home/ubuntu/FFM-source-PersonalLifeManager-Siklus1-verified/FFM-source-2d123ad-v67`.
- Arsip asli dan worktree lama v84 dipertahankan.

File wajib proyek ditemukan. Namun source aktual belum memuat domain `DailyNotes`, `Tasks`, `DailyRoutines`, `ScheduleItems`, atau `UserProfiles`; `schemaVersion` masih 33 dan generated Drift masih sesuai skema existing. Dokumen status yang dikirim dalam arsip sebelumnya memuat klaim yang lebih maju daripada source aktual; status tersebut sudah dikoreksi di worktree ini.

## Perubahan audit navigasi yang diterapkan

Navbar sekarang memiliki lima slot dengan urutan dan label: **Beranda**, **Transaksi**, **Aktivitas & Jurnal**, **Anggaran**, dan **Lainnya**. Aksi asisten/widget untuk membuka Anggaran diarahkan ke indeks 3, sedangkan Aktivitas diarahkan ke indeks 2.

`Analisa` tetap dibuka dari kartu menu **Lainnya**. Routing asisten untuk Analisa diarahkan ke indeks Lainnya lalu membuka `AnalysisPage`, sehingga tidak lagi salah membuka Anggaran.

Import dan kartu `Catatan Harian` yang sebelumnya menunjuk ke file tidak ada dihapus sementara. Ini disengaja: fitur Catatan Harian belum ada dalam baseline dan tidak boleh dipalsukan melalui routing. Entri `Aktivitas & jurnal` yang menggandakan navbar di katalog asisten juga dihapus, dan pengujian jumlah item katalog disesuaikan dari 18 menjadi 17.

Pemeriksaan import/export/part relatif setelah perubahan menghasilkan **OK**; tidak ada rujukan relatif ke file yang hilang.

## Keputusan database

Tidak ada tabel existing yang dihapus. `ActivitySessions`, `ActivityCheckpoints`, dan `ActivityEntries` tetap dipakai oleh ActivityRepository, ActivityBloc, ActivityPage, dan query asisten. Semua 29 tabel existing memiliki referensi source di luar definisi tabel/generated file berdasarkan audit statis.

## Batas validasi

Flutter SDK tidak tersedia. Oleh karena itu, analyzer, formatter Dart, build_runner, migration test, widget test, dan build APK belum dijalankan. Perubahan ini adalah perbaikan source berbasis audit statis, bukan bukti bahwa APK sudah dapat dibangun atau dipasang.

## Langkah berikutnya

Spesifikasi Daily Notes harus dibuat terlebih dahulu sebelum menambah tabel atau page baru. Jika diterapkan, Daily Notes akan menjadi tab/section di dalam Aktivitas & Jurnal, bukan item navbar baru. Setelah spesifikasi disetujui, baru dilakukan perubahan Drift, repository, UI, capability asisten, dan test secara bertahap.
