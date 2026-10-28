import 'calendar.dart';

enum WasteStream {
  garbage('Ordures', 'le bac à ordures'),
  recycling('Recyclage', 'le bac bleu'),
  compost('Compost', 'le bac brun');

  const WasteStream(this.label, this.bin);

  final String label;

  /// Avec l'article, pour « Sors le bac bleu ».
  final String bin;
}

/// Une collecte qui revient aux deux semaines le même jour.
///
/// Le compost passe chaque semaine en été : du 8 mai au 25 septembre dans le
/// calendrier 2026 de la Ville.
class CollectionRule {
  const CollectionRule({
    required this.weekday,
    required this.anchor,
    this.everyDays = 14,
    this.weeklyInSummer = false,
  });

  final int weekday;

  /// Une date connue de passage, qui fixe la semaine.
  final DateTime anchor;
  final int everyDays;
  final bool weeklyInSummer;

  bool occursOn(DateTime day) {
    if (day.weekday != weekday) return false;
    if (weeklyInSummer && _isSummer(day)) return true;
    return (dayNumber(day) - dayNumber(anchor)) % everyDays == 0;
  }

  static bool _isSummer(DateTime d) {
    final md = d.month * 100 + d.day;
    return md >= 508 && md <= 925;
  }
}

typedef Pickup = ({DateTime day, List<WasteStream> streams});

class CollectionSchedule {
  const CollectionSchedule(this.rules, {this.publishedThrough});

  factory CollectionSchedule.fromJson(Map<String, Object?> json) {
    final rules = <WasteStream, CollectionRule>{};
    for (final MapEntry(:key, :value) in ((json['rules'] as Map?) ?? const {}).entries) {
      final stream = WasteStream.values.where((s) => s.name == key).firstOrNull;
      if (stream == null || value is! Map) continue;
      rules[stream] = CollectionRule(
        weekday: value['weekday'] as int,
        anchor: DateTime.parse(value['anchor'] as String),
        everyDays: value['everyDays'] as int? ?? 14,
        weeklyInSummer: value['weeklyInSummer'] as bool? ?? false,
      );
    }
    final through = json['publishedThrough'];
    return CollectionSchedule(
      rules,
      publishedThrough: through is String ? DateTime.parse(through) : null,
    );
  }

  final Map<WasteStream, CollectionRule> rules;

  /// Dernier jour couvert par le calendrier publié. Au-delà, on ne devine pas.
  final DateTime? publishedThrough;

  bool covers(DateTime day) =>
      publishedThrough == null || !startOfDay(day).isAfter(publishedThrough!);

  List<WasteStream> on(DateTime day) {
    if (!covers(day)) return const [];
    return [
      for (final MapEntry(:key, :value) in rules.entries)
        if (value.occursOn(day)) key,
    ];
  }

  /// La prochaine collecte à partir de [from] inclus.
  Pickup? next(DateTime from, {int horizonDays = 31}) {
    final start = startOfDay(from);
    for (var n = 0; n <= horizonDays; n++) {
      final day = addDays(start, n);
      if (!covers(day)) return null;
      final streams = on(day);
      if (streams.isNotEmpty) return (day: day, streams: streams);
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'publishedThrough': publishedThrough?.toIso8601String(),
    'rules': {
      for (final MapEntry(:key, :value) in rules.entries)
        key.name: {
          'weekday': value.weekday,
          'anchor': value.anchor.toIso8601String(),
          'everyDays': value.everyDays,
          'weeklyInSummer': value.weeklyInSummer,
        },
    },
  };

  List<Pickup> upcoming(DateTime from, {int count = 5}) {
    final out = <Pickup>[];
    var cursor = startOfDay(from);
    while (out.length < count) {
      final p = next(cursor);
      if (p == null) break;
      out.add(p);
      cursor = addDays(p.day, 1);
    }
    return out;
  }
}
