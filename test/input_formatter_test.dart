import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/shared/widgets/app_components.dart';

void main() {
  const formatter = RupiahInputFormatter();

  test('formatter nominal menerima ketikan angka bertahap', () {
    final first = formatter.formatEditUpdate(
      const TextEditingValue(),
      const TextEditingValue(text: '1'),
    );
    final second = formatter.formatEditUpdate(
      first,
      const TextEditingValue(text: '12'),
    );
    final grouped = formatter.formatEditUpdate(
      second,
      const TextEditingValue(text: '1234'),
    );

    expect(first.text, '1');
    expect(second.text, '12');
    expect(grouped.text, '1.234');
  });

  test('formatter nominal tetap mendukung hapus dan paste angka', () {
    final formatted = formatter.formatEditUpdate(
      const TextEditingValue(text: '1.234'),
      const TextEditingValue(text: '123'),
    );
    final cleared = formatter.formatEditUpdate(
      formatted,
      const TextEditingValue(),
    );

    expect(formatted.text, '123');
    expect(cleared.text, isEmpty);
  });
}
