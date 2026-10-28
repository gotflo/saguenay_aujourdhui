import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:saguenay_core/saguenay_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../home_widget/widget_sync.dart';
import '../notifications/notifications.dart';
import '../state/addresses.dart';
import '../state/providers.dart';

/// Point d'entrée de la tâche de fond, appelé par Android même quand l'app
/// est fermée.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await BackgroundRefresh.run();
    } on Object catch (e) {
      debugPrint('Rafraîchissement en arrière-plan : $e');
    }
    // Toujours vrai : un échec réseau n'a pas à être reprogrammé en rafale.
    return true;
  });
}

/// Toutes les heures, app fermée ou non : relire ce qui vient en direct,
/// prévenir d'un nouvel avis ou d'une alerte, redessiner le widget et
/// prolonger les rappels. Sans serveur : c'est le téléphone qui fait le travail.
abstract final class BackgroundRefresh {
  static const task = 'rafraichir';

  /// Sur iOS, l'identifiant déclaré dans `Info.plist` et dans `AppDelegate`.
  static const iosTask = 'ca.saguenayaujourdhui.rafraichir';

  static Future<void> register() async {
    if (!HomeWidgetBridge.available) return;
    try {
      await Workmanager().initialize(backgroundDispatcher);
      final name = defaultTargetPlatform == TargetPlatform.iOS ? iosTask : task;
      await Workmanager().registerPeriodicTask(
        name,
        task,
        frequency: const Duration(hours: 1),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } on Object catch (e) {
      debugPrint('Tâche de fond non programmée : $e');
    }
  }

  static Future<void> run({
    http.Client? client,
    Notifications? notifications,
    HomeScreenWidget? widget,
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final id = prefs.getString('place');
    if (id == null) return;
    final t = now ?? DateTime.now();

    final address = readSavedAddresses(prefs).where((a) => a.id == id).firstOrNull;
    final demo = Demo.places.where((p) => p.id == id).firstOrNull;
    if (address == null && demo == null) return;

    final water = await _refresh(
      prefs,
      'aqueduc',
      () => CityLayersClient(client: client).water(now: t),
      WaterSnapshot.fromJson,
      (v) => v.toJson(),
    );
    final works = await _refresh(
      prefs,
      'travaux',
      () => CityLayersClient(client: client).roadworks(now: t),
      RoadworkSnapshot.fromJson,
      (v) => v.toJson(),
    );
    final weather = await _refresh(
      prefs,
      'meteo',
      () => WeatherClient(
        client: client,
      ).fetch(lat: address?.lat ?? demo?.lat, lon: address?.lon ?? demo?.lon, now: t),
      WeatherSnapshot.fromJson,
      (v) => v.toJson(),
    );
    final power = await _refresh(
      prefs,
      'pannes',
      () => HydroClient(client: client).fetch(now: t),
      PowerSnapshot.fromJson,
      (v) => v.toJson(),
    );

    final place =
        demo ??
        livePlace(
          address!,
          collection: readCached(prefs, 'collecte:$id', CollectionSchedule.fromJson)?.$2,
          stop: readCached(prefs, 'bus:$id', StopSchedule.fromJson)?.$2,
          water: water,
          roadworks: works,
        );
    final city = CityData(
      waterNotices: water?.notices ?? Demo.waterNotices,
      waterKnownUntil: water?.knownUntil ?? Demo.city.waterKnownUntil,
      weather: weather,
      power: power,
    );

    final n = notifications ?? await createNotifications();
    final enabled = RemindersNotifier.read(prefs);
    if (n.supported) {
      await _alerts(prefs, n, place, city, t, enabled);
      await n.replaceScheduled(
        const ReminderPlanner().plan(place, n.nowInSaguenay(), enabled: enabled, city: city),
      );
    }

    final w = widget ?? await HomeWidgetBridge.create();
    if (w.supported) await w.show(WidgetContent.compute(place, city, t));
  }

  static Future<void> _alerts(
    SharedPreferences prefs,
    Notifications n,
    Place place,
    CityData city,
    DateTime now,
    Set<ReminderKind> enabled,
  ) async {
    const key = 'alertes-signalees';
    final sent = {...?prefs.getStringList(key)};
    final due = <Alert>[
      if (enabled.contains(ReminderKind.water))
        ...WaterAlerts.due(place, city, now, alreadySent: sent),
      if (enabled.contains(ReminderKind.weather))
        ...WeatherAlerts.due(city, now, alreadySent: sent),
    ];
    if (due.isEmpty || !await n.isAllowed()) return;
    final quiet = prefs.getBool(QuietHoursNotifier.key) ?? false;
    for (final alert in due) {
      final later = quiet ? QuietHours.deferral(alert, now) : null;
      await (later == null ? n.showAlert(alert) : n.scheduleAlert(alert, later));
    }
    final keep = [...sent, for (final a in due) a.key];
    await prefs.setStringList(key, keep.skip(keep.length > 200 ? keep.length - 200 : 0).toList());
  }

  /// Relit une source et garde le relevé ; sans réseau, rend le dernier gardé.
  static Future<T?> _refresh<T>(
    SharedPreferences prefs,
    String key,
    Future<T> Function() fetch,
    T Function(Map<String, Object?>) decode,
    Map<String, Object?> Function(T) encode,
  ) async {
    try {
      final value = await fetch();
      await prefs.setString(key, jsonEncode(encode(value)));
      return value;
    } on Object catch (e) {
      debugPrint('$key non mis à jour en arrière-plan : $e');
      final raw = prefs.getString(key);
      if (raw == null) return null;
      try {
        return decode((jsonDecode(raw) as Map).cast<String, Object?>());
      } on Object {
        return null;
      }
    }
  }
}
