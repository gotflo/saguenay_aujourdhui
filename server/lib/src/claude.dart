import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Ce que le serveur demande à Claude : un texte, à partir d'une consigne et
/// d'un message (texte, image ou PDF).
abstract interface class Claude {
  Future<String> reply({required String system, required List<Map<String, Object?>> content});
}

/// Claude a décliné la demande.
class ClaudeDeclined implements Exception {
  const ClaudeDeclined();
}

/// Claude ne répond pas : surcharge, panne, délai dépassé, clé refusée.
class ClaudeUnavailable implements Exception {
  const ClaudeUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'Claude indisponible : $reason';
}

/// Sans clé d'API : l'assistant répond qu'il n'est pas disponible.
class NoClaude implements Claude {
  const NoClaude();

  @override
  Future<String> reply({
    required String system,
    required List<Map<String, Object?>> content,
  }) async => throw const ClaudeUnavailable('pas de clé d’API');
}

/// L'API Messages d'Anthropic, appelée directement : il n'y a pas de SDK
/// officiel pour Dart.
class HttpClaude implements Claude {
  HttpClaude(
    this._apiKey, {
    http.Client? client,
    this.model = 'claude-opus-5-5',
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

  static final endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  final String _apiKey;
  final http.Client _client;
  final String model;
  final Duration timeout;

  @override
  Future<String> reply({
    required String system,
    required List<Map<String, Object?>> content,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {
              'content-type': 'application/json',
              'x-api-key': _apiKey,
              'anthropic-version': '2026-10-21',
              // Si le modèle décline, l'API reprend la demande avec un autre.
              'anthropic-beta': 'server-side-fallback-2026-07-01',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 16000,
              // La consigne ne change pas d'une demande à l'autre : on la garde
              // en cache chez Anthropic.
              'system': [
                {
                  'type': 'text',
                  'text': system,
                  'cache_control': {'type': 'ephemeral'},
                },
              ],
              'messages': [
                {'role': 'user', 'content': content},
              ],
              // Des réponses courtes à des questions simples.
              'output_config': {'effort': 'low'},
              'fallbacks': 'default',
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ClaudeUnavailable('délai dépassé');
    } on Exception catch (e) {
      throw ClaudeUnavailable('réseau : $e');
    }
    if (response.statusCode != 200) {
      throw ClaudeUnavailable('HTTP ${response.statusCode}');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ClaudeUnavailable('réponse illisible');
    }
    if (json is! Map) throw const ClaudeUnavailable('réponse illisible');
    if (json['stop_reason'] == 'refusal') throw const ClaudeDeclined();
    final text = [
      for (final block in json['content'] is List ? json['content'] as List : const [])
        if (block is Map && block['type'] == 'text' && block['text'] is String)
          block['text'] as String,
    ].join().trim();
    if (text.isEmpty) throw const ClaudeUnavailable('réponse vide');
    // L'app affiche du texte brut : pas de ligne vide avant la source.
    return text.replaceAll(RegExp(r'\n\s*\n+'), '\n');
  }

  void close() => _client.close();
}
