# Spesifikasi Pembaruan Hutang — Agent FFM

## Batas Domain

Hutang adalah domain keuangan aktif. Source saat ini menyediakan `SaveLiability` untuk menyimpan perubahan dan `DeleteLiability` yang sebenarnya melakukan **arsip lunak** melalui `isActive = false`. Tidak ada jalur Agent yang aman untuk update atau arsip Hutang saat ini.

## Pemisahan Update Metadata dan Pembayaran

| Aksi | Status proposal | Dampak |
|---|---|---|
| Ubah nama, catatan, tanggal mulai/jatuh tempo, cicilan bulanan, atau bunga | Diizinkan setelah target tunggal dan konfirmasi | Tidak membuat transaksi atau mengubah sisa hutang. |
| Ubah nilai pokok awal | Tidak diizinkan pada tahap ini | Mengubah histori dan perlu kontrak keuangan tersendiri. |
| Ubah sisa hutang | Tidak diizinkan pada tahap ini | Berpotensi menyerupai pembayaran atau koreksi saldo. |
| Catat pembayaran/pelunasan | Di luar scope tahap ini | Harus memakai alur transaksi/pembayaran tersendiri dan konfirmasi khusus. |
| Arsip Hutang | Diizinkan sebagai arsip lunak | Mengubah `isActive` menjadi false; tidak menghapus record atau transaksi. |

## Alur Agent yang Dikunci

Agent hanya membaca Hutang aktif lokal untuk mencari satu target. Jika tidak ditemukan atau ambigu, Agent meminta klarifikasi tanpa write. Draft update membawa metadata yang diperbolehkan sambil mempertahankan `id`, `householdId`, `originalAmount`, dan `remainingBalance`. Draft arsip hanya menonaktifkan record melalui usecase resmi. Setiap mutasi mengikuti draft → preview/edit → konfirmasi eksplisit → usecase resmi → audit lokal → readback.

> Agent tidak boleh membuat pembayaran, transaksi, perubahan saldo rekening, perubahan sisa hutang, penghapusan permanen, notifikasi, cloud, atau update massal melalui kontrak ini.

## Kriteria Validasi

Regresi harus membuktikan resolver target tunggal, tidak ada database write dari interpreter, update menjaga nilai pokok dan sisa hutang, arsip bersifat lunak, audit/readback berjalan, serta seluruh analyzer dan suite test lulus sebelum checkpoint Git.
