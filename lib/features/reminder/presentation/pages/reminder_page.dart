import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_components.dart';

class ReminderPage extends StatefulWidget {
  const ReminderPage({super.key});

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  final _items = <String>[];

  Future<void> _add() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => const _ReminderDialog(),
    );
    if (!mounted || value == null || value.isEmpty) return;
    setState(() => _items.add(value));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pengingat')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _add,
      icon: const Icon(Icons.add_alert_outlined),
      label: const Text('Tambah'),
    ),
    body: _items.isEmpty
        ? const AppEmptyState(
            icon: Icons.notifications_none_outlined,
            title: 'Belum ada pengingat',
            message: 'Tambahkan pengingat sederhana. Semua ini berjalan lokal di perangkat.',
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: _items
                .map(
                  (item) => AppCard(
                    child: ListTile(
                      leading: const Icon(Icons.notifications_none_outlined),
                      title: Text(item),
                    ),
                  ),
                )
                .toList(),
          ),
  );
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog();

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tambah pengingat'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.done,
      onSubmitted: (value) => Navigator.pop(context, value.trim()),
      decoration: const InputDecoration(labelText: 'Mau diingatkan soal apa?'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Simpan'),
      ),
    ],
  );
}
