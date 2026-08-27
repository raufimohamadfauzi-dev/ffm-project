# Kode Diagnostik Gemini FFM

Dokumen ini menjelaskan indikator yang tampil pada halaman **Google Gemini (AI Studio)** di Intelligence Dashboard. Kode diagnostik membantu melacak alur dari pengisian API key sampai pemakaian chatbot.

> **Prinsip keamanan:** log diagnostik tidak menyimpan atau menampilkan API key, fingerprint/panjang key, prompt, system instruction, konteks finansial, kredensial Supabase, PIN/OTP, transaksi mentah, maupun raw response Gemini.

## Alur pemeriksaan

| Tahap | Aksi pengguna atau aplikasi | Indikator berhasil |
|---|---|---|
| 1. API key | Key diisi pada form. Nilai field tetap disamarkan. | `GEM-KEY-200` |
| 2. Daftar model | Aplikasi meminta `GET /v1beta/models` memakai header `x-goog-api-key`. | `GEM-MODEL-200` |
| 3. Model | Pengguna memilih model yang mendukung `generateContent`. | `GEM-MODEL-201` |
| 4. Test | Aplikasi mengirim request nyata `POST /v1beta/models/{model}:generateContent`. | `GEM-VERIFY-200` |
| 5. Penyimpanan | Tuple key + model + verified disimpan di secure storage. | `GEM-CONFIG-200` |
| 6. Chatbot | Interpreter membaca tuple tersimpan yang sama dan mencatat metadata pemakaian terakhir. | `GEM-CHAT-200` |

Perubahan API key atau model langsung membatalkan status verified sebelumnya. Daftar model dan test generateContent harus dilakukan ulang. Pemeriksaan otomatis ketika halaman dibuka tidak mengubah status verified secara diam-diam.

## Katalog kode

### API key dan konfigurasi

| Kode | Level | Arti dan tindakan |
|---|---|---|
| `GEM-KEY-000` | Warning | API key belum diisi. Isi key lalu muat daftar model. |
| `GEM-KEY-001` | Warning | API key berubah. Verifikasi lama dibatalkan dan test harus diulang. |
| `GEM-KEY-200` | Success | Key terisi di form. Ini belum berarti key valid di Google. Lanjutkan ke daftar model. |
| `GEM-CONFIG-000` | Error | Tuple key, model, dan verified belum lengkap ketika chatbot hendak memakai Gemini. |
| `GEM-CONFIG-200` | Success | Key dan model tersimpan dengan status verified. Chatbot boleh memakai pasangan tersebut. |
| `GEM-CONFIG-422` | Warning | Konfigurasi disimpan, tetapi test gagal sehingga chatbot tidak memakai Gemini. |

### Daftar dan pemilihan model

| Kode | Level | Arti dan tindakan |
|---|---|---|
| `GEM-MODEL-100` | Info | Request daftar model sedang dimulai. |
| `GEM-MODEL-200` | Success | Daftar model berhasil diambil dan setidaknya satu model mendukung `generateContent`. |
| `GEM-MODEL-201` | Info | Model dipilih. Pemilihan model belum sama dengan verifikasi koneksi. |
| `GEM-MODEL-000` | Error | Model belum dipilih. Pilih model dari daftar hasil API key. |
| `GEM-MODEL-204` | Error | Tidak ada model `generateContent` yang tersedia untuk key atau akun tersebut. |
| `GEM-MODEL-404` | Error | Model tidak ditemukan atau tidak tersedia pada endpoint yang digunakan. |

### Test generateContent dan respons

| Kode | Level | Arti dan tindakan |
|---|---|---|
| `GEM-TEST-100` | Info | Test `generateContent` sedang dikirim ke model pilihan. |
| `GEM-TEST-422` | Warning | Test generateContent belum berhasil dilakukan. Jangan menganggap Gemini sudah aktif. |
| `GEM-VERIFY-200` | Success | Test request berhasil. Pasangan key + model siap disimpan dan dipakai chatbot. |
| `GEM-CHAT-200` | Success | Chatbot berhasil menerima jawaban dari Gemini. |
| `GEM-RESP-204` | Error | HTTP berhasil, tetapi respons tidak memiliki teks yang dapat dibaca. |
| `GEM-RESP-422` | Error | Respons bukan JSON valid atau struktur respons tidak dapat diproses. |
| `GEM-CHAT-500` | Error | Chatbot mencoba Gemini tetapi request gagal. Lihat HTTP status dan pesan sanitasi pada log. |

### HTTP dan jaringan

| Kode | HTTP atau kondisi | Arti dan tindakan |
|---|---:|---|
| `GEM-REQ-400` | 400 | Format atau parameter request ditolak. Periksa model dan endpoint. |
| `GEM-AUTH-401` | 401 | API key tidak valid atau ditolak. Buat atau salin ulang key yang benar. |
| `GEM-AUTH-403` | 403 | Key tidak memiliki izin untuk request tersebut. Periksa project, API, dan pembatasan key. |
| `GEM-RATE-429` | 429 | Kuota atau rate limit tercapai. Tunggu atau periksa kuota akun Google AI Studio. |
| `GEM-SRV-500` | 500 atau lebih | Layanan Gemini bermasalah sementara. Ulangi setelah layanan pulih. |
| `GEM-NET-408` | Timeout | Request melewati batas waktu. Periksa koneksi lalu ulangi test. |
| `GEM-NET-001` | Network | Koneksi ke endpoint Gemini gagal sebelum respons valid diterima. |

## Cara memakai log di APK

Buka **Intelligence Dashboard**, isi API key Gemini, lalu tekan **Muat model dari key**. Pilih salah satu model yang ditampilkan, tekan **Test API Key**, dan baca kartu **Pelacakan Gemini**. Jika test berhasil, status langkah keempat menjadi `GEM-VERIFY-200` dan langkah kelima menjadi `GEM-CONFIG-200` setelah konfigurasi disimpan.

Kartu **Log diagnostik aman** menampilkan maksimal 12 event terbaru. Tombol **Salin log aman** menyalin waktu, kode, pesan, model, HTTP status, dan latency tanpa rahasia. Tombol **Hapus log tampilan** menghapus log yang hanya berada di memori halaman. Log dashboard tidak dipersistenkan.

Kartu **Pemakaian chatbot terakhir** mengambil metadata aman dari secure storage. Metadata tersebut hanya berisi kode, model, hasil berhasil/gagal, waktu, HTTP status, dan latency. Kartu ini tidak membuktikan bahwa request baru sedang berlangsung; tekan tombol refresh setelah menguji chatbot.

## Batasan arsitektur

Gemini menerima konteks finansial yang telah dirakit dan dibatasi oleh agent aplikasi sesuai kebutuhan pertanyaan. Gemini tidak menerima API key, kredensial Supabase, PIN/OTP, seluruh database mentah, atau hak mutasi langsung. Draft, validasi, konfirmasi, eksekusi, dan verifikasi perubahan data tetap dikendalikan oleh jalur deterministic aplikasi.

## Catatan rilis

APK yang memuat kode diagnostik harus dibangun dari source setelah commit fitur diagnostik dan harus menggunakan signing keystore release resmi. File `android/key.properties`, keystore, password, dan API key tidak boleh di-commit ke repository.
