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
    this.risbeSkupne,
    this.smeSkupno = false,
    this.posnetki,
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

  /// Skupne risbe pesmi (npr. pobarvani refreni) in ali jih član sme risati.
  final Risbe? risbeSkupne;
  final bool smeSkupno;

  /// Odpre posnetke pesmi (osebno ali skupno, kot je izbrano pri zapiskih).
  final void Function(bool skupno)? posnetki;

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
  Risbe? get risbeSkupne => widget.risbeSkupne;

  @override
  bool get smeSkupno => widget.smeSkupno;

  @override
  void Function(bool skupno)? get posnetki => widget.posnetki;

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

  /// Besedilo vrstice brez akordov (za iskanje vrstice oznake, ko se besedilo spremeni).
  static String _besedilo(cp.Vrstica v) => (v.komentar + v.kosi.map((k) => k.besedilo).join()).trim();

  /// Ali je vrstica z akordi nad besedilom (oznaka pokrije le besedilo, ne akordov).
  bool _zAkordi(int i) =>
      _vrstice[i].vrsta == cp.VrstaVrstice.besedilo && _vrstice[i].imaAkorde && Nastavitve.aplikacija.akordi;

  /// Izrisane neprazne vrstice: indeks vrstice in njen pravokotnik, relativno na širino strani.
  List<(int, Rect)> _izrisaneVrstice() {
    final strTelo = _stranKljuc.currentContext?.findRenderObject() as RenderBox?;
    if (strTelo == null) return const [];
    const sirina = BesediloZRisanjem.sirinaStrani;
    return [
      for (var i = 0; i < _kljuci.length && i < _vrstice.length; i++)
        if (_vrstice[i].vrsta != cp.VrstaVrstice.prazna)
          if (_kljuci[i].currentContext?.findRenderObject() case final RenderBox telo when telo.hasSize)
            () {
              final zgoraj = strTelo.globalToLocal(telo.localToGlobal(Offset.zero));
              var r = zgoraj & telo.size;
              if (_zAkordi(i) && !_prelomljena(telo.size.height)) {
                r = Rect.fromLTRB(r.left, r.bottom - BesediloZRisanjem.osnovnaPisava * 1.3, r.right, r.bottom);
              }
              r = r.inflate(2);
              return (i, Rect.fromLTRB(r.left / sirina, r.top / sirina, r.right / sirina, r.bottom / sirina));
            }(),
    ];
  }

  /// Vrstica z akordi, ki se je prelomila v več vrstic (oznaka takrat pokrije vse).
  static bool _prelomljena(double visina) => visina > BesediloZRisanjem.osnovnaPisava * 1.3 * 2.6;

  /// Vrstice besedila (pri vrstici z akordi samo besedilo, brez akordov), relativno na širino strani.
  @override
  List<Rect> vrsticeStrani(int stran) => [for (final (_, r) in _izrisaneVrstice()) r];

  @override
  List<int> indeksiVrstic(int stran) => [for (final (i, _) in _izrisaneVrstice()) i];

  @override
  String besediloVrstice(int indeks) => indeks < _vrstice.length ? _besedilo(_vrstice[indeks]) : '';

  /// Vrstica, na katero spada oznaka: ista, če se besedilo ujema, sicer najbližja z enakim besedilom.
  int? _vrsticaOznake(Oznaka o) {
    final v = o.vrstica;
    if (v == null) return null;
    if (v < _vrstice.length && (o.besedilo.isEmpty || _besedilo(_vrstice[v]) == o.besedilo)) return v;
    if (o.besedilo.isEmpty) return null;
    int? najblizja;
    for (var i = 0; i < _vrstice.length; i++) {
      if (_besedilo(_vrstice[i]) == o.besedilo && (najblizja == null || (i - v).abs() < (najblizja - v).abs())) {
        najblizja = i;
      }
    }
    return najblizja;
  }

  @override
  Rect? obmocjeOznake(int stran, Oznaka o) {
    if (o.vrstica == null) return o.obmocje;
    final k = _vrsticaOznake(o);
    for (final (i, r) in _izrisaneVrstice()) {
      if (i == k) return Rect.fromLTRB(r.left + o.od * r.width, r.top, r.left + o.doo * r.width, r.bottom);
    }
    return null;
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
    // Oznake, vezane na vrstice, se narišejo pod svojo vrstico, kjerkoli je ta zdaj.
    final poVrsticah = <int, List<Oznaka>>{};
    for (final o in oznakeVrstic(BesediloZRisanjem.stran)) {
      if (_vrsticaOznake(o) case final i?) poVrsticah.putIfAbsent(i, () => []).add(o);
    }
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
                                      KeyedSubtree(
                                        key: i < _kljuci.length ? _kljuci[i] : null,
                                        child: switch (poVrsticah[i]) {
                                          final oznake? => Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Positioned.fill(
                                                child: CustomPaint(
                                                  painter: _OznakeVrstice(oznake, zAkordi: _zAkordi(i)),
                                                ),
                                              ),
                                              vrstice[i],
                                            ],
                                          ),
                                          null => vrstice[i],
                                        },
                                      ),
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

/// Oznake ene vrstice besedila: delež širine vrstice, pri vrstici z akordi le pas besedila.
class _OznakeVrstice extends CustomPainter {
  _OznakeVrstice(this.oznake, {required this.zAkordi});

  final List<Oznaka> oznake;
  final bool zAkordi;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final pas = zAkordi && !_BesediloZRisanjemState._prelomljena(size.height)
        ? Rect.fromLTRB(r.left, r.bottom - BesediloZRisanjem.osnovnaPisava * 1.3, r.right, r.bottom)
        : r;
    final v = pas.inflate(2);
    for (final o in oznake) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(v.left + o.od * v.width, v.top, v.left + o.doo * v.width, v.bottom),
          const Radius.circular(3),
        ),
        Paint()..color = Color(o.barva).withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_OznakeVrstice old) => true;
}
