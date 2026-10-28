import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saguenay_core/saguenay_core.dart';

import '../../notifications/notification_sync.dart';
import '../../state/addresses.dart';
import '../../state/launch.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../widgets/pressable.dart';
import '../../widgets/sheet_parts.dart';
import 'address_sharing.dart';

/// Ce qu'on dit de chaque adresse de démo.
const placeHints = {
  'racine': 'Chicoutimi · calendrier de collecte officiel',
  'saint-jean': 'Avis d’ébullition en cours dans la démo',
  'saint-pierre': 'Jonquière · travaux sur la rue',
};

Future<void> showPlacePicker(BuildContext context) => showAppSheet<void>(context, (sheetContext) {
  void done() => Navigator.of(sheetContext).pop();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SheetHeader(
        'Tes adresses',
        subtitle: 'Elles restent sur ce téléphone. On veille sur chacune : eau et pannes.',
      ),
      SavedAddressList(onChosen: done),
      const SectionLabel('Ajouter une adresse'),
      AddressSearch(onChosen: done),
      const SectionLabel('Adresses de démo'),
      PlaceList(onChosen: done),
    ],
  );
});

/// Choisit l'adresse, puis demande la permission des notifications : c'est
/// le moment où les rappels prennent leur sens.
Future<void> chooseAddress(ProviderContainer container, String id, {VoidCallback? onChosen}) async {
  // Lus avant d'attendre : à l'accueil, l'écran disparaît dès que l'adresse
  // est choisie, et le widget qui a lancé l'action avec lui.
  final notifications = container.read(notificationsProvider);
  await container.read(placeIdProvider.notifier).choose(id);
  onChosen?.call();
  if (await notifications.ensurePermission()) container.invalidate(alertSyncProvider);
}

/// Un champ, et des propositions de vraies adresses de Saguenay pendant qu'on tape.
class AddressSearch extends ConsumerStatefulWidget {
  const AddressSearch({super.key, this.onChosen, this.onCard = true});

  final VoidCallback? onChosen;
  final bool onCard;

  @override
  ConsumerState<AddressSearch> createState() => _AddressSearchState();
}

enum _SearchState { idle, loading, results, empty, offline }

class _AddressSearchState extends ConsumerState<AddressSearch> {
  final _field = TextEditingController();
  Timer? _debounce;
  var _state = _SearchState.idle;
  var _results = const <AddressSuggestion>[];
  String? _resolving;
  int _query = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    // Un lien d'adresse collé ici fait comme s'il avait été ouvert.
    final link = Uri.tryParse(text.trim());
    if (link != null && link.scheme == 'aujourdhui') {
      ref.read(incomingAddressProvider.notifier).receive(link);
      _field.clear();
      setState(() => _state = _SearchState.idle);
      return;
    }
    if (text.trim().length < 3) {
      setState(() => _state = _SearchState.idle);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(text));
  }

  Future<void> _search(String text) async {
    final query = ++_query;
    setState(() => _state = _SearchState.loading);
    try {
      final results = await ref.read(addressClientProvider).search(text);
      if (!mounted || query != _query) return;
      setState(() {
        _results = results.take(6).toList();
        _state = _results.isEmpty ? _SearchState.empty : _SearchState.results;
      });
    } on Object {
      if (!mounted || query != _query) return;
      setState(() => _state = _SearchState.offline);
    }
  }

  Future<void> _pick(AddressSuggestion s) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _resolving = s.label);
    try {
      final address = await container.read(addressClientProvider).resolve(s);
      if (address == null) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('La Ville ne connaît pas cette adresse. Essaie avec le numéro civique.'),
          ),
        );
        return;
      }
      await container.read(savedAddressesProvider.notifier).add(address);
      await chooseAddress(container, address.id, onChosen: widget.onChosen);
    } on Object {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Pas de réseau pour l’instant. Réessaie dans un moment.')),
      );
    } finally {
      if (mounted) setState(() => _resolving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final fill = widget.onCard ? c.bg : c.glass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _field,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'Par exemple : 201 rue Racine Est',
            prefixIcon: Icon(Icons.search_rounded, color: c.ink3),
            suffixIcon: _state == _SearchState.loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            filled: true,
            fillColor: fill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        switch (_state) {
          _SearchState.empty => _Hint('Aucune adresse trouvée à Saguenay.', style: text.bodySmall),
          _SearchState.offline => _Hint(
            'Pas de réseau : essaie une adresse de démo.',
            style: text.bodySmall,
          ),
          _SearchState.results => Column(
            children: [
              for (final s in _results)
                Pressable(
                  onTap: _resolving == null ? () => _pick(s) : null,
                  semanticLabel: s.label,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                    child: Row(
                      children: [
                        Icon(Icons.place_outlined, size: 20, color: c.ink3),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.label.split(',').first, style: text.labelLarge),
                              Text(
                                s.label.split(',').skip(1).join(',').trim(),
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (_resolving == s.label)
                          const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
    child: Text(text, style: style),
  );
}

/// Les vraies adresses ajoutées, avec de quoi passer de l'une à l'autre.
class SavedAddressList extends ConsumerWidget {
  const SavedAddressList({super.key, this.onChosen, this.onCard = true});

  final VoidCallback? onChosen;
  final bool onCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedAddressesProvider);
    final current = ref.watch(placeIdProvider);
    final c = context.colors;
    if (saved.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final a in saved)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PlaceOption(
              title: a.displayName,
              hint: a.name == null ? a.sector : a.label,
              selected: a.id == current,
              onCard: onCard,
              onTap: () => chooseAddress(
                ProviderScope.containerOf(context, listen: false),
                a.id,
                onChosen: onChosen,
              ),
              trailing: PopupMenuButton<_AddressAction>(
                tooltip: 'Nommer, partager ou retirer',
                icon: Icon(Icons.more_horiz_rounded, color: c.ink3),
                onSelected: (action) => switch (action) {
                  _AddressAction.rename => showRenameSheet(context, a),
                  _AddressAction.share => shareAddress(a),
                  _AddressAction.remove => ref.read(savedAddressesProvider.notifier).remove(a.id),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _AddressAction.rename, child: Text('Nommer')),
                  PopupMenuItem(value: _AddressAction.share, child: Text('Partager')),
                  PopupMenuItem(value: _AddressAction.remove, child: Text('Retirer')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

enum _AddressAction { rename, share, remove }

/// Les trois adresses de démo.
class PlaceList extends ConsumerWidget {
  const PlaceList({super.key, this.onChosen, this.onCard = true});

  final VoidCallback? onChosen;

  /// Vrai dans une feuille (fond carte), faux sur le fond de l'app.
  final bool onCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(placesProvider);
    final current = ref.watch(placeIdProvider);
    return Column(
      children: [
        for (final p in places)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PlaceOption(
              title: p.label,
              hint: placeHints[p.id] ?? '',
              selected: p.id == current,
              onCard: onCard,
              onTap: () => chooseAddress(
                ProviderScope.containerOf(context, listen: false),
                p.id,
                onChosen: onChosen,
              ),
            ),
          ),
      ],
    );
  }
}

class PlaceOption extends StatelessWidget {
  const PlaceOption({
    super.key,
    required this.title,
    required this.hint,
    required this.onTap,
    this.selected = false,
    this.onCard = true,
    this.trailing,
  });

  final String title;
  final String hint;
  final VoidCallback onTap;
  final bool selected;
  final bool onCard;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : (onCard ? c.bg : c.glass),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? c.accent : (onCard ? Colors.transparent : c.glassEdge),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
              child: Icon(Icons.place_rounded, size: 20, color: c.ink),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall),
                  if (hint.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(hint, style: text.bodySmall),
                  ],
                ],
              ),
            ),
            trailing ??
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                  color: selected ? c.ink : c.ink3,
                ),
          ],
        ),
      ),
    );
  }
}
