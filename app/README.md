# L'app

Ta journée à Saguenay, d'un coup d'œil. L'app Flutter (Android, iOS, web), ses widgets natifs et
sa tâche de fond. La présentation du projet est dans le [README principal](../README.md).

| Dossier | Contenu |
|---|---|
| `lib/features/` | Les écrans : aujourd'hui, fiches, adresses, assistant, signalement, réglages |
| `lib/state/` | Les sources en direct, les adresses gardées, le relais web |
| `lib/notifications/` | Rappels programmés et alertes |
| `lib/background/` | La relecture horaire, app fermée |
| `lib/home_widget/` | La suite des sept prochains jours, écrite pour les widgets |
| `lib/widgets/glass.dart` | Le verre dépoli et le fond à halos |
| `android/.../TodayWidgetProvider.kt` | Le widget Android |
| `ios/TodayWidget/` | Le widget iOS (WidgetKit) |

```bash
flutter run
flutter test
flutter build apk --release
flutter build web --dart-define=ASSISTANT_URL=https://assistant.exemple.ca/
```

`ASSISTANT_URL` active l'assistant en ligne et, dans un navigateur, le relais des sources qui
bloquent les navigateurs. Seules les adresses en https sont acceptées (et `localhost` pendant le
développement).
