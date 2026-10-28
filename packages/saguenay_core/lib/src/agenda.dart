import 'calendar.dart';
import 'format.dart';
import 'parking.dart';
import 'place.dart';
import 'relevance.dart';
import 'signal.dart';
import 'water.dart';

class AgendaItem {
  const AgendaItem(this.kind, this.title, [this.detail]);

  final SignalKind kind;
  final String title;
  final String? detail;
}

class AgendaDay {
  const AgendaDay(this.day, this.items);

  final DateTime day;
  final List<AgendaItem> items;
}

/// Les jours à venir, plus ce qui vaut pour toute la semaine.
class Week {
  const Week({required this.days, required this.ongoing});

  /// Seulement les jours où il se passe quelque chose.
  final List<AgendaDay> days;

  /// « Chaque nuit, pas d'auto dans la rue », « Travaux sur ta rue jusqu'au 6 nov. ».
  final List<AgendaItem> ongoing;

  bool get isEmpty => days.isEmpty && ongoing.isEmpty;

  /// Une phrase pour le résumé du dimanche : « Recyclage mardi, compost vendredi. »
  String? summary({int max = 3}) {
    final parts = <String>[
      for (final d in days)
        for (final i in d.items) '${_lowerFirst(i.title)} ${weekdayName(d.day)}',
    ];
    if (parts.isEmpty && ongoing.isEmpty) return null;
    final shown = parts.take(max).toList();
    final sentence = shown.isEmpty ? null : '${capitalize(shown.join(', '))}.';
    final extra = ongoing.isEmpty ? null : _sentence(ongoing.first.title);
    return [?sentence, ?extra].join(' ');
  }

  static String _sentence(String s) => s.endsWith('.') ? s : '$s.';

  static String _lowerFirst(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}

/// Ce qui est prévu pour une adresse les prochains jours. Tout se calcule sur
/// le téléphone, sans réseau : collectes, nuits d'hiver, coupures annoncées,
/// travaux et interruptions planifiées d'Hydro-Québec.
class Agenda {
  const Agenda({this.parking = const WinterParking()});

  final WinterParking parking;

  Week week(Place place, CityData city, DateTime from, {int days = 7}) {
    final first = startOfDay(from);
    final out = <AgendaDay>[];
    final ongoing = <AgendaItem>[];

    if (parking.appliesOn(first) && parking.appliesOn(addDays(first, 1))) {
      ongoing.add(
        const AgendaItem(
          SignalKind.parking,
          'Chaque nuit, pas d’auto dans la rue',
          'de minuit à 7 h',
        ),
      );
    }
    for (final number in place.waterNotices) {
      final n = city.waterNotices.where((w) => w.number == number).firstOrNull;
      if (n != null &&
          n.type == WaterNoticeType.boil &&
          n.stateAt(from, knownUntil: city.waterKnownUntil) == NoticeState.active) {
        ongoing.add(
          const AgendaItem(SignalKind.water, 'Avis d’ébullition en cours', 'à ton adresse'),
        );
      }
    }
    for (final r in place.roadworks.where((r) => r.onMyStreet)) {
      if (!from.isBefore(r.work.start) && from.isBefore(r.work.end)) {
        ongoing.add(
          AgendaItem(
            SignalKind.roadwork,
            'Travaux sur ta rue jusqu’au ${r.work.end.day} ${_month(r.work.end)}',
            r.work.street,
          ),
        );
      }
    }

    for (var n = 0; n < days; n++) {
      final day = addDays(first, n);
      final items = <AgendaItem>[];

      final streams = place.collection.on(day);
      if (streams.isNotEmpty) {
        items.add(
          AgendaItem(
            SignalKind.collection,
            streams.map((s) => s.label).join(' et '),
            streams.map((s) => s.bin).join(' et '),
          ),
        );
      }

      final tomorrow = addDays(day, 1);
      if (!parking.appliesOn(day) && parking.appliesOn(tomorrow)) {
        items.add(
          const AgendaItem(
            SignalKind.parking,
            'Première nuit d’hiver',
            'pas d’auto dans la rue dès minuit',
          ),
        );
      } else if (parking.appliesOn(day) && !parking.appliesOn(tomorrow) && n > 0) {
        items.add(
          const AgendaItem(SignalKind.parking, 'Fin du stationnement de nuit', 'dernière nuit'),
        );
      }

      for (final number in place.waterNotices) {
        final w = city.waterNotices.where((x) => x.number == number).firstOrNull;
        if (w == null || !sameDay(w.start, day) || !w.start.isAfter(from)) continue;
        final end = w.end;
        items.add(
          AgendaItem(
            SignalKind.water,
            w.type.label,
            end == null
                ? 'dès ${clockTimeOf(w.start)}'
                : 'de ${clockTimeOf(w.start)} à ${clockTimeOf(end)}',
          ),
        );
      }

      for (final r in place.roadworks.where((r) => r.onMyStreet)) {
        if (sameDay(r.work.start, day) && r.work.start.isAfter(from)) {
          items.add(AgendaItem(SignalKind.roadwork, 'Début des travaux', r.work.street));
        }
        if (sameDay(r.work.end, day) && n > 0) {
          items.add(AgendaItem(SignalKind.roadwork, 'Fin prévue des travaux', r.work.street));
        }
      }

      final power = city.power;
      final lat = place.lat, lon = place.lon;
      if (power != null && lat != null && lon != null) {
        for (final o in power.near(lat, lon)) {
          final end = o.end;
          if (!o.planned || end == null || !sameDay(o.start, day) || !end.isAfter(from)) continue;
          items.add(
            AgendaItem(
              SignalKind.power,
              'Courant coupé',
              'de ${clockTimeOf(o.start)} à ${clockTimeOf(end)}, travaux d’Hydro-Québec',
            ),
          );
        }
      }

      if (items.isNotEmpty) out.add(AgendaDay(day, items));
    }
    return Week(days: out, ongoing: ongoing);
  }

  static String _month(DateTime d) => shortDate(d).split(' ').last;
}
