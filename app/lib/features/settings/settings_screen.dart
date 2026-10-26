import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:share_plus/share_plus.dart';

import '../../notifications/notification_sync.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../widgets/pressable.dart';
import '../assistant/assistant_screen.dart';
import '../demo/moments_sheet.dart';
import '../places/place_picker.dart';
import '../report/report_screen.dart';
import '../../widgets/glass.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // De retour des réglages du téléphone : on relit les permissions.
  late final _lifecycle = AppLifecycleListener(
    onResume: () {
      ref.invalidate(notificationStatusProvider);
      forceReschedule(ref);
    },
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final place = ref.watch(placeProvider);
    final reminders = ref.watch(remindersProvider);
    final frozen = ref.watch(demoTimeProvider) != null;
    final palette = ref.watch(paletteProvider);
    final notifications = ref.watch(notificationsProvider);
    final status = ref.watch(notificationStatusProvider).value;
    final quiet = ref.watch(quietHoursProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          const _Label('Mon adresse'),
          _Card(
            children: [
              _Row(
                title: place?.label ?? 'Aucune adresse',
                subtitle: 'Elle reste sur ce téléphone.',
                trailing: Text('Changer', style: text.labelLarge),
                onTap: () => showPlacePicker(context),
              ),
            ],
          ),
          const _Label('Rappels'),
          if (status != null && !status.allowed) ...[
            _Card(
              children: [
                _Row(
                  title: 'Les notifications sont bloquées',
                  subtitle: 'Aucun rappel ne peut s’afficher pour l’instant.',
                  trailing: Text('Réglages', style: text.labelLarge),
                  onTap: notifications.openSettings,
                ),
              ],
            ),
            const SizedBox(height: 10),
          ] else if (status != null && !status.exact) ...[
            _Card(
              children: [
                _Row(
                  title: 'Rappels à l’heure pile',
                  subtitle: 'Sans ça, Android peut les retarder de quelques minutes.',
                  trailing: Text('Autoriser', style: text.labelLarge),
                  onTap: notifications.requestExact,
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          _Card(
            children: [
              for (final r in ReminderKind.values)
                // Le titre et l'interrupteur se lisent ensemble au lecteur d'écran.
                MergeSemantics(
                  child: _Row(
                    title: r.title,
                    subtitle: r.when,
                    trailing: Switch.adaptive(
                      value: reminders.contains(r),
                      onChanged: (on) async {
                        await ref.read(remindersProvider.notifier).toggle(r, on);
                        if (on && await notifications.ensurePermission()) {
                          ref.invalidate(notificationStatusProvider);
                          ref.invalidate(alertSyncProvider);
                        }
                      },
                    ),
                  ),
                ),
              MergeSemantics(
                child: _Row(
                  title: 'Heures calmes',
                  subtitle:
                      'De 22 h à 7 h, les alertes attendent le matin, sauf un avis d’ébullition',
                  trailing: Switch.adaptive(
                    value: quiet,
                    onChanged: (on) => ref.read(quietHoursProvider.notifier).set(on),
                  ),
                ),
              ),
              _Row(
                title: 'M’envoyer un rappel test',
                subtitle: 'Pour voir à quoi ça ressemble',
                trailing: Icon(Icons.notifications_none_rounded, color: c.ink3),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (!notifications.supported) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Les rappels ne marchent pas dans un navigateur.'),
                      ),
                    );
                    return;
                  }
                  final allowed = await notifications.ensurePermission();
                  if (allowed) {
                    await notifications.showTest();
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Les notifications sont bloquées dans les réglages du téléphone.',
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'Les rappels sont programmés sur ton téléphone pour les quatre prochaines semaines '
              'et sonnent même sans réseau. Les avis d’eau et les alertes météo s’affichent dès '
              'que l’app les voit.',
              style: text.bodySmall,
            ),
          ),
          const _Label('Outils'),
          _Card(
            children: [
              _Row(
                title: 'Demande à l’app',
                subtitle: 'Le bac, le stationnement, l’eau, ça va où ?',
                trailing: Icon(Icons.chevron_right_rounded, color: c.ink3),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => const AssistantScreen())),
              ),
              _Row(
                title: 'Ajouter mes collectes à mon calendrier',
                subtitle: 'Les quatre prochains mois, avec un rappel la veille',
                trailing: Icon(Icons.event_rounded, color: c.ink3),
                onTap: place == null ? null : () => _shareCalendar(context, ref, place),
              ),
              _Row(
                title: 'Signaler un problème à la Ville',
                subtitle: 'Un message clair, prêt à coller dans son formulaire',
                trailing: Icon(Icons.chevron_right_rounded, color: c.ink3),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => const ReportScreen())),
              ),
            ],
          ),
          const _Label('Démo'),
          _Card(
            children: [
              _Row(
                title: 'Rejouer un moment',
                subtitle: 'Pour présenter l’app avec les données du 25 octobre',
                trailing: Icon(Icons.chevron_right_rounded, color: c.ink3),
                onTap: () => showMomentsSheet(context),
              ),
              if (frozen)
                _Row(
                  title: 'Revenir à l’heure réelle',
                  trailing: Icon(Icons.restore_rounded, color: c.ink3),
                  onTap: () => ref.read(demoMomentProvider.notifier).stop(),
                ),
            ],
          ),
          const _Label('Couleurs'),
          _Card(
            children: [
              for (final p in AppPalette.values)
                _Row(
                  title: p.label,
                  subtitle: p == AppPalette.ville
                      ? 'Le bleu de la Ville, pour la lui présenter'
                      : 'Jaune et noir',
                  trailing: Icon(
                    palette == p ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: palette == p ? c.ink : c.line,
                  ),
                  onTap: () => ref.read(paletteProvider.notifier).choose(p),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'Les couleurs de la Ville ne seront utilisées en public qu’avec son accord.',
              style: text.bodySmall,
            ),
          ),
          const _Label('À propos'),
          _Card(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Saguenay Aujourd’hui est un projet indépendant. Il n’est pas affilié à la '
                'Ville de Saguenay, à la Société de transport du Saguenay ni à Santé Québec.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Sources : Ville de Saguenay (collectes, avis d’aqueduc, travaux), Données Québec, '
                'ministère de la Santé (urgences), Société de transport du Saguenay (horaires), '
                'Environnement Canada (météo), Hydro-Québec (pannes).',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Les chiffres des urgences ne servent pas à choisir un hôpital. '
                'Urgence : 911. Conseil santé : 811.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 14),
              Text('Version 0.2, démo', style: text.bodySmall),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await ref.read(placeIdProvider.notifier).forget();
              },
              child: Text('Oublier mon adresse', style: text.labelLarge?.copyWith(color: c.red)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un fichier .ics à ouvrir dans Google Agenda ou Calendrier.
Future<void> _shareCalendar(BuildContext context, WidgetRef ref, Place place) async {
  final ics = calendarExport(place, DateTime.now(), power: ref.read(liveCityProvider).power);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(utf8.encode(ics)),
          mimeType: 'text/calendar',
          name: 'collectes.ics',
        ),
      ],
      subject: 'Mes collectes',
      text: 'Collectes et dates d’hiver pour ${place.label}',
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.labelMedium),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.padding = EdgeInsets.zero});

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Glass(
    padding: padding,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, this.trailing, this.onTap});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.labelLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: text.bodySmall),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
    return onTap == null ? row : Pressable(onTap: onTap, child: row);
  }
}
