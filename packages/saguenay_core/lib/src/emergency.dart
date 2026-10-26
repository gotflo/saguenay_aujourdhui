class EmergencyRoom {
  const EmergencyRoom({
    required this.permit,
    required this.hospital,
    required this.occupied,
    required this.functional,
    required this.present,
    required this.waiting,
  });

  factory EmergencyRoom.fromJson(Map<String, Object?> json) => EmergencyRoom(
    permit: json['permit'] as String,
    hospital: json['hospital'] as String,
    occupied: json['occupied'] as int?,
    functional: json['functional'] as int?,
    present: json['present'] as int?,
    waiting: json['waiting'] as int?,
  );

  /// Numéro de permis de l'installation, stable d'un fichier à l'autre.
  final String permit;
  final String hospital;

  /// Civières occupées et civières fonctionnelles.
  final int? occupied;
  final int? functional;

  /// Personnes présentes à l'urgence et personnes en attente d'un médecin.
  final int? present;
  final int? waiting;

  int? get occupancyPercent {
    final o = occupied, f = functional;
    if (o == null || f == null || f == 0) return null;
    return (o * 100 / f).round();
  }

  Map<String, Object?> toJson() => {
    'permit': permit,
    'hospital': hospital,
    'occupied': occupied,
    'functional': functional,
    'present': present,
    'waiting': waiting,
  };
}

class EmergencySnapshot {
  const EmergencySnapshot({required this.takenAt, required this.rooms});

  factory EmergencySnapshot.fromJson(Map<String, Object?> json) => EmergencySnapshot(
    takenAt: DateTime.parse(json['takenAt'] as String),
    rooms: [
      for (final r in json['rooms'] as List)
        EmergencyRoom.fromJson((r as Map).cast<String, Object?>()),
    ],
  );

  final DateTime takenAt;
  final List<EmergencyRoom> rooms;

  /// Le fichier est publié chaque heure ; au-delà de trois heures, c'est qu'il
  /// y a un problème quelque part.
  bool isStaleAt(DateTime now) => now.difference(takenAt) > const Duration(hours: 3);

  Map<String, Object?> toJson() => {
    'takenAt': takenAt.toIso8601String(),
    'rooms': [for (final r in rooms) r.toJson()],
  };
}

/// Les trois urgences de Saguenay, par numéro de permis.
const saguenayEmergencyPermits = {
  '51218394': 'Chicoutimi',
  '51224541': 'Jonquière',
  '51221364': 'La Baie',
};
