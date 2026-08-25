# Spesifikasi Pembaruan Anggaran — Agent FFM

## Status Persetujuan dan Implementasi

Kontrak ini telah disetujui pengguna melalui perintah **“lanjut”** setelah draf ditinjau. Implementasi mengikuti batas persis di bawah: Agent tidak dapat membuat pos Anggaran, transfer alokasi, atau transaksi; schema juga tidak berubah.

Audit menemukan bahwa jalur Agent saat ini masih berupa create generik: Agent hanya menerima nominal, lalu menulis Anggaran bulanan bernama `Anggaran Asisten` tanpa target pos, kategori, periode, atau guard arsip yang deterministik. Jalur ini tidak memenuhi standar mutasi finansial konservatif yang telah dipakai untuk Kategori dan Rekening; jalur tersebut harus digantikan, bukan diperluas diam-diam.

## Model dan Formula Saat Ini

Tabel `envelope_budgets` menyimpan `id`, `householdId`, `categoryId`, `categoryIdsJson`, `name`, `month`, `allocated`, `periodType`, `startDate`, `endDate`, `alertPercent`, `rollover`, `isActive`, `createdAt`, dan `updatedAt`. Tabel `envelope_transfers` menyimpan perpindahan alokasi antarpos melalui `fromEnvelopeId`, `toEnvelopeId`, dan `amount`.

> **Sisa Anggaran = `allocated` + `rollover` + transfer masuk − transfer keluar − pengeluaran yang cocok dalam periode.**

Pengeluaran yang cocok adalah transaksi bernilai negatif, bukan transfer, berada dalam periode Anggaran, dan berada dalam kategori yang cocok—termasuk turunan kategori bila pos memakai kategori induk. Karena itu, perubahan `allocated`, `rollover`, kategori, atau periode langsung mengubah batas, sisa, progres, serta peringatan yang terlihat pengguna.

| Elemen | Peran | Risiko bila dimutasi Agent |
|---|---|---|
| `allocated` | Batas alokasi pos | Tinggi; langsung mengubah sisa, progres, dan status peringatan. Dapat diubah hanya dengan preview angka sebelum/sesudah dan guard saldo sisa nonnegatif. |
| `rollover` | Saldo alokasi terbawa | Tinggi; bagian dari batas efektif. Dibekukan. |
| `categoryId` / `categoryIdsJson` | Cakupan pengeluaran pos | Kritis; mengubah transaksi yang dihitung tanpa mengubah transaksi itu sendiri. Dibekukan. |
| `periodType`, `startDate`, `endDate`, `month` | Jendela perhitungan | Kritis; dapat memasukkan atau mengecualikan histori. Dibekukan. |
| `alertPercent` | Ambang peringatan | Tinggi; mengubah makna peringatan. Dibekukan pada milestone pertama. |
| `isActive` | Menampilkan pos pada Anggaran dan analisis | Tinggi; arsip hanya boleh pada pos yang benar-benar belum punya pemakaian atau alokasi ulang. |
| `envelope_transfers` | Riwayat pemindahan alokasi | Kritis; tidak boleh dibuat, diubah, dipindahkan, atau dihapus Agent dalam milestone ini. |
| Transaksi dan kategori | Sumber pemakaian pos | Kritis; tidak boleh dibuat, diubah, dipindahkan, diarsipkan, atau dihapus Agent melalui kontrak Anggaran. |

## Kontrak yang Disetujui

### Tujuan Sangat Terbatas

Milestone Anggaran hanya mengizinkan Agent menargetkan **satu pos Anggaran kategori aktif yang cocok secara unik** untuk salah satu operasi berikut.

1. Mengubah **batas alokasi `allocated`** saja; atau
2. Mengarsipkan lunak pos dengan mengubah `isActive` menjadi `false` hanya bila seluruh guard arsip lolos.

Create Anggaran, edit kategori, penggantian periode, rollover, pengaturan ambang peringatan, pemindahan alokasi antarpos, penghapusan permanen, dan perubahan transaksi berada di luar kontrak ini.

### Kelayakan Target Wajib

Target harus memenuhi seluruh syarat berikut sebelum draft dapat dibuat. Jika ada nol atau lebih dari satu kandidat, Agent wajib meminta klarifikasi dan tidak melakukan write.

| Syarat | Aturan |
|---|---|
| Status | `isActive = true` dan belum diarsipkan secara logis. |
| Bentuk pos | Bukan pos sistem `overall-*`; bukan placeholder; bukan pos gabungan; `categoryIdsJson` harus memuat tepat satu kategori pengeluaran aktif. |
| Periode | Hanya pos periode berulang yang sedang berjalan menurut tanggal lokal (`weekly`, `biweekly`, `monthly`, `bimonthly`, `fourmonthly`, atau `fivemonthly`). Pos `nonrecurring`, periode lampau, dan periode masa depan tidak dapat dimutasi Agent pada milestone ini. |
| Target | Nama pos harus cocok unik setelah normalisasi; frasa target terlalu pendek, kosong, atau ambigu harus berhenti pada klarifikasi. |
| Batas plan | Satu Action Plan hanya memuat satu mutasi Anggaran. |

### Kontrak Update Batas

Perintah yang kelak didukung berbentuk seperti `ubah batas anggaran Makan jadi 750 ribu`. Parser hanya membuat draft. Preview wajib menampilkan nama dan ID target, kategori, periode, batas lama dan baru, rollover, transfer masuk/keluar, pengeluaran terhitung, sisa sebelum/sesudah, dan status bahwa tidak ada transaksi atau transfer yang dibuat.

Update hanya boleh menulis `allocated` dan `updatedAt`. Nominal baru harus berupa bilangan bulat rupiah positif dan harus membuat:

> **`allocated baru` + `rollover` + transfer masuk − transfer keluar − pengeluaran terhitung ≥ 0**

Guard ini menolak penurunan batas yang langsung membuat sisa negatif atau menyembunyikan pemakaian yang sudah terjadi. Update tidak boleh mengubah `id`, `householdId`, `name`, `categoryId`, `categoryIdsJson`, `month`, `periodType`, `startDate`, `endDate`, `rollover`, `alertPercent`, `isActive`, atau `createdAt`.

### Guard Arsip Wajib

Arsip lunak harus ditolak bila terdapat **satu saja** kondisi berikut.

| Guard | Alasan penolakan |
|---|---|
| Ada `envelope_transfers.fromEnvelopeId` atau `toEnvelopeId` yang menunjuk pos | Riwayat alokasi ulang akan kehilangan konteks aktif dan sisa pos dapat berubah secara menyesatkan. |
| Ada transaksi pengeluaran—termasuk yang telah diarsipkan atau dihapus lunak—yang masuk periode dan kategori pos, termasuk turunan kategori | Pos memiliki jejak pemakaian keuangan dan tidak boleh disembunyikan dari analisis aktif melalui Agent. |
| Pos sistem `overall-*`, pos kategori gabungan, pos nonrutin, periode lampau, atau periode masa depan | Semantik pos tidak cukup sempit untuk arsip Agent pada milestone pertama. |
| Target tidak aktif, tidak ada, atau ambigu | Tidak ada write. |

Jika semua guard lolos, archive hanya menulis `isActive = false` dan `updatedAt`. Semua field lain, termasuk `allocated`, `rollover`, kategori, periode, dan identitas, harus tetap sama. Tidak ada delete fisik.

### Pipeline dan Readback Wajib

Setiap write mengikuti **draft → preview/edit → konfirmasi eksplisit → executor allowlisted serial → repository resmi → audit lokal → readback**. Model lokal dan parser hanya boleh menghasilkan proposal; keduanya tidak boleh menjalankan SQL atau CRUD langsung.

Capability baru harus dipisahkan menjadi `draft.budget_update`, `draft.budget_archive`, dan `verify.budget_mutation`. Executor harus menggunakan `BudgetRepository` baru, bukan Drift langsung. Guard arsip berjalan saat preview dan sekali lagi tepat sebelum write untuk menutup race condition lokal.

Readback update membuktikan `allocated` sama dengan nominal yang disetujui, menghitung kembali sisa, dan membuktikan semua field terlindungi tidak berubah. Readback arsip membuktikan `isActive = false` dan seluruh field selain `updatedAt` tidak berubah. Kedua operasi harus menghasilkan audit lokal dengan nilai sebelum dan sesudah.

### Larangan Keras

Agent dilarang membuat Anggaran baru, mengubah `rollover`, kategori, periode, bulan, ambang peringatan, atau nama; mengarsipkan pos berjejak; membuat atau mengubah `envelope_transfers`; membuat atau mengubah transaksi; memindahkan transaksi antar kategori; menghitung ulang atau menciptakan rollover; menghapus fisik; melakukan mutasi massal; atau menggunakan SQL/CRUD langsung.

## Regresi Wajib Jika Kontrak Disetujui

Regresi harus membuktikan draft tidak menulis, target ambigu atau terlalu pendek hanya meminta klarifikasi, update batas menjaga semua field terlindungi dan menghitung sisa sesuai formula, update ditolak bila sisa pascaubah negatif, serta archive ditolak terpisah karena transfer asal, transfer tujuan, transaksi kategori langsung, transaksi kategori turunan, pos overall, pos gabungan, nonrutin, periode bukan aktif, dan histori transaksi terarsip/terhapus lunak. Arsip tanpa pemakaian atau transfer harus bersifat lunak, diaudit, dan dibaca kembali tanpa menambah transaksi atau transfer.

## Keputusan yang Diterapkan

Persetujuan pengguna berarti menyetujui **tepat** batas di atas: Agent hanya boleh memperbarui batas `allocated` satu pos kategori aktif yang sedang berjalan dengan sisa akhir nonnegatif, atau mengarsipkan pos yang tidak punya transaksi maupun transfer. Pos keseluruhan, pos gabungan, pos nonrutin, periode lampau/masa depan, create Anggaran, rollover, kategori, periode, peringatan, dan transfer alokasi tetap dikecualikan sampai ada kontrak terpisah.
