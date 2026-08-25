import '../../domain/ffm_agent_harness.dart';

/// Plugin Tangan & Logika: Ekstraksi catatan cepat terstruktur (Quick Notes) dan kalkulasi otomatis.
class FfmQuickNoteActuatorPlugin extends FfmAgentPlugin {
  FfmQuickNoteActuatorPlugin();

  @override
  String get name => 'quick_note_actuator';

  @override
  FfmPluginCategory get category => FfmPluginCategory.actuator;

  @override
  int get priority => 10;

  @override
  List<String> get triggers => [
    'catat luas',
    'luas tanah',
    'total luas',
    'hitung luas',
    'catat note',
    'simpan koordinat',
    'catat koordinat',
    'quick note',
    'catatan cepat',
    'berapa total luas',
    'hitung total luas',
  ];

  @override
  bool canHandle(String normalizedText) {
    final lower = normalizedText.toLowerCase();
    if (lower.contains('harian') ||
        lower.contains('pengeluaran') ||
        lower.contains('pemasukan') ||
        lower.contains('beli ') ||
        lower.contains('jual ') ||
        lower.contains('bayar ') ||
        lower.contains('transfer') ||
        lower.contains('anggaran') ||
        lower.contains('target') ||
        lower.contains('aset') ||
        lower.contains('hutang') ||
        lower.contains('piutang') ||
        lower.contains('rutinitas') ||
        lower.contains('jadwal') ||
        lower.contains('profil') ||
        lower.contains('pengingat')) {
      return false;
    }
    return triggers.any((t) => lower.contains(t));
  }

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final raw = context.rawText;
    final normalized = context.normalizedText.toLowerCase();

    // 1. Check if user is asking for calculation of existing notes (e.g. "total luas", "hitung luas", "berapa total luas")
    final isCalculationQuery = normalized.contains('total luas') ||
        normalized.contains('hitung luas') ||
        normalized.contains('berapa total luas') ||
        normalized.contains('total tanah');

    if (isCalculationQuery) {
      return _calculateTotal(context);
    }

    // 2. Structured Extraction for New Note
    final extracted = _extractNoteData(raw, normalized);
    if (extracted == null) return null;

    final snapshot = context.activitySnapshot;
    final activeRoot = snapshot?.rootSession;

    final buffer = StringBuffer();
    buffer.writeln('Saya menyiapkan draf catatan baru:');
    buffer.writeln('📝 **Kategori:** ${extracted.category}');
    buffer.writeln('📄 **Isi:** ${extracted.text}');
    if (extracted.numericValue != null) {
      final formattedVal = extracted.numericValue!.truncateToDouble() == extracted.numericValue!
          ? extracted.numericValue!.toInt().toString()
          : extracted.numericValue!.toString();
      buffer.writeln('🔢 **Nilai:** $formattedVal ${extracted.unit ?? ""}');
    }
    if (extracted.latitude != null && extracted.longitude != null) {
      buffer.writeln('📍 **Koordinat:** ${extracted.latitude}, ${extracted.longitude}');
    }
    if (activeRoot != null) {
      buffer.writeln('🔗 **Terkait Sesi:** ${activeRoot.title}');
    }
    buffer.writeln('\nTekan **Konfirmasi** untuk menyimpan.');

    return FfmHarnessResult(
      pluginName: name,
      category: category,
      isDraft: true,
      text: buffer.toString().trim(),
      metadata: {
        'action': 'add_quick_note',
        'text': extracted.text,
        'category': extracted.category,
        'numericValue': extracted.numericValue,
        'unit': extracted.unit,
        'latitude': extracted.latitude,
        'longitude': extracted.longitude,
        'linkedSessionId': activeRoot?.id,
        'expectedRevision': snapshot?.revision,
      },
    );
  }

  FfmHarnessResult _calculateTotal(FfmHarnessContext context) {
    final snapshot = context.activitySnapshot;
    final notes = snapshot?.notes ?? const [];

    final areaNotes = notes.where(
      (n) => (n.category == 'luas_tanah' || (n.unit != null && (n.unit!.contains('m2') || n.unit!.contains('m²') || n.unit!.contains('ha')))) &&
          n.numericValue != null &&
          !n.isArchived,
    ).toList();

    if (areaNotes.isEmpty) {
      return const FfmHarnessResult(
        pluginName: 'quick_note_actuator',
        category: FfmPluginCategory.logic,
        text: 'Belum ada catatan luas tanah yang tersimpan untuk dihitung.',
        metadata: {'total': 0},
      );
    }

    double total = 0;
    final itemsBuffer = StringBuffer();
    final unit = areaNotes.first.unit ?? 'm²';

    for (final note in areaNotes) {
      final val = note.numericValue!;
      total += val;
      final formatted = val.truncateToDouble() == val ? val.toInt().toString() : val.toString();
      itemsBuffer.writeln('• ${note.text}: **$formatted ${note.unit ?? unit}**');
    }

    final formattedTotal = total.truncateToDouble() == total ? total.toInt().toString() : total.toString();

    final buffer = StringBuffer();
    buffer.writeln('📐 **Total Luas Tanah:** **$formattedTotal $unit**\n');
    buffer.writeln('**Rincian Catatan:**');
    buffer.write(itemsBuffer.toString());

    return FfmHarnessResult(
      pluginName: name,
      category: FfmPluginCategory.logic,
      text: buffer.toString().trim(),
      metadata: {
        'total': total,
        'unit': unit,
        'count': areaNotes.length,
      },
    );
  }

  _ExtractedNote? _extractNoteData(String raw, String normalized) {
    // Check for area note: e.g. "catat luas tanah 1200 m2", "tambahkan 500 m2", "luas 1200 m2"
    final areaMatch = RegExp(r'(?:luas(?: tanah)?|tambahkan|tambah)?\s*(\d+(?:[.,]\d+)?)\s*(m2|m²|meter persegi|hektar|ha)', caseSensitive: false).firstMatch(raw);
    if (areaMatch != null) {
      final numStr = areaMatch.group(1)!.replaceAll(',', '.');
      final val = double.tryParse(numStr);
      final unit = areaMatch.group(2)!.toLowerCase();
      return _ExtractedNote(
        text: raw,
        category: 'luas_tanah',
        numericValue: val,
        unit: unit == 'meter persegi' ? 'm²' : unit,
      );
    }

    // Check for coordinate note: e.g. "simpan koordinat -6.2088, 106.8456"
    final coordMatch = RegExp(r'(-?\d+\.\d+)[,\s]+(-?\d+\.\d+)').firstMatch(raw);
    if (coordMatch != null && (normalized.contains('koordinat') || normalized.contains('lokasi'))) {
      final lat = double.tryParse(coordMatch.group(1)!);
      final lon = double.tryParse(coordMatch.group(2)!);
      return _ExtractedNote(
        text: raw,
        category: 'koordinat',
        latitude: lat,
        longitude: lon,
      );
    }

    // Check for general numeric note: e.g. "catat harga 50000", "catat 100 kg"
    final numMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*([a-zA-Z%]+)?').firstMatch(raw);
    if (numMatch != null && (normalized.startsWith('catat') || normalized.startsWith('simpan'))) {
      final numStr = numMatch.group(1)!.replaceAll(',', '.');
      final val = double.tryParse(numStr);
      final unit = numMatch.group(2);
      return _ExtractedNote(
        text: raw,
        category: 'angka_catatan',
        numericValue: val,
        unit: unit,
      );
    }

    // Generic note
    if (normalized.startsWith('catat ') || normalized.startsWith('simpan catatan')) {
      final cleanText = raw.replaceFirst(RegExp(r'^(catat|simpan catatan)\s+', caseSensitive: false), '').trim();
      if (cleanText.isNotEmpty) {
        return _ExtractedNote(
          text: cleanText,
          category: 'catatan_umum',
        );
      }
    }

    return null;
  }
}

class _ExtractedNote {
  const _ExtractedNote({
    required this.text,
    required this.category,
    this.numericValue,
    this.unit,
    this.latitude,
    this.longitude,
  });

  final String text;
  final String category;
  final double? numericValue;
  final String? unit;
  final double? latitude;
  final double? longitude;
}
