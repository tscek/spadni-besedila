import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../risbe.dart';

/// PDF z osebnim slojem risb in opomb. V načinu risanja je premikanje PDF-ja izklopljeno,
/// da poteze s prstom ali pisalom rišejo, namesto da bi drsele po strani.
class PdfZRisanjem extends StatefulWidget {
  const PdfZRisanjem({super.key, required this.pdf, required this.ime, required this.pesem, required this.risbe});

  final Uint8List pdf;

  /// Ime vira za pdfrx (Drive ID), da se dokument ob ponovnem izrisu ne naloži znova.
  final String ime;
  final String pesem;
  final Risbe risbe;

  @override
  State<PdfZRisanjem> createState() => _PdfZRisanjemState();
}

enum _Nacin { pisalo, marker, radirka, opomba }

const _barvePisala = [Color(0xFF000000), Color(0xFFD32F2F), Color(0xFF1565C0), Color(0xFF2E7D32)];
const _barvePisalaTemno = [Color(0xFFFFFFFF), Color(0xFFFF5252), Color(0xFF64B5F6), Color(0xFF81C784)];
const _barveMarkerja = [Color(0xFFFFEB3B), Color(0xFF76FF03), Color(0xFFFF4081), Color(0xFF40C4FF)];
const _debelinaPisala = 0.004;
const _debelinaMarkerja = 0.025;
const _polmerRadirke = 0.02;

class _PdfZRisanjemState extends State<PdfZRisanjem> with RisanjeNaStrani {
  @override
  Risbe get risbe => widget.risbe;

  @override
  String get pesem => widget.pesem;

  // Stran 0 je besedilo pesmi, PDF ima strani od 1 naprej.
  @override
  bool mojaStran(int stran) => stran > 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PdfViewer.data(
          widget.pdf,
          sourceName: widget.ime,
          params: PdfViewerParams(
            panEnabled: !risem,
            scaleEnabled: !risem,
            pageOverlaysBuilder: (context, rect, page) => [slojStrani(page.pageNumber, rect.size)],
          ),
        ),
        ...kontrole(context),
      ],
    );
  }
}

/// Obvestilo zaslonu okoli prikaza, da se je risanje vklopilo ali izklopilo (med risanjem ni gest).
class RisanjeObvestilo extends Notification {
  RisanjeObvestilo(this.risem);

  final bool risem;
}

/// Risanje in opombe na eni ali več straneh (PDF ali besedilo). Koordinate so relativne:
/// x glede na širino strani, y glede na [enotaY] (višino strani pri PDF-ju, širino pri besedilu).
mixin RisanjeNaStrani<T extends StatefulWidget> on State<T> {
  Risbe get risbe;
  String get pesem;

  /// Ali stran pripada temu prikazu (»Izbriši vse« briše samo te strani).
  bool mojaStran(int stran);

  /// Temno ozadje (besedilo): svetle barve pisala in marker brez množenja barv.
  bool get temnoOzadje => false;

  Risba _risba = Risba();
  bool risem = false;
  _Nacin _nacin = _Nacin.pisalo;
  late Color _barvaPisala = _pisala[1];
  Color _barvaMarkerja = _barveMarkerja[0];

  // Trenutna poteza (stran in točke), dokler prst ne gre z zaslona.
  int? _stranPoteze;
  Poteza? _poteza;
  final _zgodovina = <String>[];

  List<Color> get _pisala => temnoOzadje ? _barvePisalaTemno : _barvePisala;

  @override
  void initState() {
    super.initState();
    risbe.nalozi(pesem).then((r) {
      if (mounted) setState(() => _risba = r);
    });
  }

  void _zapomniZaRazveljavi() {
    _zgodovina.add(_risba.vBesedilo());
    if (_zgodovina.length > 50) _zgodovina.removeAt(0);
  }

  void _shrani() => risbe.shrani(pesem, _risba);

  void _razveljavi() {
    if (_zgodovina.isEmpty) return;
    setState(() => _risba = Risba.izBesedila(_zgodovina.removeLast()));
    _shrani();
  }

  Future<void> _izbrisiVse() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(opisIzbrisa),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Prekliči')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Izbriši')),
        ],
      ),
    );
    if (ok != true) return;
    _zapomniZaRazveljavi();
    setState(() {
      _risba.poteze.removeWhere((stran, _) => mojaStran(stran));
      _risba.opombe.removeWhere((stran, _) => mojaStran(stran));
    });
    _shrani();
  }

  // ---------- Dotiki na strani ----------

  void _zacetek(int stran, Offset p) {
    switch (_nacin) {
      case _Nacin.pisalo:
      case _Nacin.marker:
        _zapomniZaRazveljavi();
        final marker = _nacin == _Nacin.marker;
        setState(() {
          _stranPoteze = stran;
          _poteza = Poteza(
            orodje: marker ? Orodje.marker : Orodje.pisalo,
            barva: (marker ? _barvaMarkerja : _barvaPisala).toARGB32(),
            debelina: marker ? _debelinaMarkerja : _debelinaPisala,
            tocke: [p],
          );
          _risba.potezeStrani(stran).add(_poteza!);
        });
      case _Nacin.radirka:
        _zapomniZaRazveljavi();
        _radiraj(stran, p);
      case _Nacin.opomba:
        break; // opomba se doda ob koncu dotika (tap), glej _konec
    }
  }

  void _premik(int stran, Offset p) {
    if (_nacin == _Nacin.radirka) {
      _radiraj(stran, p);
    } else if (_poteza != null && _stranPoteze == stran) {
      setState(() => _poteza!.tocke.add(p));
    }
  }

  void _konec(int stran, Offset p) {
    if (_nacin == _Nacin.opomba) {
      _urediOpombo(stran, p);
      return;
    }
    final spremenjeno = _poteza != null || _nacin == _Nacin.radirka;
    _poteza = null;
    _stranPoteze = null;
    if (spremenjeno) _shrani();
  }

  void _radiraj(int stran, Offset p) {
    final poteze = _risba.potezeStrani(stran);
    final opombe = _risba.opombeStrani(stran);
    final pred = poteze.length + opombe.length;
    poteze.removeWhere((x) => x.blizu(p, _polmerRadirke));
    opombe.removeWhere((o) => (o.polozaj - p).distance < _polmerRadirke * 2);
    if (poteze.length + opombe.length != pred) setState(() {});
  }

  Future<void> _urediOpombo(int stran, Offset p) async {
    final opombe = _risba.opombeStrani(stran);
    // Tap blizu obstoječe opombe jo uredi, drugače doda novo.
    Opomba? obstojeca;
    for (final o in opombe) {
      if ((o.polozaj - p).distance < 0.04) obstojeca = o;
    }
    final kontroler = TextEditingController(text: obstojeca?.besedilo ?? '');
    final besedilo = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(obstojeca == null ? 'Nova opomba' : 'Uredi opombo'),
        content: TextField(controller: kontroler, autofocus: true, maxLines: 3, minLines: 1),
        actions: [
          if (obstojeca != null) TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Izbriši')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Prekliči')),
          FilledButton(onPressed: () => Navigator.pop(c, kontroler.text.trim()), child: const Text('Shrani')),
        ],
      ),
    );
    if (besedilo == null) return;
    _zapomniZaRazveljavi();
    setState(() {
      if (obstojeca != null) {
        if (besedilo.isEmpty) {
          opombe.remove(obstojeca);
        } else {
          obstojeca.besedilo = besedilo;
        }
      } else if (besedilo.isNotEmpty) {
        opombe.add(Opomba(polozaj: p, besedilo: besedilo, barva: _barvaPisala.toARGB32()));
      }
    });
    _shrani();
  }

  String get opisIzbrisa => 'Izbrišem vse risbe in opombe na tej pesmi?';

  // ---------- Prikaz ----------

  /// Sloj risb nad stranjo velikosti [velikost]; [enotaY] je dolžina, s katero se množi y (privzeto višina).
  Widget slojStrani(int stran, Size velikost, {double? enotaY}) {
    final enota = Size(velikost.width, enotaY ?? velikost.height);
    Offset rel(Offset l) => Offset(l.dx / enota.width, l.dy / enota.height);
    final risba = CustomPaint(
      size: velikost,
      painter: _RisbaSlikar(
        poteze: List.of(_risba.poteze[stran] ?? const []),
        opombe: List.of(_risba.opombe[stran] ?? const []),
        enota: enota,
        temnoOzadje: temnoOzadje,
      ),
    );
    if (!risem) return IgnorePointer(child: risba);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _zacetek(stran, rel(e.localPosition)),
      onPointerMove: (e) => _premik(stran, rel(e.localPosition)),
      onPointerUp: (e) => _konec(stran, rel(e.localPosition)),
      child: SizedBox.fromSize(size: velikost, child: risba),
    );
  }

  /// Orodjarna spodaj (med risanjem) in okrogel gumb za vklop risanja.
  List<Widget> kontrole(BuildContext context) => [
    if (risem) Positioned(left: 0, right: 0, bottom: 0, child: _orodjarna(context)),
    Positioned(
      right: 16,
      bottom: risem ? 88 : 16,
      child: FloatingActionButton(
        heroTag: null,
        tooltip: risem ? 'Končaj risanje' : 'Riši in piši opombe',
        onPressed: () {
          setState(() => risem = !risem);
          RisanjeObvestilo(risem).dispatch(context);
        },
        child: Icon(risem ? Icons.check : Icons.edit),
      ),
    ),
  ];

  Widget _orodjarna(BuildContext context) {
    final barve = _nacin == _Nacin.marker ? _barveMarkerja : _pisala;
    final izbrana = _nacin == _Nacin.marker ? _barvaMarkerja : _barvaPisala;
    Widget gumb(_Nacin n, IconData ikona, String opis) => IconButton(
      tooltip: opis,
      isSelected: _nacin == n,
      icon: Icon(ikona),
      onPressed: () => setState(() => _nacin = n),
    );
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              gumb(_Nacin.pisalo, Icons.edit, 'Pisalo'),
              gumb(_Nacin.marker, Icons.highlight, 'Marker'),
              gumb(_Nacin.radirka, Icons.auto_fix_normal, 'Radirka'),
              gumb(_Nacin.opomba, Icons.sticky_note_2_outlined, 'Opomba'),
              const SizedBox(width: 12),
              if (_nacin != _Nacin.radirka)
                for (final b in barve)
                  GestureDetector(
                    onTap: () => setState(() {
                      if (_nacin == _Nacin.marker) {
                        _barvaMarkerja = b;
                      } else {
                        _barvaPisala = b;
                      }
                    }),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: b,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: b == izbrana ? Theme.of(context).colorScheme.primary : Colors.grey,
                          width: b == izbrana ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              const SizedBox(width: 12),
              IconButton(tooltip: 'Razveljavi', icon: const Icon(Icons.undo), onPressed: _razveljavi),
              IconButton(tooltip: 'Izbriši vse', icon: const Icon(Icons.delete_outline), onPressed: _izbrisiVse),
            ],
          ),
        ),
      ),
    );
  }
}

class _RisbaSlikar extends CustomPainter {
  _RisbaSlikar({required this.poteze, required this.opombe, required this.enota, this.temnoOzadje = false});

  final List<Poteza> poteze;
  final List<Opomba> opombe;

  /// Velikost, s katero se pomnožijo relativne koordinate (x: širina, y: višina ali širina).
  final Size enota;
  final bool temnoOzadje;

  @override
  void paint(Canvas canvas, Size platno) {
    final size = enota;
    for (final p in poteze) {
      final marker = p.orodje == Orodje.marker;
      final barva = Color(p.barva);
      final copic = Paint()
        ..color = marker ? barva.withValues(alpha: 0.4) : barva
        ..strokeWidth = p.debelina * size.width
        ..style = PaintingStyle.stroke
        ..strokeCap = marker ? StrokeCap.square : StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = marker && !temnoOzadje ? BlendMode.multiply : BlendMode.srcOver;
      final tocke = [for (final t in p.tocke) Offset(t.dx * size.width, t.dy * size.height)];
      if (tocke.length == 1) {
        canvas.drawPoints(ui.PointMode.points, tocke, copic);
        continue;
      }
      // Gladka črta skozi sredine sosednjih točk.
      final pot = Path()..moveTo(tocke.first.dx, tocke.first.dy);
      for (var i = 1; i < tocke.length - 1; i++) {
        final sredina = (tocke[i] + tocke[i + 1]) / 2;
        pot.quadraticBezierTo(tocke[i].dx, tocke[i].dy, sredina.dx, sredina.dy);
      }
      pot.lineTo(tocke.last.dx, tocke.last.dy);
      canvas.drawPath(pot, copic);
    }

    for (final o in opombe) {
      final tp = TextPainter(
        text: TextSpan(
          text: o.besedilo,
          style: TextStyle(
            // Belo pisalo (besedilo na temnem ozadju) bi se na rumenem listku ne videlo.
            color: Color(o.barva).computeLuminance() > 0.8 ? Colors.black : Color(o.barva),
            fontSize: size.width * 0.028,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.5);
      final mesto = Offset(o.polozaj.dx * size.width, o.polozaj.dy * size.height);
      final ozadje = (mesto & tp.size).inflate(size.width * 0.006);
      canvas.drawRRect(
        RRect.fromRectAndRadius(ozadje, Radius.circular(size.width * 0.008)),
        Paint()..color = const Color(0xF2FFF8C4),
      );
      tp.paint(canvas, mesto);
    }
  }

  @override
  bool shouldRepaint(_RisbaSlikar old) => true;
}
