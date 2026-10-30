/// Les quatre niveaux d'Environnement Canada, du plus grave au plus doux.
enum WeatherAlertLevel {
  warning('Avertissement', .85, 1),
  watch('Veille', .7, .8),
  advisory('Avis', .6, .7),
  statement('Bulletin', .5, .5);

  const WeatherAlertLevel(this.label, this.weight, this.urgency);

  final String label;
  final double weight;
  final double urgency;

  static WeatherAlertLevel parse(String? type) => switch (type) {
    'warning' => warning,
    'watch' => watch,
    'advisory' => advisory,
    _ => statement,
  };
}

class WeatherAlert {
  const WeatherAlert({
    required this.name,
    required this.level,
    required this.issuedAt,
    this.what,
    this.when,
    this.endsAt,
  });

  factory WeatherAlert.fromJson(Map<String, Object?> json) => WeatherAlert(
    name: json['name'] as String,
    level: WeatherAlertLevel.parse(json['level'] as String?),
    issuedAt: DateTime.parse(json['issuedAt'] as String),
    what: json['what'] as String?,
    when: json['when'] as String?,
    endsAt: switch (json['endsAt']) {
      final String s => DateTime.parse(s),
      _ => null,
    },
  );

  /// « Avertissement de neige ».
  final String name;
  final WeatherAlertLevel level;
  final DateTime issuedAt;

  /// Les lignes « Quoi : » et « Quand : » du bulletin.
  final String? what;
  final String? when;

  /// Fin de l'événement ou de l'alerte, selon ce qu'on connaît.
  final DateTime? endsAt;

  bool activeAt(DateTime t) => endsAt == null || t.isBefore(endsAt!);

  /// Une alerte reprise ou mise à jour garde le même nom le même jour.
  String get key => '${name.toLowerCase()}:${issuedAt.year}-${issuedAt.month}-${issuedAt.day}';

  Map<String, Object?> toJson() => {
    'name': name,
    'level': level.name,
    'issuedAt': issuedAt.toIso8601String(),
    'what': what,
    'when': when,
    'endsAt': endsAt?.toIso8601String(),
  };
}

/// La météo de Saguenay au moment du relevé.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.takenAt,
    this.temperature,
    this.condition,
    this.snowTonightCm,
    this.alerts = const [],
    this.forecast = const [],
  });

  factory WeatherSnapshot.fromJson(Map<String, Object?> json) => WeatherSnapshot(
    takenAt: DateTime.parse(json['takenAt'] as String),
    temperature: (json['temperature'] as num?)?.toDouble(),
    condition: json['condition'] as String?,
    snowTonightCm: json['snowTonightCm'] as int?,
    alerts: [
      for (final a in (json['alerts'] as List?) ?? const [])
        WeatherAlert.fromJson((a as Map).cast<String, Object?>()),
    ],
    forecast: [for (final f in (json['forecast'] as List?) ?? const []) '$f'],
  );

  final DateTime takenAt;
  final double? temperature;

  /// « Généralement ensoleillé ».
  final String? condition;

  /// Neige annoncée pour ce soir et cette nuit, en centimètres.
  final int? snowTonightCm;
  final List<WeatherAlert> alerts;

  /// Les prochaines périodes du bulletin : « Samedi : Neige. Maximum moins 2. »
  final List<String> forecast;

  /// La température d'il y a plus de trois heures ne veut plus dire grand-chose.
  bool isStaleAt(DateTime now) => now.difference(takenAt) > const Duration(hours: 3);

  Map<String, Object?> toJson() => {
    'takenAt': takenAt.toIso8601String(),
    'temperature': temperature,
    'condition': condition,
    'snowTonightCm': snowTonightCm,
    'alerts': [for (final a in alerts) a.toJson()],
    'forecast': forecast,
  };
}
