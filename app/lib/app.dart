import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/places/address_sharing.dart';
import 'features/today/today_screen.dart';
import 'features/welcome/welcome_screen.dart';
import 'home_widget/widget_sync.dart';
import 'notifications/notification_sync.dart';
import 'state/launch.dart';
import 'state/live_sources.dart';
import 'state/position.dart';
import 'state/providers.dart';
import 'theme/theme.dart';

class SaguenayApp extends ConsumerStatefulWidget {
  const SaguenayApp({super.key, this.googleFonts = true});

  /// Désactivé dans les tests, qui n'ont pas accès au réseau.
  final bool googleFonts;

  @override
  ConsumerState<SaguenayApp> createState() => _SaguenayAppState();
}

class _SaguenayAppState extends ConsumerState<SaguenayApp> {
  late final AppLifecycleListener _lifecycle;
  final _subscriptions = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    // De retour au premier plan : on relit ce qui vient en direct (ce qui
    // relance aussi la vérification des alertes) et on recale le widget.
    final foreground = ref.read(appInForegroundProvider.notifier);
    _lifecycle = AppLifecycleListener(
      // La position n'est lue que pendant que l'app est à l'écran.
      onShow: () => foreground.set(true),
      onHide: () => foreground.set(false),
      onResume: () {
        unawaited(refreshLiveSources(ref.read));
        ref.read(widgetRefreshProvider.notifier).bump();
      },
    );

    // Une notification, le widget ou un raccourci : on ouvre la bonne fiche.
    final launch = ref.read(launchTargetProvider.notifier);
    final notifications = ref.read(notificationsProvider);
    final widget = ref.read(homeScreenWidgetProvider);
    _subscriptions
      ..add(notifications.taps.listen((p) => launch.open(kindFromLaunch(p))))
      ..add(widget.clicks.listen((uri) => launch.open(kindFromLaunch(uri?.toString()))))
      // Une adresse partagée par un proche.
      ..add(ref.read(appLinksProvider).listen(ref.read(incomingAddressProvider.notifier).receive));
    unawaited(() async {
      try {
        final payload = await notifications.launchPayload();
        final uri = await widget.initialClick();
        if (!mounted) return;
        launch.open(kindFromLaunch(payload) ?? kindFromLaunch(uri?.toString()));
      } on Object catch (e) {
        debugPrint('Lancement non lu : $e');
      }
    }());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..watch(widgetSyncProvider)
      ..watch(reminderSyncProvider)
      ..watch(alertSyncProvider);
    final hasPlace = ref.watch(savedPlaceProvider) != null;
    final palette = ref.watch(paletteProvider);

    return MaterialApp(
      title: 'Saguenay Aujourd’hui',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(palette: palette, googleFonts: widget.googleFonts),
      darkTheme: AppTheme.dark(palette: palette, googleFonts: widget.googleFonts),
      locale: const Locale('fr', 'CA'),
      supportedLocales: const [Locale('fr', 'CA'), Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: SharedAddressListener(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutCubic,
          child: hasPlace ? const TodayScreen() : const WelcomeScreen(),
        ),
      ),
    );
  }
}
