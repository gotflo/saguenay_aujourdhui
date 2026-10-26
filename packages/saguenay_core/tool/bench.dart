// Mesure le temps de calcul de la timeline du widget : dart run tool/bench.dart

import 'dart:convert';

import 'package:saguenay_core/saguenay_core.dart';

void main() {
  const engine = RelevanceEngine();
  for (final id in ['racine', 'saint-jean', 'saint-pierre']) {
    final w = Stopwatch()..start();
    final t = engine.timeline(Demo.place(id), Demo.city, DateTime(2026, 11, 16, 6));
    final ms = w.elapsedMilliseconds;
    final json = jsonEncode([for (final e in t) e.toJson()]);
    print('$id: ${t.length} entrées, $ms ms, ${json.length ~/ 1024} ko');
  }
}
