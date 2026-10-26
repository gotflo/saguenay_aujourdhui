import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saguenay_aujourdhui/background/background_refresh.dart';
import 'package:saguenay_aujourdhui/home_widget/widget_sync.dart';

// Des réglages que seule la version de production sur un vrai téléphone
// révèle quand ils manquent. Ces tests les gardent en place.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('polices embarquées', () {
    for (final file in [
      'BricolageGrotesque-Bold.ttf',
      'Figtree-Regular.ttf',
      'Figtree-SemiBold.ttf',
      'Figtree-Bold.ttf',
      'OFL-BricolageGrotesque.txt',
      'OFL-Figtree.txt',
    ]) {
      test(file, () async {
        final data = await rootBundle.load('assets/fonts/$file');
        expect(data.lengthInBytes, greaterThan(1000));
      });
    }
  });

  group('Android', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('la version de production a accès à Internet', () {
      expect(manifest, contains('android.permission.INTERNET'));
    });

    test('notifications : permission, redémarrage et récepteurs', () {
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
      expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
      expect(manifest, contains('ScheduledNotificationReceiver'));
      expect(manifest, contains('ScheduledNotificationBootReceiver'));
    });

    test('le widget est déclaré et se redessine aux bons moments', () {
      expect(manifest, contains('.TodayWidgetProvider'));
      expect(manifest, contains('@xml/today_widget_info'));
      expect(manifest, contains('es.antonborri.home_widget.HomeWidgetScheduledUpdateReceiver'));
      expect(manifest, contains('android.intent.action.TIME_SET'));
      expect(manifest, contains('android.intent.action.TIMEZONE_CHANGED'));
      expect(manifest, contains('SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED'));
      expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    });

    test('l’adresse ne quitte pas le téléphone, et rien ne passe en clair', () {
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('@xml/data_extraction_rules'));
      expect(manifest, contains('@xml/network_security_config'));
      final network = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsStringSync();
      expect(network, contains('cleartextTrafficPermitted="false"'));
      final extraction = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      expect(extraction, contains('<device-transfer>'));
      expect(extraction, contains('domain="sharedpref"'));
    });

    test('les raccourcis visent la bonne activité', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final id = RegExp(r'applicationId = "([^"]+)"').firstMatch(gradle)!.group(1)!;
      final shortcuts = File('android/app/src/main/res/xml/shortcuts.xml').readAsStringSync();
      expect(RegExp('targetPackage="$id"').allMatches(shortcuts), hasLength(3));
      expect(shortcuts, contains('targetClass="$id.MainActivity"'));
      expect(manifest, contains('@xml/shortcuts'));
    });

    test('la clé de signature ne vit pas dans le dépôt', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('key.properties'));
      final ignore = File('android/.gitignore').readAsStringSync();
      expect(ignore, contains('key.properties'));
    });

    test('les ressources appelées par leur nom ne sont pas supprimées', () {
      final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
      expect(keep, contains('@drawable/ic_notification'));
      expect(keep, contains('@layout/today_widget'));
      expect(keep, contains('@layout/today_widget_preview'));
      expect(keep, contains('@layout/today_widget_small'));
      expect(keep, contains('@layout/today_widget_large'));
      expect(File('android/app/src/main/res/drawable/ic_notification.xml').existsSync(), isTrue);
    });

    test('les étiquettes du widget restent lisibles, de jour comme de nuit', () {
      for (final folder in ['values', 'values-night']) {
        final xml = File('android/app/src/main/res/$folder/colors.xml').readAsStringSync();
        Color color(String name) {
          final hex = RegExp('name="$name">#([0-9A-Fa-f]{6})<').firstMatch(xml)!.group(1)!;
          return Color(int.parse('FF$hex', radix: 16));
        }

        final bg = color('widget_bg');
        for (final kind in [
          'water',
          'weather',
          'power',
          'roads',
          'parking',
          'collection',
          'bus',
          'roadwork',
          'critical',
        ]) {
          final fg = color('widget_kind_$kind');
          final (a, b) = (fg.computeLuminance(), bg.computeLuminance());
          final ratio = (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$folder/$kind');
        }
      }
    });

    test('désucrage activé pour les notifications programmées', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('isCoreLibraryDesugaringEnabled = true'));
      expect(gradle, contains('desugar_jdk_libs'));
    });
  });

  group('iOS', () {
    String read(String path) => File('ios/$path').readAsStringSync();
    final info = read('Runner/Info.plist');
    final project = read('Runner.xcodeproj/project.pbxproj');

    test('la relecture horaire est déclarée des deux côtés, sous le même nom', () {
      expect(info, contains('<string>${BackgroundRefresh.iosTask}</string>'));
      expect(info, contains('<string>fetch</string>'));
      expect(info, contains('<string>processing</string>'));
      final delegate = read('Runner/AppDelegate.swift');
      expect(delegate, contains('withIdentifier: "${BackgroundRefresh.iosTask}"'));
      expect(delegate, contains('setPluginRegistrantCallback'));
    });

    test('photo, liens du widget, chiffrement : ce que l’App Store vérifie', () {
      expect(info, contains('NSCameraUsageDescription'));
      expect(info, contains('NSPhotoLibraryUsageDescription'));
      expect(info, contains('<string>aujourdhui</string>'));
      expect(info, contains('ITSAppUsesNonExemptEncryption'));
    });

    test('l’app et le widget partagent le même groupe', () {
      for (final file in ['Runner/Runner.entitlements', 'TodayWidget/TodayWidget.entitlements']) {
        expect(read(file), contains('<string>${HomeWidgetBridge.appGroup}</string>'), reason: file);
      }
      expect(read('Runner/Runner.entitlements'), contains('usernotifications.time-sensitive'));
      final swift = read('TodayWidget/TodayWidget.swift');
      expect(swift, contains('appGroup = "${HomeWidgetBridge.appGroup}"'));
      expect(swift, contains('kind: "${HomeWidgetBridge.iOSName}"'));
      for (final key in ['place', 'timeline', 'until']) {
        expect(swift, contains('forKey: "$key"'), reason: key);
      }
    });

    test('le widget est une cible du projet, intégrée à l’app', () {
      expect(project, contains('productType = "com.apple.product-type.app-extension"'));
      expect(project, contains('TodayWidgetExtension.appex in Embed Foundation Extensions'));
      expect(project, contains('dstSubfolderSpec = 13;'));
      expect(project, contains('CODE_SIGN_ENTITLEMENTS = TodayWidget/TodayWidget.entitlements;'));
      expect(
        RegExp('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;').allMatches(project),
        hasLength(3),
      );
      final app = RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER = ([\w.]+);',
      ).allMatches(project).map((m) => m[1]!);
      expect(app, contains('ca.saguenayaujourdhui.saguenayAujourdhui'));
      expect(app, contains('ca.saguenayaujourdhui.saguenayAujourdhui.TodayWidget'));
      expect(read('TodayWidget/Info.plist'), contains('com.apple.widgetkit-extension'));
    });

    test('iOS 14 au minimum, comme le demandent home_widget et workmanager', () {
      expect(project, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0;')));
      expect(RegExp('IPHONEOS_DEPLOYMENT_TARGET = 14.0;').allMatches(project), hasLength(3));
      expect(read('Podfile'), contains("platform :ios, '14.0'"));
    });

    test('manifestes de confidentialité : aucun suivi, raisons déclarées', () {
      for (final file in ['Runner/PrivacyInfo.xcprivacy', 'TodayWidget/PrivacyInfo.xcprivacy']) {
        final manifest = read(file);
        expect(manifest, contains('<false/>'), reason: file);
        expect(manifest, contains('NSPrivacyAccessedAPICategoryUserDefaults'), reason: file);
      }
      expect(RegExp(r'PrivacyInfo\.xcprivacy in Resources \*/,').allMatches(project), hasLength(2));
    });
  });
}
