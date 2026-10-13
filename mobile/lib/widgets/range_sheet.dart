import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/format.dart';

Future<DateTimeRange?> showRangeSheet(BuildContext context, DateTimeRange current) {
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => RangeSheet(current: current),
  );
}

String formatRangeLabel(DateTimeRange range) {
  if (range.start == range.end) return formatShortDate(range.start);
  final sameYear = range.start.year == range.end.year;
  return '${formatShortDate(range.start)} – ${formatShortDate(range.end)}${sameYear ? '' : ' ${range.end.year}'}';
}

class RangeSheet extends StatelessWidget {
  const RangeSheet({super.key, required this.current});

  final DateTimeRange current;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final presets = <(String, IconData, DateTimeRange)>[
      ('Hoy', Icons.today_rounded, DateTimeRange(start: today, end: today)),
      (
        'Ayer',
        Icons.history_rounded,
        DateTimeRange(start: today.subtract(const Duration(days: 1)), end: today.subtract(const Duration(days: 1))),
      ),
      ('Este mes', Icons.calendar_month_rounded, DateTimeRange(start: DateTime(today.year, today.month), end: today)),
      (
        'Mes anterior',
        Icons.event_repeat_rounded,
        DateTimeRange(start: DateTime(today.year, today.month - 1), end: DateTime(today.year, today.month, 0)),
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text('Periodo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            for (final (label, icon, range) in presets)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(icon, color: AppColors.primary),
                title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(formatRangeLabel(range)),
                selected: range == current,
                selectedColor: AppColors.primary,
                selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                trailing: range == current ? const Icon(Icons.check_circle_rounded) : null,
                onTap: () => Navigator.pop(context, range),
              ),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: const Icon(Icons.date_range_rounded, color: AppColors.primary),
              title: const Text('Personalizado…', style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(today.year - 3),
                  lastDate: today,
                  initialDateRange: current,
                  helpText: 'Selecciona el periodo',
                  saveText: 'Aplicar',
                );
                if (picked != null && context.mounted) Navigator.pop(context, picked);
              },
            ),
          ],
        ),
      ),
    );
  }
}
