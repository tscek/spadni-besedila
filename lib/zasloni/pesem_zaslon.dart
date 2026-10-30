import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../baza.dart';
import '../chordpro.dart' as cp;
import '../config.dart';
import '../midi/midi.dart';
import '../midi/ukazi.dart';
import '../models.dart';
import '../nastavitve.dart';
import '../odigrane.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'besedilo_risanje.dart';
import 'iskalnik_pesmi.dart';
import 'midi_zaslon.dart';
import 'naslednje.dart';
import 'orodja.dart';
import 'oznake.dart';
import 'pdf_risanje.dart';
import 'prehod.dart';
import 'spil_zaslon.dart';
import 'urejanje_pesmi.dart';

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
    this.izIskalnika,
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

  /// Kaj naredi dotik pesmi v iskalniku (npr. v playlisti); privzeto gre pesem v čakalno vrsto.
  final void Function(Pesem)? izIskalnika;

  @override
  State<PesemZaslon> createState() => _PesemZaslonState();
}

class _PesemZaslonState extends State<PesemZaslon> {
  double get _pisava => Nastavitve.aplikacija.pisava;
  bool _prikaziBesedilo = true;
  Uint8List? _pdf;
  bool _pdfPrebran = false;
  bool _iskalnik = false;

  /// Risanje vklopi pridržanje na pesmi; med risanjem ni gest (podrsaj, trojni dotik).
  final _risanje = ValueNotifier(false);
  bool get _risem => _risanje.value;
  final _iskalnikKljuc = GlobalKey<IskalnikPesmiState>();

  /// Ko je pesem dovolj dolgo odprta, se označi kot odigrana.
  Timer? _odigrana;

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
      Midi.aplikacija.odprta(_pesem, widget.baza.midi);
    });
    final minute = Nastavitve.aplikacija.minuteOdigrane;
    if (minute > 0) {
      _odigrana = Timer(Duration(minutes: minute), () => Odigrane.aplikacija.oznaci(widget.pesem.id));
    }
    _naloziPdf();
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
    _risanje.dispose();
    Midi.aplikacija.zaprta(_pesem);
    super.dispose();
  }

  Future<void> _spremeniPisavo(double d) => Nastavitve.aplikacija.nastaviPisavo(_pisava + d);

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

  /// Pesmi v iskalniku: najprej prednostne (playlista), nato ostale iz mape.
  List<Pesem> get _pesmiIskalnika {
    final mapa = widget.mapa ?? _pesem.mapa;
    final vMapi = widget.baza.pesmiMape(mapa == PesemZaslon.vse ? null : mapa);
    final prednostne = widget.prednostne ?? const <Pesem>[];
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

  void _uvod() {
    final k = widget.baza.midi;
    Midi.aplikacija.poslji(k.razsiri(_pesem.midiZaUvod), knjiznica: k);
  }

  /// Nožno stikalo: gumbi pesmi, uvod, iskalnik in premikanje po seznamu.
  bool _dejanje(DejanjeMidi d) {
    if (d.gumb > 0) {
      final gumbi = _gumbi;
      if (d.gumb <= gumbi.length) _pritisni(gumbi[d.gumb - 1]);
      return true;
    }
    if (d == DejanjeMidi.uvod) {
      if (_pesem.midiZaUvod.isNotEmpty) _uvod();
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
    // Izbrana pesem s seznamčka; v setlisti in pri sledenju (odpri je podan) naslednjo vodi zaslon okoli pesmi.
    final izbrana = widget.spil?.prvaNaslednja();
    if (izbrana != null &&
        (d == DejanjeMidi.izbrana || (d == DejanjeMidi.naslednja && widget.odpri == null)) &&
        widget.baza.pesem(izbrana.pesem) != null) {
      _odpri(widget.baza.pesem(izbrana.pesem)!, smer: 1);
      return true;
    }
    final seznam = widget.seznam;
    if (seznam != null && (d == DejanjeMidi.naslednja || d == DejanjeMidi.prejsnja)) {
      final i = seznam.indexWhere((p) => p.id == widget.pesem.id) + (d == DejanjeMidi.naslednja ? 1 : -1);
      if (i >= 0 && i < seznam.length) _odpri(seznam[i], smer: d == DejanjeMidi.naslednja ? 1 : -1);
      return true;
    }
    return false;
  }

  /// Naslednja pesem za prikaz spodaj: s čakalne vrste ali s seznama.
  Pesem? get _naslednja {
    if (widget.spil?.prvaNaslednja() case final n?) return widget.baza.pesem(n.pesem);
    final seznam = widget.seznam;
    if (seznam == null) return null;
    final i = seznam.indexWhere((p) => p.id == widget.pesem.id) + 1;
    return i > 0 && i < seznam.length ? seznam[i] : null;
  }

  // ---------- Pridržanje (risanje) in trojni dotik (klicaj) ----------

  void _dol(PointerDownEvent e) {
    _dotiki[e.pointer] = e.position;
    _pridrzanje?.cancel();
    if (_dotiki.length > 1 || _risem || _iskalnik) return;
    _pridrzanje = Timer(const Duration(milliseconds: 550), () {
      _tapi.clear();
      HapticFeedback.mediumImpact();
      _risanje.value = true;
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
      _preklopiKlicaj();
    }
  }

  /// Rdeč klicaj (za ponoviti na vaji) vklopi ali izklopi kdorkoli; vidijo ga vsi.
  Future<void> _preklopiKlicaj() async {
    final messenger = ScaffoldMessenger.of(context);
    final nova = !_pesem.zaVajo;
    HapticFeedback.heavyImpact();
    final Api? api = Config.prekoVodje
        ? widget.baza.risbe.api
        : widget.prijava.prijavljen
        ? Api(widget.prijava.zeton)
        : null;
    try {
      await widget.baza.nastaviZaVajo(api, widget.pesem.id, nova);
    } catch (_) {
      // ostane med neposlanimi
    }
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(nova ? 'Označeno za vajo: ${_pesem.naslov}' : 'Klicaj odstranjen'),
      ),
    );
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
    final uvod = _pesem.midiZaUvod.isNotEmpty;
    if ((gumbi.isEmpty && !uvod) || !Midi.aplikacija.vklopljen) return null;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: [
            if (uvod)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: _uvod,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Uvod'),
                ),
              ),
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
            if (_pesem.zaVajo) const Positioned(top: 4, right: 12, child: IgnorePointer(child: Klicaj(velikost: 44))),
          ],
        ),
      ),
    );
  }

  Widget _telo(BuildContext context) {
    if (!_iskalnik) return _vsebinaZGestami(context);
    return LayoutBuilder(
      builder: (context, meje) => Stack(
        children: [
          _vsebinaZGestami(context),
          Positioned(
            right: 16,
            bottom: 16,
            width: (meje.maxWidth - 32).clamp(0, 400).toDouble(),
            height: (meje.maxHeight * 0.6).clamp(0, 520).toDouble(),
            child: IskalnikPesmi(
              key: _iskalnikKljuc,
              pesmi: _pesmiIskalnika,
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
          Orodje.pisava when besedilo => [
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
          _ => const <Widget>[],
        },
    ];
  }

  /// Podatek v enem od treh delov spodnje vrstice.
  Widget _info(BuildContext context, InfoVrstice v, TextAlign poravnava) {
    final p = _pesem;
    Widget napis(String s, {Color? barva}) => Text(
      s,
      textAlign: poravnava,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: barva, fontWeight: barva != null ? FontWeight.bold : null),
    );
    final harmonika = barvaHarmonike(widget.baza, p.harmonika);
    final vsebina = switch (v) {
      InfoVrstice.nic => const SizedBox.shrink(),
      InfoVrstice.naslov => napis(p.naslov),
      InfoVrstice.izvajalec => napis(p.izvajalec),
      InfoVrstice.avtorji => napis({p.avtorGlasbe, p.avtorBesedila}.where((x) => x.isNotEmpty).join(' / ')),
      InfoVrstice.tonaliteta => napis(p.tonaliteta),
      InfoVrstice.harmonika => napis(p.harmonika, barva: harmonika),
      InfoVrstice.tonalitetaHarmonika => Text.rich(
        TextSpan(
          children: [
            TextSpan(text: p.tonaliteta),
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
      ),
      InfoVrstice.vrsta => napis(p.vrsta),
      InfoVrstice.tempo => napis(PoljePesmi.tempo.vrednost(p).isEmpty ? '' : '${PoljePesmi.tempo.vrednost(p)} BPM'),
      InfoVrstice.trajanje => napis(PoljePesmi.trajanje.vrednost(p)),
      InfoVrstice.ocena => Zvezdice(ocena: p.ocena),
      InfoVrstice.status => Row(
        mainAxisSize: MainAxisSize.min,
        children: [IkonaStatusa(p.status), const SizedBox(width: 4), Text(p.status.ime)],
      ),
      InfoVrstice.opombe => napis(besedilo(p.vrstica['Opombe'])),
      InfoVrstice.naslednja => switch (_naslednja) {
        final n? => napis(
          'Naslednja: ${napisVrste(n)}',
          barva: menjaHarmoniko(p, n) ? barvaHarmonike(widget.baza, n.harmonika) : null,
        ),
        null => const SizedBox.shrink(),
      },
      InfoVrstice.ura => const Ura(),
      InfoVrstice.runda => const CasRunde(),
    };
    return Align(
      alignment: switch (poravnava) {
        TextAlign.left => Alignment.centerLeft,
        TextAlign.right => Alignment.centerRight,
        _ => Alignment.center,
      },
      child: vsebina,
    );
  }

  /// Spodnja vrstica: trije deli s podatki, orodja »spodaj« in vedno iskanje v desnem vogalu.
  Widget _spodnjaVrstica(BuildContext context) {
    final deli = Nastavitve.aplikacija.spodaj;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        bottom: widget.spodaj == null,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 12),
              for (final (i, poravnava) in [(0, TextAlign.left), (1, TextAlign.center), (2, TextAlign.right)]) ...[
                Expanded(child: _info(context, deli[i], poravnava)),
                const SizedBox(width: 8),
              ],
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
    );
  }

  Widget _zaslon(BuildContext context) {
    final p = _pesem;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            OznakePesmi(pesem: p),
            Flexible(child: Text(p.naslov, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [..._orodja(context, Mesto.zgoraj), const SizedBox(width: 4)],
      ),
      body: _telo(context),
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
        vsebina: _besedila.first.vsebina,
        povecava: _pisava / BesediloZRisanjem.osnovnaPisava,
        pesem: widget.pesem.id,
        risbe: widget.baza.risbe,
        risanje: _risanje,
        knjiznica: widget.baza.midi,
        obPovecavi: (v) => Nastavitve.aplikacija.nastaviPisavo(v * BesediloZRisanjem.osnovnaPisava),
      );
    }
    if (_pdfji.isNotEmpty) {
      if (!_pdfPrebran) return const Center(child: CircularProgressIndicator());
      final pdf = _pdf;
      if (pdf == null) {
        return const Center(child: Text('PDF še ni prenesen. Osveži iz baze, ko imaš internet.'));
      }
      return PdfZRisanjem(
        key: ValueKey(_pdfji.first.driveId),
        pdf: pdf,
        ime: _pdfji.first.driveId,
        pesem: widget.pesem.id,
        risbe: widget.baza.risbe,
        risanje: _risanje,
        knjiznica: widget.baza.midi,
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
                      for (final k in v.kosi)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Presledek za akordom, da se sosednja akorda ne zlepita.
                            Text(k.akord.isEmpty ? ' ' : '${k.akord} ', style: akord),
                            Text(k.besedilo, style: besedilo),
                          ],
                        ),
                    ],
                  )
                : Text(v.kosi.map((k) => k.besedilo).join(), style: besedilo),
        },
    ];
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: vrstice(context, vsebina, velikost));
}
