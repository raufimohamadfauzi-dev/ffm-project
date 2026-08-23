# Native vendor repair

ZIP baseline `FFM-cc403d0-v01.zip` berisi llama.cpp tanpa direktori `src/models` dan `tools/mtmd/models`, padahal CMake dan source native mereferensikan keduanya.

Direktori tersebut dipulihkan dari checkout resmi `ggml-org/llama.cpp` pada commit `95b8e33` agar source native lengkap dan APK dapat direproduksi. Perubahan ini menjadi bagian dari checkpoint source berikutnya.
