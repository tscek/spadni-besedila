import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../midi/midi.dart';
import '../midi/ukazi.dart';
import '../models.dart' show KlicajPesmi;
import '../nastavitve.dart' show Nastavitve;
import '../risbe.dart';
import 'midi_zaslon.dart';
import 'oznake.dart';

/// PDF z osebnim slojem risb, opomb in gumbov. Med risanjem je premikanje s prstom izklopljeno,
/// z dvema prstoma pa se PDF še vedno poveča ali pomanjša. Privzeto je vidna cela stran;
/// povečava, ki jo nastaviš, se za to pesem shrani na napravi.
class PdfZRisanjem extends StatefulWidget {
  const PdfZRisanjem({
    super.key,
    required this.pdf,
    required this.ime,
    required this.pesem,
    required this.risbe,
    required this.risanje,
    required this.knjiznica,
    this.klicaji = const [],
  });

  final Uint8List pdf;

  /// Ime vira za pdfrx (Drive ID), da se dokument ob ponovnem izrisu ne naloži znova.
  final String ime;
  final String pesem;
  final Risbe risbe;

  /// Ali je vklopljeno risanje (vklopi ga pridržanje na pesmi).
  final ValueNotifier<bool> risanje;
  final KnjiznicaMidi knjiznica;

  /// Klicaji pesmi (na straneh PDF-ja so tisti s stranjo 1 in več).
  final List<KlicajPesmi> klicaji;

  @override
  State<PdfZRisanjem> createState() => _PdfZRisanjemState();
}

enum _Nacin { pisalo, marker, oznacevalec, radirka, opomba, gumb }

const _barvePisala = [Color(0xFF000000), Color(0xFFD32F2F), Color(0xFF1565C0), Color(0xFF2E7D32)];
const _barvePisalaTemno = [Color(0xFFFFFFFF), Color(0xFFFF5252), Color(0xFF64B5F6), Color(0xFF81C784)];
const _barveMarkerja = [Color(0xFFFFEB3B), Color(0xFF76FF03), Color(0xFFFF4081), Color(0xFF40C4FF)];

/// Barve gumbov v opombah.
const barveGumbov = [
  Color(0xFFD32F2F),
  Color(0xFFF57C00),
  Color(0xFFFBC02D),
  Color(0xFF388E3C),
  Color(0xFF1976D2),
  Color(0xFF7B1FA2),
  Color(0xFF455A64),
];
const _debelinaPisala = 0.004;
const _debelinaMarkerja = 0.025;
const _polmerRadirke = 0.02;

class _PdfZRisanjemState extends State<PdfZRisanjem> with RisanjeNaStrani {
  final _kontroler = PdfViewerController();
  PdfViewerSizeDelegateProviderLegacy? _velikost;

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

  // Stran 0 je besedilo pesmi, PDF ima strani od 1 naprej.
  @override
  bool mojaStran(int stran) => stran > 0;

  @override
  void initState() {
    super.initState();
    Nastavitve.aplikacija.povecavaPdf(widget.pesem).then((zoom) {
      if (!mounted) return;
      setState(
        () => _velikost = PdfViewerSizeDelegateProviderLegacy(
          // Shranjena povečava ali cela stran na zaslonu.
          calculateInitialZoom: (dokument, kontroler, cela, pokrij) => zoom ?? cela,
        ),
      );
    });
  }

  /// Shrani povečavo po ščipu; blizu cele strani pomeni privzeto.
  void _shraniPovecavo() {
    if (!_kontroler.isReady) return;
    final zoom = _kontroler.currentZoom;
    final cela = _kontroler.alternativeFitScale;
    final privzeto = cela != null && (zoom - cela).abs() < cela * 0.03;
    Nastavitve.aplikacija.nastaviPovecavoPdf(widget.pesem, privzeto ? null : zoom);
  }

  @override
  Widget build(BuildContext context) {
    final velikost = _velikost;
    if (velikost == null) return const SizedBox.expand();
    return Stack(
      children: [
        PdfViewer.data(
          widget.pdf,
          sourceName: widget.ime,
          controller: _kontroler,
          params: PdfViewerParams(
            panEnabled: !risem,
            sizeDelegateProvider: velikost,
            // Pridržanje vklopi risanje, zato izbiranje besedila v PDF-ju ni vklopljeno.
            textSelectionParams: const PdfTextSelectionParams(enabled: false),
            onInteractionEnd: (_) => _shraniPovecavo(),
            pageOverlaysBuilder: (context, rect, page) => [slojStrani(page.pageNumber, rect.size)],
          ),
        ),
        ...kontrole(context),
      ],
    );
  }
}

/// Risanje, markiranje, opombe in gumbi na eni ali več straneh (PDF ali besedilo). Koordinate so relativne:
/// x glede na širino strani, y glede na [enotaY] (višino strani pri PDF-ju, širino pri besedilu).
mixin RisanjeNaStrani<T extends StatefulWidget> on State<T> {
  Risbe get risbe;
  String get pesem;
  ValueNotifier<bool> get risanje;
  KnjiznicaMidi get knjiznica;

  /// Klicaji pesmi; narisani so na svojih straneh in utripajo.
  List<KlicajPesmi> get klicaji;

  // Izrisane strani: ključ za iskanje točke pod prstom in enota relativnih koordinat.
  final _kljuciStrani = <int, GlobalKey>{};
  final _enoteStrani = <int, Size>{};

  /// Ali stran pripada temu prikazu (»Izbriši vse« briše samo te strani).
  bool mojaStran(int stran);

  /// Temno ozadje (besedilo): svetle barve pisala in marker brez množenja barv.
  bool get temnoOzadje => false;

  /// Vrstica besedila pod točko (relativno), za markiranje besedila; null, če markiranja ni.
  Rect? vrsticaPod(int stran, Offset tocka) => null;

  bool get lahkoOznacuje => false;

  Risba _risba = Risba();
  bool get risem => risanje.value;
  _Nacin _nacin = _Nacin.pisalo;
  late Color _barvaPisala = _pisala[1];
  Color _barvaMarkerja = _barveMarkerja[0];

  // Trenutna poteza (stran in točke), dokler prst ne gre z zaslona.
  int? _stranPoteze;
  Poteza? _poteza;
  Oznaka? _oznaka;
  Rect? _vrsticaOznake;
  double _zacetekOznake = 0;
  bool _zaceto = false;
  final _zgodovina = <String>[];

  // Dva prsta pomenita povečavo, ne risanja: poteza se prekliče.
  final _prsti = <int>{};
  int? _prviPrst;
  bool _vecPrstov = false;

  List<Color> get _pisala => temnoOzadje ? _barvePisalaTemno : _barvePisala;

  Risba get risba => _risba;

  @override
  void initState() {
    super.initState();
    risanje.addListener(_spremembaRisanja);
    risbe.nalozi(pesem).then((r) {
      if (mounted) setState(() => _risba = r);
    });
  }

  @override
  void dispose() {
    risanje.removeListener(_spremembaRisanja);
    super.dispose();
  }

  void _spremembaRisanja() {
    if (!mounted) return;
    if (!risem && _nacin == _Nacin.oznacevalec && !lahkoOznacuje) _nacin = _Nacin.pisalo;
    setState(() {});
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
    setState(() => _risba.izbrisiStrani(mojaStran));
    _shrani();
  }

  // ---------- Dotiki na strani ----------

  void _dol(int stran, PointerDownEvent e, Offset p) {
    _prsti.add(e.pointer);
    if (_prsti.length > 1) {
      _prekliciPotezo();
      _vecPrstov = true;
      return;
    }
    if (_vecPrstov) return;
    _prviPrst = e.pointer;
    _zacetek(stran, p);
  }

  void _premikPrsta(int stran, PointerMoveEvent e, Offset p) {
    if (_vecPrstov || e.pointer != _prviPrst) return;
    _premik(stran, p);
  }

  void _gor(int stran, PointerEvent e, Offset p, {bool preklicano = false}) {
    _prsti.remove(e.pointer);
    if (_vecPrstov) {
      if (_prsti.isEmpty) _vecPrstov = false;
      return;
    }
    if (e.pointer != _prviPrst) return;
    _prviPrst = null;
    preklicano ? _prekliciPotezo() : _konec(stran, p);
  }

  /// Drugi prst: kar je prvi začel risati, se razveljavi.
  void _prekliciPotezo() {
    if (_zaceto && _zgodovina.isNotEmpty) {
      setState(() => _risba = Risba.izBesedila(_zgodovina.removeLast()));
    }
    _zaceto = false;
    _poteza = null;
    _oznaka = null;
    _stranPoteze = null;
    _prviPrst = null;
  }

  void _zacetek(int stran, Offset p) {
    switch (_nacin) {
      case _Nacin.pisalo:
      case _Nacin.marker:
        _zapomniZaRazveljavi();
        _zaceto = true;
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
      case _Nacin.oznacevalec:
        final vrstica = vrsticaPod(stran, p);
        if (vrstica == null) return;
        _zapomniZaRazveljavi();
        _zaceto = true;
        _vrsticaOznake = vrstica;
        _zacetekOznake = p.dx.clamp(vrstica.left, vrstica.right);
        setState(() {
          _stranPoteze = stran;
          _oznaka = Oznaka(
            obmocje: Rect.fromLTRB(_zacetekOznake, vrstica.top, _zacetekOznake, vrstica.bottom),
            barva: _barvaMarkerja.toARGB32(),
          );
          _risba.oznakeStrani(stran).add(_oznaka!);
        });
      case _Nacin.radirka:
        _zapomniZaRazveljavi();
        _zaceto = true;
        _radiraj(stran, p);
      case _Nacin.opomba:
      case _Nacin.gumb:
        break; // doda se ob koncu dotika (tap), glej _konec
    }
  }

  void _premik(int stran, Offset p) {
    if (_nacin == _Nacin.radirka) {
      _radiraj(stran, p);
    } else if (_poteza != null && _stranPoteze == stran) {
      setState(() => _poteza!.tocke.add(p));
    } else if (_oznaka != null && _stranPoteze == stran) {
      final v = _vrsticaOznake!;
      final x = p.dx.clamp(v.left, v.right);
      final oznake = _risba.oznakeStrani(stran);
      final nova = Oznaka(
        obmocje: Rect.fromLTRB(math.min(_zacetekOznake, x), v.top, math.max(_zacetekOznake, x), v.bottom),
        barva: _oznaka!.barva,
      );
      setState(() {
        oznake[oznake.indexOf(_oznaka!)] = nova;
        _oznaka = nova;
      });
    }
  }

  void _konec(int stran, Offset p) {
    if (_nacin == _Nacin.opomba) {
      _urediOpombo(stran, p);
      return;
    }
    if (_nacin == _Nacin.gumb) {
      _urediGumb(stran, p);
      return;
    }
    // Dotik brez vlečenja označi celo vrstico.
    if (_oznaka case final o? when o.obmocje.width < 0.01) {
      final oznake = _risba.oznakeStrani(stran);
      oznake[oznake.indexOf(o)] = Oznaka(obmocje: _vrsticaOznake!, barva: o.barva);
    }
    final spremenjeno = _zaceto;
    _zaceto = false;
    _poteza = null;
    _oznaka = null;
    _stranPoteze = null;
    if (spremenjeno) {
      setState(() {});
      _shrani();
    }
  }

  void _radiraj(int stran, Offset p) {
    final poteze = _risba.potezeStrani(stran);
    final opombe = _risba.opombeStrani(stran);
    final oznake = _risba.oznakeStrani(stran);
    final gumbi = _risba.gumbiStrani(stran);
    final pred = poteze.length + opombe.length + oznake.length + gumbi.length;
    poteze.removeWhere((x) => x.blizu(p, _polmerRadirke));
    opombe.removeWhere((o) => (o.polozaj - p).distance < _polmerRadirke * 2);
    oznake.removeWhere((o) => o.obmocje.inflate(_polmerRadirke / 2).contains(p));
    gumbi.removeWhere((g) => (g.polozaj - p).distance < _polmerRadirke * 2);
    if (poteze.length + opombe.length + oznake.length + gumbi.length != pred) setState(() {});
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

  /// Tap v načinu Gumb: nov gumb ali urejanje bližnjega.
  Future<void> _urediGumb(int stran, Offset p) async {
    final gumbi = _risba.gumbiStrani(stran);
    GumbNaStrani? obstojeci;
    for (final g in gumbi) {
      if ((g.polozaj - p).distance < 0.05) obstojeci = g;
    }
    final rezultat = await urediGumb(context, obstojeci, knjiznica);
    if (rezultat == null) return;
    _zapomniZaRazveljavi();
    setState(() {
      if (obstojeci != null) gumbi.remove(obstojeci);
      if (rezultat.gumb case final g?) gumbi.add(g.kopija(polozaj: obstojeci?.polozaj ?? p));
    });
    _shrani();
  }

  String get opisIzbrisa => 'Izbrišem vse risbe, oznake, opombe in gumbe na tej pesmi?';

  // ---------- Klicaji (mesto na strani) ----------

  /// Stran in relativna točka pod [globalno] (npr. trojni dotik); null, če ni nad nobeno stranjo.
  ({int stran, Offset tocka})? naStrani(Offset globalno) {
    for (final MapEntry(key: stran, value: kljuc) in _kljuciStrani.entries) {
      final telo = kljuc.currentContext?.findRenderObject();
      final enota = _enoteStrani[stran];
      if (telo is! RenderBox || !telo.attached || !telo.hasSize || enota == null) continue;
      final l = telo.globalToLocal(globalno);
      if ((Offset.zero & telo.size).contains(l)) {
        return (stran: stran, tocka: Offset(l.dx / enota.width, l.dy / enota.height));
      }
    }
    return null;
  }

  /// Klicaj blizu [globalno] (dotik ali pridržanje na klicaju).
  KlicajPesmi? klicajPri(Offset globalno) {
    KlicajPesmi? najblizji;
    var razdalja = 40.0;
    for (final k in klicaji) {
      final telo = _kljuciStrani[k.stran]?.currentContext?.findRenderObject();
      final enota = _enoteStrani[k.stran];
      if (telo is! RenderBox || !telo.attached || !telo.hasSize || enota == null) continue;
      final g = telo.localToGlobal(Offset(k.x * enota.width, k.y * enota.height));
      final d = (g - globalno).distance;
      if (d < razdalja) {
        razdalja = d;
        najblizji = k;
      }
    }
    return najblizji;
  }

  // ---------- Prikaz ----------

  /// Označeno besedilo pod besedilom strani (barva za črkami).
  Widget podlagaStrani(int stran, Size velikost, {double? enotaX, double? enotaY}) => IgnorePointer(
    child: CustomPaint(
      size: velikost,
      painter: _OznakeSlikar(
        oznake: List.of(_risba.oznake[stran] ?? const []),
        enota: Size(enotaX ?? velikost.width, enotaY ?? velikost.height),
      ),
    ),
  );

  /// Sloj risb nad stranjo velikosti [velikost]; [enotaX] in [enotaY] sta dolžini, s katerima se množita
  /// x in y (privzeto širina in višina). Z [zOznakami] false so oznake narisane posebej pod besedilom ([podlagaStrani]).
  Widget slojStrani(int stran, Size velikost, {double? enotaX, double? enotaY, bool zOznakami = true}) {
    final enota = Size(enotaX ?? velikost.width, enotaY ?? velikost.height);
    _enoteStrani[stran] = enota;
    return KeyedSubtree(
      key: _kljuciStrani.putIfAbsent(stran, GlobalKey.new),
      child: _sloj(stran, velikost, enota, zOznakami),
    );
  }

  Widget _sloj(int stran, Size velikost, Size enota, bool zOznakami) {
    Offset rel(Offset l) => Offset(l.dx / enota.width, l.dy / enota.height);
    final risba = CustomPaint(
      size: velikost,
      painter: _RisbaSlikar(
        poteze: List.of(_risba.poteze[stran] ?? const []),
        opombe: List.of(_risba.opombe[stran] ?? const []),
        oznake: zOznakami ? List.of(_risba.oznake[stran] ?? const []) : const [],
        enota: enota,
        temnoOzadje: temnoOzadje,
      ),
    );
    final gumbi = [
      for (final g in _risba.gumbi[stran] ?? const <GumbNaStrani>[])
        Positioned(
          left: g.polozaj.dx * enota.width,
          top: g.polozaj.dy * enota.height,
          child: IgnorePointer(
            ignoring: risem,
            child: GumbVOpombah(gumb: g, velikost: enota.width * 0.03, knjiznica: knjiznica),
          ),
        ),
      // Klicaj: točka je pod klicajem, klicaj stoji nad njo.
      for (final k in klicaji)
        if (k.stran == stran)
          Positioned(
            left: k.x * enota.width - enota.width * 0.02,
            top: k.y * enota.height - enota.width * 0.07,
            child: IgnorePointer(child: UtripajociKlicaj(velikost: enota.width * 0.08)),
          ),
    ];
    if (!risem) {
      return SizedBox.fromSize(
        size: velikost,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            IgnorePointer(child: risba),
            ...gumbi,
          ],
        ),
      );
    }
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _dol(stran, e, rel(e.localPosition)),
      onPointerMove: (e) => _premikPrsta(stran, e, rel(e.localPosition)),
      onPointerUp: (e) => _gor(stran, e, rel(e.localPosition)),
      onPointerCancel: (e) => _gor(stran, e, rel(e.localPosition), preklicano: true),
      child: SizedBox.fromSize(
        size: velikost,
        child: Stack(clipBehavior: Clip.none, children: [risba, ...gumbi]),
      ),
    );
  }

  /// Orodjarna spodaj, dokler je risanje vklopljeno (vklopi ga pridržanje na pesmi).
  List<Widget> kontrole(BuildContext context) => [
    if (risem) Positioned(left: 0, right: 0, bottom: 0, child: _orodjarna(context)),
  ];

  Widget _orodjarna(BuildContext context) {
    final markerji = _nacin == _Nacin.marker || _nacin == _Nacin.oznacevalec;
    final barve = _nacin == _Nacin.gumb ? const <Color>[] : (markerji ? _barveMarkerja : _pisala);
    final izbrana = markerji ? _barvaMarkerja : _barvaPisala;
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
              FilledButton.icon(
                onPressed: () => risanje.value = false,
                icon: const Icon(Icons.check),
                label: const Text('Končano'),
              ),
              const SizedBox(width: 8),
              gumb(_Nacin.pisalo, Icons.edit, 'Pisalo'),
              gumb(_Nacin.marker, Icons.brush, 'Marker (prostoročno)'),
              if (lahkoOznacuje) gumb(_Nacin.oznacevalec, Icons.format_color_fill, 'Označi besedilo'),
              gumb(_Nacin.radirka, Icons.auto_fix_normal, 'Radirka'),
              gumb(_Nacin.opomba, Icons.sticky_note_2_outlined, 'Opomba'),
              gumb(_Nacin.gumb, Icons.smart_button, 'Gumb z MIDI ukazom'),
              const SizedBox(width: 12),
              if (_nacin != _Nacin.radirka)
                for (final b in barve)
                  GestureDetector(
                    onTap: () => setState(() {
                      if (markerji) {
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

/// Gumb v opombah: ob dotiku pošlje svoje MIDI ukaze.
class GumbVOpombah extends StatelessWidget {
  const GumbVOpombah({super.key, required this.gumb, required this.velikost, required this.knjiznica});

  final GumbNaStrani gumb;

  /// Velikost pisave na gumbu.
  final double velikost;
  final KnjiznicaMidi knjiznica;

  @override
  Widget build(BuildContext context) {
    final barva = Color(gumb.barva);
    final OutlinedBorder oblika = switch (gumb.oblika) {
      OblikaGumba.zaobljen => RoundedRectangleBorder(borderRadius: BorderRadius.circular(velikost * 0.6)),
      OblikaGumba.krog => const CircleBorder(),
      OblikaGumba.kvadrat => const RoundedRectangleBorder(),
    };
    final besedilo = Text(
      gumb.napis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: velikost,
        fontWeight: FontWeight.bold,
        color: barva.computeLuminance() > 0.5 ? Colors.black : Colors.white,
      ),
    );
    return Material(
      color: barva,
      shape: oblika,
      elevation: 3,
      child: InkWell(
        customBorder: oblika,
        onTap: () => _pritisni(context),
        child: gumb.oblika == OblikaGumba.krog
            ? SizedBox.square(
                dimension: velikost * 3.2,
                child: Center(child: besedilo),
              )
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: velikost * 0.8, vertical: velikost * 0.45),
                child: besedilo,
              ),
      ),
    );
  }

  void _pritisni(BuildContext context) {
    final midi = Midi.aplikacija;
    if (!midi.vklopljen) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('MIDI je izklopljen (Nastavitve MIDI).')));
      return;
    }
    final ukazi = knjiznica.razsiri(gumb.midi);
    if (ukazi.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gumb »${gumb.napis}« nima veljavnega ukaza.')));
      return;
    }
    midi.poslji(ukazi, knjiznica: knjiznica);
  }
}

/// Okno za nov ali obstoječ gumb v opombah. Vrne null ob preklicu, (gumb: null) ob brisanju.
Future<({GumbNaStrani? gumb})?> urediGumb(
  BuildContext context,
  GumbNaStrani? obstojeci,
  KnjiznicaMidi knjiznica,
) async {
  final predloge = await GumbNaStrani.predloge();
  if (!context.mounted) return null;
  final napis = TextEditingController(text: obstojeci?.napis ?? '');
  final midi = TextEditingController(text: obstojeci?.midi ?? '');
  var barva = obstojeci?.barva ?? barveGumbov[4].toARGB32();
  var oblika = obstojeci?.oblika ?? OblikaGumba.zaobljen;
  var shrani = false;
  final rezultat = await showDialog<({GumbNaStrani? gumb})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, nastavi) => AlertDialog(
        title: Text(obstojeci == null ? 'Nov gumb' : 'Uredi gumb'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (predloge.isNotEmpty) ...[
                const Text('Shranjeni gumbi'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final g in predloge)
                      InputChip(
                        avatar: CircleAvatar(backgroundColor: Color(g.barva)),
                        label: Text(g.napis),
                        onPressed: () => nastavi(() {
                          napis.text = g.napis;
                          midi.text = g.midi;
                          barva = g.barva;
                          oblika = g.oblika;
                        }),
                        onDeleted: () async {
                          predloge.remove(g);
                          await GumbNaStrani.shraniPredloge(predloge);
                          nastavi(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: napis,
                autofocus: obstojeci == null && predloge.isEmpty,
                decoration: const InputDecoration(labelText: 'Napis (npr. Solo, Konec)'),
              ),
              const SizedBox(height: 12),
              PoljeMidi(
                oznaka: 'MIDI ukazi ali makri',
                vnos: midi,
                knjiznica: knjiznica,
                pomoc: 'Npr. PC 1 5 ali ime ukaza oziroma makra; več jih loči s ;',
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final b in barveGumbov)
                    GestureDetector(
                      onTap: () => nastavi(() => barva = b.toARGB32()),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: b,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: b.toARGB32() == barva ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<OblikaGumba>(
                segments: [for (final o in OblikaGumba.values) ButtonSegment(value: o, label: Text(o.ime))],
                selected: {oblika},
                onSelectionChanged: (o) => nastavi(() => oblika = o.first),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Shrani za ponovno uporabo'),
                value: shrani,
                onChanged: (v) => nastavi(() => shrani = v ?? false),
              ),
            ],
          ),
        ),
        actions: [
          if (obstojeci != null)
            TextButton(onPressed: () => Navigator.pop(context, (gumb: null)), child: const Text('Izbriši')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
          FilledButton(
            onPressed: () {
              if (napis.text.trim().isEmpty) return;
              Navigator.pop(context, (
                gumb: GumbNaStrani(napis: napis.text.trim(), midi: midi.text.trim(), barva: barva, oblika: oblika),
              ));
            },
            child: const Text('Shrani'),
          ),
        ],
      ),
    ),
  );
  final g = rezultat?.gumb;
  if (shrani && g != null) {
    predloge
      ..removeWhere((x) => x.napis == g.napis)
      ..add(g);
    await GumbNaStrani.shraniPredloge(predloge);
  }
  napis.dispose();
  midi.dispose();
  return rezultat;
}

class _OznakeSlikar extends CustomPainter {
  _OznakeSlikar({required this.oznake, required this.enota});

  final List<Oznaka> oznake;
  final Size enota;

  @override
  void paint(Canvas canvas, Size platno) {
    for (final o in oznake) {
      final r = o.obmocje;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(r.left * enota.width, r.top * enota.height, r.right * enota.width, r.bottom * enota.height),
          Radius.circular(enota.width * 0.004),
        ),
        Paint()..color = Color(o.barva).withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_OznakeSlikar old) => true;
}

class _RisbaSlikar extends CustomPainter {
  _RisbaSlikar({
    required this.poteze,
    required this.opombe,
    this.oznake = const [],
    required this.enota,
    this.temnoOzadje = false,
  });

  final List<Poteza> poteze;
  final List<Opomba> opombe;
  final List<Oznaka> oznake;

  /// Velikost, s katero se pomnožijo relativne koordinate (x: širina, y: višina ali širina).
  final Size enota;
  final bool temnoOzadje;

  @override
  void paint(Canvas canvas, Size platno) {
    final size = enota;
    _OznakeSlikar(oznake: oznake, enota: enota).paint(canvas, platno);
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
