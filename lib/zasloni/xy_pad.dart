import 'package:flutter/material.dart';

import '../midi/midi.dart';
import '../midi/ukazi.dart';
import '../midi/xy.dart';
import '../zvok_spila.dart';
import 'drsnik.dart';

/// Gumbi in pad: vodoravno pošilja CC osi X, navpično CC osi Y. Začne na sredini in ne pošlje nič,
/// dokler ga ne premakneš.
class XyPad extends StatefulWidget {
  const XyPad({super.key, required this.knjiznica});

  final KnjiznicaMidi knjiznica;

  @override
  State<XyPad> createState() => _XyPadState();
}

class _XyPadState extends State<XyPad> {
  Offset _v = const Offset(0.5, 0.5);
  bool _premaknjen = false;

  /// Izbrana skupina osi; zapomni se do zaprtja aplikacije.
  static int _skupina = 0;

  SkupinaXy? get _izbrana {
    final s = Midi.aplikacija.xy.skupine;
    return s.isEmpty ? null : s[_skupina.clamp(0, s.length - 1)];
  }

  late final _posiljalec = PosiljalecVrednosti(
    () {
      final s = _izbrana;
      final k = widget.knjiznica;
      if (s == null) return const <PoslaniUkaz>[];
      return [?ukazDrsnika(k, s.x, (_v.dx * 127).round()), ?ukazDrsnika(k, s.y, ((1 - _v.dy) * 127).round())];
    },
    widget.knjiznica,
    fx: true,
  );

  @override
  void dispose() {
    _posiljalec.dispose();
    super.dispose();
  }

  void _nastavi(Offset lokalno, double stranica) {
    setState(() {
      _v = Offset((lokalno.dx / stranica).clamp(0.0, 1.0), (lokalno.dy / stranica).clamp(0.0, 1.0));
      _premaknjen = true;
    });
    _posiljalec.premik();
  }

  @override
  Widget build(BuildContext context) {
    final n = Midi.aplikacija.xy;
    final tema = Theme.of(context);
    const stranica = 288.0;
    if (!n.nastavljen) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'XY pad še ni nastavljen. Administrator ga nastavi v Nastavitve MIDI (skupine osi X in Y ter gumbi).',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (n.gumbi.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  for (var i = 0; i < n.gumbi.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: FilledButton.tonal(
                        key: ValueKey('xy-gumb-$i'),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                        // Brez MIDI na tej napravi gre ukaz prek špila na napravo z efekti (PC).
                        onPressed: () => ZvokSpila.aplikacija.posljiMidiZapis(n.gumbi[i].ukazi, widget.knjiznica),
                        child: Text(n.gumbi[i].napis, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (_izbrana != null)
            GestureDetector(
              key: const ValueKey('xy-ploskev'),
              onPanDown: (d) => _nastavi(d.localPosition, stranica),
              onPanUpdate: (d) => _nastavi(d.localPosition, stranica),
              onPanEnd: (_) => _posiljalec.konec(),
              child: CustomPaint(
                size: const Size.square(stranica),
                painter: _XySlikar(_v, tema.colorScheme.primary, tema.colorScheme.surfaceContainerHighest),
              ),
            ),
          const SizedBox(height: 6),
          if (_izbrana case final s?)
            Text(
              _premaknjen
                  ? 'X ${(_v.dx * 127).round()} · Y ${((1 - _v.dy) * 127).round()}'
                  : [if (s.x.isNotEmpty) 'X: ${s.x}', if (s.y.isNotEmpty) 'Y: ${s.y}'].join(' · '),
              style: tema.textTheme.bodySmall,
            ),
          if (n.skupine.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i < n.skupine.length; i++)
                    ChoiceChip(
                      key: ValueKey('xy-skupina-$i'),
                      label: Text(n.skupine[i].ime),
                      selected: i == _skupina.clamp(0, n.skupine.length - 1),
                      // Nova skupina začne na sredini in ne pošlje nič, dokler pada ne premakneš.
                      onSelected: (_) => setState(() {
                        _skupina = i;
                        _v = const Offset(0.5, 0.5);
                        _premaknjen = false;
                      }),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _XySlikar extends CustomPainter {
  _XySlikar(this.v, this.barva, this.ozadje);

  final Offset v;
  final Color barva;
  final Color ozadje;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    canvas.drawRRect(r, Paint()..color = ozadje);
    final mreza = Paint()
      ..color = barva.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(size.width * i / 4, 0), Offset(size.width * i / 4, size.height), mreza);
      canvas.drawLine(Offset(0, size.height * i / 4), Offset(size.width, size.height * i / 4), mreza);
    }
    final p = Offset(v.dx * size.width, v.dy * size.height);
    final crta = Paint()
      ..color = barva.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(p.dx, 0), Offset(p.dx, size.height), crta);
    canvas.drawLine(Offset(0, p.dy), Offset(size.width, p.dy), crta);
    canvas.drawCircle(p, 16, Paint()..color = barva);
    canvas.drawCircle(p, 6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_XySlikar o) => o.v != v || o.barva != barva || o.ozadje != ozadje;
}
