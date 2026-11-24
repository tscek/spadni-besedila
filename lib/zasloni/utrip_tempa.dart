import 'package:flutter/material.dart';

/// Pika, ki utripa v tempu pesmi (BPM): ob vsaki dobi zasveti in počasi ugasne.
class UtripTempa extends StatefulWidget {
  const UtripTempa({super.key, required this.bpm, this.velikost = 12});

  final double bpm;
  final double velikost;

  @override
  State<UtripTempa> createState() => _UtripTempaState();
}

class _UtripTempaState extends State<UtripTempa> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _doba)..repeat();

  Duration get _doba => Duration(microseconds: (60e6 / widget.bpm.clamp(20, 300)).round());

  @override
  void didUpdateWidget(UtripTempa old) {
    super.didUpdateWidget(old);
    if (old.bpm != widget.bpm) {
      _c
        ..duration = _doba
        ..repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barva = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Hitro zasveti na začetku dobe, nato ugaša.
        final svetlost = (1 - _c.value * 1.6).clamp(0.15, 1.0);
        return Container(
          width: widget.velikost,
          height: widget.velikost,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: barva.withValues(alpha: svetlost),
          ),
        );
      },
    );
  }
}
