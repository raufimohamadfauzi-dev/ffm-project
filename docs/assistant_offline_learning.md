# Pembelajaran Offline Asisten FFM

Dokumen ini menjelaskan alur agar Asisten FFM dapat bertambah paham tanpa mengirim data pengguna dari aplikasi. Rilis ini mendukung **memori ajar SQLite**, **contoh belajar teranonimkan**, **ekspor dataset**, serta **kontrak manifest classifier intent**. Runtime model di APK masih sengaja nonaktif sampai evaluasi model dan integrasi native selesai diuji.

> **Prinsip utama:** classifier hanya boleh memberi dugaan *intent*. Parser deterministik FFM tetap menentukan data yang dipahami, membuat pertanyaan balik, menyiapkan draft, dan menunggu konfirmasi pengguna. Model tidak boleh menyimpan transaksi atau mengakses database secara mandiri.

## Alur penggunaan di aplikasi

Pengguna dapat memilih **Bantu Asisten belajar** dari preview draft chat. Sebelum disimpan, FFM menampilkan teks yang sudah disamarkan. Nominal diganti menjadi `<NOMINAL>`, sementara nama rekening, kategori, target, atau pihak dari draft diganti menjadi `<ENTITAS>`. Pengguna bisa menolak dialog ini tanpa mengubah draft atau transaksi.

Contoh yang disetujui muncul di **Lainnya → Pusat Latihan Asisten**. Di halaman itu, pengguna dapat mengarsipkan contoh dan menyalin dataset JSON. Hanya contoh aktif yang masuk ke dataset berikutnya. Knowledge pack untuk ajaran manual dan dataset latihan adalah dua hal yang terpisah: knowledge pack dipakai untuk alias/jawaban/alur, sedangkan dataset latihan dipakai untuk evaluasi atau pelatihan classifier intent.

## Melatih classifier di komputer pengembang

Salin dataset dari Pusat Latihan, simpan misalnya sebagai `dataset.json`, lalu jalankan validasi berikut dari root proyek.

```bash
python3 tools/ffm_intent_dataset_validate.py dataset.json
```

Validator akan menghentikan proses bila format salah, intent tidak dikenal, atau masih menemukan pola nomor telepon, email, maupun nomor panjang. Sebelum dilatih, setiap intent yang dipakai perlu memiliki sekurang-kurangnya **12 contoh** yang jelas dan bervariasi. Jumlah itu adalah ambang minimum internal untuk uji awal, bukan jaminan bahwa model sudah akurat.

Jika dataset sudah memadai, pasang TensorFlow di komputer pengembang yang terpisah dari APK. Lalu jalankan:

```bash
python3 -m pip install tensorflow
python3 tools/ffm_intent_train.py dataset.json --output-dir ./ffm-intent-artifacts
```

Skrip menghasilkan dua berkas, yaitu `ffm_intent_classifier.tflite` dan `ffm_intent_classifier.manifest.json`. Manifest memuat nama model, daftar label intent, ambang confidence, hash SHA-256 model, dan hasil validasi dasar. Jangan membagikan dataset mentah atau model pada pihak lain tanpa meninjau ulang isi contoh yang dipilih pengguna.

## Pemeriksaan sebelum aktivasi runtime

Setiap model baru wajib melalui evaluasi terpisah terhadap perintah nyata yang aman dan tidak memuat data keuangan pengguna. Set skenario minimal perlu mencakup pemasukan, pengeluaran, transfer dengan admin, target, hutang/piutang, aset, pengingat, aktivitas, pertanyaan halaman, serta typo umum bahasa Indonesia.

| Pemeriksaan | Syarat sebelum dipertimbangkan |
|---|---|
| Integritas paket | SHA-256 file `.tflite` harus identik dengan `sha256` di manifest. |
| Kompatibilitas | `formatVersion` harus `ffm-assistant-intent-classifier-v1`; seluruh label harus cocok dengan enum intent FFM. |
| Confidence | Proposal di bawah ambang manifest, atau di bawah 0,85, wajib dibuang. |
| Keamanan tindakan | Hasil model tidak boleh langsung navigasi, menyimpan, atau mengubah data. Semua kembali ke parser dan draft. |
| Regressi | Analyzer bersih, seluruh test Flutter lulus, dan test khusus fallback membuktikan parser tetap berjalan ketika model tidak tersedia. |

## Status rilis saat ini

APK saat ini dapat mengimpor file `.tflite` secara privat dan menghitung hash-nya, tetapi gateway model tetap **disabled**. Artinya, file model tidak dibuka, tidak dieksekusi, dan tidak dapat memengaruhi hasil parser. Kontrak manifest telah disiapkan agar aktivasi runtime nanti dapat dilakukan lewat rilis tersendiri setelah model lolos evaluasi.

Dengan batas ini, kecerdasan personal terus bertambah hari ini melalui alias, kebiasaan, jawaban, dan contoh teranonimkan yang disetujui sendiri oleh pengguna; sedangkan pembaruan model global tetap dilakukan secara bertanggung jawab oleh pengembang melalui rilis APK berikutnya.
