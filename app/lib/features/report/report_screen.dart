import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/providers.dart';
import '../../theme/colors.dart';

/// Le formulaire public de la Ville pour les requêtes et plaintes.
final requestPortal = Uri.parse('https://requete-web.saguenay.ca/');

const _categories = {
  'Nid-de-poule': 'Il y a un nid-de-poule',
  'Lampadaire': 'Un lampadaire ne fonctionne pas',
  'Déneigement': 'Le déneigement pose problème',
  'Collecte manquée': 'Le bac n’a pas été ramassé',
  'Signalisation': 'Un panneau ou un feu pose problème',
  'Autre': 'J’aimerais signaler un problème',
};

/// Prépare une requête claire pour la Ville : le problème, l'endroit, les
/// détails. L'app ne l'envoie pas : on copie le texte et on le colle dans le
/// formulaire officiel.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  var _category = _categories.keys.first;
  late final _where = TextEditingController(text: ref.read(placeProvider)?.label ?? '');
  final _details = TextEditingController();

  @override
  void dispose() {
    _where.dispose();
    _details.dispose();
    super.dispose();
  }

  String get _message {
    final details = _details.text.trim();
    return [
      '${_categories[_category]}.',
      if (_where.text.trim().isNotEmpty) 'Endroit : ${_where.text.trim()}.',
      if (details.isNotEmpty) details,
    ].join('\n');
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _message));
    messenger.showSnackBar(
      const SnackBar(content: Text('Texte copié. Colle-le dans le formulaire de la Ville.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    InputDecoration field(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: c.glass,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Signaler à la Ville')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text('Quel problème ?', style: text.labelLarge),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in _categories.keys)
                ChoiceChip(
                  label: Text(k),
                  selected: _category == k,
                  onSelected: (_) => setState(() => _category = k),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _where,
            decoration: field('Où ?'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _details,
            minLines: 3,
            maxLines: 6,
            decoration: field('Quelques détails (facultatif)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Text('Ton message', style: text.labelLarge),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.glass,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.glassEdge),
            ),
            child: SelectableText(_message, style: text.bodyMedium?.copyWith(color: c.ink)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _copy,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copier le texte'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => launchUrl(requestPortal, mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Ouvrir le formulaire de la Ville'),
          ),
          const SizedBox(height: 16),
          Text(
            'L’app n’envoie rien à ta place : tu gardes la main sur ce que tu transmets. '
            'Urgence : 911.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
