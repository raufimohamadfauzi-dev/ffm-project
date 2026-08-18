const _bulanIndonesia = <String>[
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

String _dua(int value) => value.toString().padLeft(2, '0');

String formatJam(DateTime dateTime) =>
    '${_dua(dateTime.hour)}:${_dua(dateTime.minute)}:${_dua(dateTime.second)}';

String formatTanggalLengkap(
  DateTime dateTime, {
  bool includeSeconds = false,
}) {
  final waktu = includeSeconds
      ? ' pukul ${formatJam(dateTime)}'
      : ' pukul ${_dua(dateTime.hour)}:${_dua(dateTime.minute)}';
  return '${dateTime.day} ${_bulanIndonesia[dateTime.month - 1]} ${dateTime.year}$waktu';
}

bool isDataSusulan(DateTime kejadian, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  return reference.difference(kejadian).inHours > 24;
}

String formatTanggalSingkat(DateTime dateTime) =>
    '${_dua(dateTime.day)}/${_dua(dateTime.month)}/${dateTime.year}';
