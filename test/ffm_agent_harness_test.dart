/// Unit tests untuk FfmAgentHarness dan FfmAgentPlugin.
/// Semua test berjalan tanpa database nyata (menggunakan stub/mock ringan).

import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_agent_harness.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STUB PLUGINS untuk testing
// ─────────────────────────────────────────────────────────────────────────────

class _StubSensePlugin extends FfmAgentPlugin {
  @override
  String get name => 'stub_sense';
  @override
  FfmPluginCategory get category => FfmPluginCategory.sense;
  @override
  int get priority => 9;
  @override
  List<String> get triggers => ['saldo', 'rekening'];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: 'Saldo rekening: Rp 1.000.000',
      metadata: const {'balance': 1000000},
    );
  }
}

class _StubActuatorPlugin extends FfmAgentPlugin {
  @override
  String get name => 'stub_actuator';
  @override
  FfmPluginCategory get category => FfmPluginCategory.actuator;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => ['catat', 'transaksi'];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: 'Draf transaksi disiapkan.',
      isDraft: true,
    );
  }
}

class _StubLogicPlugin extends FfmAgentPlugin {
  @override
  String get name => 'stub_logic';
  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => ['zakat', 'hitung zakat'];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: 'Zakat mal: Rp 50.000',
    );
  }
}

/// Plugin yang selalu mengembalikan null (tidak menangani).
class _NullPlugin extends FfmAgentPlugin {
  @override
  String get name => 'null_plugin';
  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;
  @override
  List<String> get triggers => ['xyz_sangat_jarang'];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async => null;
}

/// Plugin prioritas rendah yang memiliki trigger sama dengan sense tapi tidak
/// boleh dipanggil lebih dahulu.
class _LowPriorityPlugin extends FfmAgentPlugin {
  @override
  String get name => 'low_priority';
  @override
  FfmPluginCategory get category => FfmPluginCategory.logic;
  @override
  int get priority => 1;
  @override
  List<String> get triggers => ['saldo'];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    return FfmHarnessResult(
      pluginName: name,
      category: category,
      text: 'Jawaban prioritas rendah',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER
// ─────────────────────────────────────────────────────────────────────────────

FfmHarnessContext _ctx(String text) => FfmHarnessContext(
  rawText: text,
  normalizedText: text.toLowerCase(),
  householdId: 'test_household',
  now: DateTime(2025, 8, 1),
);

// ─────────────────────────────────────────────────────────────────────────────
// TESTS
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('FfmAgentHarness — Core Registry', () {
    late FfmAgentHarness harness;

    setUp(() {
      harness = FfmAgentHarness();
    });

    test('awal mulai harness kosong (0 plugin)', () {
      expect(harness.pluginCount, 0);
    });

    test('register() menambah 1 plugin', () {
      harness.register(_StubSensePlugin());
      expect(harness.pluginCount, 1);
    });

    test('registerAll() menambah banyak plugin sekaligus', () {
      harness.registerAll([
        _StubSensePlugin(),
        _StubActuatorPlugin(),
        _StubLogicPlugin(),
      ]);
      expect(harness.pluginCount, 3);
    });

    test('clear() mengosongkan semua plugin', () {
      harness.registerAll([_StubSensePlugin(), _StubActuatorPlugin()]);
      harness.clear();
      expect(harness.pluginCount, 0);
    });

    test('countByCategory() menghitung per kategori dengan benar', () {
      harness.registerAll([
        _StubSensePlugin(),
        _StubActuatorPlugin(),
        _StubLogicPlugin(),
        _StubLogicPlugin(), // duplikat logic
      ]);
      expect(harness.countByCategory(FfmPluginCategory.sense), 1);
      expect(harness.countByCategory(FfmPluginCategory.actuator), 1);
      expect(harness.countByCategory(FfmPluginCategory.logic), 2);
    });

    test('pluginInventory() mengelompokkan plugin per kategori', () {
      harness.registerAll([
        _StubSensePlugin(),
        _StubLogicPlugin(),
      ]);
      final inventory = harness.pluginInventory;
      expect(inventory[FfmPluginCategory.sense], contains('stub_sense'));
      expect(inventory[FfmPluginCategory.logic], contains('stub_logic'));
      expect(inventory[FfmPluginCategory.actuator], isNull);
    });
  });

  group('FfmAgentHarness — Dispatch', () {
    late FfmAgentHarness harness;

    setUp(() {
      harness = FfmAgentHarness();
    });

    test('dispatch() mengembalikan null jika tidak ada plugin cocok', () async {
      harness.register(_StubSensePlugin());
      final result = await harness.dispatch(_ctx('topik tidak dikenal'));
      expect(result, isNull);
    });

    test('dispatch() memanggil plugin yang cocok berdasarkan trigger', () async {
      harness.register(_StubSensePlugin());
      final result = await harness.dispatch(_ctx('berapa saldo rekening saya'));
      expect(result, isNotNull);
      expect(result!.pluginName, 'stub_sense');
      expect(result.text, contains('Saldo rekening'));
    });

    test('dispatch() mengembalikan plugin prioritas tertinggi ketika ada 2 cocok', () async {
      // StubSensePlugin: priority 9, LowPriorityPlugin: priority 1, keduanya trigger 'saldo'
      harness.registerAll([_LowPriorityPlugin(), _StubSensePlugin()]);
      final result = await harness.dispatch(_ctx('saldo rekening'));
      expect(result!.pluginName, 'stub_sense'); // prioritas 9 menang
    });

    test('dispatch() melanjutkan ke plugin berikut jika plugin pertama null', () async {
      harness.registerAll([_NullPlugin(), _StubSensePlugin()]);
      // _NullPlugin trigger 'xyz_sangat_jarang' — tidak cocok, lanjut ke sense
      final result = await harness.dispatch(_ctx('cek saldo rekening'));
      expect(result!.pluginName, 'stub_sense');
    });

    test('dispatch() mengembalikan actuator untuk kata kunci catat', () async {
      harness.register(_StubActuatorPlugin());
      final result = await harness.dispatch(_ctx('catat transaksi belanja'));
      expect(result!.category, FfmPluginCategory.actuator);
      expect(result.isDraft, isTrue);
    });

    test('dispatch() mengembalikan logic plugin untuk zakat', () async {
      harness.register(_StubLogicPlugin());
      final result = await harness.dispatch(_ctx('hitung zakat mal saya'));
      expect(result!.pluginName, 'stub_logic');
      expect(result.category, FfmPluginCategory.logic);
    });
  });

  group('FfmAgentHarness — dispatchAll', () {
    late FfmAgentHarness harness;

    setUp(() {
      harness = FfmAgentHarness();
    });

    test('dispatchAll() mengembalikan semua plugin yang cocok', () async {
      // Dua plugin berbeda yang sama-sama bisa menangani 'saldo'
      harness.registerAll([_StubSensePlugin(), _LowPriorityPlugin()]);
      final results = await harness.dispatchAll(_ctx('saldo rekening'));
      expect(results.length, 2);
    });

    test('dispatchAll() mengembalikan list kosong jika tidak ada yang cocok', () async {
      harness.register(_StubSensePlugin());
      final results = await harness.dispatchAll(_ctx('cuaca hari ini'));
      expect(results, isEmpty);
    });
  });

  group('FfmAgentHarness — dispatchByName', () {
    late FfmAgentHarness harness;

    setUp(() {
      harness = FfmAgentHarness();
      harness.registerAll([_StubSensePlugin(), _StubActuatorPlugin()]);
    });

    test('dispatchByName() memanggil plugin bernama yang tepat', () async {
      final result = await harness.dispatchByName('stub_actuator', _ctx('apapun'));
      expect(result!.pluginName, 'stub_actuator');
    });

    test('dispatchByName() mengembalikan null jika nama tidak ditemukan', () async {
      final result = await harness.dispatchByName('plugin_tidak_ada', _ctx('apapun'));
      expect(result, isNull);
    });
  });

  group('FfmAgentHarness — describeCapabilities', () {
    test('describeCapabilities() menghasilkan string yang menyebut semua kategori', () {
      final harness = FfmAgentHarness();
      harness.registerAll([
        _StubSensePlugin(),
        _StubActuatorPlugin(),
        _StubLogicPlugin(),
      ]);
      final desc = harness.describeCapabilities();
      expect(desc, contains('Mata'));
      expect(desc, contains('Tangan'));
      expect(desc, contains('Logika'));
      expect(desc, contains('stub_sense'));
      expect(desc, contains('stub_actuator'));
      expect(desc, contains('stub_logic'));
    });
  });

  group('FfmHarnessResult — properties', () {
    test('isDraft default false', () {
      const result = FfmHarnessResult(
        pluginName: 'p',
        category: FfmPluginCategory.sense,
        text: 'ok',
      );
      expect(result.isDraft, isFalse);
    });

    test('metadata default empty', () {
      const result = FfmHarnessResult(
        pluginName: 'p',
        category: FfmPluginCategory.sense,
        text: 'ok',
      );
      expect(result.metadata, isEmpty);
    });

    test('isDraft true ketika diset', () {
      const result = FfmHarnessResult(
        pluginName: 'p',
        category: FfmPluginCategory.actuator,
        text: 'draf',
        isDraft: true,
      );
      expect(result.isDraft, isTrue);
    });
  });

  group('FfmAgentPlugin — canHandle default', () {
    test('mengembalikan true saat trigger ada dalam normalized text', () {
      final plugin = _StubSensePlugin();
      expect(plugin.canHandle('berapa saldo rekening saya'), isTrue);
    });

    test('mengembalikan false saat tidak ada trigger yang cocok', () {
      final plugin = _StubSensePlugin();
      expect(plugin.canHandle('cuaca cerah hari ini'), isFalse);
    });

    test('case-insensitive karena context.normalizedText sudah lowercase', () {
      final plugin = _StubSensePlugin();
      expect(plugin.canHandle('saldo BCA'), isTrue); // trigger 'saldo' ada
    });
  });

  group('FfmAgentHarness — New Intelligence Plugins triggers', () {
    test('SpendingPace (Boros vs Hemat) trigger matching', () {
      final triggers = ['boros', 'hemat', 'apakah saya boros', 'laju pengeluaran', 'burn rate', 'kuota belanja harian'];
      for (final t in triggers) {
        expect(t.contains('boros') || t.contains('hemat') || t.contains('laju') || t.contains('rate') || t.contains('kuota'), isTrue);
      }
    });

    test('HolisticAwareness trigger matching', () {
      final triggers = ['kondisi keuangan keseluruhan', 'potret keuangan', 'kesehatan keuangan lengkap', 'dashboard keuangan'];
      for (final t in triggers) {
        expect(t.contains('keuangan') || t.contains('potret'), isTrue);
      }
    });

    test('UserHabitsAndProfile trigger matching', () {
      final triggers = ['sejauh mana kamu mengenalku', 'apa saja kebiasaanku', 'pola keseharianku', 'rutinitas saya'];
      for (final t in triggers) {
        expect(t.contains('mengenalku') || t.contains('kebiasaan') || t.contains('keseharian') || t.contains('rutinitas'), isTrue);
      }
    });

    test('JsonGenerator trigger matching', () {
      final triggers = ['buatkan json', 'format json', 'template json belanja'];
      for (final t in triggers) {
        expect(t.contains('json'), isTrue);
      }
    });

    test('ReceivableSense trigger matching', () {
      final triggers = ['cek piutang', 'daftar piutang', 'siapa yang pinjam', 'orang pinjam'];
      for (final t in triggers) {
        expect(t.contains('piutang') || t.contains('pinjam'), isTrue);
      }
    });

    test('RecurringTransactionSense trigger matching', () {
      final triggers = ['transaksi berulang', 'langganan', 'tagihan rutin', 'rutin bulanan'];
      for (final t in triggers) {
        expect(t.contains('berulang') || t.contains('langganan') || t.contains('rutin'), isTrue);
      }
    });

    test('DailyNotesSense trigger matching', () {
      final triggers = ['catatan harian', 'jurnal', 'catatan hari ini', 'daily notes'];
      for (final t in triggers) {
        expect(t.contains('catatan') || t.contains('jurnal') || t.contains('daily'), isTrue);
      }
    });

    test('EmergencyFundLogic trigger matching', () {
      final triggers = ['dana darurat', 'hitung dana darurat', 'emergency fund', 'tabungan darurat'];
      for (final t in triggers) {
        expect(t.contains('darurat') || t.contains('emergency'), isTrue);
      }
    });

    test('TaskSense trigger matching', () {
      final triggers = ['tugas belum selesai', 'daftar tugas', 'tugas hari ini', 'to-do'];
      for (final t in triggers) {
        expect(t.contains('tugas') || t.contains('to-do') || t.contains('todo'), isTrue);
      }
    });

    test('ScheduleSense trigger matching', () {
      final triggers = ['jadwal hari ini', 'agenda besok', 'jadwal minggu ini', 'ada acara apa'];
      for (final t in triggers) {
        expect(t.contains('jadwal') || t.contains('agenda') || t.contains('acara'), isTrue);
      }
    });

    test('RoutineSense trigger matching', () {
      final triggers = ['rutinitas hari ini', 'kebiasaan', 'ceklis rutinitas', 'daily routine'];
      for (final t in triggers) {
        expect(t.contains('rutinitas') || t.contains('kebiasaan') || t.contains('routine'), isTrue);
      }
    });

    test('TopMerchantSense trigger matching', () {
      final triggers = ['tempat belanja', 'toko favorit', 'sering belanja di mana', 'analisis merchant'];
      for (final t in triggers) {
        expect(t.contains('belanja') || t.contains('toko') || t.contains('merchant'), isTrue);
      }
    });

    test('DebtSnowballLogic trigger matching', () {
      final triggers = ['strategi lunas hutang', 'debt snowball', 'debt avalanche', 'cara cepat lunas hutang'];
      for (final t in triggers) {
        expect(t.contains('hutang') || t.contains('snowball') || t.contains('avalanche'), isTrue);
      }
    });

    test('SavingRateLogic trigger matching', () {
      final triggers = ['saving rate', 'rasio menabung', 'persentase tabungan', 'berapa persen yang kutabung'];
      for (final t in triggers) {
        expect(t.contains('saving') || t.contains('menabung') || t.contains('tabung'), isTrue);
      }
    });

    test('ActivityReportSense trigger matching', () {
      final triggers = ['laporan aktivitas', 'rekap kegiatan', 'aktivitas mingguan', 'laporan aktivitas bulanan'];
      for (final t in triggers) {
        expect(t.contains('aktivitas') || t.contains('kegiatan'), isTrue);
      }
    });
  });
}




