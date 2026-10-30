import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saguenay_aujourdhui/state/position.dart';
import 'package:saguenay_aujourdhui/state/providers.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';
import 'live_address_test.dart' show liveAddress, racineAddress;

/// Une position qu'on fait bouger à la main.
class FakeLocation implements LocationSource {
  FakeLocation({this.allow = true});

  bool allow;
  final positions = StreamController<LatLon>.broadcast();

  @override
  Future<bool> ensurePermission() async => allow;

  @override
  Stream<LatLon> watch() => positions.stream;
}

/// Un arrêt à Jonquière, loin du 201, rue Racine Est (Chicoutimi).
final jonquiere = TransitDay(
  date: startOfDay(sundayEvening),
  stops: const [GtfsStop('9', 'Place des copains', 48.4200, -71.2480)],
  byStop: const {
    '9': [Departure(1305, '11', 'Place des copains', tripId: 'T9', stopId: '9')],
  },
);

Map<String, Object> home({bool following = false}) => {
  'adresses': [jsonEncode(racineAddress.toJson())],
  'place': racineAddress.id,
  if (following) BusPosition.key: true,
};

void main() {
  Future<FakeNotifications> pump(
    WidgetTester tester,
    FakeLocation location, {
    bool following = true,
  }) => pumpApp(
    tester,
    prefs: home(following: following),
    extra: [
      ...liveAddress(),
      locationSourceProvider.overrideWithValue(location),
      transitDayProvider.overrideWith((ref) async => jonquiere),
    ],
  );

  testWidgets('hors de chez soi : l’arrêt le plus proche de l’endroit où l’on est', (tester) async {
    final location = FakeLocation();
    final n = await pump(tester, location);
    location.positions.add((lat: 48.4201, lon: -71.2482));
    await settle(tester);
    n.tap('detail:bus');
    await settle(tester);
    expect(find.text('Près de toi : Place des copains'), findsOneWidget);
    expect(find.text('Garder l’arrêt de mon adresse'), findsOneWidget);
  });

  testWidgets('à la maison, l’arrêt reste celui de l’adresse', (tester) async {
    final location = FakeLocation();
    final n = await pump(tester, location);
    location.positions.add((lat: racineAddress.lat + .001, lon: racineAddress.lon));
    await settle(tester);
    n.tap('detail:bus');
    await settle(tester);
    expect(find.textContaining('Près de toi'), findsNothing);
  });

  testWidgets('permission refusée : l’app le dit et garde l’adresse', (tester) async {
    final location = FakeLocation(allow: false);
    final n = await pump(tester, location, following: false);
    n.tap('detail:bus');
    await settle(tester);
    // La feuille s'ouvre après l'image qui a reçu la demande.
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Arrêts près de moi'));
    await tester.tap(find.text('Arrêts près de moi'));
    await settle(tester);
    expect(find.textContaining('Sans la permission'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(BusPosition.key), isNull);
  });

  testWidgets('permission donnée : le choix est gardé', (tester) async {
    final location = FakeLocation();
    final n = await pump(tester, location, following: false);
    n.tap('detail:bus');
    await settle(tester);
    // La feuille s'ouvre après l'image qui a reçu la demande.
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Arrêts près de moi'));
    await tester.tap(find.text('Arrêts près de moi'));
    await settle(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(BusPosition.key), isTrue);
    expect(find.text('Garder l’arrêt de mon adresse'), findsOneWidget);
  });

  test('l’app quitte l’écran : on ne lit plus la position', () async {
    SharedPreferences.setMockInitialValues({BusPosition.key: true});
    final prefs = await SharedPreferences.getInstance();
    final location = FakeLocation();
    final c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        locationSourceProvider.overrideWithValue(location),
      ],
    );
    addTearDown(c.dispose);
    c.listen(positionProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(location.positions.hasListener, isTrue);
    c.read(appInForegroundProvider.notifier).set(false);
    c.read(positionProvider);
    await Future<void>.delayed(Duration.zero);
    expect(location.positions.hasListener, isFalse);
  });
}
