import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:saguenay_core/saguenay_core.dart';

import 'claude.dart';
import 'polite.dart';
import 'prompts.dart';

/// La salle des médias de la Ville : une page publique qui liste les
/// communiqués, chacun en PDF.
final pressPage = Uri.parse(
  'https://ville.saguenay.ca/la-ville-et-vie-democratique/salle-des-medias/communiques-de-presse',
);

class PressRelease {
  const PressRelease({required this.title, required this.issued, required this.url});

  final String title;
  final DateTime issued;
  final Uri url;
}

const _months = {
  'janvier': 1,
  'fevrier': 2,
  'février': 2,
  'mars': 3,
  'avril': 4,
  'mai': 5,
  'juin': 6,
  'juillet': 7,
  'aout': 8,
  'août': 8,
  'septembre': 9,
  'octobre': 10,
  'novembre': 11,
  'decembre': 12,
  'décembre': 12,
};

final _article = RegExp(r'<article[^>]*>(.*?)</article>', dotAll: true);
final _issued = RegExp(r'Émis le\s*:\s*(\d{1,2})(?:er)?\s+(\S+)\s+(\d{4})', caseSensitive: false);
final _pdf = RegExp(r'<a[^>]*href="([^"]+\.pdf)"[^>]*>([^<]+)</a>', caseSensitive: false);

/// Les communiqués de la page, dans l'ordre de la page (le plus récent
/// d'abord). Les articles mal formés sont ignorés.
List<PressRelease> parsePressReleases(String html, {Uri? base}) => [
  for (final article in _article.allMatches(html))
    if ((_issued.firstMatch(article[1]!), _pdf.firstMatch(article[1]!)) case (
      final date?,
      final link?,
    ))
      if (_months[date[2]!.toLowerCase()] case final month?)
        PressRelease(
          title: _unescape(link[2]!).trim(),
          issued: DateTime(int.parse(date[3]!), month, int.parse(date[1]!)),
          url: (base ?? pressPage).resolve(link[1]!.trim()),
        ),
];

String _unescape(String s) => s
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&rsquo;', '’')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('`', '’')
    .replaceAll(RegExp(r'\s+'), ' ');

/// Lit les derniers communiqués et les résume en langage simple. Un PDF ne
/// change pas une fois publié : chaque résumé est fait une seule fois.
class PressDesk {
  PressDesk(this._claude, {http.Client? client, this.count = 5, DateTime Function()? clock})
    : _client = PoliteClient(client ?? http.Client()),
      _clock = clock ?? DateTime.now;

  final Claude _claude;
  final http.Client _client;
  final DateTime Function() _clock;

  /// Le nombre de communiqués résumés.
  final int count;

  static const listLifetime = Duration(hours: 1);

  List<PressRelease>? _list;
  DateTime? _listAt;
  final _summaries = <Uri, String>{};
  Future<List<Map<String, Object?>>>? _pending;

  /// Les communiqués déjà résumés, sans rien lire ni rien payer de plus : ce
  /// que l'assistant peut citer en répondant à une question.
  List<String> known() => [
    for (final r in (_list ?? const <PressRelease>[]).take(count))
      if (_summaries[r.url] case final summary?) '${r.title} (${isoDate(r.issued)}) : $summary',
  ];

  /// Les derniers communiqués avec leur résumé. Les demandes simultanées
  /// partagent le même travail.
  Future<List<Map<String, Object?>>> latest() =>
      _pending ??= _latest().whenComplete(() => _pending = null);

  Future<List<Map<String, Object?>>> _latest() async {
    final at = _listAt;
    if (_list == null || at == null || _clock().difference(at) >= listLifetime) {
      try {
        final found = parsePressReleases(
          utf8.decode(
            await download(_client, pressPage, maxBytes: 3 * 1024 * 1024),
            allowMalformed: true,
          ),
        );
        if (found.isEmpty) throw const FormatException('Aucun communiqué sur la page');
        _list = found;
        _listAt = _clock();
      } on Exception {
        // La dernière liste lue fait l'affaire si la Ville ne répond pas.
        if (_list == null) rethrow;
      }
    }
    final releases = _list!.take(count).toList();
    final summaries = await Future.wait(releases.map(_summary));
    return [
      for (final (i, r) in releases.indexed)
        {
          'titre': r.title,
          'date': isoDate(r.issued),
          'lien': r.url.toString(),
          'resume': summaries[i],
        },
    ];
  }

  Future<String?> _summary(PressRelease r) async {
    if (_summaries[r.url] case final known?) return known;
    try {
      final pdf = await download(
        _client,
        r.url,
        maxBytes: 10 * 1024 * 1024,
        timeout: const Duration(seconds: 30),
      );
      if (!_isPdf(pdf)) return null;
      final text = await _claude.reply(
        system: pressPrompt,
        content: [
          {
            'type': 'document',
            'source': {
              'type': 'base64',
              'media_type': 'application/pdf',
              'data': base64Encode(pdf),
            },
          },
          {'type': 'text', 'text': 'Titre : ${r.title}\nÉmis le ${longDate(r.issued)}'},
        ],
      );
      return _summaries[r.url] = text;
    } on Exception {
      // Sans résumé, l'app montre le titre et le lien.
      return null;
    }
  }

  static bool _isPdf(Uint8List b) =>
      b.length > 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46;

  void close() => _client.close();
}

String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
