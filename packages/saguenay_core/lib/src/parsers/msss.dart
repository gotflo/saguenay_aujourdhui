import '../emergency.dart';

/// Lit le relevé horaire du ministère de la Santé
/// (`Releve_horaire_urgences_7jours_nbpers.csv`, licence CC BY 4.0).
///
/// Le fichier arrive en Latin-1 : décoder les octets avec `latin1` avant.
/// Quelques en-têtes traînent des tabulations, l'heure n'a pas de zéro
/// (« 2026-10-25T6:45 ») et certains champs valent « pas d'information
/// disponible ». Malgré son nom, il ne contient que la dernière heure.
EmergencySnapshot parseMsssHourly(
  String csv, {
  Map<String, String> only = saguenayEmergencyPermits,
}) {
  final lines = csv.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) throw const FormatException('Fichier vide');

  final header = _fields(lines.first).map((h) => h.trim()).toList();
  int column(String name) {
    final i = header.indexOf(name);
    if (i < 0) throw FormatException('Colonne absente : $name');
    return i;
  }

  final permit = column('No_permis_installation');
  final name = column('Nom_installation');
  final functional = column('Nombre_de_civieres_fonctionnelles');
  final occupied = column('Nombre_de_civieres_occupees');
  final present = column('Nombre_total_de_patients_presents_a_lurgence');
  final waiting = column('Nombre_total_de_patients_en_attente_de_PEC');
  final updated = column('Mise_a_jour');

  DateTime? takenAt;
  // Une ligne par installation : si le fichier en répète une, la plus récente gagne.
  final byPermit = <String, (DateTime?, EmergencyRoom)>{};
  for (final line in lines.skip(1)) {
    final f = _fields(line);
    if (f.length < header.length) continue;
    final p = f[permit].trim();
    if (only.isNotEmpty && !only.containsKey(p)) continue;
    final at = _timestamp(f[updated]);
    final previous = byPermit[p];
    if (previous != null && (at == null || (previous.$1 != null && !at.isAfter(previous.$1!)))) {
      continue;
    }
    if (at != null && (takenAt == null || at.isAfter(takenAt))) takenAt = at;
    byPermit[p] = (
      at,
      EmergencyRoom(
        permit: p,
        hospital: only[p] ?? f[name].trim(),
        occupied: int.tryParse(f[occupied].trim()),
        functional: int.tryParse(f[functional].trim()),
        present: int.tryParse(f[present].trim()),
        waiting: int.tryParse(f[waiting].trim()),
      ),
    );
  }
  final rooms = [for (final (_, room) in byPermit.values) room];

  // Un fichier sans nos urgences ou sans heure : mieux vaut garder le relevé
  // précédent que d'afficher un relevé vide.
  if (rooms.isEmpty || takenAt == null) throw const FormatException('Relevé incomplet');

  if (only.isNotEmpty) {
    final order = only.keys.toList();
    rooms.sort((a, b) => order.indexOf(a.permit).compareTo(order.indexOf(b.permit)));
  }
  return EmergencySnapshot(takenAt: takenAt, rooms: rooms);
}

DateTime? _timestamp(String raw) {
  final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})T(\d{1,2}):(\d{2})').firstMatch(raw);
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  return DateTime(g(1), g(2), g(3), g(4), g(5));
}

List<String> _fields(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(buf.toString());
  return out;
}
