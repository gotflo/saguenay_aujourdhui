import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saguenay_core/saguenay_core.dart';

/// La fiche à ouvrir quand on arrive dans l'app par une notification, par le
/// widget ou par un raccourci de l'icône.
final launchTargetProvider = NotifierProvider<LaunchTarget, SignalKind?>(LaunchTarget.new);

class LaunchTarget extends Notifier<SignalKind?> {
  @override
  SignalKind? build() => null;

  void open(SignalKind? kind) {
    if (kind != null) state = kind;
  }

  void consumed() => state = null;
}

/// `detail:collection` (notification) ou `aujourdhui://detail/collection`
/// (widget, raccourci). Tout le reste est ignoré.
SignalKind? kindFromLaunch(String? raw) {
  if (raw == null) return null;
  String? name;
  if (raw.startsWith('detail:')) {
    name = raw.substring('detail:'.length);
  } else {
    final uri = Uri.tryParse(raw);
    if (uri != null &&
        uri.scheme == 'aujourdhui' &&
        uri.host == 'detail' &&
        uri.pathSegments.length == 1) {
      name = uri.pathSegments.single;
    }
  }
  return SignalKind.values.where((k) => k.name == name).firstOrNull;
}
