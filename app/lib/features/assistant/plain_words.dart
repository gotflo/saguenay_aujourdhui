import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/colors.dart';
import 'remote_assistant.dart';

/// « En mots simples » : un texte officiel réécrit par l'assistant en ligne.
/// Ne s'affiche que si l'assistant en ligne est configuré.
class PlainWords extends ConsumerStatefulWidget {
  const PlainWords(this.source, {super.key});

  final String source;

  @override
  ConsumerState<PlainWords> createState() => _PlainWordsState();
}

class _PlainWordsState extends ConsumerState<PlainWords> {
  String? _answer;
  var _busy = false;
  var _failed = false;

  Future<void> _explain() async {
    setState(() => _busy = true);
    try {
      final answer = await ref.read(remoteAssistantProvider).explain(widget.source);
      if (mounted) setState(() => _answer = answer);
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(remoteAssistantProvider).available) return const SizedBox.shrink();
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final answer = _answer;
    if (answer == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : _explain,
          icon: const Icon(Icons.short_text_rounded, size: 18),
          label: Text(
            _busy
                ? 'Un instant…'
                : _failed
                ? 'Pas de réponse, réessayer'
                : 'En mots simples',
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(answer, style: text.bodyMedium?.copyWith(color: c.ink)),
          const SizedBox(height: 6),
          Text('Assistant en ligne', style: text.bodySmall),
        ],
      ),
    );
  }
}
