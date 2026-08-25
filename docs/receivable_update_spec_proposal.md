# Spesifikasi Pembaruan Piutang — Agent FFM

## Batas Domain

Piutang adalah domain keuangan aktif. `SaveReceivable` dapat menyimpan seluruh record, sedangkan `DeleteReceivable` melakukan arsip lunak dengan menonaktifkan record. Agent belum memiliki jalur aman untuk update atau arsip Piutang.

## Mutasi yang Diusulkan

Agent hanya boleh memperbarui metadata Piutang—nama, catatan, tanggal mulai/jatuh tempo, cicilan bulanan, dan bunga—pada satu target yang ditemukan secara unik. Nilai `originalAmount` dan `remainingBalance` wajib dipertahankan. Pencatatan tagihan, penerimaan pembayaran, pelunasan, transaksi, dan perubahan saldo tetap berada di luar scope karena membutuhkan kontrak keuangan tersendiri.

Arsip hanya bersifat lunak melalui usecase resmi; tidak ada penghapusan permanen. Setiap perubahan mengikuti draft → preview/edit → konfirmasi eksplisit → usecase resmi → audit lokal → readback.

> Agent tidak boleh membuat transaksi, pembayaran, perubahan saldo, perubahan sisa piutang, notifikasi, cloud, atau update massal melalui kontrak ini.

## Kriteria Validasi

Regresi harus membuktikan target ambigu ditolak, interpreter tidak menulis database, update mempertahankan nilai pokok dan sisa Piutang, arsip lunak tercatat audit, serta readback memverifikasi hasil sebelum checkpoint Git.
