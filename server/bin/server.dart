import 'dart:async';
import 'dart:io';

import 'package:saguenay_assistant/assistant_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Variables d'environnement :
/// - `ANTHROPIC_API_KEY` : sans elle, seul le relais de la version web répond ;
/// - `PORT` (8080 par défaut) ;
/// - `ALLOWED_ORIGINS` : sites web autorisés, séparés par des virgules ;
/// - `TRUST_PROXY=1` derrière un proxy qui remplit `X-Forwarded-For` ;
/// - `DAILY_LIMIT` : plafond de demandes par jour (2000 par défaut) ;
/// - `TZ=America/Toronto` : les heures des textos sont celles de Saguenay.
Future<void> main() async {
  final env = Platform.environment;
  final key = env['ANTHROPIC_API_KEY'] ?? '';
  if (key.isEmpty) stderr.writeln('ANTHROPIC_API_KEY absente : seul le relais répond.');

  final Claude claude = key.isEmpty ? const NoClaude() : HttpClaude(key);
  final press = PressDesk(claude);
  final relay = Relay();
  // La journée d'une adresse par texto ou au téléphone (format Twilio).
  final dayLine = DayLine();
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(
        assistantHandler(
          claude: claude,
          press: press,
          relay: relay,
          dayLine: dayLine,
          limiter: RateLimiter(perDay: int.tryParse(env['DAILY_LIMIT'] ?? '') ?? 2000),
          allowedOrigins: {
            for (final o in (env['ALLOWED_ORIGINS'] ?? '').split(','))
              if (o.trim().isNotEmpty) o.trim(),
          },
          trustProxy: env['TRUST_PROXY'] == '1',
        ),
      );

  final server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    int.tryParse(env['PORT'] ?? '') ?? 8080,
  );
  server.autoCompress = true;
  stdout.writeln('Assistant prêt sur le port ${server.port}');

  // Les communiqués sont lus d'avance, puis toutes les heures : l'app n'attend pas.
  Future<void> readPress() =>
      press.latest().then((_) {}, onError: (Object e) => stderr.writeln('Communiqués : $e'));
  if (key.isNotEmpty) {
    unawaited(readPress());
    Timer.periodic(PressDesk.listLifetime, (_) => readPress());
  }
}
