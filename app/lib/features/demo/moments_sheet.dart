import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saguenay_core/saguenay_core.dart';

import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../widgets/pressable.dart';
import '../../widgets/sheet_parts.dart';

Future<void> showMomentsSheet(BuildContext context) =>
    showAppSheet<void>(context, (_) => const MomentsSheet());

/// Pour présenter l'app : rejouer un moment précis avec les données du relevé.
class MomentsSheet extends ConsumerWidget {
  const MomentsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final frozen = ref.watch(demoTimeProvider);
    final playing = ref.watch(demoMomentProvider);
    final now = ref.watch(nowProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetHeader(
          'Rejouer un moment',
          subtitle: 'Avec les données relevées le 25 octobre 2026.',
        ),
        for (final m in Demo.moments)
          Pressable(
            // L'adresse choisie ne change pas : le moment apporte la sienne.
            onTap: () => ref.read(demoMomentProvider.notifier).play(m),
            child: SheetRow(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: playing == m ? c.accent : c.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  size: 19,
                  color: playing == m ? c.onAccent : c.ink2,
                ),
              ),
              title: m.label,
              subtitle: m.isScenario
                  ? '${capitalize(shortDate(m.at))}, ${clockTimeOf(m.at)}. Données inventées.'
                  : '${capitalize(shortDate(m.at))}, ${clockTimeOf(m.at)}',
            ),
          ),
        if (frozen != null) ...[
          const SectionLabel('Heure'),
          Row(
            children: [
              Text(clockTimeOf(now), style: text.titleMedium),
              Expanded(
                child: Slider(
                  value: minuteOfDay(now).toDouble(),
                  max: 1435,
                  divisions: 287,
                  activeColor: c.ink,
                  inactiveColor: c.line,
                  label: clockTimeOf(now),
                  onChanged: (v) =>
                      ref.read(demoTimeProvider.notifier).set(atMinute(now, v.round())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => ref.read(demoMomentProvider.notifier).stop(),
              child: Text('Revenir à l’heure réelle', style: text.labelLarge),
            ),
          ),
        ],
      ],
    );
  }
}
