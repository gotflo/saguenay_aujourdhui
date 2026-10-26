// Affiche l'état actuel des urgences de Saguenay, lu sur le site du ministère.
//
//   dart run example/urgences.dart

import 'package:saguenay_core/saguenay_core.dart';

Future<void> main() async {
  final client = MsssClient();
  try {
    final snapshot = await client.fetch();
    print('Relevé du ${longDate(snapshot.takenAt)} à ${clockTimeOf(snapshot.takenAt)}');
    for (final room in snapshot.rooms) {
      final pct = room.occupancyPercent;
      print(
        '  ${room.hospital.padRight(11)} '
        '${room.occupied ?? '?'}/${room.functional ?? '?'} civières'
        '${pct == null ? '' : ' ($pct %)'}, '
        '${room.waiting ?? '?'} en attente',
      );
    }
  } finally {
    client.close();
  }
}
