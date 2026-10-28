import 'package:flutter/material.dart';
import 'package:saguenay_core/saguenay_core.dart';

import '../../theme/colors.dart';
import '../../theme/kind_style.dart';
import '../../widgets/glass.dart';

/// Les jours à venir, en quelques lignes : ce qu'il faut prévoir, sans ouvrir
/// cinq sites.
class WeekCard extends StatelessWidget {
  const WeekCard({super.key, required this.week, required this.now, this.onTap});

  final Week week;
  final DateTime now;
  final void Function(SignalKind kind)? onTap;

  String _dayLabel(DateTime day) {
    if (sameDay(day, now)) return 'Aujourd’hui';
    if (sameDay(day, addDays(now, 1))) return 'Demain';
    return capitalize(shortDate(day));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    Widget line(AgendaItem item) {
      final color = item.kind.color(c);
      final row = Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: text.titleSmall),
                  if (item.detail != null)
                    Text(item.detail!, style: text.bodySmall?.copyWith(color: c.ink2)),
                ],
              ),
            ),
          ],
        ),
      );
      final tap = onTap;
      if (tap == null) return row;
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => tap(item.kind),
        child: row,
      );
    }

    return Glass(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (week.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Rien de prévu cette semaine.', style: text.bodyMedium),
            ),
          for (final item in week.ongoing) line(item),
          if (week.ongoing.isNotEmpty && week.days.isNotEmpty) Divider(height: 10, color: c.line),
          // Le jour au-dessus de ses lignes : rien ne déborde, même en grand texte.
          for (final day in week.days) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_dayLabel(day.day), style: text.labelMedium?.copyWith(color: c.ink3)),
            ),
            for (final item in day.items) line(item),
          ],
        ],
      ),
    );
  }
}
