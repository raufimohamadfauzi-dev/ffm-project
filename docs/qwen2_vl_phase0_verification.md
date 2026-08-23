# Fase 0 — Verifikasi Qwen2-VL dan llama.cpp

**Proyek:** Family Finance Manager (FFM)  
**Tanggal pemeriksaan:** 22 Agustus 2026  
**Status:** **LULUS dengan catatan produksi**

## Ringkasan keputusan

Aset yang disebut briefing tersedia dan dapat diunduh dari release `v1.0.0` repository `raufimohamadfauzi-dev/ffm-project`. Kedua file berhasil diunduh ke sandbox, ukuran byte eksaknya cocok dengan metadata GitHub API dan SHA-256 yang diberikan briefing. Empat byte pertama masing-masing file adalah `GGUF`, dan versi format yang terbaca langsung dari header adalah `3`.

Dokumentasi resmi `llama.cpp` pada commit `2115b73d8ebdbd659075cce66c609506863bc826` mencantumkan Qwen 2 VL sebagai model vision yang didukung dan mendokumentasikan penggunaan `-m model.gguf --mmproj file.gguf` untuk pasangan model teks dan multimodal projector.[1] Commit tersebut dirilis sebagai `b10581`, yang menyediakan artefak Android arm64 CPU.[2] Keputusan ABI awal ditetapkan **`arm64-v8a`**.

Qwen2-VL-2B-Instruct resmi dinyatakan menggunakan **Apache License 2.0** oleh Qwen, dan teks lisensi memberikan hak untuk mereproduksi, membuat derivative work, serta mendistribusikan Work/Derivative Works dengan kewajiban mempertahankan lisensi dan attribution notices.[3] Ini cukup untuk melanjutkan kelayakan teknis dengan kewajiban memasukkan lisensi dan atribusi yang sesuai pada distribusi FFM. Catatan produksi: repository host aset GGUF tidak menampilkan file `LICENSE` pada root yang diperiksa, sehingga provenance kuantisasi harus dicatat dan paket rilis harus menyertakan lisensi Qwen serta attribution/NOTICE yang diperlukan; laporan ini bukan pendapat hukum.

## G0-01 — Repository, release, dan URL aset

| Item | Hasil |
|---|---|
| Repository | `raufimohamadfauzi-dev/ffm-project` |
| Release | `v1.0.0`, nama `Qwen2-VL Model Files` |
| Release published | `2026-08-22T10:04:38Z` |
| Commit yang diperiksa | `4ef5b76745338885b0e8e82fc29692cc210e2d13` |
| URL model bahasa | `https://github.com/raufimohamadfauzi-dev/ffm-project/releases/download/v1.0.0/Qwen2-VL-2B-Instruct-IQ4_NL.gguf` |
| URL multimodal projector | `https://github.com/raufimohamadfauzi-dev/ffm-project/releases/download/v1.0.0/mmproj-Qwen2-VL-2B-Instruct-f16.gguf` |
| HTTP | Kedua URL mengikuti redirect GitHub release asset dan mengembalikan `200` untuk aset final |
| Kesimpulan | **Lulus** |

Metadata release dari GitHub API mencatat ukuran dan digest SHA-256 untuk kedua aset. Nilai tersebut dicocokkan lagi dengan file yang benar-benar diunduh di sandbox.

## G0-02 — Unduh, ukuran eksak, dan SHA-256

Pengunduhan dilakukan menggunakan `curl` dengan `--continue-at -` sehingga proses dapat dilanjutkan jika terputus. Verifikasi SHA-256 memakai `sha256sum`, yang membaca file secara streaming; tidak ada `readAsBytes()` atau pemuatan seluruh file ke memori.

| Peran | Nama file | Ukuran eksak | SHA-256 aktual | Hash briefing/API | Hasil |
|---|---|---:|---|---|---|
| Language model | `Qwen2-VL-2B-Instruct-IQ4_NL.gguf` | `936329984` byte | `7df01d764cbb22ce270cd09eb2ff483f7161fcb42b80ea9a93e99d8de4b815e8` | Sama | **Lulus** |
| Multimodal projector | `mmproj-Qwen2-VL-2B-Instruct-f16.gguf` | `1331656192` byte | `05cc3ae461a7b6aa4023312ccab549ecab77cf8677efee04f049fcbab55b8bc3` | Sama | **Lulus** |

Total ukuran dua aset adalah `2267986176` byte. File bukti lokal berada di `/home/ubuntu/ffm-phase0-models/` dan tidak dimasukkan ke source archive atau Git.

## G0-03 — Header GGUF

Header dibaca langsung dari file dengan hasil berikut.

| File | Delapan byte awal | Magic empat byte | Versi GGUF little-endian | Hasil |
|---|---|---|---:|---|
| `Qwen2-VL-2B-Instruct-IQ4_NL.gguf` | `47 47 55 46 03 00 00 00` | `GGUF` | `3` | **Lulus** |
| `mmproj-Qwen2-VL-2B-Instruct-f16.gguf` | `47 47 55 46 03 00 00 00` | `GGUF` | `3` | **Lulus** |

Header yang benar tidak menggantikan validasi runtime; loader native tetap harus menolak file yang tidak sesuai manifest, ukuran, dan SHA-256.

## G0-04 — Pin llama.cpp dan dukungan multimodal Android

Pin yang dipilih adalah:

| Item | Nilai |
|---|---|
| Tag | `b10581` |
| Commit | `2115b73d8ebdbd659075cce66c609506863bc826` |
| Release published | `2026-08-22T10:13:08Z` |
| Android artifact | `llama-b10581-bin-android-arm64.tar.gz` |
| Dukungan model | Dokumentasi pada commit yang sama mencantumkan Qwen 2 VL dalam daftar vision models |
| Pemakaian projector | Dokumentasi pada commit yang sama mendukung `-m model.gguf --mmproj file.gguf` |
| GPU projector | Default offload ke GPU; opsi `--no-mmproj-offload` tersedia untuk jalur CPU |
| Status | **Lulus untuk baseline CPU arm64; integrasi Flutter/NDK tetap harus dibuktikan pada Fase 2** |

Pin ini membuktikan ketersediaan baseline upstream yang relevan, tetapi belum membuktikan smoke test di perangkat Android FFM. Smoke test native dan audit lifecycle tetap menjadi acceptance criteria Fase 2.

## G0-05 — ABI Android

ABI awal ditetapkan **`arm64-v8a` saja**. Alasannya adalah release upstream yang dipilih menyediakan artefak Android arm64 CPU, target FFM adalah perangkat Android 64-bit, dan pembatasan ABI mengurangi ukuran distribusi serta permukaan kompatibilitas native. Konfigurasi aplikasi FFM saat ini mempertahankan `applicationId "com.ffm_manager"`, `minSdk = 26`, dan `targetSdk` dari konfigurasi Flutter.

| Keputusan | Nilai |
|---|---|
| ABI awal | `arm64-v8a` |
| ABI lain | Tidak ditargetkan pada iterasi pertama |
| Kegagalan/ketidaktersediaan native | Harus menghasilkan fallback aman, bukan crash atau cloud fallback |
| Status | **Lulus sebagai keputusan desain; harus diverifikasi lewat build release Fase 7** |

## G0-06 — Lisensi Qwen2-VL

Sumber resmi Qwen menyatakan Qwen2-VL-2B dan Qwen2-VL-7B dirilis di bawah **Apache 2.0**.[3] File lisensi resmi juga memberikan hak distribusi Work dan Derivative Works, dengan kewajiban memberikan salinan lisensi, mempertahankan copyright/patent/trademark/attribution notices yang relevan, serta menyertakan NOTICE bila ada.

Kesimpulan untuk implementasi adalah **dapat dilanjutkan dengan kewajiban kepatuhan lisensi**, bukan memasukkan aset tanpa atribusi. Saat FFM mendistribusikan model atau downloader-nya, rilis harus menyediakan setidaknya lisensi Apache 2.0 Qwen, atribusi `Copyright 2024 Alibaba Cloud` sesuai sumber resmi, URL provenance aset, dan catatan bahwa GGUF adalah artefak terkuantisasi/derivatif bila memang didistribusikan sebagai bagian dari paket aplikasi.

Repository host release yang diperiksa tidak menampilkan `LICENSE` pada daftar root dan README-nya hanya menjelaskan proyek FFM.[4] Hal ini tidak mengubah lisensi resmi Qwen yang ditemukan, tetapi membuat provenance/atribusi artefak pihak ketiga perlu diperlakukan hati-hati. Sebelum distribusi publik final, provenance kuantisasi sebaiknya dikonfirmasi kepada pemilik release atau aset didistribusikan dengan pemisahan yang jelas serta seluruh notice yang diwajibkan.

| Pertanyaan | Kesimpulan |
|---|---|
| Apakah lisensi resmi Qwen mengizinkan distribusi ulang derivative work? | Ya, Apache 2.0 mengizinkannya dengan syarat redistribusi |
| Apakah penggunaan on-device dilarang? | Tidak ditemukan larangan tersebut pada lisensi resmi yang diperiksa |
| Apakah kewajiban notice boleh diabaikan? | Tidak; lisensi dan attribution notices harus dipertahankan |
| Apakah ada catatan provenance aset GGUF pihak ketiga? | Ya; host release tidak menyediakan LICENSE pada root yang diperiksa |
| Status G0-06 | **Lulus teknis dengan catatan kepatuhan produksi** |

## G0-07 — Keputusan gerbang

| ID | Status |
|---|---|
| G0-01 | Lulus |
| G0-02 | Lulus |
| G0-03 | Lulus |
| G0-04 | Lulus sebagai pin baseline; smoke test ditunda ke fase bridge |
| G0-05 | Lulus sebagai keputusan ABI |
| G0-06 | Lulus dengan kewajiban lisensi, atribusi, dan provenance |
| **Fase 0** | **LULUS untuk melanjutkan implementasi bertahap** |

Fase 0 tidak menemukan mismatch hash, ukuran, atau header. Tidak ada penggantian model atau pendekatan. Implementasi berikutnya tetap wajib menghentikan pemakaian aset bila manifest, ukuran, atau hash tidak valid.

## Bukti lokal

| Artefak | Lokasi |
|---|---|
| Model language | `/home/ubuntu/ffm-phase0-models/Qwen2-VL-2B-Instruct-IQ4_NL.gguf` |
| Model projector | `/home/ubuntu/ffm-phase0-models/mmproj-Qwen2-VL-2B-Instruct-f16.gguf` |
| Source project | `/home/ubuntu/FFM-source-2d123ad-v67` |
| Arsip source asli | `/home/ubuntu/FFM-source-2d123ad-v67/FFM-source-2d123ad-v67.original.zip` |

## Referensi

[1]: https://github.com/ggml-org/llama.cpp/blob/2115b73d8ebdbd659075cce66c609506863bc826/docs/multimodal.md "llama.cpp multimodal documentation at pinned commit"

[2]: https://github.com/ggml-org/llama.cpp/releases/tag/b10581 "llama.cpp b10581 release"

[3]: https://github.com/QwenLM/Qwen2-VL/blob/main/LICENSE "Official Qwen2-VL Apache License 2.0"

[4]: https://github.com/raufimohamadfauzi-dev/ffm-project/tree/main "Asset host repository contents"

[5]: https://api.github.com/repos/raufimohamadfauzi-dev/ffm-project/releases/tags/v1.0.0 "GitHub API metadata for asset release"
