import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../chordpro.dart' as cp;
import '../midi/ukazi.dart';
import '../models.dart' show KlicajPesmi;
import '../nastavitve.dart' show Nastavitve;
import '../risbe.dart';
import 'pdf_risanje.dart';
import 'pesem_zaslon.dart';

/// Besedilo kot stran z risbami, oznakami in opombami (enako kot pri PDF-ju). Risbe besedila so v isti
/// risbi pesmi kot stran 0, koordinate so v enotah strani širine [sirinaStrani].
/// Brez preloma ([prelom] false) se vrstice vedno prelomijo enako in večja pisava stran le poveča
/// (premikanje tudi vstran). S prelomom je stran vedno široka kot zaslon in se ob večji pisavi
/// prelomi v več vrstic; risbe ostanejo na istem mestu strani, zato se lahko zamaknejo glede na besedilo.
/// Z dvema prstoma (ščip) se besedilo poveča ali pomanjša, tudi med risanjem.
class BesediloZRisanjem extends StatefulWidget {
  const BesediloZRisanjem({
    super.key,
    required this.vsebina,
    required this.povecava,
    required this.pesem,
    required this.risbe,
    required this.risanje,
    required this.knjiznica,
    this.obPovecavi,
    this.prelom = false,
    this.klicaji = const [],
  });

  /// Širina strani v logičnih točkah in pisava, pri kateri je povečava 1.
  static const sirinaStrani = 600.0;
  static const osnovnaPisava = 22.0;

  /// Stran 0 v risbi pesmi je besedilo (PDF ima strani od 1 naprej).
  static const stran = 0;

  final String vsebina;
  final double povecava;
  final String pesem;
  final Risbe risbe;
  final ValueNotifier<bool> risanje;
  final KnjiznicaMidi knjiznica;

  /// Konec ščipa: nova povečava (shrani se kot velikost pisave).
  final ValueChanged<double>? obPovecavi;

  /// Vrstice se prelomijo na širino zaslona.
  final bool prelom;

  /// Klicaji pesmi (na besedilu so tisti s stranjo 0).
  final List<KlicajPesmi> klicaji;

  @override
  State<BesediloZRisanjem> createState() => _BesediloZRisanjemState();
}

class _BesediloZRisanjemState extends State<BesediloZRisanjem> with RisanjeNaStrani {
  final _navpicno = ScrollController();
  final _vodoravno = ScrollController();
  final _stranKljuc = GlobalKey();
  List<GlobalKey> _kljuci = [];
  List<cp.Vrstica> _vrstice = [];

  // Ščip: prsti na zaslonu, začetna razdalja in povečava.
  final _prsti = <int, Offset>{};
  double? _zacetnaRazdalja;
  double _zacetnaPovecava = 1;
  Offset? _zadnjeSredisce;
  double? _zacasna;

  @override
  Risbe get risbe => widget.risbe;

  @override
  String get pesem => widget.pesem;

  @override
  ValueNotifier<bool> get risanje => widget.risanje;

  @override
  KnjiznicaMidi get knjiznica => widget.knjiznica;

  @override
  List<KlicajPesmi> get klicaji => widget.klicaji;

  @override
  bool mojaStran(int stran) => stran == BesediloZRisanjem.stran;

  @override
  bool get temnoOzadje => Theme.of(context).brightness == Brightness.dark;

  @override
  bool get lahkoOznacuje => true;

  @override
  String get opisIzbrisa => 'Izbrišem vse risbe, oznake, opombe in gumbe na besedilu?';

  @override
  void dispose() {
    _navpicno.dispose();
    _vodoravno.dispose();
    super.dispose();
  }

  /// Vrstice besedila (pri vrstici z akordi samo besedilo, brez akordov), relativno na širino strani.
  @override
  List<Rect> vrsticeStrani(int stran) {
    final strTelo = _stranKljuc.currentContext?.findRenderObject() as RenderBox?;
    if (strTelo == null) return const [];
    const sirina = BesediloZRisanjem.sirinaStrani;
    return [
      for (var i = 0; i < _kljuci.length && i < _vrstice.length; i++)
        if (_vrstice[i].vrsta != cp.VrstaVrstice.prazna)
          if (_kljuci[i].currentContext?.findRenderObject() case final RenderBox telo when telo.hasSize)
            () {
              final v = _vrstice[i];
              final zgoraj = strTelo.globalToLocal(telo.localToGlobal(Offset.zero));
              var r = zgoraj & telo.size;
              if (v.vrsta == cp.VrstaVrstice.besedilo && v.imaAkorde && Nastavitve.aplikacija.akordi) {
                r = Rect.fromLTRB(r.left, r.bottom - BesediloZRisanjem.osnovnaPisava * 1.3, r.right, r.bottom);
              }
              r = r.inflate(2);
              return Rect.fromLTRB(r.left / sirina, r.top / sirina, r.right / sirina, r.bottom / sirina);
            }(),
    ];
  }

  void _dol(PointerDownEvent e) {
    _prsti[e.pointer] = e.position;
    if (_prsti.length == 2) {
      final t = _prsti.values.toList();
      _zacetnaRazdalja = (t[0] - t[1]).distance;
      _zacetnaPovecava = widget.povecava;
      _zadnjeSredisce = (t[0] + t[1]) / 2;
    }
  }

  void _premik(PointerMoveEvent e) {
    if (!_prsti.containsKey(e.pointer)) return;
    _prsti[e.pointer] = e.position;
    final d0 = _zacetnaRazdalja;
    if (_prsti.length != 2 || d0 == null || d0 < 20) return;
    final t = _prsti.values.toList();
    final nova = (_zacetnaPovecava * (t[0] - t[1]).distance / d0).clamp(12 / 22, 64 / 22);
    final sredisce = (t[0] + t[1]) / 2;
    // Med risanjem se stran ne premika s prstom, zato jo premikata dva prsta.
    if (risem && _zadnjeSredisce != null) {
      final premik = sredisce - _zadnjeSredisce!;
      for (final (c, d) in [(_navpicno, premik.dy), (_vodoravno, premik.dx)]) {
        if (c.hasClients) c.jumpTo((c.offset - d).clamp(0, c.position.maxScrollExtent));
      }
    }
    _zadnjeSredisce = sredisce;
    setState(() => _zacasna = nova);
  }

  void _gor(PointerEvent e) {
    _prsti.remove(e.pointer);
    if (_prsti.length < 2) {
      final z = _zacasna;
      _zacetnaRazdalja = null;
      _zadnjeSredisce = null;
      if (z != null) {
        _zacasna = null;
        widget.obPovecavi?.call(z);
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const enota = BesediloZRisanjem.sirinaStrani;
    final premikanje = risem ? const NeverScrollableScrollPhysics() : null;
    final povecava = _zacasna ?? widget.povecava;
    // S prelomom je stran ožja (v enotah strani), prikazana pa čez cel zaslon: pisava je enako velika.
    final sirina = widget.prelom ? math.max(enota / povecava, 150.0) : enota;
    _vrstice = cp.razcleni(widget.vsebina);
    if (_kljuci.length != _vrstice.length) _kljuci = [for (final _ in _vrstice) GlobalKey()];
    final vrstice = BesediloPogled.vrstice(context, widget.vsebina, BesediloZRisanjem.osnovnaPisava);
    return Stack(
      children: [
        Listener(
          onPointerDown: _dol,
          onPointerMove: _premik,
          onPointerUp: _gor,
          onPointerCancel: _gor,
          child: LayoutBuilder(
            builder: (context, omejitve) {
              // Pri povečavi 1 je stran široka kot zaslon; večja pisava jo poveča (premikanje tudi vstran),
              // s prelomom pa ostane široka kot zaslon.
              final prikazano = math.max(omejitve.maxWidth * (widget.prelom ? 1 : povecava), 1.0);
              return SingleChildScrollView(
                controller: _navpicno,
                physics: premikanje,
                padding: EdgeInsets.only(bottom: risem ? 160 : 88),
                child: SingleChildScrollView(
                  controller: _vodoravno,
                  scrollDirection: Axis.horizontal,
                  physics: premikanje,
                  child: SizedBox(
                    width: math.max(prikazano, omejitve.maxWidth),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: prikazano,
                        child: FittedBox(
                          fit: BoxFit.fitWidth,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: sirina,
                            child: _Stran(
                              kljuc: _stranKljuc,
                              podlaga: (velikost) =>
                                  podlagaStrani(BesediloZRisanjem.stran, velikost, enotaX: enota, enotaY: enota),
                              sloj: (velikost) => slojStrani(
                                BesediloZRisanjem.stran,
                                velikost,
                                enotaX: enota,
                                enotaY: enota,
                                zOznakami: false,
                              ),
                              // Prostor pod kratkim besedilom za opombe.
                              child: Container(
                                constraints: const BoxConstraints(minHeight: enota),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var i = 0; i < vrstice.length; i++)
                                      KeyedSubtree(key: i < _kljuci.length ? _kljuci[i] : null, child: vrstice[i]),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        ...kontrole(context),
      ],
    );
  }
}

/// Besedilo z oznakami pod njim in slojem risb čez celo stran (velikost slojev = velikost besedila).
class _Stran extends StatelessWidget {
  const _Stran({required this.kljuc, required this.podlaga, required this.sloj, required this.child});

  final Key kljuc;
  final Widget Function(Size velikost) podlaga;
  final Widget Function(Size velikost) sloj;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: kljuc,
      children: [
        Positioned.fill(child: LayoutBuilder(builder: (context, o) => podlaga(Size(o.maxWidth, o.maxHeight)))),
        child,
        Positioned.fill(child: LayoutBuilder(builder: (context, o) => sloj(Size(o.maxWidth, o.maxHeight)))),
      ],
    );
  }
}
