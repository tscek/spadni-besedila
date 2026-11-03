import 'dart:async';

import 'package:flutter/material.dart';

import '../midi/midi.dart';
import '../midi/ukazi.dart';
import '../risbe.dart';

/// CC ukaz drsnika z dano vrednostjo: prvi CC iz zapisa (ime ukaza iz knjižnice, npr. »Nivo glasbe«,
/// ali neposredno »CC 1 7«). Null, če v zapisu ni CC ukaza.
PoslaniUkaz? ukazDrsnika(KnjiznicaMidi k, String zapis, int vrednost) {
  for (final u in k.razsiri(zapis)) {
    if (u.ukaz.vrsta != VrstaUkaza.cc) continue;
    final c = u.ukaz;
    return PoslaniUkaz(
      MidiUkaz(
        ime: c.ime,
        vrsta: VrstaUkaza.cc,
        kanal: c.kanal,
        stevilka: c.stevilka,
        vrednost: vrednost.clamp(0, 127),
        izhod: c.izhod,
      ),
      u.izhod,
    );
  }
  return null;
}

/// Drsnik (fader) na besedilu ali PDF-ju. Začne na sredini in ne pošlje ničesar, dokler ga ne premakneš;
/// med vlečenjem pošilja CC približno 30-krat na sekundo, ob spustu še končno vrednost.
class DrsnikVOpombah extends StatefulWidget {
  const DrsnikVOpombah({super.key, required this.gumb, required this.velikost, required this.knjiznica});

  final GumbNaStrani gumb;

  /// Velikost pisave (kot pri gumbu); drsnik je dolg 10 in debel 2,4 te enote.
  final double velikost;
  final KnjiznicaMidi knjiznica;

  /// Prsti, ki trenutno vlečejo drsnik: zaslon pesmi zanje ne vklopi risanja in ne šteje dotikov.
  static final kazalci = <int>{};

  @override
  State<DrsnikVOpombah> createState() => _DrsnikVOpombahState();
}

class _DrsnikVOpombahState extends State<DrsnikVOpombah> {
  double _v = 0.5;
  bool _premaknjen = false;
  DateTime _zadnje = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _odlozeno;

  bool get _pokoncen => widget.gumb.oblika == OblikaGumba.drsnikPokoncen;
  int get _vrednost => (_v * 127).round();

  @override
  void dispose() {
    _odlozeno?.cancel();
    super.dispose();
  }

  void _nastavi(Offset lokalno, Size velikost) {
    final v = _pokoncen ? 1 - lokalno.dy / velikost.height : lokalno.dx / velikost.width;
    setState(() {
      _v = v.clamp(0.0, 1.0);
      _premaknjen = true;
    });
    final midi = Midi.aplikacija;
    // Prek vodje (iPad) redkeje, da omrežje ne zaostaja.
    final razmik = Duration(milliseconds: midi.prekoVodje != null ? 100 : 33);
    final zdaj = DateTime.now();
    if (zdaj.difference(_zadnje) >= razmik) {
      _poslji();
    } else {
      _odlozeno ??= Timer(razmik - zdaj.difference(_zadnje), _poslji);
    }
  }

  void _poslji({bool koncno = false}) {
    _odlozeno?.cancel();
    _odlozeno = null;
    _zadnje = DateTime.now();
    final midi = Midi.aplikacija;
    if (!midi.vklopljen) return;
    final u = ukazDrsnika(widget.knjiznica, widget.gumb.midi, _vrednost);
    if (u == null) return;
    if (koncno || midi.prekoVodje != null) {
      midi.poslji([u], knjiznica: widget.knjiznica);
    } else {
      midi.posljiSurovo(u.ukaz.bajti, u.izhod);
      midi.aktivnostIzhoda.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dolzina = widget.velikost * 10;
    final debelina = widget.velikost * 2.4;
    final size = _pokoncen ? Size(debelina, dolzina) : Size(dolzina, debelina);
    final barva = Color(widget.gumb.barva);
    return Listener(
      onPointerDown: (e) => DrsnikVOpombah.kazalci.add(e.pointer),
      // Zaslon pesmi dobi isti dogodek za drsnikom, zato prst odstranimo malo kasneje.
      onPointerUp: (e) => scheduleMicrotask(() => DrsnikVOpombah.kazalci.remove(e.pointer)),
      onPointerCancel: (e) => scheduleMicrotask(() => DrsnikVOpombah.kazalci.remove(e.pointer)),
      child: GestureDetector(
        key: ValueKey('drsnik-${widget.gumb.napis}'),
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) => _nastavi(d.localPosition, size),
        onPanUpdate: (d) => _nastavi(d.localPosition, size),
        onPanEnd: (_) => _poslji(koncno: true),
        child: CustomPaint(
          size: size,
          painter: _DrsnikSlikar(
            vrednost: _v,
            barva: barva,
            pokoncen: _pokoncen,
            napis: widget.gumb.napis,
            stevilka: _premaknjen ? '$_vrednost' : '',
            pisava: widget.velikost,
          ),
        ),
      ),
    );
  }
}

class _DrsnikSlikar extends CustomPainter {
  _DrsnikSlikar({
    required this.vrednost,
    required this.barva,
    required this.pokoncen,
    required this.napis,
    required this.stevilka,
    required this.pisava,
  });

  final double vrednost;
  final Color barva;
  final bool pokoncen;
  final String napis;
  final String stevilka;
  final double pisava;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(pisava * 0.6));
    canvas.drawRRect(r, Paint()..color = barva.withValues(alpha: 0.3));
    canvas.save();
    canvas.clipRRect(r);
    final polno = pokoncen
        ? Rect.fromLTRB(0, size.height * (1 - vrednost), size.width, size.height)
        : Rect.fromLTRB(0, 0, size.width * vrednost, size.height);
    canvas.drawRect(polno, Paint()..color = barva.withValues(alpha: 0.85));
    canvas.restore();
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = barva,
    );
    // Ročica.
    final rocica = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    if (pokoncen) {
      final y = size.height * (1 - vrednost);
      canvas.drawLine(Offset(3, y), Offset(size.width - 3, y), rocica);
    } else {
      final x = size.width * vrednost;
      canvas.drawLine(Offset(x, 3), Offset(x, size.height - 3), rocica);
    }
    final besedilo = TextPainter(
      text: TextSpan(
        text: stevilka.isEmpty ? napis : '$napis  $stevilka',
        style: TextStyle(
          fontSize: pisava * 0.9,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          shadows: const [Shadow(blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: pokoncen ? size.height - 8 : size.width - 8);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    if (pokoncen) canvas.rotate(-1.5707963267948966);
    besedilo.paint(canvas, Offset(-besedilo.width / 2, -besedilo.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DrsnikSlikar o) =>
      o.vrednost != vrednost || o.barva != barva || o.napis != napis || o.stevilka != stevilka || o.pisava != pisava;
}
