import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class NewEntrySheetBody extends StatefulWidget {
  const NewEntrySheetBody({
    super.key,
    required this.controller,
    required this.onSelect,
  });

  final ScrollController controller;
  final ValueChanged<String> onSelect;

  @override
  State<NewEntrySheetBody> createState() => _NewEntrySheetBodyState();
}

class _NewEntrySheetBodyState extends State<NewEntrySheetBody> {
  int _section = 0; // 0 = utama, 1 = target, 2 = lebih banyak

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool showTrailing = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NewEntryChoiceTile(
        icon: icon,
        color: color,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        showTrailing: showTrailing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        const Text(
          'Mau mencatat apa?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          _section == 1
              ? 'Pilih alur target keuangan.'
              : _section == 2
              ? 'Input manual dan impor JSON dari LLM eksternal.'
              : 'Pilih alurnya.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 16),
        if (_section == 0) ...[
          _tile(
            icon: Icons.north_east_rounded,
            color: AppColors.negative,
            title: 'Pengeluaran',
            subtitle: 'Satu uang keluar',
            onTap: () => widget.onSelect('expense'),
          ),
          _tile(
            icon: Icons.south_west_rounded,
            color: AppColors.positive,
            title: 'Pemasukan',
            subtitle: 'Satu uang masuk',
            onTap: () => widget.onSelect('income'),
          ),
          _tile(
            icon: Icons.swap_horiz_rounded,
            color: AppColors.primary,
            title: 'Transfer',
            subtitle: 'Pindah saldo antar rekening',
            onTap: () => widget.onSelect('transfer'),
          ),
          _tile(
            icon: Icons.flag_outlined,
            color: AppColors.warning,
            title: 'Target Keuangan',
            subtitle: 'Isi atau pakai dana target',
            onTap: () => setState(() => _section = 1),
          ),
          const Divider(height: 28),
          _tile(
            icon: Icons.more_horiz_rounded,
            color: AppColors.primary,
            title: 'Lebih banyak',
            subtitle: 'Input banyak dan impor JSON',
            onTap: () => setState(() => _section = 2),
          ),
        ] else if (_section == 1) ...[
          _tile(
            icon: Icons.arrow_back_rounded,
            color: AppColors.primary,
            title: 'Kembali',
            subtitle: 'Ke pilihan utama',
            onTap: () => setState(() => _section = 0),
            showTrailing: false,
          ),
          _tile(
            icon: Icons.flag_outlined,
            color: AppColors.primary,
            title: 'Isi target uang terkumpul',
            subtitle: 'Setor ke target',
            onTap: () => widget.onSelect('goal'),
          ),
          _tile(
            icon: Icons.outbox_outlined,
            color: AppColors.warning,
            title: 'Pakai dana target',
            subtitle: 'Gunakan dana terkumpul',
            onTap: () => widget.onSelect('goal_usage'),
          ),
        ] else ...[
          _tile(
            icon: Icons.arrow_back_rounded,
            color: AppColors.primary,
            title: 'Kembali',
            subtitle: 'Ke pilihan utama',
            onTap: () => setState(() => _section = 0),
            showTrailing: false,
          ),
          _tile(
            icon: Icons.auto_awesome_outlined,
            color: AppColors.primary,
            title: 'Tempel hasil dari Asisten AI',
            subtitle: 'Nota atau daftar transaksi dari Gemini/LLM',
            onTap: () => widget.onSelect('json'),
          ),
          _tile(
            icon: Icons.playlist_add_rounded,
            color: AppColors.primary,
            title: 'Input banyak sekaligus',
            subtitle: 'Isi beberapa transaksi manual dengan cepat',
            onTap: () => widget.onSelect('quick'),
          ),
        ],
      ],
    );
  }
}

class NewEntryChoiceTile extends StatelessWidget {
  const NewEntryChoiceTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showTrailing = true,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showTrailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: .16),
                foregroundColor: color,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle),
                  ],
                ),
              ),
              if (showTrailing) Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
