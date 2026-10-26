# iOS : ce qui est prêt, ce qu'il reste à signer

Tout est configuré dans le projet Xcode ; il ne reste que ce qui dépend d'un compte développeur
Apple.

## Déjà dans le projet

- **La cible du widget** `TodayWidgetExtension` (`app/ios/TodayWidget/`), intégrée à l'app,
  iOS 16 au minimum. Petit, moyen, grand, et l'écran verrouillé. Ses numéros de version suivent
  ceux de l'app (`TodayWidget.xcconfig` lit `Flutter/Generated.xcconfig`).
- **Le groupe d'apps** `group.ca.saguenayaujourdhui`, dans les droits de l'app et du widget. L'app
  y écrit la suite des sept prochains jours, le widget la lit. Le même nom est dans
  `lib/home_widget/widget_sync.dart` : si on le change, il faut le changer partout (un test le
  vérifie).
- **La relecture horaire, app fermée** : l'identifiant `ca.saguenayaujourdhui.rafraichir` est
  déclaré dans `Info.plist` (`BGTaskSchedulerPermittedIdentifiers`, modes `fetch` et
  `processing`) et dans `AppDelegate.swift`. iOS décide du moment, au plus tôt une heure après la
  précédente.
- **Les notifications urgentes** (`time-sensitive`) pour les avis d'eau et les alertes météo.
- **Les autorisations** : appareil photo et photos (pour « Ça va où ? »), et la déclaration de
  chiffrement standard.
- **Les manifestes de confidentialité** de l'app et du widget : aucun suivi, aucune donnée
  collectée, raisons déclarées pour les préférences partagées.
- iOS 14 au minimum pour l'app, comme le demandent home_widget et workmanager.
- Le schéma `aujourdhui://` : un toucher sur le widget ouvre la bonne fiche.

À chaque envoi sur GitHub, une machine macOS vérifie les plists, compile l'app et son widget pour
le simulateur, vérifie que le widget est bien intégré, puis compile la version appareil sans
signature (`.github/workflows/apple.yml`). Les tests de l'app vérifient aussi que l'identifiant de
la tâche, le groupe d'apps et le nom du widget concordent entre Dart, Swift et les plists.

## À faire sur un Mac, une fois

1. Ouvrir `app/ios/Runner.xcworkspace` dans Xcode.
2. Dans **Signing & Capabilities**, choisir l'équipe pour les cibles `Runner` et
   `TodayWidgetExtension`. Xcode enregistre le groupe d'apps et les identifiants
   `ca.saguenayaujourdhui.saguenayAujourdhui` et `…TodayWidget` sur le compte.
3. Vérifier que **Time Sensitive Notifications** et **Background Modes** apparaissent bien sur
   `Runner` (ils viennent des fichiers du projet).
4. Lancer l'app une fois sur l'iPhone, puis ajouter le widget « Aujourd'hui ».

Pour tester la relecture horaire sans attendre, dans le débogueur Xcode, l'app étant en
arrière-plan :

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"ca.saguenayaujourdhui.rafraichir"]
```
