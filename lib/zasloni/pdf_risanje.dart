import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.obPovecavi,
    this.risbeSkupne,
    this.smeSkupno = false,
    this.posnetki,
  });

  /// Skupne risbe pesmi in ali jih član sme risati.
  final Risbe? risbeSkupne;
  final bool smeSkupno;

  /// Odpre posnetke pesmi (osebno ali skupno, kot je izbrano pri zapiskih).
  final void Function(bool skupno)? posnetki;

  final Uint8List pdf;

  /// Po ščipu: nova povečava (null = cela stran); shrani jo šele zaslon pesmi z ikono za shranjevanje.
  final void Function(double? zoom)? obPovecavi;

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

  /// Povečava po ščipu; blizu cele strani pomeni privzeto.
  void _shraniPovecavo() {
    if (!_kontroler.isReady) return;
    final zoom = _kontroler.currentZoom;
    final cela = _kontroler.alternativeFitScale;
    final privzeto = cela != null && (zoom - cela).abs() < cela * 0.03;
    widget.obPovecavi?.call(privzeto ? null : zoom);
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

  /// Skupne risbe pesmi (vidijo jih vsi); null, če jih ta prikaz nima.
  Risbe? get risbeSkupne => null;

  /// Ali sme član risati skupne risbe (urejevalec pesmi).
  bool get smeSkupno => false;

  /// Gumb za zvočne posnetke pesmi v orodjarni (dobi, ali je izbrano skupno).
  void Function(bool skupno)? get posnetki => null;
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

  /// Vrstice besedila na strani (relativno, od zgoraj navzdol), za markiranje besedila; prazno, če ga ni.
  List<Rect> vrsticeStrani(int stran) => const [];

  /// Indeksi vrstic besedila za [vrsticeStrani], če stran oznake veže na besedilo (sicer prazno).
  /// Taka oznaka ostane na svoji vrstici ob povečavi, prelomu ali novih vrsticah.
  List<int> indeksiVrstic(int stran) => const [];

  /// Besedilo vrstice z [indeks] (za iskanje vrstice oznake, ko se besedilo spremeni).
  String besediloVrstice(int indeks) => '';

  /// Kje je oznaka zdaj (za radirko); vezana na besedilo se izračuna iz trenutnih vrstic.
  Rect? obmocjeOznake(int stran, Oznaka o) => o.obmocje;

  /// Indeks vrstice pri višini [y]; z [natancno] samo, če je [y] v vrstici, sicer najbližja.
  static int? _indeksVrstice(List<Rect> vrstice, double y, {bool natancno = false}) {
    int? najblizja;
    var razdalja = double.infinity;
    for (var i = 0; i < vrstice.length; i++) {
      final v = vrstice[i];
      if (y >= v.top && y <= v.bottom) return i;
      final d = math.min((y - v.top).abs(), (y - v.bottom).abs());
      if (d < razdalja) {
        razdalja = d;
        najblizja = i;
      }
    }
    return natancno ? null : najblizja;
  }

  bool get lahkoOznacuje => false;

  // Osebna risba (privzeto) in skupna risba pesmi; urejaš tisto, ki je izbrana v orodjarni.
  Risba _osebna = Risba();
  Risba _skupna = Risba();
  bool _skupno = false;

  Risba get _risba => _skupno ? _skupna : _osebna;
  set _risba(Risba r) => _skupno ? _skupna = r : _osebna = r;

  /// Obe risbi za prikaz: najprej skupna (spodaj), nato osebna.
  List<Risba> get _obe => [if (risbeSkupne != null) _skupna, _osebna];
  bool get risem => risanje.value;
  _Nacin _nacin = _Nacin.pisalo;
  late Color _barvaPisala = _pisala[1];
  Color _barvaMarkerja = _barveMarkerja[0];

  // Trenutna poteza (stran in točke), dokler prst ne gre z zaslona.
  int? _stranPoteze;
  Poteza? _poteza;
  // Markiranje besedila: vrstice strani, začetna vrstica in točka ter oznake, ki jih vlečenje riše.
  List<Rect> _vrsticeOznake = const [];
  List<int> _indeksiOznake = const [];
  int _zacetnaVrstica = 0;
  double _zacetekOznake = 0;
  List<Oznaka> _oznakeVlecenja = [];

  // Pridržanje na gumbu ali opombi: po kratkem času ga premikaš.
  Timer? _casPremika;
  Object? _kandidat;
  Offset _zacetekKandidata = Offset.zero;
  Object? _premikam;
  Offset _odmikPremika = Offset.zero;
  bool _zaceto = false;
  final _zgodovina = <String>[];

  // Dva prsta pomenita povečavo, ne risanja: poteza se prekliče.
  final _prsti = <int>{};
  int? _prviPrst;
  bool _vecPrstov = false;

  List<Color> get _pisala => temnoOzadje ? _barvePisalaTemno : _barvePisala;

  Risba get risba => _osebna;

  @override
  void initState() {
    super.initState();
    risanje.addListener(_spremembaRisanja);
    risbe.nalozi(pesem).then((r) {
      if (mounted) setState(() => _osebna = r);
    });
    risbeSkupne?.nalozi(pesem).then((r) {
      if (mounted) setState(() => _skupna = r);
    });
  }

  /// Oznake obeh risb na [stran], vezane na vrstice besedila (nariše jih besedilo ob vrstici).
  List<Oznaka> oznakeVrstic(int stran) => [
    for (final r in _obe)
      for (final o in r.oznake[stran] ?? const <Oznaka>[])
        if (o.vrstica != null) o,
  ];

  /// Preklop med osebno in skupno risbo (razveljavljanje velja za vsako posebej).
  void _preklopiSkupno(bool skupno) => setState(() {
    _skupno = skupno && smeSkupno && risbeSkupne != null;
    _zgodovina.clear();
  });

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

  void _shrani() => (_skupno ? risbeSkupne! : risbe).shrani(pesem, _risba);

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
    // Na gumbu ali opombi: pridržanje ga premakne, premik prsta pred tem je navadna poteza.
    final predmet = _predmetPri(stran, p);
    if (predmet != null && _nacin != _Nacin.radirka) {
      _kandidat = predmet;
      _zacetekKandidata = p;
      _casPremika = Timer(const Duration(milliseconds: 450), () {
        if (_kandidat == null) return;
        _zapomniZaRazveljavi();
        HapticFeedback.mediumImpact();
        setState(() {
          _premikam = _kandidat;
          _odmikPremika = _zacetekKandidata - _polozaj(_kandidat!);
          _kandidat = null;
        });
      });
      return;
    }
    _zacetek(stran, p);
  }

  void _premikPrsta(int stran, PointerMoveEvent e, Offset p) {
    if (_vecPrstov || e.pointer != _prviPrst) return;
    if (_premikam case final x?) {
      setState(() => _nastaviPolozaj(x, p - _odmikPremika));
      return;
    }
    if (_kandidat != null) {
      if ((p - _zacetekKandidata).distance < 0.015) return;
      _casPremika?.cancel();
      _kandidat = null;
      _zacetek(stran, _zacetekKandidata);
    }
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
    _casPremika?.cancel();
    if (_premikam != null) {
      _premikam = null;
      setState(() {});
      _shrani();
      return;
    }
    if (_kandidat != null) {
      // Kratek dotik na gumbu ali opombi: kot dotik na tem mestu (npr. urejanje v načinu Gumb ali Opomba).
      _kandidat = null;
      if (preklicano) return;
      _zacetek(stran, _zacetekKandidata);
      _konec(stran, _zacetekKandidata);
      return;
    }
    preklicano ? _prekliciPotezo() : _konec(stran, p);
  }

  Offset _polozaj(Object x) => switch (x) {
    final Opomba o => o.polozaj,
    final GumbNaStrani g => g.polozaj,
    _ => Offset.zero,
  };

  void _nastaviPolozaj(Object x, Offset p) {
    final q = Offset(p.dx.clamp(0, 0.98), math.max(p.dy, 0));
    switch (x) {
      case final Opomba o:
        o.polozaj = q;
      case final GumbNaStrani g:
        g.polozaj = q;
    }
  }

  /// Gumb ali opomba pod točko (približno, po velikosti pisave).
  Object? _predmetPri(int stran, Offset p) {
    final enota = _enoteStrani[stran];
    if (enota == null) return null;
    // Delež višine, ki ustreza enoti širine (pri besedilu 1, pri PDF-ju razmerje strani).
    final r = enota.width / enota.height;
    for (final g in (_risba.gumbi[stran] ?? const <GumbNaStrani>[]).reversed) {
      final x = g.prikaz;
      final pisava = 0.03 * g.velikost;
      final (s, v) = x.oblika == OblikaGumba.krog
          ? (pisava * 3.2, pisava * 3.2)
          : ((x.napis.length * 0.62 + 1.6) * pisava, 2.4 * pisava);
      if (Rect.fromLTWH(g.polozaj.dx, g.polozaj.dy, s, v * r).inflate(0.01).contains(p)) return g;
    }
    for (final o in (_risba.opombe[stran] ?? const <Opomba>[]).reversed) {
      final x = o.prikaz;
      final pisava = 0.028 * o.velikost;
      final sirina = math.min(x.besedilo.length * 0.55 * pisava, 0.5 * o.velikost);
      final vrstic = math.max(1, (x.besedilo.length * 0.55 * pisava / (0.5 * o.velikost)).ceil());
      if (Rect.fromLTWH(o.polozaj.dx, o.polozaj.dy, sirina, vrstic * 1.3 * pisava * r).inflate(0.01).contains(p)) {
        return o;
      }
    }
    return null;
  }

  /// Drugi prst: kar je prvi začel risati, se razveljavi.
  void _prekliciPotezo() {
    if (_zaceto && _zgodovina.isNotEmpty) {
      setState(() => _risba = Risba.izBesedila(_zgodovina.removeLast()));
    }
    _zaceto = false;
    _poteza = null;
    _oznakeVlecenja = [];
    _stranPoteze = null;
    _prviPrst = null;
    _casPremika?.cancel();
    _kandidat = null;
    _premikam = null;
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
        final vrstice = vrsticeStrani(stran);
        final i = _indeksVrstice(vrstice, p.dy, natancno: true);
        if (i == null) return;
        _zapomniZaRazveljavi();
        _zaceto = true;
        _vrsticeOznake = vrstice;
        final indeksi = indeksiVrstic(stran);
        _indeksiOznake = indeksi.length == vrstice.length ? indeksi : const [];
        _zacetnaVrstica = i;
        _zacetekOznake = p.dx.clamp(vrstice[i].left, vrstice[i].right);
        _oznakeVlecenja = [];
        _stranPoteze = stran;
        _oznaci(stran, p);
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
    } else if (_vrsticeOznake.isNotEmpty && _stranPoteze == stran && _nacin == _Nacin.oznacevalec) {
      _oznaci(stran, p);
    }
  }

  /// Oznake od začetka vlečenja do [p], čez več vrstic kot pri izbiranju besedila.
  void _oznaci(int stran, Offset p) {
    final vrstice = _vrsticeOznake;
    final j = _indeksVrstice(vrstice, p.dy) ?? _zacetnaVrstica;
    final i = _zacetnaVrstica;
    final x = p.dx.clamp(vrstice[j].left, vrstice[j].right);
    final barva = _barvaMarkerja.toARGB32();
    final (od, odX, doo, doX) = j > i || (j == i && x >= _zacetekOznake)
        ? (i, _zacetekOznake, j, x)
        : (j, x, i, _zacetekOznake);
    final nove = [
      for (var k = od; k <= doo; k++)
        _novaOznaka(vrstice, k, k == od ? odX : vrstice[k].left, k == doo ? doX : vrstice[k].right, barva),
    ];
    final oznake = _risba.oznakeStrani(stran);
    setState(() {
      oznake.removeWhere(_oznakeVlecenja.contains);
      oznake.addAll(nove);
      _oznakeVlecenja = nove;
    });
  }

  /// Oznaka na vrstici [k] od [levo] do [desno]; na besedilu vezana na vrstico (deleža širine vrstice).
  Oznaka _novaOznaka(List<Rect> vrstice, int k, double levo, double desno, int barva) {
    final v = vrstice[k];
    final obmocje = Rect.fromLTRB(levo, v.top, desno, v.bottom);
    if (_indeksiOznake.isEmpty || v.width <= 0) return Oznaka(obmocje: obmocje, barva: barva);
    final i = _indeksiOznake[k];
    return Oznaka(
      obmocje: obmocje,
      barva: barva,
      vrstica: i,
      besedilo: besediloVrstice(i),
      od: ((levo - v.left) / v.width).clamp(0, 1),
      doo: ((desno - v.left) / v.width).clamp(0, 1),
    );
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
    if (_oznakeVlecenja case [final o] when o.obmocje.width < 0.01) {
      final oznake = _risba.oznakeStrani(stran);
      final v = _vrsticeOznake[_zacetnaVrstica];
      oznake[oznake.indexOf(o)] = _novaOznaka(_vrsticeOznake, _zacetnaVrstica, v.left, v.right, o.barva);
    }
    final spremenjeno = _zaceto;
    _zaceto = false;
    _poteza = null;
    _oznakeVlecenja = [];
    _vrsticeOznake = const [];
    _indeksiOznake = const [];
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
    final predmet = _predmetPri(stran, p);
    opombe.removeWhere((o) => o == predmet || (o.polozaj - p).distance < _polmerRadirke * 2);
    oznake.removeWhere((o) => obmocjeOznake(stran, o)?.inflate(_polmerRadirke / 2).contains(p) ?? false);
    gumbi.removeWhere((g) => g == predmet || (g.polozaj - p).distance < _polmerRadirke * 2);
    if (poteze.length + opombe.length + oznake.length + gumbi.length != pred) setState(() {});
  }

  /// Tap v načinu Opomba: nova opomba ali urejanje tiste pod prstom.
  Future<void> _urediOpombo(int stran, Offset p) async {
    final opombe = _risba.opombeStrani(stran);
    final obstojeca = switch (_predmetPri(stran, p)) {
      final Opomba o => o,
      _ => null,
    };
    final rezultat = await urediOpombo(context, obstojeca, _barvaPisala.toARGB32());
    if (rezultat == null) return;
    _zapomniZaRazveljavi();
    setState(() {
      final i = obstojeca == null ? -1 : opombe.indexOf(obstojeca);
      final nova = rezultat.opomba;
      if (nova == null) {
        if (i >= 0) opombe.removeAt(i);
      } else {
        nova.polozaj = obstojeca?.polozaj ?? p;
        i >= 0 ? opombe[i] = nova : opombe.add(nova);
      }
    });
    _shrani();
  }

  /// Tap v načinu Gumb: nov gumb ali urejanje bližnjega.
  Future<void> _urediGumb(int stran, Offset p) async {
    final gumbi = _risba.gumbiStrani(stran);
    final obstojeci = switch (_predmetPri(stran, p)) {
      final GumbNaStrani g => g,
      _ => null,
    };
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
        // Oznake, vezane na besedilo, nariše besedilo samo (vsaka ob svoji vrstici).
        oznake: [
          for (final r in _obe)
            for (final o in r.oznake[stran] ?? const <Oznaka>[])
              if (o.vrstica == null) o,
        ],
        enota: Size(enotaX ?? velikost.width, enotaY ?? velikost.height),
        temnoOzadje: temnoOzadje,
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
        poteze: [for (final r in _obe) ...?r.poteze[stran]],
        opombe: [for (final r in _obe) ...?r.opombe[stran]],
        oznake: zOznakami ? [for (final r in _obe) ...?r.oznake[stran]] : const [],
        enota: enota,
        temnoOzadje: temnoOzadje,
      ),
    );
    final gumbi = [
      for (final r in _obe)
        for (final g in r.gumbi[stran] ?? const <GumbNaStrani>[])
          Positioned(
            left: g.polozaj.dx * enota.width,
            top: g.polozaj.dy * enota.height,
            child: IgnorePointer(
              ignoring: risem,
              child: GumbVOpombah(gumb: g.prikaz, velikost: enota.width * 0.03 * g.velikost, knjiznica: knjiznica),
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
              // Osebno (privzeto) ali skupno za vse (npr. pobarvani refreni); skupno le urejevalci.
              if (smeSkupno && risbeSkupne != null) ...[
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.person_outline), tooltip: 'Osebno (samo zame)'),
                    ButtonSegment(value: true, icon: Icon(Icons.groups_outlined), tooltip: 'Skupno (za vse)'),
                  ],
                  selected: {_skupno},
                  onSelectionChanged: (v) => _preklopiSkupno(v.first),
                ),
                const SizedBox(width: 8),
              ],
              if (posnetki case final odpri?) ...[
                IconButton.filledTonal(
                  key: const ValueKey('posnetki'),
                  tooltip: 'Posnetki (snemalnik)',
                  icon: const Icon(Icons.mic_none),
                  onPressed: () => odpri(_skupno),
                ),
                const SizedBox(width: 8),
              ],
              gumb(_Nacin.pisalo, Icons.edit, 'Pisalo'),
              gumb(_Nacin.marker, Icons.brush, 'Marker (prostoročno)'),
              if (lahkoOznacuje) gumb(_Nacin.oznacevalec, Icons.format_color_fill, 'Označi besedilo'),
              IconButton(
                tooltip: 'Radirka',
                isSelected: _nacin == _Nacin.radirka,
                icon: const IkonaRadirke(),
                onPressed: () => setState(() => _nacin = _Nacin.radirka),
              ),
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
              IconButton(tooltip: 'Izbriši vse', icon: const Icon(Icons.delete_sweep_outlined), onPressed: _izbrisiVse),
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

/// Ikona radirke (dvobarvna radirka postrani), ker je med ikonami Material ni.
class IkonaRadirke extends StatelessWidget {
  const IkonaRadirke({super.key, this.velikost = 24});

  final double velikost;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(velikost), painter: _RadirkaSlikar(IconTheme.of(context).color ?? Colors.black));
}

class _RadirkaSlikar extends CustomPainter {
  _RadirkaSlikar(this.barva);

  final Color barva;

  @override
  void paint(Canvas canvas, Size size) {
    final e = size.width / 24;
    canvas.save();
    canvas.translate(12 * e, 11 * e);
    canvas.rotate(-math.pi / 4);
    final telo = Rect.fromCenter(center: Offset.zero, width: 18 * e, height: 9 * e);
    final konica = Rect.fromLTRB(telo.left, telo.top, telo.left + 7 * e, telo.bottom);
    final obroba = Paint()
      ..color = barva
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * e;
    canvas.drawRRect(
      RRect.fromRectAndRadius(konica, Radius.circular(1.5 * e)),
      Paint()..color = const Color(0xFFF48FB1),
    );
    canvas.drawRRect(RRect.fromRectAndRadius(telo, Radius.circular(1.5 * e)), obroba);
    canvas.drawLine(Offset(konica.right, telo.top), Offset(konica.right, telo.bottom), obroba);
    canvas.restore();
    canvas.drawLine(Offset(3 * e, 21.5 * e), Offset(21 * e, 21.5 * e), obroba);
  }

  @override
  bool shouldRepaint(_RadirkaSlikar old) => old.barva != barva;
}

/// Seznam shranjenih gumbov ali opomb (z brisanjem); vrne izbrano ID ali null.
Future<String?> _izberiShranjeno(BuildContext context, {required bool gumbi}) => showDialog<String>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: Predloge.aplikacija,
    builder: (context, _) {
      final p = Predloge.aplikacija;
      final vrstice = gumbi
          ? [for (final g in p.gumbi) (id: g.predloga, napis: g.napis, opis: g.midi, barva: Color(g.barva))]
          : [for (final o in p.opombe) (id: o.predloga, napis: o.besedilo, opis: '', barva: Color(o.barva))];
      return AlertDialog(
        title: Text(gumbi ? 'Shranjeni gumbi' : 'Shranjene opombe'),
        content: SizedBox(
          width: 360,
          child: vrstice.isEmpty
              ? Text(
                  gumbi
                      ? 'Ni še shranjenih gumbov. Pri gumbu obkljukaj »Shrani za ponovno uporabo«.'
                      : 'Ni še shranjenih opomb. Pri opombi obkljukaj »Shrani za ponovno uporabo«.',
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final v in vrstice)
                      ListTile(
                        leading: CircleAvatar(radius: 10, backgroundColor: v.barva),
                        title: Text(v.napis, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: v.opis.isEmpty ? null : Text(v.opis, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          tooltip: 'Odstrani s seznama',
                          icon: const Icon(Icons.close),
                          onPressed: () => gumbi ? p.izbrisiGumb(v.id) : p.izbrisiOpombo(v.id),
                        ),
                        onTap: () => Navigator.pop(context, v.id),
                      ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zapri'))],
      );
    },
  ),
);

/// Velikost gumba ali opombe (drsnik).
Widget _drsnikVelikosti(double v, ValueChanged<double> spremeni) => Row(
  children: [
    const Text('Velikost'),
    Expanded(
      child: Slider(value: v, min: 0.5, max: 3, divisions: 25, label: '${(v * 100).round()} %', onChanged: spremeni),
    ),
  ],
);

/// Kaj narediti z gumbom ali opombo ob zaprtju okna: [tu] shrani (samo to mesto ali novo shranjeno),
/// [povsod] spremeni shranjenega, [nov] naredi nov gumb samo tu, [shranjen] postavi izbranega s seznama.
enum _Shranjevanje { tu, povsod, nov, shranjen, izbrisi }

/// Okno za nov ali obstoječ gumb v opombah. Vrne null ob preklicu, (gumb: null) ob brisanju.
/// Gumb, postavljen iz shranjenega, je pri vseh besedilih enak: sprememba ga spremeni povsod
/// ali pa nastane nov gumb samo na tem mestu.
Future<({GumbNaStrani? gumb})?> urediGumb(
  BuildContext context,
  GumbNaStrani? obstojeci,
  KnjiznicaMidi knjiznica,
) async {
  final predloge = Predloge.aplikacija;
  final shranjen = predloge.gumb(obstojeci?.predloga ?? '') != null;
  final zacetni = obstojeci?.prikaz;
  final napis = TextEditingController(text: zacetni?.napis ?? '');
  final midi = TextEditingController(text: zacetni?.midi ?? '');
  var barva = zacetni?.barva ?? barveGumbov[4].toARGB32();
  var oblika = zacetni?.oblika ?? OblikaGumba.zaobljen;
  var velikost = obstojeci?.velikost ?? 1.0;
  var shrani = false;
  String? izShranjenih;
  final nacin = await showDialog<_Shranjevanje?>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, nastavi) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(obstojeci == null ? 'Nov gumb' : 'Uredi gumb')),
            IconButton(
              tooltip: 'Shranjeni gumbi',
              icon: const Icon(Icons.bookmarks_outlined),
              onPressed: () async {
                final id = await _izberiShranjeno(context, gumbi: true);
                if (id != null && context.mounted) {
                  izShranjenih = id;
                  Navigator.pop(context, _Shranjevanje.shranjen);
                }
              },
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (shranjen)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'To je shranjen gumb: sprememba velja pri vseh besedilih, kjer je. '
                    'Lahko pa narediš nov gumb samo na tem mestu.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              TextField(
                controller: napis,
                autofocus: obstojeci == null,
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
              _drsnikVelikosti(velikost, (v) => nastavi(() => velikost = v)),
              if (!shranjen)
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
            TextButton(onPressed: () => Navigator.pop(context, _Shranjevanje.izbrisi), child: const Text('Izbriši')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
          if (shranjen)
            TextButton(
              onPressed: () => napis.text.trim().isEmpty ? null : Navigator.pop(context, _Shranjevanje.nov),
              child: const Text('Shrani kot nov'),
            ),
          FilledButton(
            onPressed: () => napis.text.trim().isEmpty
                ? null
                : Navigator.pop(context, shranjen ? _Shranjevanje.povsod : _Shranjevanje.tu),
            child: Text(shranjen ? 'Spremeni povsod' : 'Shrani'),
          ),
        ],
      ),
    ),
  );
  final g = GumbNaStrani(
    napis: napis.text.trim(),
    midi: midi.text.trim(),
    barva: barva,
    oblika: oblika,
    velikost: velikost,
    predloga: nacin == _Shranjevanje.povsod ? obstojeci!.predloga : '',
  );
  napis.dispose();
  midi.dispose();
  switch (nacin) {
    case null:
      return null;
    case _Shranjevanje.izbrisi:
      return (gumb: null);
    case _Shranjevanje.shranjen:
      // Napis in ukazi pridejo iz shranjenega (GumbNaStrani.prikaz).
      final s = predloge.gumb(izShranjenih!)!;
      return (gumb: s.kopija(predloga: izShranjenih, velikost: velikost));
    case _Shranjevanje.povsod:
      await predloge.shraniGumb(g);
    case _Shranjevanje.tu when shrani:
      g.predloga = await predloge.shraniGumb(g);
    case _Shranjevanje.tu || _Shranjevanje.nov:
      break;
  }
  return (gumb: g);
}

/// Okno za novo ali obstoječo opombo; enako kot pri gumbu (shranjene opombe, velikost).
/// Vrne null ob preklicu, (opomba: null) ob brisanju.
Future<({Opomba? opomba})?> urediOpombo(BuildContext context, Opomba? obstojeca, int barva) async {
  final predloge = Predloge.aplikacija;
  final shranjena = predloge.opomba(obstojeca?.predloga ?? '') != null;
  final besedilo = TextEditingController(text: obstojeca?.prikaz.besedilo ?? '');
  var velikost = obstojeca?.velikost ?? 1.0;
  var shrani = false;
  String? izShranjenih;
  final nacin = await showDialog<_Shranjevanje>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, nastavi) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(obstojeca == null ? 'Nova opomba' : 'Uredi opombo')),
            IconButton(
              tooltip: 'Shranjene opombe',
              icon: const Icon(Icons.bookmarks_outlined),
              onPressed: () async {
                final id = await _izberiShranjeno(context, gumbi: false);
                if (id != null && context.mounted) {
                  izShranjenih = id;
                  Navigator.pop(context, _Shranjevanje.shranjen);
                }
              },
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shranjena)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'To je shranjena opomba: sprememba velja pri vseh besedilih, kjer je. '
                    'Lahko pa narediš novo opombo samo na tem mestu.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              TextField(controller: besedilo, autofocus: true, maxLines: 3, minLines: 1),
              _drsnikVelikosti(velikost, (v) => nastavi(() => velikost = v)),
              if (!shranjena)
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
          if (obstojeca != null)
            TextButton(onPressed: () => Navigator.pop(context, _Shranjevanje.izbrisi), child: const Text('Izbriši')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
          if (shranjena)
            TextButton(
              onPressed: () => Navigator.pop(context, _Shranjevanje.nov),
              child: const Text('Shrani kot novo'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, shranjena ? _Shranjevanje.povsod : _Shranjevanje.tu),
            child: Text(shranjena ? 'Spremeni povsod' : 'Shrani'),
          ),
        ],
      ),
    ),
  );
  final tekst = besedilo.text.trim();
  besedilo.dispose();
  final o = Opomba(
    polozaj: Offset.zero,
    besedilo: tekst,
    barva: obstojeca?.prikaz.barva ?? barva,
    velikost: velikost,
    predloga: nacin == _Shranjevanje.povsod ? obstojeca!.predloga : '',
  );
  switch (nacin) {
    case null:
      return null;
    case _Shranjevanje.izbrisi:
      return (opomba: null);
    case _Shranjevanje.shranjen:
      // Besedilo pride iz shranjene (Opomba.prikaz); kopija ostane, če shranjeno kdaj odstraniš.
      final s = predloge.opomba(izShranjenih!)!;
      return (
        opomba: Opomba(
          polozaj: Offset.zero,
          besedilo: s.besedilo,
          barva: s.barva,
          predloga: izShranjenih!,
          velikost: velikost,
        ),
      );
    case _ when tekst.isEmpty:
      return obstojeca == null ? null : (opomba: null);
    case _Shranjevanje.povsod:
      await predloge.shraniOpombo(o);
    case _Shranjevanje.tu when shrani:
      o.predloga = await predloge.shraniOpombo(o);
    case _Shranjevanje.tu || _Shranjevanje.nov:
      break;
  }
  return (opomba: o);
}

/// Markerji in označeno besedilo so ena plast: znotraj nje se rišejo neprosojno (novejše prepiše starejše),
/// prosojnost se doda enkrat za vso plast, zato večkratno prekrivanje ne potemni.
void _plastMarkerjev(Canvas canvas, Size platno, bool temnoOzadje, void Function() risi) {
  canvas.saveLayer(
    Offset.zero & platno,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..blendMode = temnoOzadje ? BlendMode.srcOver : BlendMode.multiply,
  );
  risi();
  canvas.restore();
}

void _risiOznake(Canvas canvas, List<Oznaka> oznake, Size enota) {
  for (final o in oznake) {
    final r = o.obmocje;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(r.left * enota.width, r.top * enota.height, r.right * enota.width, r.bottom * enota.height),
        Radius.circular(enota.width * 0.004),
      ),
      Paint()..color = Color(o.barva).withValues(alpha: 1),
    );
  }
}

class _OznakeSlikar extends CustomPainter {
  _OznakeSlikar({required this.oznake, required this.enota, this.temnoOzadje = false});

  final List<Oznaka> oznake;
  final Size enota;
  final bool temnoOzadje;

  @override
  void paint(Canvas canvas, Size platno) {
    if (oznake.isEmpty) return;
    _plastMarkerjev(canvas, platno, temnoOzadje, () => _risiOznake(canvas, oznake, enota));
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
    Paint copic(Poteza p, {bool marker = false}) => Paint()
      ..color = Color(p.barva).withValues(alpha: 1)
      ..strokeWidth = p.debelina * size.width
      ..style = PaintingStyle.stroke
      ..strokeCap = marker ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void risi(Poteza p, Paint c) {
      final tocke = [for (final t in p.tocke) Offset(t.dx * size.width, t.dy * size.height)];
      if (tocke.length == 1) {
        canvas.drawPoints(ui.PointMode.points, tocke, c);
        return;
      }
      // Gladka črta skozi sredine sosednjih točk.
      final pot = Path()..moveTo(tocke.first.dx, tocke.first.dy);
      for (var i = 1; i < tocke.length - 1; i++) {
        final sredina = (tocke[i] + tocke[i + 1]) / 2;
        pot.quadraticBezierTo(tocke[i].dx, tocke[i].dy, sredina.dx, sredina.dy);
      }
      pot.lineTo(tocke.last.dx, tocke.last.dy);
      canvas.drawPath(pot, c);
    }

    // Markerji v eni plasti (pod pisalom), pisalo ohrani vse poteze.
    final markerji = [
      for (final p in poteze)
        if (p.orodje == Orodje.marker) p,
    ];
    if (markerji.isNotEmpty || oznake.isNotEmpty) {
      _plastMarkerjev(canvas, platno, temnoOzadje, () {
        _risiOznake(canvas, oznake, size);
        for (final p in markerji) {
          risi(p, copic(p, marker: true));
        }
      });
    }
    for (final p in poteze) {
      if (p.orodje != Orodje.marker) risi(p, copic(p));
    }

    for (final shranjena in opombe) {
      final o = shranjena.prikaz;
      final tp = TextPainter(
        text: TextSpan(
          text: o.besedilo,
          style: TextStyle(
            // Belo pisalo (besedilo na temnem ozadju) bi se na rumenem listku ne videlo.
            color: Color(o.barva).computeLuminance() > 0.8 ? Colors.black : Color(o.barva),
            fontSize: size.width * 0.028 * o.velikost,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.5 * o.velikost);
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
