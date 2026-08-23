# Diagnostik Unduhan Qwen2-VL

## Temuan

Pesan pada perangkat, `SocketException: Failed host lookup: 'github.com'`, berarti perangkat gagal menerjemahkan nama host `github.com` saat mencoba membuka koneksi. Ini merupakan kegagalan jaringan atau DNS pada perangkat, bukan bukti bahwa file model rusak, SHA-256 salah, atau model tidak didukung.

Pemeriksaan source memastikan Android memiliki izin `android.permission.INTERNET`. Endpoint release yang dipakai juga tersedia dan asetnya memiliki metadata ukuran serta SHA-256 yang tetap dikunci di `FfmQwen2VlBundle`. Jalur unduh selalu memeriksa ukuran, SHA-256 secara streaming per chunk 256 KB, dan header GGUF v3 sebelum model dapat ditandai siap.

| Berkas | Ukuran target | SHA-256 target |
|---|---:|---|
| `Qwen2-VL-2B-Instruct-IQ4_NL.gguf` | 936.329.984 byte | `7df01d764cbb22ce270cd09eb2ff483f7161fcb42b80ea9a93e99d8de4b815e8` |
| `mmproj-Qwen2-VL-2B-Instruct-f16.gguf` | 1.331.656.192 byte | `05cc3ae461a7b6aa4023312ccab549ecab77cf8677efee04f049fcbab55b8bc3` |

## Perilaku setelah perbaikan

Jika DNS atau jaringan gagal, aplikasi menampilkan penjelasan yang lebih jelas: periksa internet, Private DNS, atau VPN; lalu tekan **Coba lagi**. Pilihan ini tidak menghapus file `.part`, sehingga unduhan dapat dilanjutkan bila server masih menerima resume yang cocok dengan metadata aset. Tombol **Mulai ulang** hanya dipakai ketika file parsial, ETag/Last-Modified, atau ukuran respons sudah tidak aman untuk diteruskan.

> Jika jaringan perangkat tetap tidak dapat menjangkau GitHub, gunakan **Impor bundle offline**. Bundle tetap diterima hanya jika model dan `mmproj` cocok dengan nama, ukuran, SHA-256, serta header GGUF yang dikunci FFM.

Tidak ada unduhan otomatis. Unduhan hanya mulai melalui tindakan pengguna. Tidak ada APK debug atau release yang dibuat untuk pemeriksaan ini; validasi dilakukan pada source dan regresi layanan model.

## Batas bukti saat ini

Endpoint dan metadata aset telah dicek dari lingkungan audit, tetapi tangkapan layar menunjukkan perangkat pengguna belum berhasil menyelesaikan unduhan penuh. Karena itu, keberhasilan unduh **penuh di perangkat tersebut** baru dapat dipastikan setelah koneksi/DNS perangkat pulih atau bundle offline diimpor. Integritas tetap menjadi penentu akhir: file tidak dipakai jika verifikasi gagal.

## Referensi

[1]: https://api.github.com/repos/raufimohamadfauzi-dev/ffm-project/releases/tags/v1.0.0 "Metadata GitHub Release Qwen2-VL FFM"
