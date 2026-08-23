# Evaluasi Integrasi Android Intent FFM

Tanggal evaluasi: 23 Agustus 2026.

## Hasil

### ACTION_SET_ALARM

Secara teknis masuk akal untuk tombol “Buat Pengingat” yang hanya membuka aplikasi Jam bawaan dengan waktu dan label terisi. Android mendokumentasikan `ACTION_SET_ALARM` dengan extras jam, menit, dan pesan. FFM harus memanggil `resolveActivity()` sebelum membuka intent agar tidak crash jika perangkat tidak memiliki aplikasi penerima. Aplikasi Jam tetap menampilkan UI dan pengguna harus menekan Simpan; FFM tidak membuat alarm langsung.

Dokumentasi Android juga menyebut permission `com.android.alarm.permission.SET_ALARM` untuk memanggil `ACTION_SET_ALARM`. Ini berbeda dari menjadwalkan exact alarm sendiri dengan `AlarmManager`. Meskipun `ACTION_SET_ALARM` dapat dipakai untuk mendelegasikan ke aplikasi Jam, FFM saat ini telah mengimplementasikan notifikasi pengingat internal menggunakan `AndroidScheduleMode.exactAllowWhileIdle`. Oleh karena itu, permission `SCHEDULE_EXACT_ALARM` wajib dipertahankan pada manifest FFM.

### ACTION_SEND / Sharesheet

Bagikan laporan sangat masuk akal dan sudah selaras dengan fitur file chat berbasis `share_plus`. Android merekomendasikan Sharesheet/resolver untuk mengirim binary content dengan `ACTION_SEND`, MIME type yang tepat, dan URI yang dapat dibaca aplikasi tujuan. FileProvider/per-URI permission diperlukan pada implementasi native langsung. `share_plus` menangani jalur platform, tetapi file tetap harus dibuat lokal dan pengguna harus memulai aksi Bagikan.

MIME type yang disarankan:

| Format | MIME type |
|---|---|
| PDF | `application/pdf` |
| Markdown | `text/markdown` atau fallback `text/plain` |
| JSON | `application/json` atau `text/json` |

Tidak ada upload cloud dari desain ini. Jika tidak ada aplikasi yang dapat menerima format tersebut, UI harus menampilkan error yang dapat dipulihkan. Data finansial detail perlu diberi privacy label dan default agregat.

## Permission dan risiko

Untuk `ACTION_SET_ALARM`, deklarasi `com.android.alarm.permission.SET_ALARM` perlu diverifikasi pada target SDK dan perangkat akhir. Untuk `ACTION_SEND` file melalui `share_plus`, jangan menambahkan storage permission legacy secara membabi buta; gunakan storage privat aplikasi, URI/content mechanism yang aman, dan grant read permission yang ditangani plugin/platform.

**Koreksi Audit:** `SCHEDULE_EXACT_ALARM` telah ditambahkan dan digunakan oleh `ReminderNotificationService` FFM. Aplikasi harus meminta izin exact alarm kepada pengguna pada Android 14+. Desain pengingat internal ini valid dan tidak boleh dihapus tanpa refactor menyeluruh.

## Keputusan roadmap

- **Bagikan laporan:** layak dipertahankan dan diselesaikan melalui file card/share sheet yang sudah dirintis di chat.
- **Buat Pengingat:** layak sebagai fitur opsional setelah adapter dan native bridge dibuat, dengan handoff ke aplikasi Jam dan konfirmasi pengguna di aplikasi Jam.
- **Implementasi fase ini:** tidak menambahkan native Intent atau permission baru sebelum pengguna mengonfirmasi roadmap item 4 secara terpisah.

## Sumber resmi

[1] [Android Developers — Common intents](https://developer.android.com/guide/components/intents-common)

[2] [Android Developers — Send data to other apps](https://developer.android.com/develop/ui/compose/sharing/send)

[3] [Android Developers — Schedule exact alarms are denied by default](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms)
