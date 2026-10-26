import 'geo.dart';

enum WaterNoticeType {
  boil('Avis d’ébullition'),
  interruption('Coupure d’eau'),
  discolored('Eau colorée'),
  other('Avis d’aqueduc');

  const WaterNoticeType(this.label);

  final String label;
}

enum NoticeState { upcoming, active, ended, unknown }

class WaterNotice {
  const WaterNotice({
    required this.number,
    required this.type,
    required this.start,
    required this.zone,
    this.end,
    this.rings = const [],
  });

  factory WaterNotice.fromJson(Map<String, Object?> json) => WaterNotice(
    number: json['number'] as String,
    type: WaterNoticeType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => WaterNoticeType.other,
    ),
    start: DateTime.parse(json['start'] as String),
    end: switch (json['end']) {
      final String s => DateTime.parse(s),
      _ => null,
    },
    zone: json['zone'] as String? ?? '',
    rings: readLonLatLists(json['rings']),
  );

  /// Numéro de la Ville, par exemple « 2026-378 ».
  final String number;
  final WaterNoticeType type;
  final DateTime start;

  /// Vide quand l'avis est en vigueur « jusqu'à nouvel ordre ».
  final DateTime? end;
  final String zone;

  /// La zone touchée, telle que la Ville la dessine sur sa carte.
  final List<List<LonLat>> rings;

  /// L'adresse est-elle dans la zone de l'avis ?
  bool covers(double lat, double lon) => insideRings(rings, lat, lon);

  /// [knownUntil] est la fin de la période pour laquelle on a des données :
  /// passé ce moment, un avis sans date de fin est peut-être levé.
  ///
  /// La couche de la Ville laisse parfois le statut « Actif » à des avis dont
  /// la date de fin est passée. On se fie à la date, pas au statut.
  NoticeState stateAt(DateTime t, {DateTime? knownUntil}) {
    if (t.isBefore(start)) return NoticeState.upcoming;
    final e = end;
    if (e == null) {
      if (knownUntil != null && t.isAfter(knownUntil)) return NoticeState.unknown;
      return NoticeState.active;
    }
    return t.isBefore(e) ? NoticeState.active : NoticeState.ended;
  }

  Map<String, Object?> toJson() => {
    'number': number,
    'type': type.name,
    'start': start.toIso8601String(),
    'end': end?.toIso8601String(),
    'zone': zone,
    'rings': writeLonLatLists(rings),
  };
}

/// Les avis d'aqueduc de toute la ville au moment du relevé.
class WaterSnapshot {
  const WaterSnapshot({required this.takenAt, required this.notices});

  factory WaterSnapshot.fromJson(Map<String, Object?> json) => WaterSnapshot(
    takenAt: DateTime.parse(json['takenAt'] as String),
    notices: [
      for (final n in (json['notices'] as List?) ?? const [])
        WaterNotice.fromJson((n as Map).cast<String, Object?>()),
    ],
  );

  final DateTime takenAt;
  final List<WaterNotice> notices;

  /// Un avis « jusqu'à nouvel ordre » peut être levé à tout moment : on ne
  /// s'y fie pas plus de douze heures après le relevé.
  DateTime get knownUntil => takenAt.add(const Duration(hours: 12));

  Map<String, Object?> toJson() => {
    'takenAt': takenAt.toIso8601String(),
    'notices': [for (final n in notices) n.toJson()],
  };
}
