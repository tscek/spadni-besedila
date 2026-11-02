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
/// Stran ima stalno širino in pisavo pesmi ([pisava], skupna vsem), zato so vrstice na vseh napravah enake.
/// Kratka pesem se pomanjša ali poveča tako, da je vsa na zaslonu; daljša se raztegne na širino zaslona
/// in se skrola (puščica spodaj pove, da besedila še ni konec). Ščip pogled le začasno poveča.
class BesediloZRisanjem extends StatefulWidget {
  const BesediloZRisanjem({
    super.key,
    required this.vsebina,
    this.pisava = osnovnaPisava,
    required this.pesem,
    required this.risbe,
    required this.risanje,
    required this.knjiznica,
    this.klicaji = const [],
    this.risbeSkupne,
    this.smeSkupno = false,
    this.posnetki,
  });

  /// Širina strani v enotah strani in privzeta pisava pesmi na njej.
  static const sirinaStrani = 600.0;
  static const osnovnaPisava = 22.0;

  /// Pod to velikostjo (v točkah zaslona) se kratka pesem ne pomanjša več, ampak se skrola.
  static const najmanjsaPisava = 14.0;

  /// Stran 0 v risbi pesmi je besedilo (PDF ima strani od 1 naprej).
  static const stran = 0;

  final String vsebina;

  /// Velikost pisave na strani (lastnost pesmi, enaka na vseh napravah).
  final double pisava;
  final String pesem;
  final Risbe risbe;
  final ValueNotifier<bool> risanje;
  final KnjiznicaMidi knjiznica;

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

  // Ščip: prsti na zaslonu, začetna razdalja in povečava (začasna, samo za ta ogled).
  final _prsti = <int, Offset>{};
  double? _zacetnaRazdalja;
  double _zacetnaPovecava = 1;
  Offset? _zadnjeSredisce;
  double _povecava = 1;

  /// Višina strani v enotah strani (izmeri se po izrisu) in merilo med risanjem (da stran ne skoči).
  double? _visina;
  double? _meriloRisanja;

  /// Besedilo se nadaljuje pod spodnjim robom zaslona.
  bool _seNadaljuje = false;

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
              if (_zAkordi(i) && !_prelomljena(telo.size.height, widget.pisava)) {
                r = Rect.fromLTRB(r.left, r.bottom - widget.pisava * 1.3, r.right, r.bottom);
              }
              r = r.inflate(2);
              return (i, Rect.fromLTRB(r.left / sirina, r.top / sirina, r.right / sirina, r.bottom / sirina));
            }(),
    ];
  }

  /// Vrstica z akordi, ki se je prelomila v več vrstic (oznaka takrat pokrije vse).
  static bool _prelomljena(double visina, double pisava) => visina > pisava * 1.3 * 2.6;

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
      _zacetnaPovecava = _povecava;
      _zadnjeSredisce = (t[0] + t[1]) / 2;
    }
  }

  void _premik(PointerMoveEvent e) {
    if (!_prsti.containsKey(e.pointer)) return;
    _prsti[e.pointer] = e.position;
    final d0 = _zacetnaRazdalja;
    if (_prsti.length != 2 || d0 == null || d0 < 20) return;
    final t = _prsti.values.toList();
    final nova = (_zacetnaPovecava * (t[0] - t[1]).distance / d0).clamp(0.5, 4.0);
    final sredisce = (t[0] + t[1]) / 2;
    // Med risanjem se stran ne premika s prstom, zato jo premikata dva prsta.
    if (risem && _zadnjeSredisce != null) {
      final premik = sredisce - _zadnjeSredisce!;
      for (final (c, d) in [(_navpicno, premik.dy), (_vodoravno, premik.dx)]) {
        if (c.hasClients) c.jumpTo((c.offset - d).clamp(0, c.position.maxScrollExtent));
      }
    }
    _zadnjeSredisce = sredisce;
    setState(() => _povecava = nova);
  }

  void _gor(PointerEvent e) {
    _prsti.remove(e.pointer);
    if (_prsti.length < 2) {
      _zacetnaRazdalja = null;
      _zadnjeSredisce = null;
      // Skoraj osnovna povečava se vrne na osnovno (cela pesem spet na zaslonu).
      if ((_povecava - 1).abs() < 0.08 && _povecava != 1) setState(() => _povecava = 1);
    }
  }

  /// Izmeri višino strani po izrisu; od nje je odvisno, ali gre cela pesem na zaslon.
  void _izmeri() {
    if (!mounted) return;
    final telo = _stranKljuc.currentContext?.findRenderObject() as RenderBox?;
    if (telo == null || !telo.hasSize) return;
    final v = telo.size.height;
    if (_visina == null || (v - _visina!).abs() > 1) setState(() => _visina = v);
  }

  bool _obSkrolu(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    _osveziNadaljevanje(n.metrics);
    return false;
  }

  void _osveziNadaljevanje(ScrollMetrics m) {
    final nadaljuje = m.maxScrollExtent - m.pixels > 24;
    if (nadaljuje != _seNadaljuje) setState(() => _seNadaljuje = nadaljuje);
  }

  void _naprej() {
    if (!_navpicno.hasClients) return;
    final p = _navpicno.position;
    _navpicno.animateTo(
      math.min(p.pixels + p.viewportDimension * 0.8, p.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    const enota = BesediloZRisanjem.sirinaStrani;
    final premikanje = risem ? const NeverScrollableScrollPhysics() : null;
    _vrstice = cp.razcleni(widget.vsebina);
    if (_kljuci.length != _vrstice.length) _kljuci = [for (final _ in _vrstice) GlobalKey()];
    final vrstice = BesediloPogled.vrstice(context, widget.vsebina, widget.pisava);
    // Oznake, vezane na vrstice, se narišejo pod svojo vrstico, kjerkoli je ta zdaj.
    final poVrsticah = <int, List<Oznaka>>{};
    for (final o in oznakeVrstic(BesediloZRisanjem.stran)) {
      if (_vrsticaOznake(o) case final i?) poVrsticah.putIfAbsent(i, () => []).add(o);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _izmeri();
      if (mounted && _navpicno.hasClients) _osveziNadaljevanje(_navpicno.position);
    });
    return Stack(
      children: [
        Listener(
          onPointerDown: _dol,
          onPointerMove: _premik,
          onPointerUp: _gor,
          onPointerCancel: _gor,
          child: LayoutBuilder(
            builder: (context, omejitve) {
              // Stran je široka kot zaslon; kratka pesem se pomanjša (ali na širokem zaslonu poveča) tako,
              // da je vsa vidna, razen če bi bila pisava premajhna za branje.
              final poSirini = omejitve.maxWidth / enota;
              var merilo = poSirini;
              var cela = false;
              final visina = _visina;
              if (visina != null && omejitve.maxHeight.isFinite) {
                final naZaslon = (omejitve.maxHeight - 8) / visina;
                if (naZaslon >= poSirini) {
                  cela = true;
                } else if (widget.pisava * naZaslon >= BesediloZRisanjem.najmanjsaPisava) {
                  merilo = naZaslon;
                  cela = true;
                }
              }
              if (risem) {
                merilo = _meriloRisanja ??= merilo;
              } else {
                _meriloRisanja = null;
              }
              merilo *= _povecava;
              final prikazano = math.max(enota * merilo, 1.0);
              return NotificationListener<ScrollNotification>(
                onNotification: _obSkrolu,
                child: SingleChildScrollView(
                  controller: _navpicno,
                  physics: premikanje,
                  padding: EdgeInsets.only(bottom: risem ? 160 : (cela && _povecava == 1 ? 0 : 88)),
                  child: SingleChildScrollView(
                    controller: _vodoravno,
                    scrollDirection: Axis.horizontal,
                    physics: premikanje,
                    child: SizedBox(
                      width: math.max(prikazano, omejitve.maxWidth),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: prikazano,
                          child: FittedBox(
                            fit: BoxFit.fitWidth,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: enota,
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
                                // Malo prostora pod besedilom za opombe.
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
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
                                                    painter: _OznakeVrstice(
                                                      oznake,
                                                      zAkordi: _zAkordi(i),
                                                      pisava: widget.pisava,
                                                    ),
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
                ),
              );
            },
          ),
        ),
        if (_seNadaljuje && !risem)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Center(child: PuscicaNaprej(onTap: _naprej)),
          ),
        ...kontrole(context),
      ],
    );
  }
}

/// Utripajoča puščica navzdol: besedila še ni konec. Dotik pomakne za en zaslon naprej.
class PuscicaNaprej extends StatefulWidget {
  const PuscicaNaprej({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<PuscicaNaprej> createState() => _PuscicaNaprejState();
}

class _PuscicaNaprejState extends State<PuscicaNaprej> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true, count: 6);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barve = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, 6 * Curves.easeInOut.transform(_anim.value)), child: child),
      child: Material(
        key: const ValueKey('puscica-naprej'),
        color: barve.primary.withValues(alpha: 0.85),
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.keyboard_double_arrow_down, color: barve.onPrimary, size: 30),
          ),
        ),
      ),
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
  _OznakeVrstice(this.oznake, {required this.zAkordi, required this.pisava});

  final List<Oznaka> oznake;
  final bool zAkordi;
  final double pisava;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final pas = zAkordi && !_BesediloZRisanjemState._prelomljena(size.height, pisava)
        ? Rect.fromLTRB(r.left, r.bottom - pisava * 1.3, r.right, r.bottom)
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
