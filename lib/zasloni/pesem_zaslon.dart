import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../baza.dart';
import '../chordpro.dart' as cp;
import '../config.dart';
import '../midi/midi.dart';
import '../midi/ukazi.dart';
import '../tipkovnica.dart' show Listanje;
import '../models.dart';
import '../nastavitve.dart';
import '../efekti.dart';
import '../uvodi.dart';
import '../zvok_spila.dart';
import '../odigrane.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'besedilo_risanje.dart';
import 'iskalnik_pesmi.dart';
import 'midi_zaslon.dart';
import 'naslednje.dart';
import 'orodja.dart';
import 'oznake.dart';
import 'drsnik.dart' show Vlecenje;
import 'pdf_risanje.dart';
import 'fx_panel.dart';
import 'posnetki.dart';
import 'prehod.dart';
import 'spil_zaslon.dart';
import 'urejanje_pesmi.dart';
import 'youtube.dart';

class PesemZaslon extends StatefulWidget {
  const PesemZaslon({
    super.key,
    required this.pesem,
    required this.baza,
    required this.prijava,
    this.spil,
    this.stanje,
    this.spodaj,
    this.seznam,
    this.odpri,
    this.mapa,
    this.prednostne,
    this.playlista,
    this.naslednja,
    this.izIskalnika,
    this.hitroUrejanje = false,
  });

  /// Vrednost [mapa] za iskanje po vseh mapah.
  static const vse = '*';

  final Pesem pesem;
  final Baza baza;
  final Prijava prijava;

  /// Špil: gumb s stanjem povezave zgoraj; vodja ob odprtju pesmi to pošlje sledilcem.
  final Spil? spil;

  /// Kar se pošlje sledilcem (npr. z mestom v setlisti); privzeto samo pesem.
  final StanjeSpila? stanje;

  /// Vrstica pod pesmijo (npr. premikanje po setlisti).
  final Widget? spodaj;

  /// Seznam, iz katerega je pesem odprta: naslednja in prejšnja pesem z nožnim stikalom.
  final List<Pesem>? seznam;

  /// Kako odpreti drugo pesem iz iskalnika; privzeto zamenja ta zaslon.
  final void Function(Pesem)? odpri;

  /// Mapa, v kateri išče iskalnik ([vse] za vse mape); privzeto mapa pesmi.
  final String? mapa;

  /// Pesmi, ki so v iskalniku na vrhu (npr. pesmi playliste).
  final List<Pesem>? prednostne;

  /// Pesmi playliste: v iskalniku označene z ikono, zaporedno številko in opombo.
  final Map<String, MestoVPlaylisti>? playlista;

  /// Naslednja pesem (npr. v playlisti) za prikaz v vrstici; privzeto s čakalne vrste ali s seznama.
  final Pesem? naslednja;

  /// Kaj naredi dotik pesmi v iskalniku (npr. v playlisti); privzeto gre pesem v čakalno vrsto.
  final void Function(Pesem)? izIskalnika;

  /// Odprto iz hitrega urejanja: naprej in nazaj po [seznam] (vrstni red tabele), risanje na skupni plasti.
  final bool hitroUrejanje;

  @override
  State<PesemZaslon> createState() => _PesemZaslonState();
}

class _PesemZaslonState extends State<PesemZaslon> {
  /// Pisava besedila je lastnost pesmi (enaka na vseh napravah); spreminja jo urednik.
  double get _pisava => _novaPisava ?? _pesem.pisava;

  /// Povečava besedila ali PDF-ja, ki še ni shranjena (ikona za shranjevanje v orodni vrstici).
  double? _novaPisava;
  (double?,)? _novaPdf;

  /// Skupne risbe (npr. pobarvane refrene) rišejo urejevalci pesmi; na iPadu prek vodje ne.
  bool get _smeSkupno => !Config.prekoVodje && widget.baza.smeUrejatiPesem(_pesem);

  /// Snemalnik in posnetki pesmi (gumb pri zapiskih); prek vodje jih ni.
  void Function(bool skupno)? get _posnetki => Config.prekoVodje
      ? null
      : (skupno) => oknoPosnetkov(
          context,
          baza: widget.baza,
          api: widget.prijava.prijavljen ? Api(widget.prijava.zeton) : null,
          pesem: widget.pesem.id,
          skupno: skupno,
        );

  bool get _neshranjenZoom => _novaPisava != null || _novaPdf != null;

  Future<void> _shraniZoom() async {
    final n = Nastavitve.aplikacija;
    final messenger = ScaffoldMessenger.of(context);
    if (_novaPisava case final v?) {
      final api = apiZaUrejanje(context, widget.prijava, baza: widget.baza);
      if (api == null) return;
      try {
        await widget.baza.shraniPesem(api, {'ID': _pesem.id, 'Naslov': _pesem.naslov, 'Pisava': v});
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
        return;
      }
    }
    if (_novaPdf case (final z,)) await n.nastaviPovecavoPdf(widget.pesem.id, z);
    if (!mounted) return;
    final pisava = _novaPisava != null;
    setState(() {
      _novaPisava = null;
      _novaPdf = null;
    });
    messenger.showSnackBar(
      SnackBar(content: Text(pisava ? 'Pisava pesmi je shranjena za vse.' : 'Povečava je shranjena za to pesem.')),
    );
  }

  bool _prikaziBesedilo = true;

  /// Pesem, pri kateri je odprto okno YouTube (ob menjavi pesmi se skrije).
  String? _youtube;
  Uint8List? _pdf;
  bool _pdfPrebran = false;
  bool _iskalnik = false;

  /// Risanje vklopi pridržanje na pesmi; med risanjem ni gest (podrsaj, trojni dotik).
  final _risanje = ValueNotifier(false);
  bool get _risem => _risanje.value;
  final _iskalnikKljuc = GlobalKey<IskalnikPesmiState>();

  /// Ko je pesem dovolj dolgo odprta, se označi kot odigrana.
  Timer? _odigrana;

  /// Med playbackom te pesmi (na katerikoli napravi špila) vrstica, ki se poje.
  final _vrsticaPlaybacka = ValueNotifier<int?>(null);
  Timer? _slediPlaybacku;

  void _obZvoku() {
    final igra = ZvokSpila.aplikacija.playback == widget.pesem.id && !_pesem.casiPlaybacka.prazno;
    if (!igra) {
      _slediPlaybacku?.cancel();
      _slediPlaybacku = null;
      _vrsticaPlaybacka.value = null;
      return;
    }
    _slediPlaybacku ??= Timer.periodic(const Duration(milliseconds: 200), (_) => _osveziVrstico());
    _osveziVrstico();
  }

  void _osveziVrstico() {
    _vrsticaPlaybacka.value = _pesem.casiPlaybacka.vrsticaOb(ZvokSpila.aplikacija.pozicijaPlaybacka);
  }

  /// Kdaj je bila pesem odprta (za dnevnik).
  final _odprto = DateTime.now();

  /// Prikaz besedila ali PDF-ja: iz njega se prebere mesto dotika za klicaj.
  var _vsebinaKljuc = GlobalKey();
  RisanjeNaStrani? get _stran => switch (_vsebinaKljuc.currentState) {
    final RisanjeNaStrani s => s,
    _ => null,
  };
  List<KlicajPesmi> get _klicaji => widget.baza.klicaji[widget.pesem.id] ?? const [];

  // Pridržanje in trojni dotik na vsebini (tudi na PDF-ju, ki sam porabi geste).
  final _dotiki = <int, Offset>{};
  Timer? _pridrzanje;
  final _tapi = <DateTime>[];
  Offset? _zadnjiTap;

  /// Trenutni podatki pesmi iz baze (po urejanju se spremenijo).
  Pesem get _pesem => widget.baza.pesem(widget.pesem.id) ?? widget.pesem;
  List<BesediloPesmi> get _besedila => widget.baza.besedilaPesmi[widget.pesem.id] ?? const [];
  List<PdfDatoteka> get _pdfji => widget.baza.pdfjiPesmi[widget.pesem.id] ?? const [];

  @override
  void initState() {
    super.initState();
    _risanje.addListener(() {
      if (mounted) setState(() {});
    });
    _prikaziBesedilo = _besedila.isNotEmpty && !(Nastavitve.aplikacija.pdfNajprej && _pdfji.isNotEmpty);
    // Po prvem izrisu, da obvestilo ne pride sredi gradnje zaslonov.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.spil?.prikazujem(widget.stanje ?? StanjeSpila(pesem: widget.pesem.id));
      Midi.aplikacija.odprta(_pesem, widget.baza.midi, uvod: Nastavitve.aplikacija.uvodi);
      Predvajanje.uvodi.obOdprtju(widget.baza, _apiZaBranje, _pesem);
    });
    final minute = Nastavitve.aplikacija.minuteOdigrane;
    if (minute > 0) {
      _odigrana = Timer(Duration(minutes: minute), () => Odigrane.aplikacija.oznaci(widget.pesem.id));
    }
    _naloziPdf();
    ZvokSpila.aplikacija.addListener(_obZvoku);
    _obZvoku();
  }

  void _naloziPdf() {
    if (_pdfji.isEmpty) return;
    widget.baza.pdf(_pdfji.first.driveId).then((b) {
      if (mounted) {
        setState(() {
          _pdf = b;
          _pdfPrebran = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _odigrana?.cancel();
    _pridrzanje?.cancel();
    ZvokSpila.aplikacija.removeListener(_obZvoku);
    _slediPlaybacku?.cancel();
    _vrsticaPlaybacka.dispose();
    _risanje.dispose();
    Midi.aplikacija.zaprta(_pesem);
    Predvajanje.uvodi.obZaprtju(_pesem);
    Predvajanje.playback.obZaprtju(_pesem);
    if (Nastavitve.aplikacija.predvajajEfekte) Efekti.aplikacija.obMenjaviPesmi();
    _zabelezi();
    super.dispose();
  }

  /// Dnevnik: pesem, odprta toliko časa kot za oznako odigrane (Nastavitve, privzeto 2 min);
  /// iPad prek vodje ne beleži, ker beleži vodja.
  void _zabelezi() {
    final trajanje = DateTime.now().difference(_odprto).inSeconds;
    final minute = Nastavitve.aplikacija.minuteOdigrane;
    if (minute == 0 || trajanje < minute * 60 || Config.prekoVodje) return;
    final p = _pesem;
    widget.baza.zabelezi(apiZaKlicaje(widget.baza, widget.prijava), {
      'cas': _odprto.toUtc().toIso8601String(),
      'pesem': p.id,
      'naslov': p.naslov,
      'trajanje': trajanje,
      'mapa': p.mapa,
      'setlista': widget.stanje?.setlista ?? '',
      'vloga': switch (widget.spil?.vloga) {
        VlogaSpila.vodja => 'Vodja',
        VlogaSpila.sledilec => 'Sledilec',
        _ => 'Sama',
      },
      'naprava': kIsWeb ? 'Splet' : defaultTargetPlatform.name,
    });
  }

  /// Gumba spremenita pisavo te pesmi za vse (samo urednik; shrani se z ikono za shranjevanje).
  void _spremeniPisavo(double d) => setState(() => _novaPisava = (_pisava + d).clamp(12, 64).toDouble());

  /// Vse o pesmi na enem zaslonu; [zavihek] izbere, kaj se odpre najprej.
  Future<void> _uredi({int zavihek = 0}) async {
    final api = apiZaUrejanje(context, widget.prijava, baza: widget.baza);
    if (api == null) return;
    final prejPdf = _pdfji.firstOrNull?.driveId;
    await Navigator.of(context).push(
      MaterialPageRoute<Pesem>(
        builder: (_) => UrejanjePesmiZaslon(baza: widget.baza, api: api, pesem: _pesem, zavihek: zavihek),
      ),
    );
    if (!mounted) return;
    if (_pdfji.firstOrNull?.driveId != prejPdf) {
      setState(() {
        _pdf = null;
        _pdfPrebran = false;
        _vsebinaKljuc = GlobalKey();
      });
      _naloziPdf();
    }
    if (_besedila.isNotEmpty && _pdfji.isEmpty) setState(() => _prikaziBesedilo = true);
    if (_besedila.isEmpty && _pdfji.isNotEmpty) setState(() => _prikaziBesedilo = false);
  }

  /// Odpre drugo pesem; [smer] 1 (naslednja) pride od desne, -1 (prejšnja) od leve.
  void _odpri(Pesem p, {int smer = 0}) {
    setState(() => _iskalnik = false);
    if (p.id == widget.pesem.id) return;
    if (widget.odpri case final odpri?) return odpri(p);
    Navigator.of(context).pushReplacement(
      potDoPesmi(
        (_) => PesemZaslon(
          pesem: p,
          baza: widget.baza,
          prijava: widget.prijava,
          spil: widget.spil,
          seznam: widget.seznam,
          mapa: widget.mapa,
          prednostne: widget.prednostne,
          playlista: widget.playlista,
          hitroUrejanje: widget.hitroUrejanje,
        ),
        smer: smer,
      ),
    );
  }

  /// Iskalnik: pesem gre v čakalno vrsto (dotik na konec, pridržanje na prvo mesto); brez špila se odpre.
  void _izIskalnika(Pesem p, {bool naPrvo = false}) {
    if (widget.izIskalnika case final f? when !naPrvo) {
      setState(() => _iskalnik = false);
      return f(p);
    }
    final spil = widget.spil;
    if (spil == null) return _odpri(p);
    setState(() => _iskalnik = false);
    vCakalnoVrsto(context, spil, widget.baza, p, naPrvo: naPrvo);
  }

  /// Pesem za pavzo v mapi, v kateri išče iskalnik (prva izbira v iskalniku).
  Pesem? get _pavza {
    final mapa = widget.mapa == null || widget.mapa == PesemZaslon.vse ? _pesem.mapa : widget.mapa!;
    return widget.baza.pesem(widget.baza.mapa(mapa)?.pavza ?? '');
  }

  /// Pesem playliste je v iskalniku na vrhu in označena le, dokler je še v čakalni vrsti
  /// (odigrane gredo med ostale). Pri igranju po setlisti (zaslon okoli pesmi) vse.
  bool _seNaVrsti(String id) =>
      widget.playlista == null || widget.odpri != null || (widget.spil?.naslednje.any((n) => n.pesem == id) ?? true);

  /// Pesmi v iskalniku: najprej prednostne (playlista), nato ostale iz mape.
  List<Pesem> get _pesmiIskalnika {
    final mapa = widget.mapa ?? _pesem.mapa;
    final vMapi = widget.baza.pesmiMape(mapa == PesemZaslon.vse ? null : mapa);
    final prednostne = [
      for (final p in widget.prednostne ?? const <Pesem>[])
        if (_seNaVrsti(p.id)) p,
    ];
    final ids = {for (final p in prednostne) p.id};
    return [...prednostne, ...vMapi.where((p) => !ids.contains(p.id))];
  }

  /// Podrsaj levo: naslednja pesem (čakalna vrsta, setlista ali seznam); desno: prejšnja.
  void _podrsaj(DragEndDetails d) {
    final hitrost = d.primaryVelocity ?? 0;
    if (_iskalnik || hitrost.abs() < 300) return;
    Midi.aplikacija.sprozi(hitrost < 0 ? DejanjeMidi.naslednja : DejanjeMidi.prejsnja);
  }

  List<MidiGumb> get _gumbi => widget.baza.midi.gumbiZa(widget.pesem.id);

  void _pritisni(MidiGumb g) {
    final k = widget.baza.midi;
    Midi.aplikacija.poslji(k.razsiri(g.ukazi), knjiznica: k);
  }

  /// Api za branje (uvodi s strežnika); brez prijave null.
  Api? get _apiZaBranje => widget.prijava.prijavljen ? Api(widget.prijava.zeton) : null;

  void _uvod() {
    final k = widget.baza.midi;
    Midi.aplikacija.poslji(k.razsiri(_pesem.midiZaUvod), knjiznica: k);
  }

  /// Nožno stikalo: gumbi pesmi, uvod, iskalnik in premikanje po seznamu.
  bool _dejanje(DejanjeMidi d) {
    if (d.gumb > 0) {
      // Gumb na besedilu ali PDF-ju s to številko ima prednost pred gumbom v spodnji vrstici.
      if (NozniGumbi.sprozi(widget.pesem.id, d.gumb)) return true;
      final gumbi = _gumbi;
      if (d.gumb <= gumbi.length) _pritisni(gumbi[d.gumb - 1]);
      return true;
    }
    if (d == DejanjeMidi.uvod) {
      if (_pesem.midiZaUvod.isNotEmpty) _uvod();
      if (_pesem.uvod.isNotEmpty && Nastavitve.aplikacija.predvajajUvode) {
        Predvajanje.uvodi.predvajaj(widget.baza, _apiZaBranje, _pesem);
      }
      return true;
    }
    if (d.fx > 0) {
      final gumbi = widget.baza.fx.poVrsti(FxPrikaz.stran.value, widget.pesem.id);
      if (d.fx <= gumbi.length) ZvokSpila.aplikacija.fxKlik(gumbi[d.fx - 1].id);
      return true;
    }
    if (d == DejanjeMidi.fxUstavi) {
      ZvokSpila.aplikacija.fxUstaviVse();
      return true;
    }
    if (d == DejanjeMidi.playback) {
      if (_pesem.playback.isNotEmpty) ZvokSpila.aplikacija.preklopiPlayback(_pesem.id);
      return true;
    }
    if (_iskalnik) {
      final i = _iskalnikKljuc.currentState;
      switch (d) {
        case DejanjeMidi.gor || DejanjeMidi.prejsnja:
          i?.premakni(-1);
        case DejanjeMidi.dol || DejanjeMidi.naslednja:
          i?.premakni(1);
        case DejanjeMidi.potrdi:
          i?.potrdi();
        default:
          setState(() => _iskalnik = false);
      }
      return true;
    }
    if (d == DejanjeMidi.iskalnik) {
      setState(() => _iskalnik = true);
      return true;
    }
    // Gor in dol premikata besedilo ali PDF (tipkovnica, nožno stikalo).
    if (d == DejanjeMidi.gor || d == DejanjeMidi.dol) {
      Listanje.premakni(d == DejanjeMidi.gor ? -1 : 1);
      return true;
    }
    // Hitro urejanje: naprej in nazaj po vrstnem redu tabele.
    final seznam = widget.seznam;
    if (widget.hitroUrejanje &&
        widget.odpri == null &&
        seznam != null &&
        (d == DejanjeMidi.naslednja || d == DejanjeMidi.prejsnja)) {
      final i = seznam.indexWhere((p) => p.id == widget.pesem.id) + (d == DejanjeMidi.naslednja ? 1 : -1);
      if (i >= 0 && i < seznam.length) {
        _odpri(seznam[i], smer: d == DejanjeMidi.naslednja ? 1 : -1);
        return true;
      }
    }
    // Sledilec obrne pesem za vse (če je administrator to dovolil): vodja odpre pesem, vsi mu sledijo.
    if (widget.spil case final spil?
        when spil.vloga == VlogaSpila.sledilec &&
            widget.baza.obracaZaVse &&
            (d == DejanjeMidi.naslednja || d == DejanjeMidi.prejsnja || d == DejanjeMidi.izbrana)) {
      final id = d == DejanjeMidi.prejsnja ? spil.nazaj() : spil.prvaNaslednja()?.pesem;
      if (id != null && widget.baza.pesem(id) != null) {
        spil.zamenjajVsem(StanjeSpila(pesem: id));
        return true;
      }
    }
    // Izbrana pesem s seznamčka; v setlisti in pri sledenju (odpri je podan) naslednjo vodi zaslon okoli pesmi.
    final izbrana = widget.spil?.prvaNaslednja();
    if (izbrana != null &&
        (d == DejanjeMidi.izbrana || (d == DejanjeMidi.naslednja && widget.odpri == null)) &&
        widget.baza.pesem(izbrana.pesem) != null) {
      _odpri(widget.baza.pesem(izbrana.pesem)!, smer: 1);
      return true;
    }
    // Nazaj po pokazanih pesmih (tudi ko je čakalna vrsta že prazna); trenutna gre spet na začetek vrste.
    final spil = widget.spil;
    if (d == DejanjeMidi.prejsnja && spil != null && widget.odpri == null && spil.imaNazaj) {
      final p = widget.baza.pesem(spil.nazaj() ?? '');
      if (p != null) _odpri(p, smer: -1);
      return true;
    }
    // V setlisti naprej in nazaj vodi zaslon setliste.
    if (widget.odpri != null) return false;
    // Brez čakalne vrste, playliste ali setliste ni listanja po seznamu: drugo pesem izbereš v seznamu
    // (tako je jasno, kdaj je playliste konec).
    if (d == DejanjeMidi.naslednja || d == DejanjeMidi.prejsnja) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const ValueKey('konec-vrste'),
            duration: const Duration(seconds: 2),
            content: Text(
              d == DejanjeMidi.prejsnja
                  ? 'Ni prejšnje pesmi v čakalni vrsti.'
                  : 'Konec čakalne vrste. Naslednjo pesem izberi v iskalniku ali seznamu.',
            ),
          ),
        );
      return true;
    }
    return false;
  }

  /// Naslednja pesem za prikaz v vrstici: samo s čakalne vrste (prazna vrsta = nič).
  Pesem? get _naslednja {
    if (widget.naslednja case final n?) return n;
    if (widget.spil?.prvaNaslednja() case final n?) return widget.baza.pesem(n.pesem);
    return null;
  }

  // ---------- Pridržanje (risanje) in trojni dotik (klicaj) ----------

  void _dol(PointerDownEvent e) {
    // Vlečenje drsnika na besedilu ni pridržanje ne dotik.
    if (Vlecenje.kazalci.contains(e.pointer)) return;
    _dotiki[e.pointer] = e.position;
    _pridrzanje?.cancel();
    if (_dotiki.length > 1 || _risem || _iskalnik) return;
    final kje = e.position;
    _pridrzanje = Timer(const Duration(milliseconds: 550), () {
      _tapi.clear();
      HapticFeedback.mediumImpact();
      // Pridržanje na klicaju odpre podatke o njem, drugje vklopi risanje.
      if (_stran?.klicajPri(kje) case final k?) {
        _oknoKlicaja(k);
      } else if (Config.samoKlicaji) {
        // Neprijavljen sledilec zapiske samo vidi; klicaj doda s trojnim dotikom.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prek vodje so zapiski samo za branje. Klicaj dodaš s trojnim dotikom.')),
        );
      } else {
        _risanje.value = true;
      }
    });
  }

  void _premik(PointerMoveEvent e) {
    final z = _dotiki[e.pointer];
    if (z != null && (e.position - z).distance > 12) _pridrzanje?.cancel();
  }

  void _gor(PointerEvent e) {
    final z = _dotiki.remove(e.pointer);
    final kratek = _pridrzanje?.isActive ?? false;
    _pridrzanje?.cancel();
    if (!kratek || _risem || z == null || (e.position - z).distance > 12) {
      if (!kratek) _tapi.clear();
      return;
    }
    final klicaj = _tapi.isEmpty ? _stran?.klicajPri(e.position) : null;
    if (klicaj != null) {
      _kdoKlicaj(klicaj);
      return;
    }
    final zdaj = DateTime.now();
    if (_tapi.isNotEmpty &&
        (zdaj.difference(_tapi.last) > const Duration(milliseconds: 450) ||
            (e.position - (_zadnjiTap ?? e.position)).distance > 60)) {
      _tapi.clear();
    }
    _tapi.add(zdaj);
    _zadnjiTap = e.position;
    if (_tapi.length >= 3) {
      _tapi.clear();
      _dodajKlicaj(e.position);
    }
  }

  /// Rdeč klicaj (za ponoviti na vaji) na mestu trojnega dotika; doda ga kdorkoli, vidijo ga vsi.
  Future<void> _dodajKlicaj(Offset kje) async {
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.heavyImpact();
    final mesto = _stran?.naStrani(kje);
    final besedilo = _prikaziBesedilo && _besedila.isNotEmpty;
    final clan = Config.prekoVodje ? await clanNaSpilu() : null;
    await widget.baza.dodajKlicaj(
      apiZaKlicaje(widget.baza, widget.prijava),
      widget.pesem.id,
      // Brez mesta (npr. PDF se še nalaga) gre klicaj v desni zgornji kot.
      mesto?.stran ?? (besedilo ? BesediloZRisanjem.stran : 1),
      mesto?.tocka.dx ?? 0.9,
      mesto?.tocka.dy ?? 0.05,
      clan: clan,
    );
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('Klicaj za vajo: ${_pesem.naslov}. Pridrži ga za podatke ali brisanje.'),
      ),
    );
  }

  String _opisKlicaja(KlicajPesmi k) {
    final kdo = k.clan.isEmpty ? 'neznan član' : widget.baza.imeClanaZ(k.clan);
    final c = k.cas;
    String dv(int x) => x.toString().padLeft(2, '0');
    return c == null ? kdo : '$kdo, ${c.day}. ${c.month}. ${c.year} ob ${dv(c.hour)}:${dv(c.minute)}';
  }

  void _kdoKlicaj(KlicajPesmi k) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(duration: const Duration(seconds: 3), content: Text('Klicaj: ${_opisKlicaja(k)}')));

  /// Pridržan klicaj: kdo in kdaj ga je dodal, in brisanje.
  Future<void> _oknoKlicaja(KlicajPesmi k) async {
    final izbrisi = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Klicaj(velikost: 40),
        title: const Text('Za ponoviti na vaji'),
        content: Text('Dodal: ${_opisKlicaja(k)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Izbriši')),
          FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zapri')),
        ],
      ),
    );
    if (izbrisi != true) return;
    await widget.baza.izbrisiKlicaj(apiZaKlicaje(widget.baza, widget.prijava), k.id);
  }

  @override
  Widget build(BuildContext context) {
    return NaMidi(
      dejanje: _dejanje,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.baza, Midi.aplikacija, Nastavitve.aplikacija, ?widget.spil]),
        builder: (context, _) => _zaslon(context),
      ),
    );
  }

  Widget? _vrsticaGumbov(BuildContext context) {
    final gumbi = _gumbi;
    if (gumbi.isEmpty || !Midi.aplikacija.vklopljen) return null;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: [
            for (var i = 0; i < gumbi.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.tonal(
                  style: barvaGumba(gumbi[i].barva),
                  onPressed: () => _pritisni(gumbi[i]),
                  child: Text('${i + 1}  ${gumbi[i].ime}'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Vsebina z gestami: podrsaj na naslednjo ali prejšnjo pesem, pridržanje vklopi risanje,
  /// trojni dotik postavi klicaj. Klicaj je v desnem zgornjem kotu.
  Widget _vsebinaZGestami(BuildContext context) {
    return Listener(
      onPointerDown: _dol,
      onPointerMove: _premik,
      onPointerUp: _gor,
      onPointerCancel: _gor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: _risem ? null : _podrsaj,
        child: Stack(
          children: [
            Positioned.fill(child: _vsebina(context)),
            if (_klicajiDrugje case final n when n > 0)
              Positioned(
                top: 4,
                right: 12,
                child: Tooltip(
                  message: _prikaziBesedilo ? 'Klicaji na PDF-ju' : 'Klicaji na besedilu',
                  child: IgnorePointer(child: Klicaj(velikost: 28, stevilo: n)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Klicaji, ki niso na prikazanem (npr. na PDF-ju, ko je odprto besedilo).
  int get _klicajiDrugje {
    final besedilo = _prikaziBesedilo && _besedila.isNotEmpty;
    final prikazan = besedilo || _pdfji.isNotEmpty;
    return _klicaji.where((k) => !prikazan || (k.stran == BesediloZRisanjem.stran) != besedilo).length;
  }

  Widget _telo(BuildContext context) {
    final oblacek = _oblacekTonalitete(context);
    if (!_iskalnik) {
      return oblacek == null ? _vsebinaZGestami(context) : Stack(children: [_vsebinaZGestami(context), oblacek]);
    }
    return LayoutBuilder(
      builder: (context, meje) => Stack(
        children: [
          _vsebinaZGestami(context),
          ?oblacek,
          // Dotik mimo iskalnika ga zapre.
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _iskalnik = false)),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            width: (meje.maxWidth - 32).clamp(0, 400).toDouble(),
            height: (meje.maxHeight * 0.6).clamp(0, 520).toDouble(),
            child: IskalnikPesmi(
              key: _iskalnikKljuc,
              baza: widget.baza,
              pesmi: _pesmiIskalnika,
              playlista: widget.playlista == null
                  ? null
                  : {
                      for (final e in widget.playlista!.entries)
                        if (_seNaVrsti(e.key)) e.key: e.value,
                    },
              pavza: _pavza,
              vVrsti: {for (final (i, n) in (widget.spil?.naslednje ?? const <Naslednja>[]).indexed) n.pesem: i + 1},
              trenutna: widget.pesem,
              odpri: _izIskalnika,
              pridrzi: (p) => _izIskalnika(p, naPrvo: true),
              zapri: () => setState(() => _iskalnik = false),
            ),
          ),
        ],
      ),
    );
  }

  /// Gumbi in prikazi na [mesto] (zgoraj ali v spodnji vrstici), kot so izbrani v nastavitvah.
  List<Widget> _orodja(BuildContext context, Mesto mesto) {
    final p = _pesem;
    final besedilo = _prikaziBesedilo && _besedila.isNotEmpty;
    return [
      for (final o in Nastavitve.aplikacija.orodjaNa(mesto))
        ...switch (o) {
          Orodje.spil => [
            if (widget.spil case final spil?) SpilGumb(spil: spil, baza: widget.baza, prijava: widget.prijava),
          ],
          Orodje.bluetooth => [BluetoothIkona(baza: widget.baza)],
          Orodje.midi => [const MidiLucki()],
          Orodje.runda => [RundaGumb(baza: widget.baza)],
          Orodje.pisava when besedilo && !Config.prekoVodje && widget.baza.smeUrejatiPesem(_pesem) => [
            IconButton(
              tooltip: 'Manjša pisava',
              icon: const Icon(Icons.text_decrease),
              onPressed: () => _spremeniPisavo(-2),
            ),
            IconButton(
              tooltip: 'Večja pisava',
              icon: const Icon(Icons.text_increase),
              onPressed: () => _spremeniPisavo(2),
            ),
          ],
          Orodje.pdf when _besedila.isNotEmpty && _pdfji.isNotEmpty => [
            IconButton(
              tooltip: _prikaziBesedilo ? 'Pokaži PDF' : 'Pokaži besedilo',
              icon: Icon(_prikaziBesedilo ? Icons.picture_as_pdf : Icons.notes),
              onPressed: () => setState(() {
                _prikaziBesedilo = !_prikaziBesedilo;
                _risanje.value = false;
              }),
            ),
          ],
          Orodje.uredi when widget.baza.smeUrejatiPesem(p) => [
            IconButton(
              tooltip: 'Uredi pesem',
              icon: const Icon(Icons.edit_note),
              // Ko je na zaslonu besedilo, se urejanje odpre pri besedilu.
              onPressed: () => _uredi(zavihek: besedilo ? UrejanjePesmiZaslon.zavihekBesedila : 0),
            ),
          ],
          Orodje.ura => [const Ura()],
          Orodje.xyPad
              when widget.baza.fx.gumbi.isNotEmpty ||
                  (widget.baza.fx.xy?.nastavljen ?? false) ||
                  widget.baza.jeAdministrator =>
            [const FxGumb()],
          Orodje.uvodi
              when Midi.aplikacija.vklopljen ||
                  Nastavitve.aplikacija.predvajajUvode ||
                  ZvokSpila.aplikacija.lahkoPlayback =>
            [
              // Uho je skupno vsem na špilu; modro, dokler kakšna naprava predvaja uvod te pesmi.
              ListenableBuilder(
                listenable: ZvokSpila.aplikacija,
                builder: (context, _) {
                  final igra = ZvokSpila.aplikacija.uvod == widget.pesem.id;
                  return IconButton(
                    key: const ValueKey('uvodi'),
                    tooltip: igra
                        ? 'Uvod se predvaja'
                        : Nastavitve.aplikacija.uvodi
                        ? 'Uvodi vklopljeni: MIDI in zvočni uvod ob odprtju pesmi'
                        : 'Uvodi izklopljeni',
                    isSelected: Nastavitve.aplikacija.uvodi,
                    icon: const Icon(Icons.hearing_disabled),
                    selectedIcon: Icon(Icons.hearing, color: igra ? Colors.blue : null),
                    onPressed: () => ZvokSpila.aplikacija.nastaviUho(!Nastavitve.aplikacija.uvodi),
                  );
                },
              ),
            ],
          Orodje.playback when _pesem.playback.isNotEmpty && ZvokSpila.aplikacija.lahkoPlayback => [
            ListenableBuilder(
              listenable: ZvokSpila.aplikacija,
              builder: (context, _) {
                final igra = ZvokSpila.aplikacija.playback == widget.pesem.id;
                return IconButton(
                  key: const ValueKey('playback'),
                  tooltip: igra ? 'Ustavi playback' : 'Predvajaj playback',
                  icon: Icon(igra ? Icons.stop_circle : Icons.play_circle, color: igra ? Colors.blue : null),
                  onPressed: () => ZvokSpila.aplikacija.preklopiPlayback(widget.pesem.id),
                );
              },
            ),
          ],
          Orodje.youtube when _pesem.youtubeId != null => [
            IconButton(
              key: const ValueKey('youtube'),
              tooltip: YoutubePesmi.vAplikaciji ? 'YouTube' : 'Odpri v YouTube',
              isSelected: _youtube == widget.pesem.id,
              icon: const Icon(Icons.smart_display_outlined),
              selectedIcon: const Icon(Icons.smart_display, color: Colors.blue),
              onPressed: () {
                final p = _pesem;
                if (!YoutubePesmi.vAplikaciji && YoutubePesmi.predvajalnikZaTest == null) {
                  YoutubePesmi.odpriZunaj(p.youtube, p.youtubeId!);
                  return;
                }
                setState(() => _youtube = _youtube == p.id ? null : p.id);
              },
            ),
          ],
          _ => const <Widget>[],
        },
    ];
  }

  /// Podatek v enem od treh delov vrstice nad ali pod pesmijo; null, če ga ni (prazen del).
  Widget? _info(
    BuildContext context,
    InfoVrstice v,
    TextAlign poravnava, {
    TextStyle? slog,
    TextStyle? slogTonalitete,
    int vrstic = 1,
  }) {
    final p = _pesem;
    final tonaliteta = slogTonalitete ?? slog;
    Widget? napis(String s, {Color? barva}) => s.isEmpty
        ? null
        : Text(
            s,
            textAlign: poravnava,
            maxLines: vrstic,
            overflow: TextOverflow.ellipsis,
            style: (slog ?? const TextStyle()).copyWith(
              color: barva,
              fontWeight: barva != null ? FontWeight.bold : null,
            ),
          );
    final harmonika = barvaHarmonike(widget.baza, p.harmonika);
    final Widget? vsebina = switch (v) {
      InfoVrstice.nic => null,
      InfoVrstice.naslov => napis(p.naslov),
      InfoVrstice.izvajalec => napis(p.izvajalec),
      InfoVrstice.avtorji => napis({p.avtorGlasbe, p.avtorBesedila}.where((x) => x.isNotEmpty).join(' / ')),
      InfoVrstice.tonaliteta when p.tonaliteta.isEmpty => null,
      InfoVrstice.tonaliteta => Text(p.tonaliteta, textAlign: poravnava, maxLines: 1, style: tonaliteta),
      InfoVrstice.harmonika => napis(p.harmonika, barva: harmonika),
      InfoVrstice.tonalitetaHarmonika when p.tonaliteta.isEmpty && p.harmonika.isEmpty => null,
      InfoVrstice.tonalitetaHarmonika => Text.rich(
        TextSpan(
          children: [
            TextSpan(text: p.tonaliteta, style: tonaliteta),
            if (p.tonaliteta.isNotEmpty && p.harmonika.isNotEmpty) const TextSpan(text: ' · '),
            TextSpan(
              text: p.harmonika,
              style: TextStyle(color: harmonika, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        textAlign: poravnava,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: slog,
      ),
      InfoVrstice.vrsta => napis(p.vrsta, barva: barvaVrste(widget.baza, p.vrsta)),
      InfoVrstice.tempo => napis(PoljePesmi.tempo.vrednost(p).isEmpty ? '' : '${PoljePesmi.tempo.vrednost(p)} BPM'),
      InfoVrstice.trajanje => napis(PoljePesmi.trajanje.vrednost(p)),
      InfoVrstice.ocena => p.ocena == 0 ? null : Zvezdice(ocena: p.ocena),
      InfoVrstice.status => Row(
        mainAxisSize: MainAxisSize.min,
        children: [IkonaStatusa(p.status), const SizedBox(width: 4), Text(p.status.ime)],
      ),
      InfoVrstice.opombe => napis(besedilo(p.vrstica['Opombe'])),
      InfoVrstice.naslednja => switch (_naslednja) {
        final n? => napis(
          '→ ${napisVrste(n)}',
          barva: menjaHarmoniko(p, n) ? barvaHarmonike(widget.baza, n.harmonika) : null,
        ),
        // Konec čakalne vrste (ali je ni): opozorilo, da naslednja ni izbrana.
        null => napis('→ ni izbrane', barva: Colors.orange),
      },
      InfoVrstice.ura => const Ura(),
      InfoVrstice.runda => const CasRunde(),
    };
    if (vsebina == null) return null;
    return Align(
      alignment: switch (poravnava) {
        TextAlign.left => Alignment.centerLeft,
        TextAlign.right => Alignment.centerRight,
        _ => Alignment.center,
      },
      child: vsebina,
    );
  }

  /// Trije deli s podatki; prazni deli se umaknejo, kratki vzamejo svojo širino, dolgi (naslov …) preostanek.
  List<Widget> _deliVrstice(
    BuildContext context,
    List<InfoVrstice> deli, {
    TextStyle? slog,
    TextStyle? slogTonalitete,
    int vrstic = 1,
  }) {
    final polni = [
      for (final (i, poravnava) in [(0, TextAlign.left), (1, TextAlign.center), (2, TextAlign.right)])
        if (_info(
              context,
              deli[i],
              poravnava,
              slog: slog,
              slogTonalitete: slogTonalitete,
              vrstic: deli[i].dolg ? vrstic : 1,
            )
            case final w?)
          (deli[i], w),
    ];
    // Brez dolgega dela si kratki razdelijo širino enakomerno (levo, sredina, desno).
    final imaDolg = polni.any((d) => d.$1.dolg);
    return [
      for (final (v, w) in polni) ...[
        if (!imaDolg || v.dolg) Expanded(child: w) else Flexible(child: w),
        const SizedBox(width: 12),
      ],
      if (polni.isEmpty) const Spacer(),
    ];
  }

  /// Besedilo daljšega dela vrstice (za oceno, ali gre v eno vrstico).
  String _besediloDela(InfoVrstice v) {
    final p = _pesem;
    return switch (v) {
      InfoVrstice.naslov => p.naslov,
      InfoVrstice.izvajalec => p.izvajalec,
      InfoVrstice.avtorji => '${p.avtorGlasbe} / ${p.avtorBesedila}',
      InfoVrstice.opombe => besedilo(p.vrstica['Opombe']),
      InfoVrstice.naslednja => _naslednja == null ? '→ ni izbrane' : '→ ${napisVrste(_naslednja!)}',
      _ => '',
    };
  }

  /// Vrstica pod orodno vrstico (npr. naslov in tonaliteta); null, če so vsi deli prazni.
  /// Dolg naslov (npr. na telefonu) gre v dve vrstici. Barvo si vsak nastavi sam.
  PreferredSizeWidget? _zgornjaVrstica(BuildContext context) {
    final n = Nastavitve.aplikacija;
    final deli = n.zgoraj;
    if (deli.every((d) => d == InfoVrstice.nic)) return null;
    final tema = Theme.of(context);
    final ozadje = n.barvaZgoraj == null ? null : Color(n.barvaZgoraj!);
    final crke = ozadje == null ? null : kontrastnaBarva(ozadje);
    final slog = tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: crke);
    // Kratki deli vzamejo okoli 90 točk, ostalo si razdelijo dolgi.
    final dolgi = [
      for (final d in deli)
        if (d.dolg) _besediloDela(d),
    ].where((x) => x.isNotEmpty).toList();
    final kratkih = deli.where((d) => d != InfoVrstice.nic && !d.dolg).length;
    final prostor = (MediaQuery.sizeOf(context).width - 32 - kratkih * 90) / (dolgi.isEmpty ? 1 : dolgi.length);
    final dveVrstici = dolgi.any((t) => sirinaBesedila(t, slog) > prostor);
    final visina = dveVrstici ? 64.0 : 44.0;
    return PreferredSize(
      preferredSize: Size.fromHeight(visina),
      child: Container(
        height: visina,
        color: ozadje,
        child: Row(
          children: [
            const SizedBox(width: 16),
            ..._deliVrstice(
              context,
              deli,
              slog: slog,
              vrstic: dveVrstici ? 2 : 1,
              slogTonalitete: tema.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: ozadje == null ? tema.colorScheme.primary : crke,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  /// Oblački v zgornjem levem in desnem kotu pesmi (nastavitve), zloženi navzdol; brez podatka se skrijejo.
  Widget? _oblacekTonalitete(BuildContext context) {
    final oblacki = Nastavitve.aplikacija.oblacki;
    if (oblacki.isEmpty || _risem) return null;
    final tema = Theme.of(context);
    Widget? oblacek(Oblacek o) {
      final ozadje = o.barva == null ? tema.colorScheme.primaryContainer : Color(o.barva!);
      final crke = o.barva == null ? tema.colorScheme.onPrimaryContainer : kontrastnaBarva(ozadje);
      final slog = TextStyle(fontSize: const [15.0, 22.0, 30.0][o.velikost], fontWeight: FontWeight.w900, color: crke);
      var w = _info(context, o.vsebina, TextAlign.center, slog: slog);
      if (w == null) return null;
      if (w is Align) w = w.child!;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: ozadje.withValues(alpha: 0.92),
          elevation: 3,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0 + 2 * o.velikost, vertical: 2.0 + 2 * o.velikost),
            child: DefaultTextStyle.merge(
              style: slog,
              child: IconTheme.merge(
                data: IconThemeData(color: crke),
                child: w,
              ),
            ),
          ),
        ),
      );
    }

    Widget? stolpec(bool levo) {
      final deli = [for (final o in oblacki.where((o) => o.levo == levo)) ?oblacek(o)];
      if (deli.isEmpty) return null;
      return Positioned(
        key: ValueKey(levo ? 'oblacki-levo' : 'oblacki-desno'),
        top: 8,
        left: levo ? 8 : null,
        right: levo ? null : 8,
        child: IgnorePointer(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Column(
              crossAxisAlignment: levo ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: deli,
            ),
          ),
        ),
      );
    }

    final l = stolpec(true);
    final d = stolpec(false);
    if (l == null && d == null) return null;
    return Positioned.fill(child: Stack(children: [?l, ?d]));
  }

  /// Spodnja vrstica: trije deli s podatki, orodja »spodaj« in vedno iskanje v desnem vogalu.
  Widget _spodnjaVrstica(BuildContext context) {
    final n = Nastavitve.aplikacija;
    final deli = n.spodaj;
    final ozadje = n.barvaSpodaj == null ? null : Color(n.barvaSpodaj!);
    final crke = ozadje == null ? null : kontrastnaBarva(ozadje);
    return Material(
      color: ozadje ?? Theme.of(context).colorScheme.surfaceContainer,
      textStyle: crke == null ? null : TextStyle(color: crke),
      child: SafeArea(
        top: false,
        bottom: widget.spodaj == null,
        child: SizedBox(
          height: 48,
          child: IconTheme.merge(
            data: IconThemeData(color: crke),
            child: Row(
              children: [
                const SizedBox(width: 12),
                ..._deliVrstice(
                  context,
                  deli,
                  slog: crke == null ? null : DefaultTextStyle.of(context).style.copyWith(color: crke),
                ),
                ..._orodja(context, Mesto.spodaj),
                IconButton(
                  tooltip: 'Išči pesem',
                  isSelected: _iskalnik,
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() => _iskalnik = !_iskalnik),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _zaslon(BuildContext context) {
    final p = _pesem;
    return Scaffold(
      appBar: AppBar(
        // Naslov je v vrstici pod orodno vrstico, če je izbran tam; zgoraj ostane prostor za orodja.
        title: Row(
          children: [
            OznakePesmi(pesem: p),
            if (!Nastavitve.aplikacija.zgoraj.contains(InfoVrstice.naslov))
              Flexible(child: Text(p.naslov, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          if (_neshranjenZoom)
            IconButton(
              tooltip: _novaPisava != null ? 'Shrani pisavo pesmi za vse' : 'Shrani povečavo za to pesem',
              icon: const Icon(Icons.save_outlined),
              onPressed: _shraniZoom,
            ),
          // Pesem ima posnetke ali je bila igrana na špilih: do njih tudi brez risanja.
          if (_posnetki != null &&
              ((widget.baza.posnetki[p.id]?.isNotEmpty ?? false) || (widget.baza.igranja[p.id]?.isNotEmpty ?? false)))
            IconButton(
              tooltip: 'Posnetki',
              icon: Badge.count(
                count: widget.baza.posnetki[p.id]?.length ?? 0,
                isLabelVisible: widget.baza.posnetki[p.id]?.isNotEmpty ?? false,
                child: const Icon(Icons.mic_none),
              ),
              onPressed: () => _posnetki!(false),
            ),
          ..._orodja(context, Mesto.zgoraj),
          const SizedBox(width: 4),
        ],
        bottom: _zgornjaVrstica(context),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: FxOkvir(baza: widget.baza, api: () => _apiZaBranje, pesem: widget.pesem.id, child: _telo(context)),
          ),
          if (_youtube == widget.pesem.id && _pesem.youtubeId != null)
            Positioned(
              right: 8,
              bottom: 8,
              child: YoutubeOkno(
                key: ValueKey('youtube-${_pesem.youtubeId}'),
                id: _pesem.youtubeId!,
                povezava: _pesem.youtube,
                zapri: () => setState(() => _youtube = null),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?vrsticaNaslednjih(context, widget.spil, widget.baza, _odpri, trenutna: p),
          ?_vrsticaGumbov(context),
          if (!_risem) _spodnjaVrstica(context),
          ?widget.spodaj,
        ],
      ),
    );
  }

  Widget _vsebina(BuildContext context) {
    if (_prikaziBesedilo && _besedila.isNotEmpty) {
      return BesediloZRisanjem(
        key: _vsebinaKljuc,
        vsebina: _besedila.first.vsebina,
        pisava: _pisava,
        pesem: widget.pesem.id,
        risbe: widget.baza.risbe,
        risanje: _risanje,
        knjiznica: widget.baza.midi,
        klicaji: _klicaji,
        risbeSkupne: widget.baza.risbeSkupne,
        smeSkupno: _smeSkupno,
        zacniSkupno: widget.hitroUrejanje,
        posnetki: _posnetki,
        vrsticaPlaybacka: _vrsticaPlaybacka,
      );
    }
    if (_pdfji.isNotEmpty) {
      if (!_pdfPrebran) return const Center(child: CircularProgressIndicator());
      final pdf = _pdf;
      if (pdf == null) {
        return const Center(child: Text('PDF še ni prenesen. Osveži iz baze, ko imaš internet.'));
      }
      return PdfZRisanjem(
        key: _vsebinaKljuc,
        pdf: pdf,
        ime: _pdfji.first.driveId,
        pesem: widget.pesem.id,
        risbe: widget.baza.risbe,
        risanje: _risanje,
        knjiznica: widget.baza.midi,
        klicaji: _klicaji,
        risbeSkupne: widget.baza.risbeSkupne,
        smeSkupno: _smeSkupno,
        zacniSkupno: widget.hitroUrejanje,
        posnetki: _posnetki,
        obPovecavi: (z) => setState(() => _novaPdf = (z,)),
      );
    }
    if (widget.baza.smeUrejatiPesem(_pesem)) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => _uredi(zavihek: UrejanjePesmiZaslon.zavihekBesedila),
          icon: const Icon(Icons.add),
          label: const Text('Dodaj besedilo'),
        ),
      );
    }
    return const Center(child: Text('Ta pesem še nima besedila ali PDF-ja.'));
  }
}

/// Besedilo z akordi nad zlogi, ki jim pripadajo.
class BesediloPogled extends StatelessWidget {
  const BesediloPogled({super.key, required this.vsebina, required this.velikost});

  final String vsebina;
  final double velikost;

  /// Kosi vrstice in ali je kos na začetku krepek (krepko se lahko začne v enem kosu in konča v drugem).
  static List<(cp.Kos, bool)> _krepkoPoKosih(List<cp.Kos> kosi) {
    final out = <(cp.Kos, bool)>[];
    var k = false;
    for (final kos in kosi) {
      out.add((kos, k));
      k = cp.deliKrepko(kos.besedilo, krepko: k).$2;
    }
    return out;
  }

  /// Besedilo z deli **krepko** kot krepkim slogom.
  static TextSpan _krepkiDeli(String s, TextStyle slog, bool krepko) => TextSpan(
    style: slog,
    children: [
      for (final (t, k) in cp.deliKrepko(s, krepko: krepko).$1)
        TextSpan(
          text: t,
          style: k ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
    ],
  );

  /// Vrstice besedila z akordi nad zlogi (za seznam ali za stran z risbami).
  static List<Widget> vrstice(BuildContext context, String vsebina, double velikost) {
    final barve = Theme.of(context).colorScheme;
    final besedilo = TextStyle(fontSize: velikost, height: 1.25);
    final akord = TextStyle(fontSize: velikost * 0.8, fontWeight: FontWeight.bold, color: barve.primary);
    final akordi = Nastavitve.aplikacija.akordi;
    final komentar = TextStyle(fontSize: velikost * 0.8, fontStyle: FontStyle.italic, color: barve.secondary);
    return [
      for (final v in cp.razcleni(vsebina))
        switch (v.vrsta) {
          cp.VrstaVrstice.prazna => SizedBox(height: velikost * 0.8),
          cp.VrstaVrstice.komentar => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(v.komentar, style: komentar),
          ),
          cp.VrstaVrstice.besedilo =>
            v.imaAkorde && akordi
                ? Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      for (final (k, krepkoNaZacetku) in _krepkoPoKosih(v.kosi))
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Presledek za akordom, da se sosednja akorda ne zlepita.
                            Text(k.akord.isEmpty ? ' ' : '${k.akord} ', style: akord),
                            Text.rich(_krepkiDeli(k.besedilo, besedilo, krepkoNaZacetku)),
                          ],
                        ),
                    ],
                  )
                : Text.rich(_krepkiDeli(v.kosi.map((k) => k.besedilo).join(), besedilo, false)),
        },
    ];
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: vrstice(context, vsebina, velikost));
}
