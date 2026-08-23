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
      id: 'draft.activity',
      label: 'Siapkan aktivitas',
      description: 'Membuat draft aktivitas tanpa menyimpan.',
      risk: FfmAssistantCapabilityRisk.prepare,
      destination: FfmAssistantDestination.activity,
      parameterNames: ['title', 'category', 'date', 'notes'],
    ),
    const FfmAssistantCapability(
      id: 'mutate.save_draft',
      label: 'Simpan draft',
      description: 'Menyimpan draft yang telah ditinjau ke database lokal.',
      risk: FfmAssistantCapabilityRisk.mutation,
      requiresConfirmation: true,
    ),
    const FfmAssistantCapability(
      id: 'verify.saved_draft',
      label: 'Verifikasi hasil simpan',
      description: 'Membaca kembali hasil mutation untuk memastikan perubahan benar-benar tersimpan.',
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
