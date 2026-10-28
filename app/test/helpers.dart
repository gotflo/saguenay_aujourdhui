import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:saguenay_aujourdhui/app.dart';
import 'package:saguenay_aujourdhui/home_widget/widget_sync.dart';
import 'package:saguenay_aujourdhui/notifications/notification_sync.dart';
import 'package:saguenay_aujourdhui/notifications/notifications.dart';
import 'package:saguenay_aujourdhui/state/live_sources.dart';
import 'package:saguenay_aujourdhui/state/providers.dart';
import 'package:saguenay_aujourdhui/widgets/live_map.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FixedTime extends DemoTimeNotifier {
  FixedTime(this.at);

  final DateTime at;

  @override
  DateTime? build() => at;
}

/// Une source en direct figée : pas de réseau ni de minuterie dans les tests.
class FixedEmergencies extends EmergenciesNotifier {
  FixedEmergencies(this.status);

  final EmergencyStatus status;

  @override
  Future<EmergencyStatus> build() async => status;
}

class FixedWeather extends WeatherNotifier {
  FixedWeather(this.status);

  final WeatherStatus status;

  @override
  Future<WeatherStatus> build() async => status;
}

class FixedPower extends PowerNotifier {
  FixedPower(this.status);

  final PowerStatus status;

  @override
  Future<PowerStatus> build() async => status;
}

class FixedWater extends WaterLayerNotifier {
  FixedWater(this.status);

  final WaterStatus status;

  @override
  Future<WaterStatus> build() async => status;
}

class FixedRoadworks extends RoadworksLayerNotifier {
  FixedRoadworks(this.status);

  final RoadworkStatus status;

  @override
  Future<RoadworkStatus> build() async => status;
}

class FixedRoads extends RoadsNotifier {
  FixedRoads(this.status);

  final RoadStatus status;

  @override
  Future<RoadStatus> build() async => status;
}

class FixedAir extends AirNotifier {
  FixedAir(this.status);

  final AirStatus status;

  @override
  Future<AirStatus> build() async => status;
}

class FixedFireBans extends FireBansNotifier {
  FixedFireBans(this.status);

  final FireStatus status;

  @override
  Future<FireStatus> build() async => status;
}

class FixedPeaks extends PeaksNotifier {
  FixedPeaks(this.status);

  final PeakStatus status;

  @override
  Future<PeakStatus> build() async => status;
}

class FixedRealtime extends TransitRealtimeNotifier {
  FixedRealtime(this.value);

  final TransitRealtime? value;

  @override
  Future<TransitRealtime?> build() async => value;
}

/// Garde tout ce que l'app demande aux notifications.
class FakeNotifications implements Notifications {
  final scheduled = <List<PlannedReminder>>[];
  final alerts = <Alert>[];
  final deferred = <(Alert, DateTime)>[];
  final _taps = StreamController<String>.broadcast();
  int permissionRequests = 0;
  int tests = 0;
  int settingsOpened = 0;
  int exactRequests = 0;
  bool allow = true;
  bool exact = true;
  String? launchedWith;

  /// L'heure de Saguenay vue par le téléphone ; `null` : l'heure réelle des tests.
  DateTime? saguenayNow;

  Iterable<WaterAlert> get waterAlerts => alerts.whereType<WaterAlert>();

  void tap(String payload) => _taps.add(payload);

  @override
  bool get supported => true;

  @override
  Future<bool> ensurePermission() async {
    permissionRequests++;
    return allow;
  }

  @override
  Future<bool> isAllowed() async => allow;

  @override
  Future<bool> canScheduleExact() async => exact;

  @override
  Future<void> requestExact() async => exactRequests++;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  DateTime nowInSaguenay() => saguenayNow ?? DateTime.now();

  @override
  Future<void> replaceScheduled(List<PlannedReminder> reminders) async => scheduled.add(reminders);

  @override
  Future<void> showAlert(Alert alert) async => alerts.add(alert);

  @override
  Future<void> scheduleAlert(Alert alert, DateTime at) async => deferred.add((alert, at));

  @override
  Future<void> showTest() async => tests++;

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> launchPayload() async => launchedWith;
}

/// Garde ce que l'app envoie au widget d'écran d'accueil.
class FakeHomeScreenWidget implements HomeScreenWidget {
  final shown = <WidgetContent>[];
  int cleared = 0;
  final _clicks = StreamController<Uri?>.broadcast();
  Uri? launchedWith;

  void click(Uri uri) => _clicks.add(uri);

  @override
  bool get supported => true;

  @override
  bool get computeInBackground => false;

  @override
  Future<void> show(WidgetContent content) async => shown.add(content);

  @override
  Future<void> clear() async => cleared++;

  @override
  Stream<Uri?> get clicks => _clicks.stream;

  @override
  Future<Uri?> initialClick() async => launchedWith;
}

final sundayEvening = DateTime(2026, 11, 15, 21, 30);

/// Lance l'app comme sur un téléphone, avec une heure et des données fixes.
Future<FakeNotifications> pumpApp(
  WidgetTester tester, {
  String? place,
  DateTime? at,
  DateTime? realNow,
  Map<String, Object> prefs = const {},
  FakeNotifications? notifications,
  FakeHomeScreenWidget? homeScreen,
  EmergencyStatus? emergencies,
  WeatherStatus? weather,
  PowerStatus? power,
  WaterStatus? water,
  RoadworkStatus? roadworks,
  RoadStatus? roads,
  TransitRealtime? realtime,
  AirStatus? air,
  FireStatus? fireBans,
  PeakStatus? peaks,
  List<Override> extra = const [],
}) async {
  SharedPreferences.setMockInitialValues({...prefs, 'place': ?place});
  final shared = await SharedPreferences.getInstance();
  final fake = notifications ?? FakeNotifications();
  final shown = at ?? sundayEvening;
  final real = realNow ?? shown;
  fake.saguenayNow ??= real;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(shared),
        demoTimeProvider.overrideWith(() => FixedTime(shown)),
        clockProvider.overrideWithValue(() => real),
        realDayProvider.overrideWithValue(startOfDay(real)),
        notificationsProvider.overrideWithValue(fake),
        homeScreenWidgetProvider.overrideWithValue(homeScreen ?? const NoHomeScreenWidget()),
        emergenciesProvider.overrideWith(
          () =>
              FixedEmergencies(emergencies ?? EmergencyStatus(Demo.emergencies, SourceOrigin.live)),
        ),
        weatherProvider.overrideWith(
          () => FixedWeather(weather ?? const WeatherStatus(null, SourceOrigin.none)),
        ),
        powerProvider.overrideWith(
          () => FixedPower(power ?? const PowerStatus(null, SourceOrigin.none)),
        ),
        waterLayerProvider.overrideWith(
          () => FixedWater(water ?? const WaterStatus(null, SourceOrigin.none)),
        ),
        roadworksLayerProvider.overrideWith(
          () => FixedRoadworks(roadworks ?? const RoadworkStatus(null, SourceOrigin.none)),
        ),
        roadsProvider.overrideWith(
          () => FixedRoads(roads ?? const RoadStatus(null, SourceOrigin.none)),
        ),
        transitRealtimeProvider.overrideWith(() => FixedRealtime(realtime)),
        airProvider.overrideWith(() => FixedAir(air ?? const AirStatus(null, SourceOrigin.none))),
        fireBansProvider.overrideWith(
          () => FixedFireBans(fireBans ?? const FireStatus(null, SourceOrigin.none)),
        ),
        peaksProvider.overrideWith(
          () => FixedPeaks(peaks ?? const PeakStatus(null, SourceOrigin.none)),
        ),
        mapTilesProvider.overrideWithValue(false),
        ...extra,
      ],
      child: const SaguenayApp(googleFonts: false),
    ),
  );
  await settle(tester);
  return fake;
}

/// Laisse passer animations et petites minuteries sans attendre l'infini.
///
/// Une page qu'on vient d'ouvrir reste cachée pendant sa première image, et une
/// animation ne démarre qu'à l'image suivante : il faut plusieurs passes.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SaguenayApp)));

/// Simule un écran : taille en points, taille du texte, mode clair ou sombre.
void useScreen(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) {
  tester.view
    ..devicePixelRatio = 2
    ..physicalSize = size * 2;
  tester.platformDispatcher
    ..textScaleFactorTestValue = textScale
    ..platformBrightnessTestValue = brightness;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
}
