import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // La relecture horaire, app fermée : iOS décide du moment, au plus tôt dans une heure.
    // Le moteur de fond a besoin des mêmes plugins (préférences, notifications, widget).
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "ca.saguenayaujourdhui.rafraichir",
      earliestBeginInSeconds: 3600
    )
    // Laisse flutter_local_notifications afficher les notifications quand l’app est ouverte.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
