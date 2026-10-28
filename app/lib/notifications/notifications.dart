import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Ce que l'app sait faire avec les notifications du téléphone.
abstract interface class Notifications {
  bool get supported;

  /// Demande la permission si besoin. Vrai si les notifications sont permises.
  Future<bool> ensurePermission();

  /// Vrai si les notifications sont permises, sans rien demander.
  Future<bool> isAllowed();

  /// Android 12 et plus : vrai si les rappels peuvent sonner à la minute près.
  /// Sans cette permission, Android peut les retarder de plusieurs minutes.
  Future<bool> canScheduleExact();

  /// Ouvre l'écran système « Alarmes et rappels ».
  Future<void> requestExact();

  /// Ouvre les réglages de notification de l'app, quand elles ont été bloquées.
  Future<void> openSettings();

  /// L'heure murale de Saguenay, même si le téléphone est réglé ailleurs.
  DateTime nowInSaguenay();

  /// Remplace tous les rappels programmés par [reminders].
  Future<void> replaceScheduled(List<PlannedReminder> reminders);

  Future<void> showAlert(Alert alert);

  /// Montre l'alerte plus tard (heures calmes).
  Future<void> scheduleAlert(Alert alert, DateTime at);

  Future<void> showTest();

  /// Ce qu'on a touché : `detail:collection`, `detail:water`... Voir [payloadFor].
  Stream<String> get taps;

  /// La notification qui a lancé l'app, s'il y en a une.
  Future<String?> launchPayload();
}

/// Ce qui ouvre la bonne fiche quand on touche une notification.
String? payloadFor(ReminderKind? kind) => switch (kind) {
  null || ReminderKind.week => null,
  _ => 'detail:${kind.name}',
};

/// Pour le web et les tests.
class NoNotifications implements Notifications {
  const NoNotifications();

  @override
  bool get supported => false;

  @override
  Future<bool> ensurePermission() async => false;

  @override
  Future<bool> isAllowed() async => false;

  @override
  Future<bool> canScheduleExact() async => true;

  @override
  Future<void> requestExact() async {}

  @override
  Future<void> openSettings() async {}

  @override
  DateTime nowInSaguenay() => DateTime.now();

  @override
  Future<void> replaceScheduled(List<PlannedReminder> reminders) async {}

  @override
  Future<void> showAlert(Alert alert) async {}

  @override
  Future<void> scheduleAlert(Alert alert, DateTime at) async {}

  @override
  Future<void> showTest() async {}

  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Future<String?> launchPayload() async => null;
}

class LocalNotifications implements Notifications {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  late final tz.Location _saguenay;

  static const _reminderChannel = AndroidNotificationDetails(
    'rappels',
    'Rappels',
    channelDescription: 'Le stationnement le soir, le bac la veille, les travaux le matin.',
    category: AndroidNotificationCategory.reminder,
  );
  static const _alertChannel = AndroidNotificationDetails(
    'avis-eau',
    'Avis et alertes',
    channelDescription: 'Avis d’ébullition, coupures d’eau et alertes météo à ton adresse.',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.status,
  );
  static const _reminderDetails = NotificationDetails(
    android: _reminderChannel,
    iOS: DarwinNotificationDetails(),
  );
  static const _alertDetails = NotificationDetails(
    android: _alertChannel,
    iOS: DarwinNotificationDetails(interruptionLevel: InterruptionLevel.timeSensitive),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  @override
  bool get supported => true;

  Future<void> init() async {
    tzdata.initializeTimeZones();
    // Les heures du projet sont celles de Saguenay, peu importe où est le téléphone.
    _saguenay = tz.getLocation('America/Toronto');
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _taps.add(payload);
      },
    );
  }

  @override
  Future<bool> ensurePermission() async {
    final android = _android;
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _ios;
    if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
    return false;
  }

  @override
  Future<bool> isAllowed() async {
    final android = _android;
    if (android != null) return await android.areNotificationsEnabled() ?? false;
    final ios = _ios;
    if (ios != null) return (await ios.checkPermissions())?.isEnabled ?? false;
    return false;
  }

  @override
  Future<bool> canScheduleExact() async => await _android?.canScheduleExactNotifications() ?? true;

  @override
  Future<void> requestExact() async => _android?.requestExactAlarmsPermission();

  @override
  Future<void> openSettings() async {
    await (_android?.openAppNotificationSettings() ?? _ios?.openAppNotificationSettings());
  }

  @override
  DateTime nowInSaguenay() {
    final t = tz.TZDateTime.now(_saguenay);
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }

  @override
  Future<void> replaceScheduled(List<PlannedReminder> reminders) async {
    // On n'annule que les rappels : une alerte reportée au matin (heures
    // calmes) a un identifiant à partir de 800 000 et doit rester.
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (pending.id < 800000 || pending.id == ReminderPlanner.renewId) {
        await _plugin.cancel(id: pending.id);
      }
    }
    final mode = await canScheduleExact()
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    final now = tz.TZDateTime.now(_saguenay);
    for (final r in reminders) {
      final at = tz.TZDateTime(_saguenay, r.at.year, r.at.month, r.at.day, r.at.hour, r.at.minute);
      if (!at.isAfter(now)) continue;
      // Un rappel refusé ne doit pas empêcher les suivants.
      try {
        await _plugin.zonedSchedule(
          id: r.id,
          scheduledDate: at,
          notificationDetails: _reminderDetails,
          androidScheduleMode: mode,
          title: r.title,
          body: r.body,
          payload: payloadFor(r.kind),
        );
      } on Object catch (e) {
        debugPrint('Rappel ${r.id} non programmé : $e');
      }
    }
  }

  @override
  Future<void> showAlert(Alert alert) => _plugin.show(
    id: alert.id,
    title: alert.title,
    body: alert.body,
    notificationDetails: _alertDetails,
    payload: payloadFor(alert.kind),
  );

  @override
  Future<void> scheduleAlert(Alert alert, DateTime at) async {
    final when = tz.TZDateTime(_saguenay, at.year, at.month, at.day, at.hour, at.minute);
    if (!when.isAfter(tz.TZDateTime.now(_saguenay))) return showAlert(alert);
    await _plugin.zonedSchedule(
      id: alert.id,
      scheduledDate: when,
      notificationDetails: _alertDetails,
      androidScheduleMode: await canScheduleExact()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      title: alert.title,
      body: alert.body,
      payload: payloadFor(alert.kind),
    );
  }

  @override
  Future<void> showTest() => _plugin.show(
    id: 1,
    title: 'Pas d’auto dans la rue cette nuit',
    body: 'Voici à quoi ressemble un rappel du soir.',
    notificationDetails: _reminderDetails,
    payload: payloadFor(ReminderKind.parking),
  );

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details?.notificationResponse?.payload;
  }
}

/// Les notifications du téléphone, ou rien sur le web.
Future<Notifications> createNotifications() async {
  if (kIsWeb) return const NoNotifications();
  final local = LocalNotifications();
  try {
    await local.init();
    return local;
  } on Object catch (e) {
    debugPrint('Notifications indisponibles : $e');
    return const NoNotifications();
  }
}
