# Kontrak Knowledge Aplikasi untuk Agent FFM

## Tujuan

Agent FFM harus mampu menjelaskan aplikasi FFM secara spesifik dan jujur, bukan hanya memproses perintah finansial. Knowledge aplikasi mencakup identitas aplikasi, pembuat yang tercatat di source, halaman dan fungsi, cara memulai, batas offline-first, status model lokal, keamanan draft, serta batas capability yang benar-benar terpasang.

## Sumber Fakta

Urutan sumber fakta adalah: `FfmAssistantSelfDescriptionService` untuk identitas aplikasi dan pembuat, `FfmAssistantCatalog` untuk halaman/menu serta fungsi, registry capability dan adapter untuk kemampuan aktual, lalu database lokal hanya untuk jawaban kondisi pengguna seperti langkah setup atau kelengkapan data. Bila informasi tidak ada pada sumber tersebut, Agent harus menyatakan tidak memiliki metadata resminya dan tidak boleh menebak.

## Kontrak Jawaban

Pertanyaan seperti “aplikasi apa ini?”, “siapa pembuatnya?”, “FFM bisa apa?”, “fitur/menu apa saja?”, “halaman ini untuk apa?”, dan “pertama kali saya harus apa?” harus dijawab dari sumber fakta di atas. Jawaban langkah pertama harus membaca data lokal dan tidak membuat rekening, saldo, transaksi, keluarga, atau nominal contoh seolah-olah data pengguna.

## Batas Keamanan

Menjelaskan aplikasi tidak boleh mengubah data. Mutasi tetap selalu mengikuti alur draft, preview, konfirmasi eksplisit, executor allowlisted, repository resmi, audit lokal, dan readback verification. Status SLM harus dibedakan antara belum siap, siap menurut konfigurasi, dan inferensi fisik yang belum terverifikasi pada perangkat.

## Batas Scope

Knowledge aplikasi tidak sama dengan domain Personal Life. Catatan Harian, Tugas, Rutinitas, dan Jadwal adalah fitur data pengguna yang dibangun terpisah. Agent dapat menjelaskan fitur tersebut hanya setelah capability dan UI-nya benar-benar tersedia.
