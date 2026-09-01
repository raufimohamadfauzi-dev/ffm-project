# FFM — Backlog Perbaikan UX & Fitur Transaksi

> Dibuat: 2026-09-01
> Tracking progress perbaikan yang belum selesai.

---

## 1. Bottom Sheet "Mau mencatat apa?" — Terlalu Ramai

**Masalah:** 7 pilihan sekaligus muncul di bottom sheet. User bingung mana yang paling penting. "JSON batch" dan "JSON nota dari LLM" terlihat teknis/developer-oriented, tidak user-friendly.

### Perbaikan
- [ ] Kurangi pilihan utama menjadi maksimal 4 opsi inti yang paling sering dipakai
- [ ] Pindahkan opsi JSON ke dalam sub-menu atau bagian "Alat Lanjutan" yang bisa di-*expand* (collapsed by default)
- [ ] Gabungkan "Impor JSON batch dari Gemini" dan "Impor JSON nota dari LLM" menjadi satu entry dengan sub-pilihan di dalam
- [ ] Pisahkan "Isi target uang terkumpul" dan "Pakai dana target" ke dalam satu tile "Target Keuangan ▸" yang membuka sub-pilihan
- [ ] Kurangi `initialChildSize` dari `.84` menjadi lebih kecil (mis. `.55`) agar sheet tidak menutupi hampir seluruh layar
- [ ] Teks subtitle yang terlalu panjang — potong maksimal 1 baris atau buat lebih ringkas

**Target struktur baru:**
```
Mau mencatat apa?
├── ↗ Pengeluaran        ← primary action
├── ↙ Pemasukan         ← primary action
├── ⇄ Transfer          ← primary action (saat ini tidak ada!)
├── 🎯 Target Keuangan ▸ ← sub-sheet: Isi / Pakai
└── ⋯ Lebih banyak ▸   ← collapsed: Input Cepat, Impor JSON/AI
```

---

## 2. Transfer — Belum Ada di Bottom Sheet Utama

**Masalah:** Pilihan "Transfer" tidak ada di menu utama bottom sheet, padahal ini transaksi yang sangat umum.

### Perbaikan
- [ ] Tambahkan pilihan "Transfer" sebagai opsi ketiga di antara Pemasukan dan Target
- [ ] Atau: tampilkan sebagai chip/tab di atas form Pengeluaran (Pengeluaran | Pemasukan | Transfer)

---

## 3. Rincian Item Belanja (Induk–Anak) di Form Transaksi Manual

**Masalah:** User mau input belanja di "Sayur Segar" dengan banyak rincian (bayam, beras, tempe), tapi tidak ada cara intuitif untuk menambah baris item anak di bawah satu transaksi induk dari form transaksi standar.

### Perbaikan
- [ ] Cek apakah `TransactionFormPage` sudah menampilkan section "Rincian item belanja" (daftar `TransactionItems`) dengan tombol tambah baris
- [ ] Jika belum ada: tambahkan section "Rincian Item (opsional)" di bawah form utama
- [ ] Tiap baris item: nama item, qty, harga satuan, subtotal otomatis
- [ ] Total transaksi induk harus **otomatis terhitung** dari sum subtotal seluruh item anak jika item anak ada
- [ ] Tombol `+ Tambah item` dan tombol hapus per baris harus jelas dan mudah dijangkau
- [ ] Validasi: jika ada item anak, nominal induk dikunci (otomatis dari sum item)
- [ ] Label "Merchant / Toko" harus mudah terlihat sebagai "nama induk" dari rincian belanja

---

## 4. Impor JSON — Terlalu Teknis, Tidak User-Friendly

**Masalah:** Label "JSON batch dari Gemini" dan "JSON nota dari LLM" tidak dipahami user biasa.

### Perbaikan
- [ ] Ganti label menjadi bahasa natural: mis. *"Tempel hasil dari Asisten AI"*
- [ ] Tambahkan langkah singkat di dalam halaman impor: "1. Tanya Asisten → 2. Salin hasil → 3. Tempel di sini"
- [ ] Sembunyikan kedua opsi JSON dari pilihan utama (pindah ke bawah "Lebih banyak")
- [ ] Gabungkan dua opsi JSON menjadi satu halaman dengan tab/pilihan di dalam

---

## 5. Koreksi Draft Multi-Item di Asisten (Chat)

**Masalah:** Jika Asisten menghasilkan 5 draft sekaligus, user tidak bisa mengoreksi draft ke-3 saja tanpa menyentuh yang lain.

### Perbaikan
- [ ] Setiap kartu draft dalam chat harus punya tombol **"Edit"** sendiri untuk item tersebut saja
- [ ] Tombol **"Simpan semua"** dan **"Simpan satu per satu"** harus tampil jelas saat ada multi-draft
- [ ] Koreksi via chat harus bisa mendeteksi mana draft yang dimaksud ("yang beras ubah jadi 80rb")
- [ ] Draft `goalDeposit` dalam batch multi-draft harus tampilkan field "Target" di kartu koreksinya

---

## 6. Dialog Koreksi Draft — Adaptasi Field per Jenis

**Status:** Sebagian sudah diperbaiki (goalDeposit, goalUsage punya field spesifik).

### Perbaikan Tambahan
- [ ] Dialog `transfer` harus tampilkan **Rekening Asal DAN Rekening Tujuan** — verifikasi muncul keduanya
- [ ] Dialog `goal` (target baru) hanya: Nama Target + Nominal Target + Tanggal Target + Catatan (tanpa Rekening)
- [ ] Tambahkan **hint text** yang informatif di setiap field (contoh: "Contoh: BCA, Tunai, ShopeePay")
- [ ] Tampilkan info "Jenis draft: Setor Target" di subtitle dialog agar user tidak bingung

---

## 7. Fitur Target Keuangan di Asisten — End-to-End

**Status:** `goalDeposit` / `goalUsage` proposal parser sudah ada. `target_aktif` sudah masuk konteks LLM.

### Perbaikan & Verifikasi
- [ ] Uji end-to-end: ketik *"simpan 500rb untuk target liburan"* → draft muncul dengan nama target yang benar
- [ ] Jika nama target tidak ada di `target_aktif`, Asisten harus **minta klarifikasi** (bukan draft kosong)
- [ ] Asisten harus bisa menjawab: *"Target keuanganku ada apa saja?"* dari `target_aktif`
- [ ] Koreksi via chat: *"ganti targetnya jadi Dana Darurat"* → update `goalName` di draft aktif

---

## Prioritas Eksekusi

| No | Item | Dampak | Usaha | Prioritas |
|---|---|---|---|---|
| 1 | Bottom sheet kurangi pilihan | Tinggi | Rendah | 🔴 P0 |
| 2 | Tambah Transfer di bottom sheet | Tinggi | Rendah | 🔴 P0 |
| 3 | Rincian item induk-anak di form | Tinggi | Tinggi | 🟠 P1 |
| 5 | Koreksi multi-draft di asisten | Tinggi | Sedang | 🟠 P1 |
| 6 | Dialog koreksi adaptif | Sedang | Rendah | 🟡 P2 |
| 7 | Target keuangan asisten e2e | Sedang | Sedang | 🟡 P2 |
| 4 | Label JSON lebih user-friendly | Rendah | Rendah | 🟢 P3 |
