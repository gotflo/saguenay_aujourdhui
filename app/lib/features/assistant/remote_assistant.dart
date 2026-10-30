import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:saguenay_core/saguenay_core.dart';

/// L'adresse du petit serveur de l'assistant en ligne, donnée à la
/// compilation : `--dart-define=ASSISTANT_URL=https://...`. Vide : pas
/// d'assistant en ligne, l'app répond seule.
const assistantUrl = String.fromEnvironment('ASSISTANT_URL');

/// L'adresse du serveur, terminée par une barre oblique, ou `null` : pas de
/// serveur, ou une adresse qui n'est pas en https (sauf `localhost`, pour
/// le développement).
final Uri? assistantBase = () {
  final url = Uri.tryParse(assistantUrl);
  if (assistantUrl.isEmpty || url == null) return null;
  final local = url.scheme == 'http' && (url.host == 'localhost' || url.host == '127.0.0.1');
  if (url.scheme != 'https' && !local) return null;
  return url.path.endsWith('/') ? url : url.replace(path: '${url.path}/');
}();

/// Un communiqué de la Ville, résumé par le serveur.
class PressNote {
  const PressNote({required this.title, required this.date, required this.url, this.summary});

  final String title;
  final DateTime date;
  final Uri url;

  /// `null` si le serveur n'a pas pu le lire : on montre le titre et le lien.
  final String? summary;

  static PressNote? fromJson(Object? json) {
    if (json is! Map) return null;
    final title = json['titre'];
    final date = DateTime.tryParse('${json['date']}');
    final url = Uri.tryParse('${json['lien']}');
    if (title is! String || date == null || url == null || url.scheme != 'https') return null;
    final summary = json['resume'];
    return PressNote(
      title: title,
      date: date,
      url: url,
      summary: summary is String && summary.trim().isNotEmpty ? summary.trim() : null,
    );
  }
}

/// L'assistant en ligne, qui s'appuie sur Claude par notre serveur. La clé
/// d'API reste sur le serveur ; l'app n'envoie ni l'adresse exacte ni rien
/// qui identifie la personne, seulement le secteur et ce que l'app affiche.
abstract interface class RemoteAssistant {
  bool get available;

  /// `history` : les questions et réponses d'avant, pour comprendre une suite.
  Future<String> ask(
    String question,
    Map<String, Object?> context, {
    List<Map<String, String>> history = const [],
  });

  /// « Ça va où ? » à partir d'une photo de l'objet.
  Future<String> sortPhoto(Uint8List jpeg);

  /// Un texte officiel réécrit en langage simple.
  Future<String> explain(String text);

  /// Les derniers communiqués de la Ville, résumés.
  Future<List<PressNote>> pressReleases();
}

class NoRemoteAssistant implements RemoteAssistant {
  const NoRemoteAssistant();

  static Never _off() => throw UnsupportedError('Assistant en ligne non configuré');

  @override
  bool get available => false;

  @override
  Future<String> ask(
    String question,
    Map<String, Object?> context, {
    List<Map<String, String>> history = const [],
  }) async => _off();

  @override
  Future<String> sortPhoto(Uint8List jpeg) async => _off();

  @override
  Future<String> explain(String text) async => _off();

  @override
  Future<List<PressNote>> pressReleases() async => _off();
}

/// Le serveur dit d'attendre : trop de demandes de cet appareil.
class RemoteBusy implements Exception {
  const RemoteBusy();
}

class HttpRemoteAssistant implements RemoteAssistant {
  HttpRemoteAssistant(this.base, {http.Client? client}) : _client = client ?? http.Client();

  final Uri base;
  final http.Client _client;

  @override
  bool get available => true;

  Object? _decode(http.Response response, Uri url) {
    if (response.statusCode == 429) throw const RemoteBusy();
    if (response.statusCode != 200) {
      throw http.ClientException('Réponse ${response.statusCode}', url);
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<String> _post(String path, Map<String, Object?> body) async {
    final url = base.resolve(path);
    final response = await _client
        .post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        // Plus long que le délai du serveur, qui a lui-même une réponse à donner.
        .timeout(const Duration(seconds: 70));
    final json = _decode(response, url);
    final text = json is Map ? json['answer'] : null;
    if (text is! String || text.trim().isEmpty) throw const FormatException('Réponse vide');
    return text.trim();
  }

  @override
  Future<String> ask(
    String question,
    Map<String, Object?> context, {
    List<Map<String, String>> history = const [],
  }) => _post('question', {'question': question, 'context': context, 'historique': history});

  @override
  Future<String> sortPhoto(Uint8List jpeg) => _post('tri', {'image': base64Encode(jpeg)});

  @override
  Future<String> explain(String text) => _post('expliquer', {'texte': text});

  @override
  Future<List<PressNote>> pressReleases() async {
    final url = base.resolve('communiques');
    final json = _decode(await _client.get(url).timeout(const Duration(seconds: 40)), url);
    final items = json is Map ? json['communiques'] : null;
    return [
      if (items is List)
        for (final item in items) ?PressNote.fromJson(item),
    ];
  }
}

final remoteAssistantProvider = Provider<RemoteAssistant>((ref) {
  final base = assistantBase;
  return base == null ? const NoRemoteAssistant() : HttpRemoteAssistant(base);
});

/// Ce que l'app envoie à l'assistant en ligne : le secteur et ce qu'elle
/// sait pour lui, jamais l'adresse.
Map<String, Object?> assistantContext(Place place, CityData city, DateTime now) =>
    const LocalAssistant().briefing(place, city, now);
