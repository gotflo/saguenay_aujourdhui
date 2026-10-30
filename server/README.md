# Le serveur de l'assistant en ligne

L'app répond seule à la plupart des questions, sur le téléphone, à partir des données de
l'adresse. Ce petit serveur prend le relais pour le reste. Il garde la clé d'API de Claude :
elle n'est jamais dans l'app.

| Demande | Ce qu'elle fait |
|---|---|
| `POST /question` `{question, context, historique}` | Répond à une question en langage naturel. `context` est ce que l'app sait pour le secteur ; seuls les champs connus sont relayés, jamais l'adresse. `historique` : les échanges d'avant, quatre au plus, pour comprendre une suite. Les communiqués déjà résumés accompagnent la question. |
| `POST /tri` `{image}` | « Ça va où ? » d'après une photo (JPEG, PNG ou WebP en base64, 5 Mo au plus), avec les règles de tri de la Ville dans la consigne. |
| `POST /expliquer` `{texte}` | Réécrit un texte officiel (alerte, avis) en langage simple. |
| `GET /communiques` | Les cinq derniers communiqués de la salle des médias de la Ville, chacun résumé à partir de son PDF. |
| `GET /sante` | Pour la surveillance. |

Les réponses sont `{"answer": "..."}`, ou `{"erreur": "..."}` avec un code HTTP. Si le
serveur ne répond pas, l'app garde sa réponse locale.

## Ce qui protège la facture et les gens

- Un plafond par appareil (20 demandes par 10 minutes) et un plafond par jour pour tout le monde
  (`DAILY_LIMIT`, 2000 par défaut).
- Des tailles bornées : 500 caractères par question, 4000 par texte, 5 Mo par photo. Le type
  d'image est lu dans les octets, pas dans ce que dit l'appelant.
- Aucun journal des questions ni des photos : seuls le chemin et le code de réponse sont notés.
- La consigne traite le contexte, la question et les textes officiels comme des données.
- Les communiqués sont lus une fois par heure et chaque PDF n'est résumé qu'une fois.

## Lancer

```bash
cd server
dart pub get
ANTHROPIC_API_KEY=... dart run bin/server.dart
```

Variables : `ANTHROPIC_API_KEY` (obligatoire), `PORT` (8080), `ALLOWED_ORIGINS` (sites web
autorisés, séparés par des virgules ; vide : tous), `TRUST_PROXY=1` derrière un proxy qui remplit
`X-Forwarded-For`, `DAILY_LIMIT`.

Puis compiler l'app avec l'adresse du serveur (https seulement) :

```bash
flutter run --dart-define=ASSISTANT_URL=https://assistant.exemple.ca/
```

Sans cette adresse, l'app n'affiche ni le bouton photo, ni les communiqués, ni « En mots
simples ».

## Côté Claude

Appel direct de l'API Messages (il n'y a pas de SDK officiel pour Dart), modèle
`claude-opus-5-5`, effort `low` pour des réponses courtes. Si le modèle décline une demande,
l'API la reprend avec un autre modèle (`fallbacks: "default"`) ; si tout décline, l'app reçoit
une phrase polie qui renvoie au 911 et à Info-Santé 811.

## Tests

```bash
dart test
```

Les tests passent par un faux Claude et par la vraie page de la salle des médias enregistrée le
25 octobre 2026. Les réponses réelles de Claude demandent une clé : elles n'ont pas été testées
ici.
