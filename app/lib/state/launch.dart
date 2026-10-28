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

/// Une adresse reçue par lien (`aujourdhui://adresse?...`) : un proche l'a
/// partagée. Rien n'est ajouté sans qu'on le confirme.
final incomingAddressProvider = NotifierProvider<IncomingAddress, ResolvedAddress?>(
  IncomingAddress.new,
);

class IncomingAddress extends Notifier<ResolvedAddress?> {
  @override
  ResolvedAddress? build() => null;

  /// Un lien qui n'est pas une adresse valide de Saguenay est ignoré.
  void receive(Uri? uri) {
    final a = uri == null ? null : AddressLink.decode(uri);
    if (a != null) state = a;
  }

  void consumed() => state = null;
}

/// Les liens qui ouvrent l'app. Remplacé dans `main()` ; vide dans les tests.
final appLinksProvider = Provider<Stream<Uri>>((ref) => const Stream.empty());

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
