import 'package:flutter/material.dart';

import '../../../../reminder/domain/entities/reminder_entity.dart';
import '../../../domain/ffm_assistant_models.dart';

/// Kartu pratinjau draf interaktif yang dapat dibuka-tutup untuk memeriksa detail lengkap.
class FfmAssistantDraftPreview extends StatefulWidget {
  const FfmAssistantDraftPreview({
    super.key,
    required this.draft,
    this.review,
    this.onEdit,
  });

  final FfmAssistantDraft draft;
  final FfmAssistantDraftReview? review;
  final VoidCallback? onEdit;

  static String draftLabel(FfmAssistantDraftKind kind) => switch (kind) {
    FfmAssistantDraftKind.income => 'Draft Pemasukan',
    FfmAssistantDraftKind.expense => 'Draft Pengeluaran',
    FfmAssistantDraftKind.transfer => 'Draft Transfer Dana',
    FfmAssistantDraftKind.goalDeposit => 'Draft Setor Target',
    FfmAssistantDraftKind.goalUsage => 'Draft Pakai Target',
    FfmAssistantDraftKind.goal => 'Draft Target Keuangan',
    FfmAssistantDraftKind.liability => 'Draft Hutang',
    FfmAssistantDraftKind.liabilityUpdate => 'Preview Perubahan Hutang',
    FfmAssistantDraftKind.liabilityArchive => 'Preview Arsip Hutang',
    FfmAssistantDraftKind.liabilityPayment => 'Draft Pembayaran Hutang',
    FfmAssistantDraftKind.receivable => 'Draft Piutang',
    FfmAssistantDraftKind.receivableUpdate => 'Preview Perubahan Piutang',
    FfmAssistantDraftKind.receivableArchive => 'Preview Arsip Piutang',
    FfmAssistantDraftKind.receivablePayment => 'Draft Penerimaan Piutang',
    FfmAssistantDraftKind.asset => 'Draft Aset',
    FfmAssistantDraftKind.assetUpdate => 'Preview Perubahan Aset',
    FfmAssistantDraftKind.assetArchive => 'Preview Arsip Aset',
    FfmAssistantDraftKind.budget => 'Draft Anggaran',
    FfmAssistantDraftKind.budgetUpdate => 'Preview Perubahan Batas Anggaran',
    FfmAssistantDraftKind.budgetArchive => 'Preview Arsip Anggaran',
    FfmAssistantDraftKind.masterData => 'Draft Data Utama',
    FfmAssistantDraftKind.merchantUpdate => 'Preview Perubahan Toko/Tempat',
    FfmAssistantDraftKind.merchantArchive => 'Preview Arsip Toko/Tempat',
    FfmAssistantDraftKind.merchantDelete => 'Preview Hapus Toko/Tempat',
    FfmAssistantDraftKind.tagUpdate => 'Preview Perubahan Tag',
    FfmAssistantDraftKind.tagArchive => 'Preview Arsip Tag',
    FfmAssistantDraftKind.tagDelete => 'Preview Hapus Tag',
    FfmAssistantDraftKind.incomeSourceUpdate =>
      'Preview Perubahan Sumber Pemasukan',
    FfmAssistantDraftKind.incomeSourceArchive =>
      'Preview Arsip Sumber Pemasukan',
    FfmAssistantDraftKind.incomeSourceDelete =>
      'Preview Hapus Sumber Pemasukan',
    FfmAssistantDraftKind.categoryUpdate => 'Preview Perubahan Nama Kategori',
    FfmAssistantDraftKind.categoryArchive => 'Preview Arsip Kategori',
    FfmAssistantDraftKind.categoryDelete => 'Preview Hapus Kategori',
    FfmAssistantDraftKind.accountUpdate => 'Preview Perubahan Nama Rekening',
    FfmAssistantDraftKind.accountArchive => 'Preview Arsip Rekening',
    FfmAssistantDraftKind.accountDelete => 'Preview Hapus Rekening',
    FfmAssistantDraftKind.reminder => 'Draft Pengingat',
    FfmAssistantDraftKind.reminderUpdate => 'Preview Perubahan Pengingat',
    FfmAssistantDraftKind.reminderArchive => 'Preview Arsip Pengingat',
    FfmAssistantDraftKind.reminderComplete => 'Preview Selesaikan Pengingat',
    FfmAssistantDraftKind.activity => 'Draft Aktivitas',
    FfmAssistantDraftKind.dailyNote => 'Draft Catatan Harian',
    FfmAssistantDraftKind.dailyNoteArchive => 'Preview Arsip Catatan Harian',
    FfmAssistantDraftKind.dailyNoteUpdate => 'Preview Ubah Catatan Harian',
    FfmAssistantDraftKind.dailyNoteRestore => 'Preview Pulihkan Catatan Harian',
    FfmAssistantDraftKind.dailyNoteDelete => 'Preview Hapus Catatan Harian',
    FfmAssistantDraftKind.task => 'Draft Tugas',
    FfmAssistantDraftKind.taskUpdate => 'Preview Perubahan Tugas',
    FfmAssistantDraftKind.taskComplete => 'Preview Selesaikan Tugas',
    FfmAssistantDraftKind.taskReopen => 'Preview Buka Kembali Tugas',
    FfmAssistantDraftKind.taskArchive => 'Preview Arsip Tugas',
    FfmAssistantDraftKind.routine => 'Draft Rutinitas',
    FfmAssistantDraftKind.routineUpdate => 'Preview Perubahan Rutinitas',
    FfmAssistantDraftKind.routineMarkComplete =>
      'Preview Tandai Rutinitas Hari Ini',
    FfmAssistantDraftKind.routineUnmarkComplete =>
      'Preview Batalkan Tanda Rutinitas Hari Ini',
    FfmAssistantDraftKind.routineActivate => 'Preview Aktifkan Rutinitas',
    FfmAssistantDraftKind.routineDeactivate => 'Preview Nonaktifkan Rutinitas',
    FfmAssistantDraftKind.routineArchive => 'Preview Arsip Rutinitas',
    FfmAssistantDraftKind.schedule => 'Draft Jadwal',
    FfmAssistantDraftKind.scheduleUpdate => 'Preview Perubahan Jadwal',
    FfmAssistantDraftKind.scheduleArchive => 'Preview Arsip Jadwal',
    FfmAssistantDraftKind.recurringTransactionUpdate =>
      'Preview Perubahan Transaksi Berkala',
    FfmAssistantDraftKind.recurringTransactionArchive =>
      'Preview Nonaktifkan Transaksi Berkala',
    FfmAssistantDraftKind.profile => 'Draft Perkenalan Diri',
    FfmAssistantDraftKind.goalUpdate => 'Preview Perubahan Target',
    FfmAssistantDraftKind.goalArchive => 'Preview Arsip Target',
    FfmAssistantDraftKind.transactionUpdate => 'Preview Perubahan Transaksi',
    FfmAssistantDraftKind.transactionArchive => 'Preview Arsip Transaksi',
    FfmAssistantDraftKind.transactionDelete => 'Preview Hapus Transaksi',
    FfmAssistantDraftKind.activityArchive => 'Preview Arsip Aktivitas',
    FfmAssistantDraftKind.activityDelete => 'Preview Hapus Aktivitas',
    FfmAssistantDraftKind.activityFinish => 'Preview Selesaikan Aktivitas',
    FfmAssistantDraftKind.activityUpdate => 'Preview Update Aktivitas',
    FfmAssistantDraftKind.activityEdit => 'Preview Edit Aktivitas',
    FfmAssistantDraftKind.cashFlowProfile => 'Draft Siklus Kas / AgroTrack',
    FfmAssistantDraftKind.monitoringJob => 'Draft Jadwal Pemantauan',
    FfmAssistantDraftKind.meterReading => 'Draft Pembacaan Meter',
  };

  static String rupiah(int amount) =>
      'Rp${amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => '.')}';

  static String friendlyDestinationName(String? route) {
    if (route == null || route.trim().isEmpty) return 'Pengingat / Alarm (Bawaan)';
    return switch (route.trim().toLowerCase()) {
      'reminders' || 'reminder' => 'Pengingat / Alarm (Bawaan)',
      'transactions' => 'Daftar Transaksi',
      'liabilities' => 'Hutang & Tagihan',
      'budget' => 'Anggaran (Budget)',
      'goals' => 'Target Keuangan (Goals)',
      'assets' => 'Daftar Aset',
      'activity' => 'Catatan Harian / Aktivitas',
      'monthlyreport' => 'Laporan Bulanan',
      'familyprofile' => 'Profil Keluarga',
      'summary' => 'Ringkasan Finansial',
      _ => route.trim(),
    };
  }

  static String formFieldLabel(String field) => switch (field) {
    'type' => 'Jenis Kategori',
    'defaultBudgetPeriod' => 'Saran Periode',
    'periodType' => 'Periode Anggaran',
    'monthlyInstallment' => 'Cicilan per Bulan',
    'dueDate' => 'Jatuh Tempo',
    'targetDate' => 'Target Tanggal',
    'interestRate' => 'Bunga (%)',
    'accountType' => 'Jenis Rekening',
    'openingBalance' => 'Saldo Awal',
    'details' => 'Keterangan',
    'targetSummary' => 'Aktivitas target',
    'beforeTitle' => 'Judul sebelumnya',
    'beforeCategory' => 'Kategori sebelumnya',
    'newMerchant' => 'Toko baru yang akan dibuat',
    'newTags' => 'Tag baru yang akan dibuat',
    'tags' => 'Tag transaksi',
    'merchant' => 'Toko',
    'merchantName' => 'Toko',
    'location' => 'Lokasi',
    'incomeSource' => 'Sumber pemasukan',
    'party' => 'Pihak/Penerima',
    'partyName' => 'Pihak/Penerima',
    'receiptNumber' => 'No. Nota',
    'receiptPaidAmount' => 'Nominal Dibayar',
    'receiptChangeAmount' => 'Kembalian',
    'receiptRawText' => 'Teks Nota',
    'itemsJson' => 'Rincian Item',
    'tax' => 'Pajak',
    'discount' => 'Diskon',
    'sourceId' => 'Referensi Sumber',
    'recurringTransactionId' => 'Transaksi Berkala',
    'attachmentPathsJson' => 'Lampiran',
    'adminFee' => 'Biaya Admin',
    'date' => 'Tanggal',
    'fromAccount' => 'Sumber Dana',
    'toAccount' => 'Tujuan Dana',
    'fromAccountName' => 'Sumber Dana',
    'toAccountName' => 'Tujuan Dana',
    'category' => 'Kategori',
    'categoryName' => 'Kategori',
    'amount' => 'Nominal',
    'soundName' => 'Nada Notifikasi',
    _ => field,
  };

  static String formFieldValue(String field, String value) {
    if (field == 'monthlyInstallment') {
      final parsed = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
      if (parsed != null) return rupiah(parsed);
    }
    return switch ('$field:$value') {
      'type:income' => 'Pemasukan',
      'type:expense' => 'Pengeluaran',
      'defaultBudgetPeriod:none' => 'Tidak ada',
      'defaultBudgetPeriod:weekly' => 'Mingguan',
      'defaultBudgetPeriod:monthly' => 'Bulanan',
      'periodType:monthly' => 'Bulanan',
      'periodType:weekly' => 'Mingguan',
      'periodType:biweekly' => 'Per Dua Minggu',
      'periodType:nonrecurring' => 'Tidak Rutin',
      'accountType:cash' => 'Tunai',
      'accountType:bank' => 'Bank',
      'accountType:ewallet' => 'E-Wallet',
      _ => value,
    };
  }

  @override
  State<FfmAssistantDraftPreview> createState() =>
      _FfmAssistantDraftPreviewState();
}

class _FfmAssistantDraftPreviewState extends State<FfmAssistantDraftPreview> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    final review = widget.review;
    final isTransaction = switch (draft.kind) {
      FfmAssistantDraftKind.income ||
      FfmAssistantDraftKind.expense ||
      FfmAssistantDraftKind.transfer => true,
      _ => false,
    };
    final itemSubtotal = draft.items.fold<int>(
      0,
      (sum, item) => sum + item.calculatedTotal,
    );

    final fields = <MapEntry<String, String>>[
      MapEntry(
        'Jenis',
        FfmAssistantDraftPreview.draftLabel(draft.kind)
            .replaceFirst('Draft ', ''),
      ),
      MapEntry('Nama/Judul', draft.title ?? 'Belum diisi'),
      if (draft.amount != null)
        MapEntry('Nominal', FfmAssistantDraftPreview.rupiah(draft.amount!)),
      if (draft.partyName != null)
        MapEntry(
          draft.kind == FfmAssistantDraftKind.liability
              ? 'Pemberi Pinjaman'
              : draft.kind == FfmAssistantDraftKind.receivable
              ? 'Peminjam'
              : draft.kind == FfmAssistantDraftKind.income
              ? 'Sumber Pemasukan'
              : 'Pihak/Penerima',
          draft.partyName!,
        ),
      if (draft.fromAccountName != null)
        MapEntry('Sumber Dana', draft.fromAccountName!),
      if (draft.toAccountName != null)
        MapEntry('Tujuan Dana', draft.toAccountName!),
      if (draft.categoryName != null) MapEntry('Kategori', draft.categoryName!),
      if (draft.merchantName != null) MapEntry('Toko', draft.merchantName!),
      if (draft.formValues['proposedMeterName'] != null ||
          draft.formValues['meterName'] != null)
        MapEntry(
          'Meteran PLN',
          (draft.formValues['proposedMeterName'] ??
                  draft.formValues['meterName'])
              .toString(),
        ),
      if (draft.formValues['meterNumber'] != null ||
          draft.formValues['idpel'] != null)
        MapEntry(
          'IDPEL / No. Meter',
          (draft.formValues['meterNumber'] ?? draft.formValues['idpel'])
              .toString(),
        ),
      if (draft.location?.trim().isNotEmpty == true)
        MapEntry('Lokasi', draft.location!.trim()),
      if (draft.date != null)
        MapEntry(
          draft.kind == FfmAssistantDraftKind.liability ||
                  draft.kind == FfmAssistantDraftKind.receivable
              ? 'Jatuh Tempo'
              : draft.kind == FfmAssistantDraftKind.goal
              ? 'Target Tanggal'
              : draft.kind == FfmAssistantDraftKind.reminder
              ? 'Jadwal Pengingat'
              : 'Tanggal',
          draft.kind == FfmAssistantDraftKind.reminder
              ? '${draft.date!.day.toString().padLeft(2, '0')}/${draft.date!.month.toString().padLeft(2, '0')}/${draft.date!.year} ${draft.date!.hour.toString().padLeft(2, '0')}:${draft.date!.minute.toString().padLeft(2, '0')} WIB'
              : '${draft.date!.day.toString().padLeft(2, '0')}/${draft.date!.month.toString().padLeft(2, '0')}/${draft.date!.year}',
        ),
      if (draft.kind == FfmAssistantDraftKind.reminder) ...[
        () {
          final recurrenceType = draft.recurrenceType ??
              (draft.formValues['recurrence'] != null ||
                      draft.formValues['recurrenceType'] != null
                  ? ReminderRecurrenceTypeX.fromStorage(
                      (draft.formValues['recurrence'] ??
                              draft.formValues['recurrenceType'])
                          .toString(),
                    )
                  : ReminderRecurrenceType.once);
          final recurrenceLabel = switch (recurrenceType) {
            ReminderRecurrenceType.once => 'Sekali',
            ReminderRecurrenceType.daily => 'Setiap hari',
            ReminderRecurrenceType.weekly => () {
              final days = draft.weekdays.isNotEmpty
                  ? draft.weekdays
                  : (draft.formValues['weekdays'] is List
                      ? (draft.formValues['weekdays'] as List)
                          .map((e) => int.tryParse(e.toString()))
                          .whereType<int>()
                          .toList()
                      : draft.formValues['weekdays'] is String
                          ? (draft.formValues['weekdays'] as String)
                              .split(',')
                              .map((e) => int.tryParse(e.trim()))
                              .whereType<int>()
                              .toList()
                          : <int>[]);
              if (days.isEmpty) return 'Hari tertentu';
              const dayNames = {
                1: 'Senin',
                2: 'Selasa',
                3: 'Rabu',
                4: 'Kamis',
                5: 'Jumat',
                6: 'Sabtu',
                7: 'Minggu',
              };
              return 'Hari: ${days.map((d) => dayNames[d] ?? '$d').join(', ')}';
            }(),
            ReminderRecurrenceType.monthly => 'Bulanan',
            ReminderRecurrenceType.yearly => 'Tahunan',
            ReminderRecurrenceType.hijriMonthly => 'Bulanan Hijriah',
          };
          return MapEntry('Pengulangan', recurrenceLabel);
        }(),
        MapEntry(
          'Tipe Pengingat',
          (draft.reminderMode == ReminderMode.alarm ||
                  draft.formValues['reminderMode'] == 'alarm' ||
                  draft.formValues['mode'] == 'alarm')
              ? 'Alarm Nyaring ⏰'
              : 'Notifikasi Biasa 🔔',
        ),
        if (draft.soundName != null || draft.formValues['soundName'] != null)
          MapEntry(
            'Nada Notifikasi',
            draft.soundName ?? draft.formValues['soundName'].toString(),
          ),
        if ((draft.destinationRoute != null &&
                draft.destinationRoute!.trim().isNotEmpty) ||
            (draft.formValues['destinationRoute'] != null &&
                draft.formValues['destinationRoute']
                    .toString()
                    .trim()
                    .isNotEmpty))
          MapEntry(
            'Halaman Tujuan',
            FfmAssistantDraftPreview.friendlyDestinationName(
              draft.destinationRoute ??
                  draft.formValues['destinationRoute'].toString(),
            ),
          ),
      ],
      if (draft.tags?.trim().isNotEmpty == true)
        MapEntry('Tag transaksi', draft.tags!.trim()),
      if (draft.newTags?.trim().isNotEmpty == true)
        MapEntry('Tag baru', draft.newTags!.trim()),
      if (draft.newMerchant?.trim().isNotEmpty == true)
        MapEntry('Toko baru', draft.newMerchant!.trim()),
      if (!isTransaction)
        ...draft.formValues.entries
            .where(
              (field) =>
                  field.value.toString().trim().isNotEmpty &&
                  !const {
                    'location',
                    'date',
                    'merchant',
                    'merchantName',
                    'category',
                    'categoryName',
                    'fromAccount',
                    'toAccount',
                    'fromAccountName',
                    'toAccountName',
                    'amount',
                    'note',
                    'party',
                    'partyName',
                    'source',
                    'sourceId',
                    'recurringTransactionId',
                    'receiptNumber',
                    'receiptPaidAmount',
                    'receiptChangeAmount',
                    'receiptRawText',
                    'itemsJson',
                    'tax',
                    'discount',
                    'attachmentPathsJson',
                    'soundUri',
                    'soundName',
                    'reminderMode',
                    'mode',
                    'hasExplicitTime',
                    'targetDate',
                    'time',
                    'recurrence',
                    'recurrenceType',
                    'weekdays',
                    'destinationRoute',
                  }.contains(field.key),
            )
            .map(
              (field) => MapEntry(
                FfmAssistantDraftPreview.formFieldLabel(field.key),
                FfmAssistantDraftPreview.formFieldValue(field.key, field.value),
              ),
            ),
      if (draft.goalName != null) MapEntry('Target', draft.goalName!),
      if (draft.adminFee != null && draft.adminFee! > 0)
        MapEntry(
          'Biaya Admin',
          FfmAssistantDraftPreview.rupiah(draft.adminFee!),
        ),
      if (draft.tax != null)
        MapEntry('Pajak', FfmAssistantDraftPreview.rupiah(draft.tax!)),
      if (draft.discount != null)
        MapEntry('Diskon', FfmAssistantDraftPreview.rupiah(draft.discount!)),
      if (draft.receiptPaidAmount != null)
        MapEntry(
          'Nominal Dibayar',
          FfmAssistantDraftPreview.rupiah(draft.receiptPaidAmount!),
        ),
      if (draft.receiptChangeAmount != null)
        MapEntry(
          'Kembalian',
          FfmAssistantDraftPreview.rupiah(draft.receiptChangeAmount!),
        ),
      if (draft.receiptNumber?.trim().isNotEmpty == true)
        MapEntry('No. Nota', draft.receiptNumber!.trim()),
      if (draft.receiptRawText?.trim().isNotEmpty == true)
        MapEntry('Isi Nota', draft.receiptRawText!.trim()),
      for (var index = 0; index < draft.items.length; index++)
        MapEntry(
          'Item ${index + 1}',
          '${draft.items[index].name} · ${draft.items[index].quantity} x '
              '${FfmAssistantDraftPreview.rupiah(draft.items[index].price)} = '
              '${FfmAssistantDraftPreview.rupiah(draft.items[index].calculatedTotal)}'
              '${draft.items[index].unit?.trim().isNotEmpty == true ? ' · ${draft.items[index].unit}' : ''}',
        ),
      if (draft.items.isNotEmpty)
        MapEntry(
          'Subtotal item',
          FfmAssistantDraftPreview.rupiah(itemSubtotal),
        ),
      for (var index = 0; index < draft.attachmentPaths.length; index++)
        MapEntry(
          'Lampiran ${index + 1}',
          draft.attachmentPaths[index]
                  .split(RegExp(r'[/\\]'))
                  .where((part) => part.isNotEmpty)
                  .lastOrNull ??
              draft.attachmentPaths[index],
        ),
      if (draft.sourceId?.trim().isNotEmpty == true)
        MapEntry('Referensi Sumber', draft.sourceId!.trim()),
      if (draft.source?.trim().isNotEmpty == true)
        MapEntry('Sumber', draft.source!.trim()),
      if (draft.recurringTransactionId?.trim().isNotEmpty == true)
        MapEntry('Transaksi Berkala', draft.recurringTransactionId!.trim()),
      if (draft.commodityOrBusinessType != null)
        MapEntry('Komoditas/Usaha', draft.commodityOrBusinessType!),
      if (draft.initialCapital != null)
        MapEntry(
          'Modal Awal',
          FfmAssistantDraftPreview.rupiah(draft.initialCapital!),
        ),
      if (draft.estimatedInflow != null)
        MapEntry(
          'Estimasi Panen/Masuk',
          FfmAssistantDraftPreview.rupiah(draft.estimatedInflow!),
        ),
      if (draft.dailyLivingBudget != null)
        MapEntry(
          'Jatah Dapur Harian',
          FfmAssistantDraftPreview.rupiah(draft.dailyLivingBudget!),
        ),
      if (draft.dailyOperationalBudget != null)
        MapEntry(
          'Operasional Harian',
          FfmAssistantDraftPreview.rupiah(draft.dailyOperationalBudget!),
        ),
      if (draft.targetHarvestDate != null)
        MapEntry(
          'Target Panen/Selesai',
          '${draft.targetHarvestDate!.day.toString().padLeft(2, '0')}/${draft.targetHarvestDate!.month.toString().padLeft(2, '0')}/${draft.targetHarvestDate!.year}',
        ),
      if (draft.cycleProfileType != null)
        MapEntry('Tipe Siklus', draft.cycleProfileType!),
      if (draft.note != null) MapEntry('Catatan', draft.note!),
    ];

    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1C) : const Color(0xFFFDFCF9),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3530) : const Color(0xFFE8E0D0),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Draf
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A28) : const Color(0xFFF3F0E7),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  draft.kind == FfmAssistantDraftKind.cashFlowProfile
                      ? Icons.agriculture_rounded
                      : Icons.receipt_long_rounded,
                  size: 18,
                  color: isDark
                      ? const Color(0xFFC9B8A8)
                      : const Color(0xFF8B6F47),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    FfmAssistantDraftPreview.draftLabel(draft.kind),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? const Color(0xFFEDE8E0)
                          : const Color(0xFF5C4A32),
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amber.shade400,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    'DRAF',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
                if (widget.onEdit != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: widget.onEdit,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 12,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Highlight Cards: Nominal & Rekening
                if (draft.amount != null || draft.fromAccountName != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (draft.amount != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.payments_outlined,
                                size: 14,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                FfmAssistantDraftPreview.rupiah(draft.amount!),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (draft.fromAccountName != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 14,
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                draft.fromAccountName!,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                const SizedBox(height: 10),

                // Toggle Accordion Rincian Lengkap
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _expanded
                              ? 'Sembunyikan rincian draf'
                              : 'Buka rincian lengkap draf',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_expanded) ...[
                  const Divider(height: 16),
                  ...fields.map(
                    (field) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              field.key,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              field.value,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                Text(
                  '🔒 Belum ada data yang tersimpan. Periksa rincian di atas lalu tekan konfirmasi.',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),

                if (review != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Versi ${review.version}${review.canContinue ? ' • siap dicek di form' : ' • masih perlu dilengkapi'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final issue in review.issues)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '• ${issue.message}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
