import 'ffm_assistant_models.dart';

enum FfmAssistantCapabilityRisk { readOnly, prepare, mutation, sensitive }

class FfmAssistantCapability {
  const FfmAssistantCapability({
    required this.id,
    required this.label,
    required this.description,
    required this.risk,
    this.destination,
    this.parameterNames = const <String>[],
    this.requiresConfirmation = false,
    this.readOnly = false,
  });

  final String id;
  final String label;
  final String description;
  final FfmAssistantCapabilityRisk risk;
  final FfmAssistantDestination? destination;
  final List<String> parameterNames;
  final bool requiresConfirmation;
  final bool readOnly;

  bool get canRunWithoutConfirmation =>
      readOnly &&
      !requiresConfirmation &&
      risk == FfmAssistantCapabilityRisk.readOnly;
}

class FfmAssistantCapabilityRegistry {
  FfmAssistantCapabilityRegistry._();

  static final List<FfmAssistantCapability> all = List.unmodifiable([
    ...FfmAssistantDestination.values.map(
      (destination) => FfmAssistantCapability(
        id: 'navigate.${destination.name}',
        label: 'Buka ${_destinationName(destination)}',
        description: 'Membuka halaman ${_destinationName(destination)}.',
        risk: FfmAssistantCapabilityRisk.readOnly,
        destination: destination,
        readOnly: true,
      ),
    ),
    const FfmAssistantCapability(
      id: 'read.summary',
      label: 'Baca ringkasan',
      description: 'Membaca ringkasan saldo dan kondisi keuangan lokal.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.summary,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.transactions',
      label: 'Baca transaksi',
      description: 'Mencari dan merangkum transaksi dari database lokal.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.transactions,
      parameterNames: ['dateFrom', 'dateTo', 'category', 'account', 'query'],
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.budget',
      label: 'Baca anggaran',
      description: 'Membaca anggaran dan pemakaian kategori secara lokal.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.budget,
      parameterNames: ['period', 'category'],
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.accounts',
      label: 'Baca rekening',
      description: 'Membaca daftar rekening aktif dalam bentuk ringkas.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.transactions,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.categories',
      label: 'Baca kategori',
      description: 'Membaca kategori aktif dalam bentuk ringkas.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.masterData,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.analysis',
      label: 'Baca analisa',
      description: 'Membaca ringkasan analisa keuangan lokal.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.analysis,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.activity',
      label: 'Baca aktivitas',
      description: 'Membaca log aktivitas lokal.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.activity,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.goals',
      label: 'Baca target',
      description: 'Membaca daftar target keuangan lokal.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.goals,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.assets',
      label: 'Baca aset',
      description: 'Membaca daftar aset lokal.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.assets,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.liabilities',
      label: 'Baca hutang/piutang',
      description: 'Membaca daftar hutang dan piutang lokal.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.liabilities,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.receivable',
      label: 'Baca piutang',
      description: 'Membaca daftar piutang lokal.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.liabilities,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.recurring',
      label: 'Baca transaksi berkala',
      description: 'Membaca jadwal transaksi berkala lokal.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.recurringTransaction,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.reminders',
      label: 'Baca pengingat',
      description: 'Membaca daftar pengingat lokal.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.reminders,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'read.model_status',
      label: 'Periksa status model',
      description: 'Memeriksa kesiapan model lokal.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.localModel,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'draft.income',
      label: 'Siapkan pemasukan',
      description: 'Membuat draft pemasukan tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.transactions,
      parameterNames: [
        'amount',
        'date',
        'account',
        'source',
        'category',
        'note',
      ],
    ),
    const FfmAssistantCapability(
      id: 'draft.expense',
      label: 'Siapkan pengeluaran',
      description: 'Membuat draft pengeluaran tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.transactions,
      parameterNames: [
        'amount',
        'date',
        'account',
        'payee',
        'category',
        'note',
        'tags',
        'attachment',
      ],
    ),
    const FfmAssistantCapability(
      id: 'draft.transfer',
      label: 'Siapkan transfer',
      description: 'Membuat draft transfer tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.transactions,
      parameterNames: [
        'amount',
        'date',
        'fromAccount',
        'toAccount',
        'fee',
        'note',
      ],
    ),
    const FfmAssistantCapability(
      id: 'draft.goal',
      label: 'Siapkan target',
      description: 'Membuat draft target keuangan tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.goals,
      parameterNames: ['name', 'amount', 'date'],
    ),
    const FfmAssistantCapability(
      id: 'draft.goal_deposit',
      label: 'Siapkan setoran target',
      description: 'Membuat draft setoran target tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.transactions,
      parameterNames: ['amount', 'date', 'account', 'goal', 'note'],
    ),
    const FfmAssistantCapability(
      id: 'draft.goal_usage',
      label: 'Siapkan penggunaan target',
      description: 'Membuat draft penggunaan target tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.transactions,
      parameterNames: ['amount', 'date', 'account', 'goal', 'note'],
    ),
    const FfmAssistantCapability(
      id: 'draft.goal_update',
      label: 'Siapkan perubahan target',
      description: 'Menampilkan perubahan target keuangan tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.goals,
      parameterNames: ['targetId', 'amount'],
    ),
    const FfmAssistantCapability(
      id: 'draft.goal_archive',
      label: 'Siapkan arsip target',
      description: 'Menampilkan target keuangan yang akan diarsipkan tanpa mengubah data.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.goals,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'draft.liability',
      label: 'Siapkan utang',
      description: 'Membuat draft utang tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.liabilities,
      parameterNames: ['name', 'amount', 'date', 'note'],
    ),
    const FfmAssistantCapability(
      id: 'draft.receivable',
      label: 'Siapkan piutang',
      description: 'Membuat draft piutang tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.liabilities,
      parameterNames: ['name', 'amount', 'date', 'note'],
    ),
    const FfmAssistantCapability(
      id: 'draft.asset',
      label: 'Siapkan aset',
      description: 'Membuat draft aset tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.assets,
      parameterNames: ['name', 'amount', 'type', 'placement', 'note'],
    ),
    const FfmAssistantCapability(
      id: 'draft.budget',
      label: 'Siapkan anggaran',
      description: 'Membuat draft anggaran tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.budget,
      parameterNames: ['category', 'amount', 'period'],
    ),
    const FfmAssistantCapability(
      id: 'draft.master_data',
      label: 'Siapkan data master',
      description: 'Membuka dan mengisi draft data master tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.masterData,
      parameterNames: ['kind', 'name', 'values'],
    ),
    const FfmAssistantCapability(
      id: 'draft.reminder',
      label: 'Siapkan pengingat',
      description: 'Membuat draft pengingat tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.reminders,
      parameterNames: ['title', 'date', 'note'],
    ),
    const FfmAssistantCapability(
      id: 'draft.reminder_archive',
      label: 'Siapkan arsip pengingat',
      description: 'Menampilkan pengingat yang akan dinonaktifkan tanpa menghapus history.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.reminders,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'draft.activity',
      label: 'Siapkan aktivitas',
      description: 'Membuat draft aktivitas tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['title', 'category', 'date', 'notes'],
    ),
    const FfmAssistantCapability(
      id: 'draft.daily_note',
      label: 'Siapkan Catatan Harian',
      description: 'Membuat preview Catatan Harian tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['title', 'body', 'date'],
    ),
    const FfmAssistantCapability(
      id: 'draft.daily_note_archive',
      label: 'Siapkan arsip Catatan Harian',
      description: 'Menampilkan satu Catatan Harian yang akan diarsipkan tanpa menghapusnya.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'draft.task',
      label: 'Siapkan Tugas',
      description: 'Membuat preview Tugas tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['title', 'note', 'date'],
    ),
    const FfmAssistantCapability(
      id: 'draft.task_update',
      label: 'Siapkan perubahan Tugas',
      description: 'Menampilkan perubahan Tugas tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId', 'title', 'note', 'date'],
    ),
    const FfmAssistantCapability(
      id: 'draft.task_complete',
      label: 'Siapkan penyelesaian Tugas',
      description:
          'Menampilkan Tugas yang akan ditandai selesai tanpa mengubah data.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'draft.task_reopen',
      label: 'Siapkan buka kembali Tugas',
      description: 'Menampilkan Tugas selesai yang akan dibuka kembali tanpa mengubah data.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'draft.task_archive',
      label: 'Siapkan arsip Tugas',
      description: 'Menampilkan Tugas yang akan diarsipkan tanpa menghapusnya.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'draft.routine',
      label: 'Siapkan Rutinitas',
      description:
          'Membuat preview Rutinitas tanpa menyimpan atau membuat pengingat.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['title', 'note', 'weekdays'],
    ),
    const FfmAssistantCapability(
      id: 'draft.routine_update',
      label: 'Siapkan perubahan Rutinitas',
      description:
          'Menampilkan satu Rutinitas yang akan diperbarui tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId', 'title', 'note', 'weekdays'],
    ),
    const FfmAssistantCapability(
      id: 'draft.routine_mark_complete',
      label: 'Siapkan tanda Rutinitas hari ini',
      description: 'Menampilkan satu Rutinitas yang akan ditandai selesai hari ini tanpa mengubah data.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId', 'date'],
    ),
    const FfmAssistantCapability(
      id: 'draft.routine_unmark_complete',
      label: 'Siapkan pembatalan tanda Rutinitas',
      description: 'Menampilkan satu tanda Rutinitas hari ini yang akan dibatalkan secara eksplisit.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId', 'date'],
    ),
    const FfmAssistantCapability(
      id: 'draft.routine_activate',
      label: 'Siapkan aktivasi Rutinitas',
      description: 'Menampilkan satu Rutinitas yang akan diaktifkan tanpa mengubah data.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'draft.routine_deactivate',
      label: 'Siapkan penonaktifan Rutinitas',
      description: 'Menampilkan satu Rutinitas yang akan dinonaktifkan tanpa mengubah data.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'draft.routine_archive',
      label: 'Siapkan arsip Rutinitas',
      description: 'Menampilkan satu Rutinitas yang akan diarsipkan tanpa hapus permanen.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'draft.schedule',
      label: 'Siapkan Jadwal',
      description:
          'Membuat preview agenda Jadwal tanpa menyimpan atau membuat alarm.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: [
        'title',
        'date',
        'note',
        'isAllDay',
        'startMinutes',
        'endMinutes',
      ],
    ),
    const FfmAssistantCapability(
      id: 'draft.schedule_update',
      label: 'Siapkan perubahan Jadwal',
      description: 'Menampilkan satu agenda Jadwal yang akan diperbarui tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: [
        'targetId',
        'title',
        'date',
        'note',
        'isAllDay',
        'startMinutes',
        'endMinutes',
      ],
    ),
    const FfmAssistantCapability(
      id: 'draft.schedule_archive',
      label: 'Siapkan arsip Jadwal',
      description: 'Menampilkan satu agenda Jadwal yang akan diarsipkan tanpa hapus permanen.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'mutate.save_draft',
      label: 'Simpan draft',
      description: 'Menyimpan draft yang telah ditinjau ke database lokal.',
      risk: FfmAssistantCapabilityRisk.mutation,
      requiresConfirmation: true,
    ),
    const FfmAssistantCapability(
      id: 'draft.transaction_update',
      label: 'Siapkan perubahan transaksi',
      description:
          'Menampilkan perubahan transaksi yang diusulkan tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.transactions,
      parameterNames: ['targetId', 'amount', 'note', 'date'],
    ),
    const FfmAssistantCapability(
      id: 'draft.transaction_archive',
      label: 'Siapkan arsip transaksi',
      description:
          'Menampilkan transaksi yang akan diarsipkan tanpa mengubah data.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.transactions,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'draft.transaction_delete',
      label: 'Siapkan hapus transaksi',
      description: 'Menampilkan transaksi yang akan dihapus sebelum konfirmasi eksplisit.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.transactions,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'draft.activity_archive',
      label: 'Siapkan arsip aktivitas',
      description: 'Menampilkan aktivitas selesai yang akan diarsipkan tanpa mengubah data.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'draft.activity_delete',
      label: 'Siapkan hapus aktivitas',
      description: 'Menampilkan aktivitas selesai beserta dampak hapusnya sebelum konfirmasi eksplisit.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['targetId'],
    ),
    const FfmAssistantCapability(
      id: 'verify.saved_draft',
      label: 'Verifikasi hasil simpan',
      description: 'Membaca kembali hasil mutation untuk memastikan perubahan benar-benar tersimpan.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'verify.transaction_mutation',
      label: 'Verifikasi perubahan transaksi',
      description: 'Membaca kembali status transaksi setelah perubahan, arsip, atau hapus.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'verify.activity_mutation',
      label: 'Verifikasi perubahan aktivitas',
      description: 'Membaca kembali status aktivitas setelah arsip atau hapus.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'verify.daily_note_mutation',
      label: 'Verifikasi Catatan Harian',
      description: 'Membaca kembali Catatan Harian setelah simpan atau arsip.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'verify.task_mutation',
      label: 'Verifikasi Tugas',
      description:
          'Membaca kembali Tugas setelah simpan, ubah status, atau arsip.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'verify.routine_mutation',
      label: 'Verifikasi Rutinitas',
      description:
          'Membaca kembali Rutinitas atau tanda hariannya setelah perubahan.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'verify.schedule_mutation',
      label: 'Verifikasi Jadwal',
      description: 'Membaca kembali agenda Jadwal setelah simpan, perubahan, atau arsip.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'verify.goal_mutation',
      label: 'Verifikasi perubahan target',
      description: 'Membaca kembali target setelah perubahan atau arsip.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'verify.reminder_mutation',
      label: 'Verifikasi arsip pengingat',
      description: 'Membaca kembali status pengingat setelah dinonaktifkan.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      readOnly: true,
    ),
    const FfmAssistantCapability(
      id: 'mutate.update',
      label: 'Perbarui data',
      description: 'Memperbarui data aplikasi yang dipilih pengguna.',
      risk: FfmAssistantCapabilityRisk.mutation,
      requiresConfirmation: true,
    ),
    const FfmAssistantCapability(
      id: 'mutate.archive',
      label: 'Arsipkan data',
      description: 'Mengarsipkan data yang dipilih pengguna.',
      risk: FfmAssistantCapabilityRisk.mutation,
      requiresConfirmation: true,
    ),
    const FfmAssistantCapability(
      id: 'sensitive.delete',
      label: 'Hapus data',
      description: 'Menghapus data setelah konfirmasi eksplisit.',
      risk: FfmAssistantCapabilityRisk.sensitive,
      requiresConfirmation: true,
    ),
    const FfmAssistantCapability(
      id: 'model.status',
      label: 'Periksa SLM lokal',
      description: 'Memeriksa kesiapan model lokal tanpa mengunduh otomatis.',
      risk: FfmAssistantCapabilityRisk.readOnly,
      destination: FfmAssistantDestination.localModel,
      readOnly: true,
    ),
  ]);

  static String _destinationName(FfmAssistantDestination destination) =>
      FfmAssistantCatalog.findByDestination(destination)?.name ??
      destination.name;

  static FfmAssistantCapability? find(String id) {
    for (final capability in all) {
      if (capability.id == id) return capability;
    }
    return null;
  }

  static List<FfmAssistantCapability> forDestination(
    FfmAssistantDestination destination,
  ) => all
      .where((capability) => capability.destination == destination)
      .toList(growable: false);
}
