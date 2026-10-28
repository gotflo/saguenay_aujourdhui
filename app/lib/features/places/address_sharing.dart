import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/addresses.dart';
import '../../state/launch.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../widgets/sheet_parts.dart';
import 'place_picker.dart';

/// Les noms qu'on donne le plus souvent à une adresse.
const addressNames = ['Chez moi', 'Chez mes parents', 'Chalet', 'Travail'];

/// Donner un nom à une adresse gardée : « Chez maman » se lit mieux dans une
/// notification qu'un numéro civique.
Future<void> showRenameSheet(BuildContext context, ResolvedAddress a) =>
    showAppSheet<void>(context, (sheetContext) {
      return Consumer(
        builder: (context, ref, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader('Nommer cette adresse', subtitle: '${a.label}, ${a.sector}'),
            _NameForm(
              initial: a.name,
              action: 'Enregistrer',
              onDone: (name) async {
                await ref.read(savedAddressesProvider.notifier).rename(a.id, name);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
      );
    });

/// Partage l'adresse par texto, courriel ou messagerie. Le lien ajoute
/// l'adresse chez l'autre, sans compte. Le nom reste ici : « Chez moi » pour
/// soi n'est pas « Chez moi » pour l'autre.
Future<void> shareAddress(ResolvedAddress a) => SharePlus.instance.share(
  ShareParams(
    subject: a.label,
    text:
        'Pour suivre ${a.label} dans Saguenay Aujourd’hui (eau, pannes, collectes), '
        'ouvre ce lien sur ton téléphone : ${AddressLink.encode(a.named(null))}',
  ),
);

/// Montre l'adresse reçue par lien et demande avant de l'ajouter.
class SharedAddressListener extends ConsumerStatefulWidget {
  const SharedAddressListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SharedAddressListener> createState() => _SharedAddressListenerState();
}

class _SharedAddressListenerState extends ConsumerState<SharedAddressListener> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(incomingAddressProvider, (_, address) {
      if (address == null) return;
      WidgetsBinding.instance
        ..addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(incomingAddressProvider.notifier).consumed();
          unawaited(_confirm(address));
        })
        ..scheduleFrame();
    }, fireImmediately: true);
  }

  Future<void> _confirm(ResolvedAddress a) => showAppSheet<void>(context, (sheetContext) {
    final container = ProviderScope.containerOf(context, listen: false);
    final first = container.read(savedPlaceProvider) == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetHeader('Une adresse partagée', subtitle: '${a.label}, ${a.sector}'),
        Text(
          first
              ? 'Ce sera ton adresse. Tu peux lui donner un nom.'
              : 'Tu recevras ses avis sur l’eau et ses pannes de courant, sous le nom '
                    'que tu lui donnes. Ton adresse affichée ne change pas.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        _NameForm(
          initial: a.name,
          action: first ? 'Choisir cette adresse' : 'Ajouter',
          onDone: (name) async {
            final named = a.named(name);
            await container.read(savedAddressesProvider.notifier).add(named);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            if (first) await chooseAddress(container, named.id);
          },
          onCancel: () => Navigator.of(sheetContext).pop(),
        ),
      ],
    );
  });

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Un champ pour le nom, des propositions, et le bouton qui valide.
class _NameForm extends StatefulWidget {
  const _NameForm({
    required this.initial,
    required this.action,
    required this.onDone,
    this.onCancel,
  });

  final String? initial;
  final String action;
  final Future<void> Function(String? name) onDone;
  final VoidCallback? onCancel;

  @override
  State<_NameForm> createState() => _NameFormState();
}

class _NameFormState extends State<_NameForm> {
  late final _field = TextEditingController(text: widget.initial);
  var _saving = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    setState(() => _saving = true);
    try {
      await widget.onDone(_field.text);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _field,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _done(),
          decoration: InputDecoration(
            hintText: 'Par exemple : Chez maman',
            counterText: '',
            filled: true,
            fillColor: c.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in addressNames)
              ActionChip(label: Text(name), onPressed: () => setState(() => _field.text = name)),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton(onPressed: _saving ? null : _done, child: Text(widget.action)),
        if (widget.onCancel != null)
          TextButton(onPressed: widget.onCancel, child: const Text('Pas maintenant')),
      ],
    );
  }
}
