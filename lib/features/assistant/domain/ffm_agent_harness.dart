import '../../activity/domain/entities/activity_entity.dart';

/// FFM Offline Agent Harness — terinspirasi arsitektur modular DeepSeek Harness (dsh).
///
/// Setiap kemampuan asisten (baca data, aksi, kalkulasi) dimodelkan sebagai
/// [FfmAgentPlugin] yang dapat didaftarkan ke [FfmAgentHarness]. Harness
/// bertindak sebagai sistem saraf pusat yang memetakan perintah teks bebas ke
/// plugin yang tepat, lalu mengembalikan [FfmHarnessResult].
///
/// Prinsip utama:
/// - 100% Offline: tidak ada plugin yang menggunakan internet.
/// - Safety Gate: semua mutasi data dikembalikan sebagai teks/deskripsi; tidak
///   ada plugin yang langsung menulis ke database.
/// - Plug-and-play: menambah kemampuan baru cukup dengan mendaftarkan plugin
///   baru ke [FfmAgentHarness.register] tanpa mengubah kode harness.

/// Kategori plugin yang menentukan peran dan izin plugin.
enum FfmPluginCategory {
  /// Plugin mata — hanya membaca data; tidak ada mutasi.
  sense,

  /// Plugin tangan — menyiapkan draf aksi; mutasi hanya setelah konfirmasi.
  actuator,

  /// Plugin logika — perhitungan/analisis deterministik tanpa I/O database.
  logic,
}

/// Hasil eksekusi plugin tunggal.
class FfmHarnessResult {
  const FfmHarnessResult({
    required this.pluginName,
    required this.category,
    required this.text,
    this.metadata = const <String, Object?>{},
    this.isDraft = false,
  });

  /// Nama plugin yang menghasilkan hasil ini.
  final String pluginName;

  /// Kategori plugin.
  final FfmPluginCategory category;

  /// Teks respons yang siap ditampilkan ke pengguna.
  final String text;

  /// Data tambahan opsional (misal: nilai numerik, daftar akun, dst).
  final Map<String, Object?> metadata;

  /// True jika [text] merupakan ringkasan draf aksi yang masih butuh konfirmasi.
  final bool isDraft;
}

/// Kontrak plugin harness. Setiap plugin wajib mengimplementasi interface ini.
abstract class FfmAgentPlugin {
  /// Nama unik plugin dalam harness.
  String get name;

  /// Kategori plugin (sense / actuator / logic).
  FfmPluginCategory get category;

  /// Kunci-kunci kata yang dipakai untuk mencocokkan permintaan pengguna.
  List<String> get triggers;

  /// Skor prioritas (1–10). Plugin dengan skor lebih tinggi diperiksa lebih
  /// dahulu dalam registry. Nilai default 5.
  int get priority => 5;

  /// Apakah plugin ini mampu menangani [normalizedText].
  /// Implementasi default: cek apakah salah satu [triggers] ada dalam teks.
  bool canHandle(String normalizedText) {
    final lower = normalizedText.toLowerCase();
    return triggers.any((t) => lower.contains(t));
  }

  /// Eksekusi plugin. Wajib mengembalikan [FfmHarnessResult] atau null jika
  /// plugin memutuskan teks tidak relevan setelah pemeriksaan lebih lanjut.
  Future<FfmHarnessResult?> execute(FfmHarnessContext context);
}

/// Konteks yang dikirim ke setiap plugin saat eksekusi.
class FfmHarnessContext {
  const FfmHarnessContext({
    required this.rawText,
    required this.normalizedText,
    required this.householdId,
    required this.now,
    this.parameters = const <String, Object?>{},
    this.activitySnapshot,
  });

  final String rawText;
  final String normalizedText;
  final String householdId;
  final DateTime now;

  /// Parameter tambahan yang bisa diisi oleh harness sebelum dispatch ke plugin.
  final Map<String, Object?> parameters;

  /// Snapshot live aktivitas yang sedang berjalan di layar (in-memory state).
  final ActivityLiveSnapshot? activitySnapshot;
}

/// FFM Offline Agent Harness — Registry & Dispatcher utama.
class FfmAgentHarness {
  FfmAgentHarness();

  final List<FfmAgentPlugin> _plugins = [];

  /// Mendaftarkan satu plugin ke harness.
  void register(FfmAgentPlugin plugin) {
    _plugins.add(plugin);
    // Urutkan dari prioritas tertinggi ke terendah setiap kali ada plugin baru.
    _plugins.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Mendaftarkan banyak plugin sekaligus.
  void registerAll(Iterable<FfmAgentPlugin> plugins) {
    for (final p in plugins) {
      _plugins.add(p);
    }
    _plugins.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Menghapus semua plugin yang terdaftar (berguna untuk testing).
  void clear() => _plugins.clear();

  /// Daftar nama semua plugin yang terdaftar, dikelompokkan per kategori.
  Map<FfmPluginCategory, List<String>> get pluginInventory {
    final result = <FfmPluginCategory, List<String>>{};
    for (final p in _plugins) {
      result.putIfAbsent(p.category, () => []).add(p.name);
    }
    return result;
  }

  /// Jumlah plugin per kategori.
  int countByCategory(FfmPluginCategory category) =>
      _plugins.where((p) => p.category == category).length;

  /// Total plugin terdaftar.
  int get pluginCount => _plugins.length;

  /// Mencoba menangani [normalizedText] dengan plugin yang tersedia.
  ///
  /// Mengembalikan [FfmHarnessResult] dari plugin pertama yang berhasil, atau
  /// null jika tidak ada plugin yang cocok.
  Future<FfmHarnessResult?> dispatch(FfmHarnessContext context) async {
    for (final plugin in _plugins) {
      if (!plugin.canHandle(context.normalizedText)) continue;
      final result = await plugin.execute(context);
      if (result != null) return result;
    }
    return null;
  }

  /// Menjalankan semua plugin yang cocok dan menggabungkan hasilnya.
  /// Berguna untuk query agregat seperti "laporan keuangan lengkap".
  Future<List<FfmHarnessResult>> dispatchAll(FfmHarnessContext context) async {
    final results = <FfmHarnessResult>[];
    for (final plugin in _plugins) {
      if (!plugin.canHandle(context.normalizedText)) continue;
      final result = await plugin.execute(context);
      if (result != null) results.add(result);
    }
    return results;
  }

  /// Menjalankan plugin tertentu by name, terlepas dari trigger matching.
  Future<FfmHarnessResult?> dispatchByName(
    String pluginName,
    FfmHarnessContext context,
  ) async {
    final plugin = _plugins.cast<FfmAgentPlugin?>().firstWhere(
      (p) => p?.name == pluginName,
      orElse: () => null,
    );
    return plugin?.execute(context);
  }

  /// Deskripsi kapabilitas harness untuk self-description asisten.
  String describeCapabilities() {
    final inventory = pluginInventory;
    final senseList =
        inventory[FfmPluginCategory.sense]?.map((n) => '- 👁️ $n').join('\n') ??
        '';
    final actuatorList =
        inventory[FfmPluginCategory.actuator]
            ?.map((n) => '- ✋ $n')
            .join('\n') ??
        '';
    final logicList =
        inventory[FfmPluginCategory.logic]
            ?.map((n) => '- 🧮 $n')
            .join('\n') ??
        '';

    final parts = <String>[];
    if (senseList.isNotEmpty) {
      parts.add('**Mata (Sensor Plugins)**:\n$senseList');
    }
    if (actuatorList.isNotEmpty) {
      parts.add('**Tangan (Actuator Plugins)**:\n$actuatorList');
    }
    if (logicList.isNotEmpty) {
      parts.add('**Logika Khusus (Logic Plugins)**:\n$logicList');
    }
    return parts.join('\n\n');
  }
}
