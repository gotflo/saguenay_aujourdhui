import 'dart:convert';
import 'dart:typed_data';

import '../transit.dart';

/// Temps réel de la STS (`saguenay.tmix.se/gtfs-realtime/tripupdates.pb`), au
/// format protobuf GTFS-realtime. On n'en lit que ce qui sert : le voyage,
/// et pour chaque arrêt, le retard.
///
/// Pas de dépendance protobuf : le format tient en quelques règles (une clé
/// varint, puis la valeur selon son type) et on ne décode que quelques champs.
TransitRealtime parseTripUpdates(Uint8List bytes, {DateTime? fallbackTime}) {
  final feed = _Reader(bytes);
  final trips = <String, Map<String, int>>{};
  DateTime? takenAt;
  while (feed.more) {
    final (field, wire) = feed.key();
    if (field == 1 && wire == 2) {
      final header = _Reader(feed.bytes());
      while (header.more) {
        final (f, w) = header.key();
        if (f == 3 && w == 0) {
          takenAt = DateTime.fromMillisecondsSinceEpoch(header.varint() * 1000);
        } else {
          header.skip(w);
        }
      }
    } else if (field == 2 && wire == 2) {
      _entity(_Reader(feed.bytes()), trips);
    } else {
      feed.skip(wire);
    }
  }
  return TransitRealtime(takenAt: takenAt ?? fallbackTime ?? DateTime.now(), trips: trips);
}

void _entity(_Reader e, Map<String, Map<String, int>> out) {
  while (e.more) {
    final (field, wire) = e.key();
    if (field == 3 && wire == 2) {
      String? tripId;
      int? tripDelay;
      final stops = <String, int>{};
      final u = _Reader(e.bytes());
      while (u.more) {
        final (f, w) = u.key();
        if (f == 1 && w == 2) {
          final t = _Reader(u.bytes());
          while (t.more) {
            final (tf, tw) = t.key();
            if (tf == 1 && tw == 2) {
              tripId = utf8.decode(t.bytes(), allowMalformed: true);
            } else {
              t.skip(tw);
            }
          }
        } else if (f == 2 && w == 2) {
          final (stopId, delay) = _stopTimeUpdate(_Reader(u.bytes()));
          if (stopId != null && delay != null) stops[stopId] = delay;
        } else if (f == 5 && w == 0) {
          tripDelay = u.varint().toSigned(32);
        } else {
          u.skip(w);
        }
      }
      if (tripId != null) {
        out[tripId] = {...stops, '': ?tripDelay ?? stops.values.firstOrNull};
      }
    } else {
      e.skip(wire);
    }
  }
}

(String?, int?) _stopTimeUpdate(_Reader s) {
  String? stopId;
  int? delay;
  while (s.more) {
    final (f, w) = s.key();
    if ((f == 2 || f == 3) && w == 2) {
      final ev = _Reader(s.bytes());
      while (ev.more) {
        final (ef, ew) = ev.key();
        // Le départ (3) l'emporte sur l'arrivée (2).
        if (ef == 1 && ew == 0) {
          final d = ev.varint().toSigned(32);
          if (f == 3 || delay == null) delay = d;
        } else {
          ev.skip(ew);
        }
      }
    } else if (f == 4 && w == 2) {
      stopId = utf8.decode(s.bytes(), allowMalformed: true);
    } else {
      s.skip(w);
    }
  }
  return (stopId, delay);
}

class _Reader {
  _Reader(this._b);

  final Uint8List _b;
  int _i = 0;

  bool get more => _i < _b.length;

  (int, int) key() {
    final k = varint();
    return (k >> 3, k & 7);
  }

  int varint() {
    var result = 0, shift = 0;
    while (true) {
      if (_i >= _b.length) throw const FormatException('Protobuf tronqué');
      final byte = _b[_i++];
      result |= (byte & 0x7f) << shift;
      if (byte < 0x80) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('Varint trop long');
    }
  }

  Uint8List bytes() {
    final n = varint();
    if (n < 0 || _i + n > _b.length) throw const FormatException('Protobuf tronqué');
    final out = Uint8List.sublistView(_b, _i, _i + n);
    _i += n;
    return out;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        _i += 8;
      case 2:
        bytes();
      case 5:
        _i += 4;
      default:
        throw FormatException('Type protobuf inconnu : $wire');
    }
    if (_i > _b.length) throw const FormatException('Protobuf tronqué');
  }
}
