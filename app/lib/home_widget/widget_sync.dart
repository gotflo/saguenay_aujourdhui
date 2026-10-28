import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:saguenay_core/saguenay_core.dart';

import '../state/providers.dart';

/// Ce que le widget reçoit : l'adresse et la suite des prochains jours.
class WidgetContent {
  const WidgetContent({
    required this.place,
    required this.timeline,
    required this.until,
    required this.changes,
  });

  final String place;

  /// Les entrées en JSON, une par changement.
  final String timeline;

  /// Fin de la suite calculée. Au-delà, le widget demande d'ouvrir l'app.
  final DateTime until;

  /// Les moments où le widget doit se redessiner.
  final List<DateTime> changes;

  /// Calcule la suite des sept prochains jours. Pur et sans état : peut tourner
  /// dans un isolat à part.
  static WidgetContent compute(Place place, CityData city, DateTime now) {
    const span = Duration(days: 7);
    final entries = engine.timeline(place, city, now, span: span);
    return WidgetContent(
      place: place.shortLabel,
      timeline: jsonEncode([for (final e in entries) e.toJson()]),
      until: now.add(span),
      changes: [for (final e in entries.skip(1)) e.at],
    );
  }
}

/// Le widget d'écran d'accueil, vu de l'app. Remplacé dans `main()`.
abstract interface class HomeScreenWidget {
  bool get supported;

  /// Faux dans les tests, qui calculent tout de suite.
  bool get computeInBackground;

  Future<void> show(WidgetContent content);

  /// Sans adresse : le widget invite à en choisir une.
  Future<void> clear();

  /// Les touchers sur le widget (ou sur un raccourci de l'icône) pendant que l'app tourne.
  Stream<Uri?> get clicks;

  /// Le toucher qui a lancé l'app, s'il y en a un.
  Future<Uri?> initialClick();
}

class NoHomeScreenWidget implements HomeScreenWidget {
  const NoHomeScreenWidget();

  @override
  bool get supported => false;

  @override
  bool get computeInBackground => false;

  @override
  Future<void> show(WidgetContent content) async {}

  @override
  Future<void> clear() async {}

  @override
  Stream<Uri?> get clicks => const Stream.empty();

  @override
  Future<Uri?> initialClick() async => null;
}

/// Le vrai widget, par le paquet home_widget.
class HomeWidgetBridge implements HomeScreenWidget {
  static const androidName = 'TodayWidgetProvider';
  static const iOSName = 'TodayWidget';
  static const appGroup = 'group.ca.saguenayaujourdhui';

  static bool get available =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<HomeScreenWidget> create() async {
    if (!available) return const NoHomeScreenWidget();
    try {
      await HomeWidget.setAppGroupId(appGroup);
      return HomeWidgetBridge();
    } on Object catch (e) {
      debugPrint('Widget indisponible : $e');
      return const NoHomeScreenWidget();
    }
  }

  @override
  bool get supported => true;

  @override
  bool get computeInBackground => true;

  @override
  Future<void> show(WidgetContent content) async {
    await HomeWidget.saveWidgetData<String>('place', content.place);
    await HomeWidget.saveWidgetData<String>('timeline', content.timeline);
    await HomeWidget.saveWidgetData<String>('until', '${content.until.millisecondsSinceEpoch}');
    await HomeWidget.updateWidget(androidName: androidName, iOSName: iOSName);
    // Android redessine le widget à chaque changement, à la minute près si
    // l'app a droit aux alarmes exactes. Sur iOS, WidgetKit lit la suite seul.
    if (defaultTargetPlatform == TargetPlatform.android) {
      await HomeWidget.scheduleWidgetUpdates([
        ...content.changes,
        content.until,
      ], androidName: androidName);
    }
  }

  @override
  Future<void> clear() async {
    for (final key in ['place', 'timeline', 'until']) {
      await HomeWidget.saveWidgetData<String>(key, null);
    }
    await HomeWidget.updateWidget(androidName: androidName, iOSName: iOSName);
    if (defaultTargetPlatform == TargetPlatform.android) {
      await HomeWidget.cancelScheduledWidgetUpdates(androidName: androidName);
    }
  }

  @override
  Stream<Uri?> get clicks => HomeWidget.widgetClicked;

  @override
  Future<Uri?> initialClick() => HomeWidget.initiallyLaunchedFromHomeWidget();
}

final homeScreenWidgetProvider = Provider<HomeScreenWidget>((ref) => const NoHomeScreenWidget());

/// Recalcule la suite quand l'adresse, la météo, les pannes ou le jour
/// changent. Toujours sur l'heure réelle et l'adresse choisie, même en démo.
final widgetSyncProvider = Provider<void>((ref) {
  final widget = ref.watch(homeScreenWidgetProvider);
  if (!widget.supported) return;
  final place = ref.watch(savedPlaceProvider);
  final weather = ref.watch(liveCityProvider.select((c) => c.weather));
  final power = ref.watch(liveCityProvider.select((c) => c.power));
  ref.watch(realDayProvider);
  ref.watch(widgetRefreshProvider);

  final generation = ++_generation;
  if (place == null) {
    unawaited(widget.clear().catchError((Object e) => debugPrint('Widget non vidé : $e')));
    return;
  }
  final city = CityData(
    waterNotices: Demo.waterNotices,
    waterKnownUntil: Demo.city.waterKnownUntil,
    weather: weather,
    power: power,
  );
  final now = ref.read(clockProvider)();

  unawaited(() async {
    try {
      final content = widget.computeInBackground
          ? await _inBackground(place, city, now)
          : WidgetContent.compute(place, city, now);
      // Une demande plus récente est arrivée pendant le calcul : elle gagne.
      if (generation != _generation) return;
      await widget.show(content);
    } on Object catch (e) {
      debugPrint('Widget non mis à jour : $e');
    }
  }());
});

int _generation = 0;

/// Dans une fonction à part : la fermeture n'emporte que ces trois valeurs
/// vers l'autre isolat.
Future<WidgetContent> _inBackground(Place place, CityData city, DateTime now) =>
    Isolate.run(() => WidgetContent.compute(place, city, now));

/// Incrémenté au retour au premier plan, pour repartir de l'heure exacte.
final widgetRefreshProvider = NotifierProvider<WidgetRefresh, int>(WidgetRefresh.new);

class WidgetRefresh extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
