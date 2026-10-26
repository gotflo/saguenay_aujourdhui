/// Garde la facture sous contrôle : un plafond par appareil sur une fenêtre
/// glissante, et un plafond pour toute la journée.
class RateLimiter {
  RateLimiter({
    this.perClient = 20,
    this.window = const Duration(minutes: 10),
    this.perDay = 2000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int perClient;
  final Duration window;
  final int perDay;
  final DateTime Function() _clock;

  final _hits = <String, List<DateTime>>{};
  var _today = 0;
  DateTime? _day;

  /// `null` si la demande passe, sinon le temps à attendre.
  Duration? check(String client) {
    final now = _clock();
    final day = _day;
    if (day == null || day.year != now.year || day.month != now.month || day.day != now.day) {
      _day = now;
      _today = 0;
    }
    if (_today >= perDay) {
      return DateTime(now.year, now.month, now.day + 1).difference(now);
    }
    final hits = _hits.putIfAbsent(client, () => [])
      ..removeWhere((t) => now.difference(t) >= window);
    if (hits.length >= perClient) return window - now.difference(hits.first);
    hits.add(now);
    _today++;
    if (_hits.length > 10000) {
      _hits.removeWhere((_, v) => v.isEmpty || now.difference(v.last) >= window);
    }
    return null;
  }
}
