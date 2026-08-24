# Third-Party Notices

## Qwen2-VL-2B-Instruct

FFM dapat mengunduh dan menggunakan dua artefak GGUF Qwen2-VL-2B-Instruct secara lokal setelah pengguna memilih setup model. Model resmi Qwen2-VL-2B-Instruct dinyatakan oleh Qwen berada di bawah **Apache License 2.0**. Salinan teks lisensi disimpan di `third_party/licenses/QWEN2-VL-APACHE-2.0.txt`.

Aset GGUF yang digunakan oleh bundle FFM berasal dari release berikut:

- Repository host: `raufimohamadfauzi-dev/ffm-project`
- Release: `v1.0.0`
- Model: `Qwen2-VL-2B-Instruct-IQ4_NL.gguf`
- Multimodal projector: `mmproj-Qwen2-VL-2B-Instruct-f16.gguf`
- Official Qwen model repository: https://github.com/QwenLM/Qwen2-VL
- Official license source: https://github.com/QwenLM/Qwen2-VL/blob/main/LICENSE

Distribusi harus mempertahankan salinan lisensi, copyright, patent, trademark, dan attribution notices yang relevan sesuai Apache License 2.0. Aset GGUF adalah artefak terkuantisasi/hasil konversi dan tidak disimpan di source repository FFM; aplikasi mengunduhnya hanya setelah pilihan eksplisit pengguna dan memverifikasi ukuran serta SHA-256 sebelum pemakaian.

## llama.cpp

FFM merencanakan penggunaan `llama.cpp` pada tag `b10581`, commit `2115b73d8ebdbd659075cce66c609506863bc826`, yang berlisensi MIT. Pin, sumber, dan status dukungan multimodal dicatat dalam `docs/qwen2_vl_phase0_verification.md`. Notice dan license upstream `llama.cpp` wajib disertakan pada distribusi native final setelah source native benar-benar diintegrasikan.
