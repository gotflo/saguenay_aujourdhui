import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saguenay_aujourdhui/features/details/detail_sheet.dart';
import 'package:saguenay_aujourdhui/features/settings/settings_screen.dart';
import 'package:saguenay_aujourdhui/features/today/today_screen.dart';
import 'package:saguenay_aujourdhui/state/providers.dart';
import 'package:saguenay_aujourdhui/theme/colors.dart';
import 'package:saguenay_core/saguenay_core.dart';

import 'helpers.dart';

// Un débordement de mise en page fait échouer le test tout seul : il suffit de
// parcourir chaque écran dans chaque configuration.

const _screens = {
  'petit téléphone': Size(320, 568),
  'téléphone': Size(390, 844),
  'tablette': Size(768, 1024),
  'ordinateur': Size(1280, 800),
};
const _textScales = [1.0, 1.4, 2.0];

Future<void> _visitAllMoments(WidgetTester tester) async {
  final container = containerOf(tester);
  for (final moment in Demo.moments) {
    container.read(demoMomentProvider.notifier).play(moment);
    await settle(tester);
    expect(find.byType(TodayScreen), findsOneWidget, reason: moment.label);
    // Jusqu'en bas, pour construire la semaine et le pied de page aussi.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await settle(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 4000));
    await settle(tester);
  }
}

void main() {
  for (final MapEntry(key: name, value: size) in _screens.entries) {
    for (final scale in _textScales) {
      for (final brightness in Brightness.values) {
        testWidgets('$name, texte ×$scale, ${brightness.name} : écran du jour', (tester) async {
          useScreen(tester, size, textScale: scale, brightness: brightness);
          await pumpApp(tester, place: 'racine');
          await _visitAllMoments(tester);
        });
      }
    }
  }

  for (final palette in AppPalette.values) {
    testWidgets('palette ${palette.name}, sombre, petit téléphone, texte ×2', (tester) async {
      useScreen(tester, _screens['petit téléphone']!, textScale: 2, brightness: Brightness.dark);
      await pumpApp(tester, place: 'racine', prefs: {'palette': palette.name});
      await _visitAllMoments(tester);
    });
  }

  testWidgets('toutes les fiches de détail, au pire cas', (tester) async {
    useScreen(tester, _screens['petit téléphone']!, textScale: 2);
    await pumpApp(tester, place: 'racine');
    final container = containerOf(tester);

    for (final moment in Demo.moments) {
      container.read(demoMomentProvider.notifier).play(moment);
      await settle(tester);
      for (final kind in SignalKind.values) {
        final context = tester.element(find.byType(TodayScreen));
        showDetailSheet(context, kind);
        await settle(tester);
        expect(find.byType(DetailSheet), findsOneWidget, reason: '${moment.label} / $kind');
        // Fait défiler la fiche jusqu'en bas pour construire toutes ses lignes.
        await tester.dragFrom(const Offset(160, 450), const Offset(0, -2000));
        await settle(tester);
        Navigator.of(context).pop();
        await settle(tester);
      }
    }
  });

  for (final scale in _textScales) {
    testWidgets('accueil et réglages, petit téléphone, texte ×$scale', (tester) async {
      useScreen(tester, _screens['petit téléphone']!, textScale: scale);
      await pumpApp(tester);
      await tester.scrollUntilVisible(find.text('201, rue Racine Est'), 400);
      await settle(tester);

      await tester.ensureVisible(find.text('201, rue Racine Est'));
      await tester.pump();
      await tester.tap(find.text('201, rue Racine Est'));
      await settle(tester);
      final context = tester.element(find.byType(TodayScreen));
      unawaited(
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
      );
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Oublier mon adresse'), 300);
      expect(find.text('Oublier mon adresse'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
    });
  }
}
