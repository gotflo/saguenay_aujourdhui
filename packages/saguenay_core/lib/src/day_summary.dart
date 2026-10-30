import 'calendar.dart';
import 'format.dart';
import 'parking.dart';
import 'place.dart';
import 'relevance.dart';
import 'signal.dart';

/// La journée d'une adresse en quelques phrases : pour un texto, une voix au
/// téléphone, ou le résumé quotidien de l'adresse d'un proche. Pas de puces
/// ni de symboles : le texte doit aussi bien se lire que s'écouter.
abstract final class DaySummary {
  /// Au-delà, un texto accentué coûte un segment de plus.
  static const maxLength = 320;
  static const maxDetail = 110;

  static String text(Place place, CityData city, DateTime now, {String? name}) {
    final today = const RelevanceEngine().today(place, city, now);
    final hero = today.hero;
    // Deux autres informations qui comptent, sans les tuiles « tout va bien ».
    final others = today.signals
        .where((s) => !identical(s, hero) && s.score >= 20)
        .take(2)
        .toList();
    final parts = <String>[
      hero == null
          ? '${name ?? place.label} : rien de spécial pour l’instant.'
          : '${name ?? place.label} : ${_sentence(hero.title)}'
                // Un long détail de chantier ne prend pas la place du reste de la journée.
                '${hero.body.length > maxDetail ? '' : ' ${_sentence(hero.body)}'}',
      for (final s in others) _sentence(s.title),
    ];
    bool told(SignalKind kind) => hero?.kind == kind || others.any((s) => s.kind == kind);

    final next = place.collectionMissing ? null : place.collection.next(now);
    if (!told(SignalKind.collection) && next != null) {
      final day = sameDay(next.day, now)
          ? 'aujourd’hui'
          : sameDay(next.day, addDays(now, 1))
          ? 'demain'
          : shortDate(next.day);
      final what = next.streams.map((s) => s.label.toLowerCase()).join(' et ');
      parts.add(_sentence('Prochaine collecte : $what, $day'));
    }
    if (!told(SignalKind.parking)) {
      parts.add(
        const WinterParking().appliesTonight(now)
            ? 'Pas d’auto dans la rue cette nuit.'
            : 'Stationnement permis cette nuit.',
      );
    }
    if (!told(SignalKind.water) && city.waterKnownUntil != null) {
      parts.add('Eau : rien à signaler.');
    }

    var out = parts.join(' ');
    // On retire les dernières phrases plutôt que de couper un mot.
    while (out.length > maxLength && parts.length > 1) {
      parts.removeLast();
      out = parts.join(' ');
    }
    return out.length > maxLength ? '${out.substring(0, maxLength - 1)}…' : out;
  }

  static String _sentence(String s) {
    final t = s.trim();
    return t.endsWith('.') || t.endsWith('!') || t.endsWith('?') ? t : '$t.';
  }
}
