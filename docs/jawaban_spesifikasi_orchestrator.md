# Jawaban Spesifikasi Orchestrator Portable

Berdasarkan dokumen `Spesifikasi-Personalisasi-Orchestrator-Portable.md`, berikut adalah jawaban teknis untuk pertanyaan Anda sebelum coding dimulai:

## 1. Ambang Batas Pola (Confidence & Sample Count)
- **Rekomendasi:** Minimal `sample_count = 5` dan `confidence_score = 80%`.
- **Alasan:** Kurang dari 5 transaksi terlalu dini untuk menyimpulkan kebiasaan tetap (misal user baru beli barang di toko A 2 kali, belum tentu seterusnya sama). 80% memastikan bahwa jika dari 5 transaksi user mengoreksi 1 kali (80% konsisten), pola tetap jalan; tapi jika dikoreksi 2 kali (60%), orchestrator akan menyerahkan kembali ke SLM karena pola berubah.

## 2. Pemetaan Kategori Saat Impor Profil
- **Strategi:** Saat `.ffmprofile` diimpor, orchestrator **tidak boleh** memaksa pembuatan kategori baru jika tidak ada di HP baru.
- **Solusi:** Pola yang merujuk ke kategori yang tidak ada (misal kategori di HP baru sudah di-rename) akan diabaikan (skip) secara halus. User tidak perlu mapping ulang manual; pola lama cukup kadaluarsa secara alami, dan orchestrator akan mengumpulkan pola baru dari nol untuk merchant tersebut. Ini menjaga proses impor tetap sederhana dan bebas error.

## 3. Estimasi Ukuran File Ekspor
- **Asumsi:** 100 transaksi/bulan = 1.200 transaksi/tahun.
- **Estimasi:** Jika setiap transaksi menghasilkan 1 baris koreksi dan agregasi, data JSON mentah untuk 1.200 baris hanya memakan sekitar **150 KB – 300 KB**.
- **Kesimpulan:** File `.ffmprofile` akan sangat kecil (di bawah 1 MB) bahkan setelah dipakai bertahun-tahun, sehingga aman dan cepat untuk diekspor/diimpor via Bluetooth atau Drive.

## 4. Perhitungan Ulang Pola (Recalculate)
- **Rekomendasi:** `recalculatePatterns()` dijalankan **secara batch/berkala di background**, bukan real-time setiap kali simpan transaksi.
- **Alasan:** Menghitung ulang seluruh tabel agregasi setiap kali user menyimpan transaksi akan membuat tombol "Simpan" terasa lambat di HP low-end. Sebaiknya agregasi dijalankan saat aplikasi baru dibuka (splash screen) atau saat aplikasi diminimalkan (background task), sehingga pengalaman input transaksi tetap instan.

## 5. Fitur Reset Kepribadian
- **Rekomendasi:** **Wajib ada**.
- **Alasan:** Kebiasaan orang berubah (misal pindah kerja, ganti prioritas budget). Harus ada tombol "Hapus Profil Kebiasaan" di Pengaturan yang hanya membersihkan tabel `user_corrections` dan `interaction_patterns` tanpa menyentuh data transaksi keuangan, sehingga orchestrator mulai belajar dari nol lagi.

## Kesimpulan Alur Kerja
Konsep ini sangat solid dan aman karena:
1. **Tidak melatih ulang SLM** (menghemat baterai dan RAM).
2. **Tidak mengirim data mentah ke cloud**.
3. **Ekspor/Impor file dipisah dari data keuangan**, sehingga aman dibagikan.

Sesuai instruksi Anda, saya akan **membuat skema database dan logika pola-matching terlebih dahulu**, dan mengujinya di satu perangkat. Fitur ekspor/impor `.ffmprofile` baru akan dibuat setelah logika inti terbukti berjalan.
