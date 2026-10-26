import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saguenay_aujourdhui/state/live_sources.dart';
import 'package:saguenay_aujourdhui/state/providers.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, SharedPreferences)> setUp({
    Future<EmergencySnapshot> Function()? emergencies,
    Future<WeatherSnapshot> Function(double?, double?)? weather,
    Future<PowerSnapshot> Function()? power,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final shared = await SharedPreferences.getInstance();
    Never offline() => throw Exception('pas de réseau');
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(shared),
        emergencyFetchProvider.overrideWithValue(emergencies ?? () async => offline()),
        weatherFetchProvider.overrideWithValue(weather ?? (_, _) async => offline()),
        powerFetchProvider.overrideWithValue(power ?? () async => offline()),
      ],
    );
    addTearDown(container.dispose);
    return (container, shared);
  }

  final fresh = EmergencySnapshot(
    takenAt: DateTime(2026, 10, 25, 12, 45),
    rooms: Demo.emergencies.rooms,
  );

  group('urgences', () {
    test('un relevé lu en direct est gardé pour plus tard', () async {
      final (container, prefs) = await setUp(emergencies: () async => fresh);
      final status = await container.read(emergenciesProvider.future);
      expect(status.origin, SourceOrigin.live);
      expect(status.snapshot?.takenAt, fresh.takenAt);
      expect(prefs.getString('urgences'), contains('2026-10-25T12:45'));
    });

    test('sans réseau, on montre le dernier relevé gardé', () async {
      var offline = false;
      final (container, _) = await setUp(
        emergencies: () async {
          if (offline) throw Exception('pas de réseau');
          return fresh;
        },
      );
      await container.read(emergenciesProvider.future);

      offline = true;
      container.invalidate(emergenciesProvider);
      final status = await container.read(emergenciesProvider.future);
      expect(status.origin, SourceOrigin.cached);
      expect(status.offline, isTrue);
      expect(status.snapshot?.takenAt, fresh.takenAt);
    });

    test('sans réseau ni relevé gardé, on retombe sur la démo', () async {
      final (container, _) = await setUp();
      final status = await container.read(emergenciesProvider.future);
      expect(status.origin, SourceOrigin.demo);
    });

    test('un relevé gardé abîmé est oublié, sans planter', () async {
      final (container, prefs) = await setUp(prefs: {'urgences': '{pas du json'});
      final status = await container.read(emergenciesProvider.future);
      expect(status.origin, SourceOrigin.demo);
      expect(prefs.getString('urgences'), isNull);
    });

    test('on repasse à HH:50, même la nuit du changement d’heure', () {
      final n = EmergenciesNotifier();
      expect(n.nextRefresh(DateTime(2026, 10, 25, 13, 10)), const Duration(minutes: 40));
      expect(
        n.nextRefresh(DateTime(2026, 10, 25, 13, 55, 30)),
        const Duration(minutes: 54, seconds: 30),
      );
      expect(n.nextRefresh(DateTime(2026, 10, 25, 13, 50)), const Duration(minutes: 60));
      // 1 h 55, la deuxième fois : le délai reste positif.
      final ambiguous = DateTime.utc(2026, 11, 1, 6, 55).toLocal();
      expect(n.nextRefresh(ambiguous).isNegative, isFalse);
    });
  });

  group('météo', () {
    final sunny = WeatherSnapshot(takenAt: DateTime(2026, 10, 25, 15), temperature: 14);

    test('lue avec les coordonnées de l’adresse choisie', () async {
      (double?, double?)? asked;
      final (container, _) = await setUp(
        prefs: {'place': 'racine'},
        weather: (lat, lon) async {
          asked = (lat, lon);
          return sunny;
        },
      );
      final status = await container.read(weatherProvider.future);
      expect(status.snapshot?.temperature, 14);
      expect(asked, (48.4283, -71.0622));
    });

    test('sans réseau ni relevé gardé : rien, et l’app le sait', () async {
      final (container, _) = await setUp();
      final status = await container.read(weatherProvider.future);
      expect(status.origin, SourceOrigin.none);
      expect(status.snapshot, isNull);
      expect(container.read(liveCityProvider).weather, isNull);
    });

    test('changer d’adresse relit les alertes', () async {
      var reads = 0;
      final (container, _) = await setUp(
        prefs: {'place': 'racine'},
        weather: (_, _) async {
          reads++;
          return sunny;
        },
      );
      await container.read(weatherProvider.future);
      await container.read(placeIdProvider.notifier).choose('saint-pierre');
      await container.read(weatherProvider.future);
      expect(reads, 2);
    });
  });

  group('électricité', () {
    test('les pannes entrent dans les données de la ville', () async {
      final snapshot = PowerSnapshot(
        takenAt: DateTime(2026, 10, 25, 15),
        outages: [
          PowerOutage(customers: 12, start: DateTime(2026, 10, 25, 14), lat: 48.43, lon: -71.06),
        ],
      );
      final (container, prefs) = await setUp(power: () async => snapshot);
      await container.read(powerProvider.future);
      expect(container.read(liveCityProvider).power?.outages.single.customers, 12);
      expect(prefs.getString('pannes'), contains('"customers":12'));
    });
  });

  test('une lecture toute récente n’est pas refaite', () async {
    var reads = 0;
    final (container, _) = await setUp(
      emergencies: () async {
        reads++;
        return fresh;
      },
    );
    await container.read(emergenciesProvider.future);
    await container.read(emergenciesProvider.notifier).refresh();
    expect(reads, 1);
    await container.read(emergenciesProvider.notifier).refresh(force: true);
    expect(reads, 2);
  });
}
