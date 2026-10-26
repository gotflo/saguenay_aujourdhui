// Vérifie les lecteurs sur le vrai flux de la STS : dart run tool/check_sts.dart <gtfs.zip> <tripupdates.pb>
import 'dart:io';

import 'package:saguenay_core/saguenay_core.dart';

void main(List<String> args) {
  final watch = Stopwatch()..start();
  final feed = GtfsFeed.parse(File(args[0]).readAsBytesSync());
  final stops = feed.nearestStops(48.42825, -71.06225);
  print('arrêts proches : ${stops.map((s) => '${s.id} ${s.name}').join(' | ')}');
  final s = feed.schedule(stops, from: DateTime(2026, 10, 25));
  print('calcul : ${watch.elapsedMilliseconds} ms, ${s.byDate!.length} jours');
  final day = s.forDay(DateTime(2026, 11, 18));
  print(
    'mercredi 18 nov. : ${day.take(8).map((d) => '${clockTime(d.minute)} ${d.route} ${d.headsign}').join(' ; ')}',
  );
  final rt = parseTripUpdates(File(args[1]).readAsBytesSync());
  print('temps réel : ${rt.trips.length} voyages, relevé ${rt.takenAt}');
  print('exemple : ${rt.trips.entries.take(2).map((e) => '${e.key} → ${e.value}').join(' ; ')}');
}
