import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:saguenay_core/saguenay_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../theme/kind_style.dart';
import '../details/detail_sheet.dart';
import 'remote_assistant.dart';

class _Exchange {
  _Exchange(this.question);

  final String question;
  String? answer;
  SignalKind? kind;
  List<String> sources = const [];
  List<PressNote> press = const [];
  bool online = false;
}

const _pressQuestion = 'Les derniers communiqués de la Ville';
final _aboutPress = RegExp(r'communiqu|nouvelles? de la ville', caseSensitive: false);

/// « Demande à l'app » : des réponses tirées des données de l'adresse,
/// calculées sur le téléphone. L'assistant en ligne prend le relais pour ce
/// que l'app ne sait pas, s'il est activé.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _field = TextEditingController();
  final _scroll = ScrollController();
  final _exchanges = <_Exchange>[];
  var _busy = false;

  @override
  void dispose() {
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String raw) async {
    final question = raw.trim();
    final place = ref.read(placeProvider);
    if (question.isEmpty || place == null || _busy) return;
    _field.clear();
    final city = ref.read(cityProvider);
    final now = ref.read(nowProvider);
    final ex = _Exchange(question);
    final local = const LocalAssistant().answer(question, place, city, now);
    // Les questions d'avant, pour comprendre une suite comme « Et demain ? ».
    final history = [
      for (final e in _exchanges)
        if (e.answer case final answer?) {'question': e.question, 'reponse': answer},
    ];
    setState(() => _exchanges.add(ex));
    _toEnd();

    final remote = ref.read(remoteAssistantProvider);
    if (remote.available && _aboutPress.hasMatch(question)) {
      await _press(ex, remote);
    } else if (!local.understood && remote.available) {
      setState(() => _busy = true);
      try {
        ex
          ..answer = await remote.ask(
            question,
            assistantContext(place, city, now),
            history: history.length > 4 ? history.sublist(history.length - 4) : history,
          )
          ..online = true
          ..kind = local.kind;
      } on RemoteBusy {
        ex.answer = 'Beaucoup de questions en peu de temps. Réessaie dans quelques minutes.';
      } on Object {
        ex.answer = '${local.text}\n\nL’assistant en ligne ne répond pas pour l’instant.';
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      ex
        ..answer = local.text
        ..kind = local.kind
        ..sources = local.sources;
    }
    if (mounted) setState(() {});
    _toEnd();
  }

  Future<void> _press(_Exchange ex, RemoteAssistant remote) async {
    setState(() => _busy = true);
    try {
      final notes = (await remote.pressReleases()).take(3).toList();
      ex
        ..press = notes
        ..online = true
        ..answer = notes.isEmpty
            ? 'Aucun communiqué récent.'
            : 'Les derniers communiqués de la Ville, en mots simples :';
    } on Object {
      ex.answer = 'Je n’arrive pas à lire les communiqués pour l’instant.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo() async {
    final remote = ref.read(remoteAssistantProvider);
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (picked == null) return;
    final ex = _Exchange('Ça va où ? (photo)');
    setState(() {
      _exchanges.add(ex);
      _busy = true;
    });
    try {
      ex
        ..answer = await remote.sortPhoto(await picked.readAsBytes())
        ..online = true
        ..kind = SignalKind.collection;
    } on Object {
      ex.answer = 'Je n’ai pas pu analyser la photo. Décris l’objet en quelques mots.';
      ex.kind = null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final remote = ref.watch(remoteAssistantProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Demande à l’app')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  if (_exchanges.isEmpty) ...[
                    Text(
                      remote.available
                          ? 'Je réponds d’abord à partir des données de ton adresse, sur ton '
                                'téléphone. Pour le reste, l’assistant en ligne prend le relais : '
                                'il reçoit ton secteur, jamais ton adresse.'
                          : 'Je réponds à partir des données de ton adresse, sur ton téléphone. '
                                'Rien n’est envoyé.',
                      style: text.bodyMedium?.copyWith(color: c.ink2),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in LocalAssistant.suggestions)
                          ActionChip(label: Text(s), onPressed: () => _ask(s)),
                        if (remote.available)
                          ActionChip(
                            label: const Text(_pressQuestion),
                            onPressed: () => _ask(_pressQuestion),
                          ),
                      ],
                    ),
                  ],
                  for (final ex in _exchanges) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(top: 14, left: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: c.accentSoft,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(ex.question, style: text.bodyMedium?.copyWith(color: c.ink)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      margin: const EdgeInsets.only(right: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.glass,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.glassEdge),
                      ),
                      child: ex.answer == null
                          ? const LinearProgressIndicator()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ex.answer!, style: text.bodyMedium?.copyWith(color: c.ink)),
                                for (final note in ex.press) _PressItem(note),
                                if (ex.sources.isNotEmpty || ex.online) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    ex.online
                                        ? 'Assistant en ligne'
                                        : 'Source : ${ex.sources.join(', ')}',
                                    style: text.bodySmall,
                                  ),
                                ],
                                if (ex.kind case final kind?) ...[
                                  const SizedBox(height: 10),
                                  ActionChip(
                                    avatar: Icon(kind.icon, size: 16, color: kind.color(c)),
                                    label: const Text('Voir la fiche'),
                                    onPressed: () => showDetailSheet(context, kind),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  if (remote.available)
                    IconButton(
                      tooltip: 'Ça va où ? En photo',
                      onPressed: _busy ? null : _photo,
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _field,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _ask,
                      decoration: InputDecoration(
                        hintText: 'Pose ta question',
                        filled: true,
                        fillColor: c.glass,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Envoyer',
                    onPressed: _busy ? null : () => _ask(_field.text),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PressItem extends StatelessWidget {
  const _PressItem(this.note);

  final PressNote note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(capitalize(shortDate(note.date)), style: text.bodySmall),
          const SizedBox(height: 2),
          Text(note.title, style: text.titleSmall?.copyWith(color: c.ink)),
          if (note.summary case final summary?) ...[
            const SizedBox(height: 4),
            Text(summary, style: text.bodyMedium?.copyWith(color: c.ink2)),
          ],
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => launchUrl(note.url, mode: LaunchMode.externalApplication),
            child: const Text('Lire le communiqué'),
          ),
        ],
      ),
    );
  }
}
