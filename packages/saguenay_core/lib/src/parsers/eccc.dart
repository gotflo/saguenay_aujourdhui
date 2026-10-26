import '../weather.dart';

/// Page météo d'une ville (`collections/citypageweather-realtime/items/qc-166`),
/// API GeoMet d'Environnement Canada, Licence du gouvernement ouvert – Canada.
///
/// Chaque texte arrive en deux langues : `{"en": ..., "fr": ...}`. La condition
/// actuelle manque parfois ; on prend alors celle de la prochaine heure.
WeatherSnapshot parseCityWeather(
  Map<String, Object?> json, {
  List<WeatherAlert> alerts = const [],
}) {
  final p = _map(json['properties']) ?? json;
  final current = _map(p['currentConditions']);
  final hourly = _list(_map(p['hourlyForecastGroup'])?['hourlyForecasts']);
  final forecasts = _list(_map(p['forecastGroup'])?['forecasts']);

  final temperature = _fr(_map(current?['temperature'])?['value']);
  final condition = _fr(current?['condition']) ?? _fr(_map(hourly.firstOrNull)?['condition']);
  final updated = p['lastUpdated'];

  return WeatherSnapshot(
    takenAt: updated is String ? DateTime.parse(updated).toLocal() : DateTime.now(),
    temperature: temperature is num ? temperature.toDouble() : null,
    condition: condition is String && condition.trim().isNotEmpty ? condition.trim() : null,
    snowTonightCm: _tonight(forecasts),
    alerts: alerts,
  );
}

/// Couche `weather-alerts`, filtrée par un petit rectangle autour de l'adresse.
///
/// Une même alerte revient une fois par région touchée : on garde la plus
/// récente de chaque nom. Les alertes terminées ou annulées sont écartées.
List<WeatherAlert> parseWeatherAlerts(Map<String, Object?> json, {required DateTime now}) {
  final byName = <String, WeatherAlert>{};
  for (final f in _list(json['features'])) {
    final p = _map(_map(f)?['properties']);
    if (p == null) continue;
    final status = (p['status_en'] as String? ?? '').toLowerCase();
    if (status == 'ended' || status == 'cancelled') continue;
    final name = p['alert_name_fr'];
    final issued = _date(p['publication_datetime']);
    if (name is! String || issued == null) continue;

    final end = _date(p['event_end_datetime']) ?? _date(p['expiration_datetime']);
    if (end != null && !now.isBefore(end)) continue;

    final text = p['alert_text_fr'] as String? ?? '';
    final alert = WeatherAlert(
      name: _capitalize(name.trim()),
      level: WeatherAlertLevel.parse(p['alert_type'] as String?),
      issuedAt: issued,
      what: _section(text, 'Quoi'),
      when: _section(text, 'Quand'),
      endsAt: end,
    );
    final previous = byName[alert.name];
    if (previous == null || alert.issuedAt.isAfter(previous.issuedAt)) byName[alert.name] = alert;
  }
  final out = byName.values.toList()..sort((a, b) => a.level.index.compareTo(b.level.index));
  return out;
}

/// La neige annoncée pour la période « ce soir et cette nuit », d'après le
/// texte du bulletin : « Neige. Accumulation de 10 à 15 cm. »
int? _tonight(List<Object?> forecasts) {
  for (final f in forecasts) {
    final m = _map(f);
    final name = _fr(_map(m?['period'])?['textForecastName']);
    if (name is! String || !name.toLowerCase().contains('nuit')) continue;
    final text = _fr(m?['textSummary']);
    return text is String ? snowCentimetres(text) : null;
  }
  return null;
}

/// Le plus grand nombre de centimètres de neige mentionné dans un texte.
int? snowCentimetres(String text) {
  final t = text.toLowerCase();
  if (!t.contains('neige')) return null;
  int? best;
  for (final m in RegExp(r'(\d+)\s*(?:à\s*(\d+)\s*)?cm').allMatches(t)) {
    final value = int.parse(m.group(2) ?? m.group(1)!);
    if (best == null || value > best) best = value;
  }
  return best;
}

String? _section(String text, String title) {
  final m = RegExp('$title\\s*:\\s*\\n?([^\\n]+)').firstMatch(text);
  final line = m?.group(1)?.trim();
  return line == null || line.isEmpty ? null : line;
}

Object? _fr(Object? v) => v is Map ? (v['fr'] ?? v['en']) : v;

Map<String, Object?>? _map(Object? v) => v is Map ? v.cast<String, Object?>() : null;

List<Object?> _list(Object? v) => v is List ? v : const [];

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
