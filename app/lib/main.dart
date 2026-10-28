import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'background/background_refresh.dart';
import 'home_widget/widget_sync.dart';
import 'notifications/notification_sync.dart';
import 'notifications/notifications.dart';
import 'state/launch.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Les polices sont dans l'app (assets/fonts) : rien à télécharger au lancement.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    for (final family in ['BricolageGrotesque', 'Figtree']) {
      final text = await rootBundle.loadString('assets/fonts/OFL-$family.txt');
      yield LicenseEntryWithLineBreaks([family], text);
    }
  });

  final prefs = await SharedPreferences.getInstance();
  final notifications = await createNotifications();
  final homeScreenWidget = await HomeWidgetBridge.create();
  // Toutes les heures, même app fermée : alertes, widget et rappels.
  unawaited(BackgroundRefresh.register());
  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        notificationsProvider.overrideWithValue(notifications),
        homeScreenWidgetProvider.overrideWithValue(homeScreenWidget),
        if (!kIsWeb) appLinksProvider.overrideWithValue(AppLinks().uriLinkStream),
      ],
      child: const SaguenayApp(),
    ),
  );
}
