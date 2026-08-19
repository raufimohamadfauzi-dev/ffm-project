import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'recent_selection_cache.dart';

import '../../core/theme/app_theme.dart';

String formatRupiahInput(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    final start = (end - 3).clamp(0, end);
    groups.insert(0, digits.substring(start, end));
  }
  return groups.join('.');
}

int parseRupiah(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits) ?? 0;
}

class RupiahInputFormatter extends TextInputFormatter {
  const RupiahInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatRupiahInput(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.onTap,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final BorderSide? border;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    final scheme = Theme.of(context).colorScheme;
    final card = Card(
      color: color ?? scheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: border ?? BorderSide(color: scheme.outline, width: .7),
      ),
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              child: Semantics(button: true, child: content),
            ),
    );
    return card;
  }
}

class AppHelpBanner extends StatefulWidget {
  const AppHelpBanner({
    required this.title,
    required this.message,
    super.key,
    this.icon = Icons.info_outline,
    this.initiallyExpanded = false,
  });

  final String title;
  final String message;
  final IconData icon;
  final bool initiallyExpanded;

  @override
  State<AppHelpBanner> createState() => _AppHelpBannerState();
}

class _AppHelpBannerState extends State<AppHelpBanner> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.primary, width: .45),
      ),
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        leading: Icon(widget.icon, color: scheme.primary),
        title: Text(
          widget.title,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          'Ketuk untuk lihat penjelasan',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.message,
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    super.key,
    this.actionLabel,
    this.onAction,
    this.helpText,
    this.trailing,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? helpText;
  final Widget? trailing;

  Future<void> _showHelp(BuildContext context) async {
    final text = helpText;
    if (text == null || text.trim().isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Oke, paham'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        if (helpText != null)
          IconButton(
            tooltip: 'Buka penjelasan',
            onPressed: () => _showHelp(context),
            icon: Icon(Icons.info_outline, size: 18, color: scheme.primary),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            padding: EdgeInsets.zero,
          ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class AppMoneyText extends StatelessWidget {
  const AppMoneyText(
    this.amount, {
    super.key,
    this.compact = false,
    this.color,
    this.maxLines = 1,
  });

  final int amount;
  final bool compact;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatRupiah(amount),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: (compact ? AppTextStyles.moneyMedium : AppTextStyles.moneyLarge)
          .copyWith(color: color ?? Theme.of(context).colorScheme.onSurface),
    );
  }

  String _formatRupiah(int value) {
    final digits = value.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, end);
      groups.insert(0, digits.substring(start, end));
    }
    final sign = value < 0 ? '-' : '';
    return '${sign}Rp${groups.join('.')}';
  }
}

class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    required this.label,
    super.key,
    this.color,
    this.backgroundColor,
  });

  final String label;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chipColor = color ?? scheme.primary;
    final chipBackground = backgroundColor ?? scheme.secondaryContainer;
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: chipColor.withValues(alpha: .3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: chipColor,
          fontWeight: FontWeight.w800,
          letterSpacing: .25,
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    required this.message,
    super.key,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.surfaceContainerLowest,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: scheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

class SearchableDropdown<T> extends StatelessWidget {
  const SearchableDropdown({
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    super.key,
    this.selectedItem,
    this.itemId,
    this.labelText,
    this.helperText,
    this.hintText = 'Pilih dari daftar',
    this.searchHintText = 'Cari pilihan',
    this.validator,
    this.enabled = true,
    this.cacheKey,
    this.allowClear = false,
    this.clearLabel = 'Belum dipilih',
  });

  final List<T> items;
  final String Function(T item) itemLabel;
  final String Function(T item)? itemId;
  final T? selectedItem;
  final ValueChanged<T?> onChanged;
  final String? labelText;
  final String? helperText;
  final String hintText;
  final String searchHintText;
  final String? Function(T? value)? validator;
  final bool enabled;
  final String? cacheKey;
  final bool allowClear;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final selectedLabel = selectedItem == null
        ? null
        : itemLabel(selectedItem as T);
    return FormField<T>(
      initialValue: selectedItem,
      validator: validator,
      builder: (field) {
        final scheme = Theme.of(context).colorScheme;
        return InputDecorator(
          decoration: InputDecoration(
            labelText: labelText,
            helperText: helperText,
            errorText: field.errorText,
            enabled: enabled,
            suffixIcon: Icon(
              Icons.unfold_more_rounded,
              color: enabled
                  ? scheme.onSurfaceVariant
                  : scheme.onSurfaceVariant,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled
                  ? () async {
                      final value = await _showPicker(context);
                      if (!context.mounted) return;
                      if (value == _SearchableDropdownAction.dismissed) {
                        return;
                      }
                      final selected = value == _SearchableDropdownAction.clear
                          ? null
                          : value as T?;
                      field.didChange(selected);
                      onChanged(selected);
                    }
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  selectedLabel ?? hintText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selectedLabel == null
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                    fontWeight: selectedLabel == null
                        ? FontWeight.w500
                        : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<Object?> _showPicker(BuildContext context) async {
    final value = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => _SearchableDropdownSheet<T>(
        items: items,
        itemLabel: itemLabel,
        itemId: itemId ?? itemLabel,
        selectedItem: selectedItem,
        searchHintText: searchHintText,
        cacheKey: cacheKey,
        allowClear: allowClear,
        clearLabel: clearLabel,
      ),
    );
    return value ?? _SearchableDropdownAction.dismissed;
  }
}

enum _SearchableDropdownAction { dismissed, clear }

class _SearchableDropdownSheet<T> extends StatefulWidget {
  const _SearchableDropdownSheet({
    required this.items,
    required this.itemLabel,
    required this.itemId,
    required this.selectedItem,
    required this.searchHintText,
    required this.cacheKey,
    required this.allowClear,
    required this.clearLabel,
  });

  final List<T> items;
  final String Function(T item) itemLabel;
  final String Function(T item) itemId;
  final T? selectedItem;
  final String searchHintText;
  final String? cacheKey;
  final bool allowClear;
  final String clearLabel;

  @override
  State<_SearchableDropdownSheet<T>> createState() =>
      _SearchableDropdownSheetState<T>();
}

class _SearchableDropdownSheetState<T>
    extends State<_SearchableDropdownSheet<T>> {
  final _searchController = TextEditingController();
  var _query = '';
  List<String> _recentIds = const [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final key = widget.cacheKey;
    if (key == null || key.trim().isEmpty) return;
    final values = await recentSelectionCache.prune(
      key,
      widget.items.map(widget.itemId),
    );
    if (mounted) setState(() => _recentIds = values);
  }

  void _onSearchChanged() {
    final next = _searchController.text.trim().toLowerCase();
    if (next == _query) return;
    setState(() => _query = next);
  }

  List<T> get _visibleItems {
    final filtered = widget.items
        .where((item) {
          return _query.isEmpty ||
              widget.itemLabel(item).toLowerCase().contains(_query);
        })
        .toList(growable: false);
    if (_query.isNotEmpty || _recentIds.isEmpty) return filtered;
    final byId = {for (final item in filtered) widget.itemId(item): item};
    final recent = <T>[];
    for (final id in _recentIds) {
      final item = byId.remove(id);
      if (item != null) recent.add(item);
    }
    return [...recent, ...byId.values];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _visibleItems;
    final recentIds = _query.isEmpty ? _recentIds.toSet() : const <String>{};
    final recentItems = items
        .where((item) => recentIds.contains(widget.itemId(item)))
        .toList(growable: false);
    final otherItems = items
        .where((item) => !recentIds.contains(widget.itemId(item)))
        .toList(growable: false);

    List<Widget> buildTiles(List<T> source) {
      return source
          .map((item) {
            final id = widget.itemId(item);
            final isSelected =
                widget.selectedItem != null &&
                widget.itemId(widget.selectedItem as T) == id;
            return ListTile(
              minVerticalPadding: 8,
              leading: Icon(
                recentIds.contains(id)
                    ? Icons.history_rounded
                    : Icons.list_alt_rounded,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              title: Text(widget.itemLabel(item)),
              trailing: isSelected
                  ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                  : null,
              selected: isSelected,
              onTap: () async {
                final key = widget.cacheKey;
                if (key != null) await recentSelectionCache.remember(key, id);
                if (context.mounted) Navigator.of(context).pop(item);
              },
            );
          })
          .toList(growable: false);
    }

    Widget sectionLabel(String label) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
      );
    }

    return FractionallySizedBox(
      heightFactor: .88,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Pilih dari Data Utama',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: widget.searchHintText,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.clear_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            if (widget.allowClear && _query.isEmpty)
              ListTile(
                minVerticalPadding: 8,
                leading: Icon(
                  Icons.remove_circle_outline,
                  color: scheme.primary,
                ),
                title: Text(widget.clearLabel),
                selected: widget.selectedItem == null,
                onTap: () =>
                    Navigator.of(context).pop(_SearchableDropdownAction.clear),
              ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty
                            ? 'Belum ada pilihan. Tambahkan dulu di Data Utama.'
                            : 'Tidak ada hasil\\nCoba kata kunci lain.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 12),
                      children: [
                        if (recentItems.isNotEmpty) ...[
                          sectionLabel('TERAKHIR DIGUNAKAN'),
                          ...buildTiles(recentItems),
                          const Divider(height: 20),
                        ],
                        if (otherItems.isNotEmpty) ...[
                          sectionLabel(
                            _query.isEmpty ? 'SEMUA ITEM' : 'HASIL PENCARIAN',
                          ),
                          ...buildTiles(otherItems),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

abstract final class AppSemanticColors {
  static Color positive(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? const Color(0xFF7DE3A7)
        : AppColors.positive;
  }

  static Color negative(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? const Color(0xFFFFB4AB)
        : AppColors.negative;
  }

  static Color warning(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? const Color(0xFFFFCC80)
        : AppColors.warning;
  }

  static Color infoContainer(BuildContext context) =>
      Theme.of(context).colorScheme.primaryContainer;

  static Color infoOnContainer(BuildContext context) =>
      Theme.of(context).colorScheme.onPrimaryContainer;

  static Color muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
}

abstract final class AppSemanticContainers {
  static Color positiveContainer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? const Color(0xFF1E4934)
        : AppColors.positiveSoft;
  }

  static Color onPositiveContainer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? const Color(0xFFD9F6E5)
        : AppColors.ink;
  }

  static Color warningContainer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? const Color(0xFF4A351E)
        : AppColors.warningSoft;
  }

  static Color onWarningContainer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.brightness == Brightness.dark
        ? const Color(0xFFFFE0B2)
        : AppColors.ink;
  }
}
