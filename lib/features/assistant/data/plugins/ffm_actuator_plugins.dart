/// Plugin kategori Actuator (Tangan) — Menyiapkan draf aksi dan format ekspor.
/// Tidak melakukan penulisan ke database secara langsung (wajib konfirmasi pengguna).

import '../../domain/ffm_agent_harness.dart';

/// Plugin Tangan: Membantu menyiapkan draf transaksi pemasukan/pengeluaran/transfer.
class FfmTransactionActuatorPlugin extends FfmAgentPlugin {
  @override
  String get name => 'transaction_actuator';
  @override
  FfmPluginCategory get category => FfmPluginCategory.actuator;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'catat transaksi',
    'input transaksi',
    'bikin transaksi',
    'tambah transaksi',
    'catat pengeluaran',
    'catat pemasukan',
    'catat transfer',
    'pindahkan uang',
    'isi form transaksi',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    return const FfmHarnessResult(
      pluginName: 'transaction_actuator',
      category: FfmPluginCategory.actuator,
      isDraft: true,
      text:
          '✍️ **Menyiapkan Draf Transaksi**\n\n'
          'Sebutkan nominal, rekening, dan kategorinya secara lengkap.\n'
          '*Contoh:* `Beli makan 25 ribu dari BCA` atau `Pemasukan gaji 5 juta ke Mandiri`.\n\n'
          'Draf akan aku tampilkan terlebih dahulu untuk kamu konfirmasi sebelum disimpan.',
    );
  }
}

/// Plugin Tangan: Membantu menyiapkan draf target tabungan baru.
class FfmGoalActuatorPlugin extends FfmAgentPlugin {
  @override
  String get name => 'goal_actuator';
  @override
  FfmPluginCategory get category => FfmPluginCategory.actuator;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'buat target',
    'bikin target',
    'tambah target',
    'target baru',
    'bikin celengan',
    'buat impian',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    return const FfmHarnessResult(
      pluginName: 'goal_actuator',
      category: FfmPluginCategory.actuator,
      isDraft: true,
      text:
          '🎯 **Menyiapkan Draf Target Tabungan**\n\n'
          'Sebutkan nama target dan nominal yang ingin kamu capai.\n'
          '*Contoh:* `Buat target Liburan Akhir Tahun 5 juta` atau `Buat target Dana Darurat 10 juta`.\n\n'
          'Draf akan disiapkan dan kamu bisa memeriksa detailnya di form.',
    );
  }
}

/// Plugin Tangan: Membantu menyiapkan draf pengingat tagihan/aktivitas.
class FfmReminderActuatorPlugin extends FfmAgentPlugin {
  @override
  String get name => 'reminder_actuator';
  @override
  FfmPluginCategory get category => FfmPluginCategory.actuator;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'buat pengingat',
    'ingatkan saya',
    'set reminder',
    'jadwalkan pengingat',
    'tambah pengingat',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    return const FfmHarnessResult(
      pluginName: 'reminder_actuator',
      category: FfmPluginCategory.actuator,
      isDraft: true,
      text:
          '⏰ **Menyiapkan Draf Pengingat**\n\n'
          'Sebutkan apa yang ingin diingatkan dan kapan jadwalnya.\n'
          '*Contoh:* `Ingatkan bayar listrik tanggal 20` atau `Buat pengingat bayar WiFi tiap awal bulan`.\n\n'
          'Notifikasi pengingat berjalan 100% lokal di perangkatmu tanpa cloud.',
    );
  }
}

/// Plugin Tangan: Membantu menyiapkan pratinjau dan ekspor laporan keuangan.
class FfmReportActuatorPlugin extends FfmAgentPlugin {
  @override
  String get name => 'report_actuator';
  @override
  FfmPluginCategory get category => FfmPluginCategory.actuator;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'buat laporan',
    'ekspor laporan',
    'cetak laporan',
    'download laporan',
    'laporan pdf',
    'laporan excel',
    'rekap laporan',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    return const FfmHarnessResult(
      pluginName: 'report_actuator',
      category: FfmPluginCategory.actuator,
      isDraft: true,
      text:
          '📑 **Menyiapkan Ekspor Laporan Keuangan**\n\n'
          'Kamu bisa mencetak atau membagikan laporan keuangan dalam format **PDF** atau **HTML**.\n'
          'Buka menu **Laporan** untuk memilih rentang tanggal dan jenis laporan yang ingin diekspor.',
    );
  }
}

/// Plugin Tangan & Logika: Pembuat data dan template JSON untuk transaksi,
/// anggaran, dan backup saat diminta user di chat.
class FfmJsonGeneratorPlugin extends FfmAgentPlugin {
  FfmJsonGeneratorPlugin();

  @override
  String get name => 'json_generator';
  @override
  FfmPluginCategory get category => FfmPluginCategory.actuator;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'buatkan json',
    'format json',
    'contoh json transaksi',
    'template json belanja',
    'generate json',
    'buat format json',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    const jsonExample = '''```json
{
  "transactions": [
    {
      "date": "2026-08-24",
      "type": "expense",
      "amount": 50000,
      "account": "BCA",
      "category": "Makan & Minum",
      "note": "Makan Siang Soto Ayam"
    },
    {
      "date": "2026-08-24",
      "type": "income",
      "amount": 5000000,
      "account": "BCA",
      "category": "Gaji Bulanan",
      "note": "Gaji Bulan Ini"
    }
  ]
}
```''';

    return const FfmHarnessResult(
      pluginName: 'json_generator',
      category: FfmPluginCategory.actuator,
      isDraft: true,
      text: '📋 **Template JSON Transaksi FFM**\n\n'
          'Berikut format JSON siap pakai untuk impor data atau pencatatan batch:\n\n'
          '$jsonExample\n\n'
          'Kamu bisa menyalin format di atas dan mengisinya dengan data yang kamu inginkan.',
    );
  }
}
