# Android Toolchain Notes

Halaman resmi Android Developers yang diperiksa pada 22 Agustus 2026 menyatakan bahwa Android SDK Command-line Tools menggantikan paket SDK Tools lama dan dipasang di `cmdline-tools/version/bin/`. Halaman tersebut juga merujuk ke unduhan command-line tools resmi melalui bagian `command-line-tools-only`.

Sumber: https://developer.android.com/tools dan https://developer.android.com/studio#command-line-tools-only

Pada sandbox saat pemeriksaan, `adb`, `sdkmanager`, Android SDK, Gradle, dan CMake tidak tersedia di PATH. Flutter SDK kemudian dipasang untuk analyzer/test Dart, tetapi Android SDK/NDK/device belum dipasang atau tersedia. Karena itu build APK dan smoke test native belum dapat diklaim berhasil.
