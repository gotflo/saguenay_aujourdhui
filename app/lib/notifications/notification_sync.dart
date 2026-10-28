import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saguenay_core/saguenay_core.dart';

import '../state/providers.dart';
import 'notifications.dart';

/// Remplacé dans `main()` par les notifications du téléphone.
final notificationsProvider = Provider<Notifications>((ref) => const NoNotifications());

/// Une file d'une seule place : si une reprogrammation arrive pendant qu'une
/// autre tourne, elle attend la fin, et seule la dernière demande compte.
/// Sans ça, deux reprogrammations rapprochées se mélangeaient et des rappels
/// désactivés pouvaient survivre.
class _LatestOnly {
  Future<void>? _running;
  Future<void> Function()? _next;

  /// Ce qui a été programmé en dernier, pour ne pas tout refaire à chaque relevé.
  String? lastScheduled;

  void run(Future<void> Function() job) {
    _next = job;
    _running ??= _drain();
  }

  Future<void> _drain() async {
    while (_next != null) {
      final job = _next!;
      _next = null;
      try {
        await job();
      } on Object catch (e) {
        debugPrint('Rappels non programmés : $e');
      }
    }
    _running = null;
  }
}

final _reminderQueue = Provider<_LatestOnly>((ref) => _LatestOnly());

/// Reprogramme les rappels des quatre prochaines semaines quand l'adresse,
/// les choix, le jour ou les coupures planifiées changent. Sans adresse, on
/// annule tout : « Oublier mon adresse » ne doit rien laisser derrière.
final reminderSyncProvider = Provider<void>((ref) {
  final place = ref.watch(savedPlaceProvider);
  final enabled = ref.watch(remindersProvider);
  final notifications = ref.watch(notificationsProvider);
  final power = ref.watch(liveCityProvider.select((c) => c.power));
  ref.watch(realDayProvider);
  if (!notifications.supported) return;

  final plan = place == null
      ? const <PlannedReminder>[]
      : const ReminderPlanner().plan(
          place,
          notifications.nowInSaguenay(),
          enabled: enabled,
          city: CityData(
            waterNotices: Demo.waterNotices,
            waterKnownUntil: Demo.city.waterKnownUntil,
            power: power,
          ),
        );
  final signature = [for (final r in plan) '${r.id}|${r.at}|${r.title}|${r.body}'].join('\n');
  final queue = ref.read(_reminderQueue);
  queue.run(() async {
    if (queue.lastScheduled == signature) return;
    await notifications.replaceScheduled(plan);
    queue.lastScheduled = signature;
  });
});

/// Signale une fois chacun les avis d'eau, les alertes météo, l'air mauvais,
/// les pannes et les pointes qui touchent l'adresse, et l'eau et les pannes
/// des autres adresses gardées.
///
/// Sans serveur, ça se passe quand l'app lit les données : à l'ouverture, au
/// retour au premier plan, et régulièrement tant qu'elle est ouverte. Les
/// notifications envoyées par un serveur viendront avec les données en direct
/// de la Ville.
final alertSyncProvider = Provider<void>((ref) {
  final place = ref.watch(savedPlaceProvider);
  final city = ref.watch(liveCityProvider);
  final enabled = ref.watch(remindersProvider);
  final notifications = ref.watch(notificationsProvider);
  final quiet = ref.watch(quietHoursProvider);
  if (place == null || !notifications.supported) return;

  final prefs = ref.read(sharedPrefsProvider);
  final sent = {
    ...?prefs.getStringList(_sentKey),
    // Clé des versions précédentes, quand seuls les avis d'eau existaient.
    ...?prefs.getStringList('avis-signales'),
  };
  final now = ref.read(clockProvider)();
  final due = Alerts.due(
    place,
    city,
    now,
    enabled: enabled,
    followed: ref.watch(followedPlacesProvider),
    alreadySent: sent,
  );
  if (due.isEmpty) return;

  unawaited(() async {
    try {
      // Sans permission, Android jette la notification sans rien dire. On ne
      // la marque donc comme envoyée que si elle peut vraiment s'afficher ;
      // sinon on réessaiera quand la permission sera donnée.
      if (!await notifications.isAllowed()) return;
      for (final alert in due) {
        final later = quiet ? QuietHours.deferral(alert, now) : null;
        await (later == null
            ? notifications.showAlert(alert)
            : notifications.scheduleAlert(alert, later));
      }
      // On ne garde que les plus récentes : la liste ne grossit pas sans fin.
      final keep = [...sent, for (final a in due) a.key];
      await prefs.setStringList(
        _sentKey,
        keep.skip(keep.length > 200 ? keep.length - 200 : 0).toList(),
      );
      await prefs.remove('avis-signales');
    } on Object catch (e) {
      debugPrint('Alerte non signalée : $e');
    }
  }());
});

const _sentKey = 'alertes-signalees';

/// Reprogramme tout, même si rien n'a changé : après une nouvelle permission,
/// les rappels passent à l'heure exacte.
void forceReschedule(WidgetRef ref) {
  ref.read(_reminderQueue).lastScheduled = null;
  ref
    ..invalidate(reminderSyncProvider)
    ..invalidate(alertSyncProvider);
}

/// Les notifications sont-elles permises, et à l'heure exacte ?
final notificationStatusProvider = FutureProvider.autoDispose<({bool allowed, bool exact})>((
  ref,
) async {
  final n = ref.watch(notificationsProvider);
  if (!n.supported) return (allowed: true, exact: true);
  return (allowed: await n.isAllowed(), exact: await n.canScheduleExact());
});
