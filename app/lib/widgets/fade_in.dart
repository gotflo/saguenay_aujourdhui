import 'dart:async';

import 'package:flutter/material.dart';

/// Apparition douce, décalée selon [index] pour que les tuiles arrivent
/// les unes après les autres.
class FadeIn extends StatefulWidget {
  const FadeIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (widget.index == 0) {
      _controller.forward();
    } else {
      _delay = Timer(Duration(milliseconds: 40 * widget.index), _controller.forward);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}
