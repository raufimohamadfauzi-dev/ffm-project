# Update SLM Background

## Sudah dikerjakan

Halaman Model Asisten Lokal sekarang memiliki pilihan **Unduh di background**. Android memakai DownloadManager sehingga dua file SLM—model utama dan projector—dapat tetap diunduh ketika aplikasi diminimalkan.

DownloadManager menampilkan progres dan status selesai di notifikasi HP. Halaman aplikasi dapat membaca statusnya kembali ketika dibuka. Setelah download selesai, file dimasukkan ke staging dan tetap diverifikasi dengan hash/ukuran/header yang sudah dipakai oleh alur impor biasa. Pengguna tetap harus menekan **Rakit dan Pasang SLM** setelah dua file masuk staging.

Ada tombol untuk membatalkan download background. Path file dibuat deterministik agar hasil download dapat ditemukan kembali oleh aplikasi dan tidak bergantung pada URI `content://` Android.

## Validasi source

Analyzer Dart: lulus, **No issues found**.

Test background baru: lulus, **2 test**.

Seluruh test Flutter: lulus, **254 test**.

## Belum terbukti

Belum ada APK yang dibangun dan belum diuji langsung pada HP Android. Karena itu notifikasi background, download ketika aplikasi diminimalkan, dan penerimaan file hasil download masih berstatus **sudah dibuat di source tetapi menunggu uji perangkat**.

Tidak ada APK release pada update ini.
