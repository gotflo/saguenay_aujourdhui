import 'package:flutter/material.dart';
import 'package:saguenay_core/saguenay_core.dart';

import 'colors.dart';

extension SignalKindStyle on SignalKind {
  IconData get icon => switch (this) {
    SignalKind.water => Icons.water_drop_rounded,
    SignalKind.weather => Icons.cloud_rounded,
    SignalKind.power => Icons.bolt_rounded,
    SignalKind.roads => Icons.alt_route_rounded,
    SignalKind.parking => Icons.directions_car_filled_rounded,
    SignalKind.collection => Icons.delete_outline_rounded,
    SignalKind.bus => Icons.directions_bus_filled_rounded,
    SignalKind.roadwork => Icons.construction_rounded,
    SignalKind.emergency => Icons.local_hospital_rounded,
  };

  Color color(AppColors c) => switch (this) {
    SignalKind.water => c.aqua,
    SignalKind.weather => c.slate,
    SignalKind.power => c.pink,
    SignalKind.roads => c.stone,
    SignalKind.parking => c.orange,
    SignalKind.collection => c.green,
    SignalKind.bus => c.blue,
    SignalKind.roadwork => c.amber,
    SignalKind.emergency => c.violet,
  };
}
