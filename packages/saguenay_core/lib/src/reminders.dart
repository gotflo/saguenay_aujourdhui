import 'agenda.dart';
import 'calendar.dart';
import 'format.dart';
import 'parking.dart';
import 'place.dart';
import 'relevance.dart';
import 'water.dart';
import 'weather.dart';

/// L'ordre compte : il sert aux identifiants des notifications.
enum ReminderKind { water, weather, power, parking, collection, roadwork, week }

/// Une notification à programmer sur le téléphone.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.kind,
    required this.title,
    required this.body,
  });

  /// Stable d'un calcul à l'autre pour un même jour et un même type.
  final int id;
  final DateTime at;

  /// `null` pour le rappel qui demande d'ouvrir l'app.
  final ReminderKind? kind;
  final String title;
  final String body;
}

/// Calcule les rappels prévisibles des prochaines semaines : le stationnement
/// le soir, le bac la veille, les travaux le matin, les coupures de courant
/// planifiées et le résumé du dimanche.
///
/// Ce qui est prévisible se programme d'avance sur le téléphone, sans serveur.
/// Les avis d'eau et les alertes météo, eux, tombent sans prévenir : voir
/// [WaterAlerts] et [WeatherAlerts].
class ReminderPlanner {
  const ReminderPlanner({this.parking = const WinterParking()});

  final WinterParking parking;

  static const parkingMinute = 21 * 60;
  static const collectionMinute = 19 * 60;
  static const roadworkMinute = 6 * 60 + 45;
  static const powerMinute = 19 * 60;
  static const weekMinute = 18 * 60;

  /// iOS garde au plus 64 notifications en attente ; on reste en dessous.
  static const maxPending = 60;

  /// Le rappel qui invite à rouvrir l'app avant que les autres s'épuisent.
  static const renewId = 899999;

  List<PlannedReminder> plan(
    Place place,
    DateTime from, {
    required Set<ReminderKind> enabled,
    CityData city = const CityData(),
    int days = 28,
  }) {
    final out = <PlannedReminder>[];
    final first = startOfDay(from);

    for (var n = 0; n < days; n++) {
      final day = addDays(first, n);
      final tomorrow = addDays(day, 1);

      if (enabled.contains(ReminderKind.parking) && parking.appliesOn(tomorrow)) {
        final firstNight = !parking.appliesOn(day);
        out.add(
          PlannedReminder(
            id: _id(day, ReminderKind.parking),
            at: atMinute(day, parkingMinute),
            kind: ReminderKind.parking,
            title: firstNight
                ? 'Première nuit sans auto dans la rue'
                : 'Pas d’auto dans la rue cette nuit',
            body: firstNight
                ? 'Dès minuit, et chaque nuit jusqu’au 1er avril.'
                : 'Stationnement interdit de minuit à 7 h.',
          ),
        );
      }

      if (enabled.contains(ReminderKind.collection)) {
        final streams = place.collection.on(tomorrow);
        if (streams.isNotEmpty) {
          out.add(
            PlannedReminder(
              id: _id(day, ReminderKind.collection),
              at: atMinute(day, collectionMinute),
              kind: ReminderKind.collection,
              title: 'Sors ${streams.map((s) => s.bin).join(' et ')}',
              body: 'La collecte passe demain matin.',
            ),
          );
        }
      }

      if (enabled.contains(ReminderKind.roadwork) && day.weekday <= DateTime.friday) {
        final check = atMinute(day, 7 * 60 + 30);
        final work = place.roadworks
            .where((w) => w.onMyStreet && w.work.activeAt(check))
            .map((w) => w.work)
            .firstOrNull;
        if (work != null) {
          out.add(
            PlannedReminder(
              id: _id(day, ReminderKind.roadwork),
              at: atMinute(day, roadworkMinute),
              kind: ReminderKind.roadwork,
              title: 'Travaux sur ta rue ce matin',
              body: '${work.street}, ${work.status}.',
            ),
          );
        }
      }

      final power = city.power;
      final lat = place.lat, lon = place.lon;
      if (enabled.contains(ReminderKind.power) && power != null && lat != null && lon != null) {
        final cut = power
            .near(lat, lon)
            .where((o) => o.planned && o.end != null && sameDay(o.start, tomorrow))
            .firstOrNull;
        if (cut != null) {
          out.add(
            PlannedReminder(
              id: _id(day, ReminderKind.power),
              at: atMinute(day, powerMinute),
              kind: ReminderKind.power,
              title:
                  'Demain, courant coupé de ${clockTimeOf(cut.start)} à ${clockTimeOf(cut.end!)}',
              body: 'Travaux planifiés par Hydro-Québec dans ton secteur.',
            ),
          );
        }
      }

      if (enabled.contains(ReminderKind.week) && day.weekday == DateTime.sunday) {
        final summary = const Agenda().week(place, city, tomorrow).summary();
        if (summary != null) {
          out.add(
            PlannedReminder(
              id: _id(day, ReminderKind.week),
              at: atMinute(day, weekMinute),
              kind: ReminderKind.week,
              title: 'Ta semaine',
              body: summary,
            ),
          );
        }
      }
    }

    final kept = out.where((r) => r.at.isAfter(from)).take(maxPending - 1).toList();
    if (kept.isEmpty) return kept;

    // Si l'app reste fermée tout ce temps, les rappels s'arrêteraient sans
    // prévenir. Deux jours avant le dernier, on demande de l'ouvrir.
    final coveredUntil = kept.length == maxPending - 1 ? kept.last.at : addDays(first, days);
    final renewAt = atMinute(addDays(coveredUntil, -2), 12 * 60);
    if (renewAt.isAfter(from)) {
      kept.add(
        PlannedReminder(
          id: renewId,
          at: renewAt,
          kind: null,
          title: 'Tes rappels s’arrêtent bientôt',
          body: 'Ouvre l’app un instant pour les prolonger.',
        ),
      );
    }
    return kept;
  }

  static int _id(DateTime day, ReminderKind kind) => (dayNumber(day) % 80000) * 10 + kind.index;
}

/// Une alerte qui mérite une notification tout de suite.
abstract class Alert {
  const Alert({required this.title, required this.body});

  final String title;
  final String body;

  ReminderKind get kind;

  /// Retenue une fois envoyée, pour ne pas prévenir deux fois.
  String get key;

  int get id;
}

/// Un avis d'eau qui touche l'adresse.
class WaterAlert extends Alert {
  const WaterAlert(
    this.notice, {
    required this.upcoming,
    required super.title,
    required super.body,
  });

  final WaterNotice notice;

  /// Annoncé pour les prochaines heures, pas encore en vigueur.
  final bool upcoming;

  @override
  ReminderKind get kind => ReminderKind.water;

  /// On prévient une fois quand l'avis est annoncé, une fois quand il entre en vigueur.
  @override
  String get key => '${notice.number}:${upcoming ? 'annonce' : 'en-cours'}';

  @override
  int get id {
    final digits = int.tryParse(notice.number.replaceAll(RegExp(r'\D'), '')) ?? 0;
    return 900000 + (digits % 49999) * 2 + (upcoming ? 0 : 1);
  }
}

/// Un avertissement ou une veille d'Environnement Canada.
class WeatherAlertNotice extends Alert {
  const WeatherAlertNotice(this.alert, {required super.title, required super.body});

  final WeatherAlert alert;

  @override
  ReminderKind get kind => ReminderKind.weather;

  static String keyFor(WeatherAlert a) => 'meteo:${a.key}';

  @override
  String get key => keyFor(alert);

  @override
  int get id => 800000 + stableHash(key) % 99999;
}

abstract final class WaterAlerts {
  /// Les avis qui touchent l'adresse, en cours ou prévus dans les 24 heures,
  /// et qu'on n'a pas encore signalés.
  static List<WaterAlert> due(
    Place place,
    CityData city,
    DateTime now, {
    Set<String> alreadySent = const {},
  }) {
    final out = <WaterAlert>[];
    for (final number in place.waterNotices) {
      final notice = city.waterNotices.where((n) => n.number == number).firstOrNull;
      if (notice == null) continue;
      final state = notice.stateAt(now, knownUntil: city.waterKnownUntil);
      final soon =
          state == NoticeState.upcoming &&
          notice.start.difference(now) <= const Duration(hours: 24);
      if (state != NoticeState.active && !soon) continue;

      final alert = _describe(notice, now, upcoming: soon);
      if (!alreadySent.contains(alert.key)) out.add(alert);
    }
    return out;
  }

  static WaterAlert _describe(WaterNotice n, DateTime now, {required bool upcoming}) {
    if (upcoming) {
      final end = n.end;
      final when = sameDay(n.start, now) ? 'Aujourd’hui' : 'Demain';
      final hours = end == null
          ? 'dès ${clockTimeOf(n.start)}'
          : 'de ${clockTimeOf(n.start)} à ${clockTimeOf(end)}';
      return WaterAlert(
        n,
        upcoming: true,
        title: '$when, ${n.type.label.toLowerCase()} $hours',
        body: n.zone,
      );
    }
    if (n.type == WaterNoticeType.boil) {
      return WaterAlert(
        n,
        upcoming: false,
        title: 'Avis d’ébullition à ton adresse',
        body: 'Fais bouillir l’eau au moins une minute avant de la boire ou de cuisiner.',
      );
    }
    return WaterAlert(n, upcoming: false, title: '${n.type.label} à ton adresse', body: n.zone);
  }
}

abstract final class WeatherAlerts {
  /// Les avertissements et les veilles en cours, pas encore signalés. Les
  /// avis et les bulletins restent dans l'app, sans notification.
  static List<WeatherAlertNotice> due(
    CityData city,
    DateTime now, {
    Set<String> alreadySent = const {},
  }) {
    final weather = city.weather;
    if (weather == null) return const [];
    return [
      for (final a in weather.alerts)
        if (a.level.index <= WeatherAlertLevel.watch.index &&
            a.activeAt(now) &&
            now.isBefore(a.issuedAt.add(const Duration(hours: 24))) &&
            !alreadySent.contains(WeatherAlertNotice.keyFor(a)))
          WeatherAlertNotice(
            a,
            title: a.name,
            body: a.what ?? 'Environnement Canada a émis une alerte pour ton secteur.',
          ),
    ];
  }
}

/// FNV-1a sur 31 bits : le même texte donne le même nombre d'une version à l'autre.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// Heures calmes, de 22 h à 7 h : une alerte qui tombe la nuit attend le
/// matin, sauf un avis d'ébullition, qui touche à la santé.
abstract final class QuietHours {
  static const startMinute = 22 * 60;
  static const endMinute = 7 * 60;

  /// Le moment où montrer l'alerte, ou `null` pour la montrer tout de suite.
  static DateTime? deferral(Alert alert, DateTime now) {
    if (alert is WaterAlert && alert.notice.type == WaterNoticeType.boil) return null;
    final m = minuteOfDay(now);
    if (m >= startMinute) return atMinute(addDays(now, 1), endMinute);
    if (m < endMinute) return atMinute(now, endMinute);
    return null;
  }
}
