import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../baza.dart';
import '../chordpro.dart' as cp;
import '../midi/midi.dart';
import '../midi/ukazi.dart';
import '../models.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'besedilo_risanje.dart';
import 'iskalnik_pesmi.dart';
import 'midi_zaslon.dart';
import 'naslednje.dart';
import 'pdf_risanje.dart';
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
  });

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

  @override
  State<PesemZaslon> createState() => _PesemZaslonState();
}

class _PesemZaslonState extends State<PesemZaslon> {
  static const _kljucPisave = 'velikost_pisave';
  double _pisava = 22;
  bool _prikaziBesedilo = true;
  Uint8List? _pdf;
  bool _pdfPrebran = false;
  bool _iskalnik = false;
  final _iskalnikKljuc = GlobalKey<IskalnikPesmiState>();

  /// Trenutni podatki pesmi iz baze (po urejanju se spremenijo).
  Pesem get _pesem => widget.baza.pesmi.where((p) => p.id == widget.pesem.id).firstOrNull ?? widget.pesem;
  List<BesediloPesmi> get _besedila => widget.baza.besedilaPesmi[widget.pesem.id] ?? const [];
  List<PdfDatoteka> get _pdfji => widget.baza.pdfjiPesmi[widget.pesem.id] ?? const [];

  @override
  void initState() {
    super.initState();
    _prikaziBesedilo = _besedila.isNotEmpty;
    // Po prvem izrisu, da obvestilo ne pride sredi gradnje zaslonov.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.spil?.prikazujem(widget.stanje ?? StanjeSpila(pesem: widget.pesem.id));
      Midi.aplikacija.odprta(_pesem, widget.baza.midi);
    });
    if (_pdfji.isNotEmpty) {
      widget.baza.pdf(_pdfji.first.driveId).then((b) {
        if (mounted) {
          setState(() {
            _pdf = b;
            _pdfPrebran = true;
          });
        }
      });
    }
    SharedPreferences.getInstance().then((p) {
      final v = p.getDouble(_kljucPisave);
      if (v != null && mounted) setState(() => _pisava = v);
    });
  }

  @override
  void dispose() {
    Midi.aplikacija.zaprta(_pesem);
    super.dispose();
  }

  Future<void> _spremeniPisavo(double d) async {
    setState(() => _pisava = (_pisava + d).clamp(12, 64));
    (await SharedPreferences.getInstance()).setDouble(_kljucPisave, _pisava);
  }

  /// Vse o pesmi na enem zaslonu; [zavihek] izbere, kaj se odpre najprej.
  Future<void> _uredi({int zavihek = 0}) async {
    final api = apiZaUrejanje(context, widget.prijava);
    if (api == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<Pesem>(
        builder: (_) => UrejanjePesmiZaslon(baza: widget.baza, api: api, pesem: _pesem, zavihek: zavihek),
      ),
    );
    if (mounted && _besedila.isNotEmpty && _pdfji.isEmpty) setState(() => _prikaziBesedilo = true);
  }

  void _odpri(Pesem p) {
    setState(() => _iskalnik = false);
    if (p.id == widget.pesem.id) return;
    if (widget.odpri case final odpri?) return odpri(p);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            PesemZaslon(pesem: p, baza: widget.baza, prijava: widget.prijava, spil: widget.spil, seznam: widget.seznam),
      ),
    );
  }

  List<MidiGumb> get _gumbi => widget.baza.midi.gumbiZa(widget.pesem.id);

  void _pritisni(MidiGumb g) {
    final k = widget.baza.midi;
    Midi.aplikacija.poslji(k.razsiri(g.ukazi), knjiznica: k);
  }

  /// Nožno stikalo: gumbi pesmi, iskalnik in premikanje po seznamu.
  bool _dejanje(DejanjeMidi d) {
    if (d.gumb > 0) {
      final gumbi = _gumbi;
      if (d.gumb <= gumbi.length) _pritisni(gumbi[d.gumb - 1]);
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
      _odpri(widget.baza.pesem(izbrana.pesem)!);
      return true;
    }
    final seznam = widget.seznam;
    if (seznam != null && (d == DejanjeMidi.naslednja || d == DejanjeMidi.prejsnja)) {
      final i = seznam.indexWhere((p) => p.id == widget.pesem.id) + (d == DejanjeMidi.naslednja ? 1 : -1);
      if (i >= 0 && i < seznam.length) _odpri(seznam[i]);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NaMidi(
      dejanje: _dejanje,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.baza, Midi.aplikacija, ?widget.spil]),
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

  Widget _telo(BuildContext context) {
    if (!_iskalnik) return _vsebina(context);
    return LayoutBuilder(
      builder: (context, meje) => Stack(
        children: [
          _vsebina(context),
          Positioned(
            right: 16,
            bottom: 16,
            width: (meje.maxWidth - 32).clamp(0, 400).toDouble(),
            height: (meje.maxHeight * 0.6).clamp(0, 520).toDouble(),
            child: IskalnikPesmi(
              key: _iskalnikKljuc,
              pesmi: widget.baza.pesmi,
              trenutna: widget.pesem,
              odpri: _odpri,
              zapri: () => setState(() => _iskalnik = false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _zaslon(BuildContext context) {
    final p = _pesem;
    final imaOboje = _besedila.isNotEmpty && _pdfji.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text('${p.koda}  ${p.naslov}'),
        actions: [
          if (widget.spil case final spil?) SpilGumb(spil: spil, baza: widget.baza, prijava: widget.prijava),
          if (widget.spil case final spil?)
            IconButton(
              tooltip: 'Dodaj med naslednje',
              icon: const Icon(Icons.playlist_add),
              onPressed: () => dodajMedNaslednje(context, spil, widget.baza, p),
            ),
          IconButton(
            tooltip: 'Išči pesem',
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _iskalnik = !_iskalnik),
          ),
          if (imaOboje)
            IconButton(
              tooltip: _prikaziBesedilo ? 'Pokaži PDF' : 'Pokaži besedilo',
              icon: Icon(_prikaziBesedilo ? Icons.picture_as_pdf : Icons.notes),
              onPressed: () => setState(() => _prikaziBesedilo = !_prikaziBesedilo),
            ),
          if (_prikaziBesedilo && _besedila.isNotEmpty) ...[
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
          if (widget.baza.smeUrejatiPesem(p))
            IconButton(
              tooltip: 'Uredi pesem',
              icon: const Icon(Icons.edit),
              // Ko je na zaslonu besedilo, se urejanje odpre pri besedilu.
              onPressed: () =>
                  _uredi(zavihek: _prikaziBesedilo && _besedila.isNotEmpty ? UrejanjePesmiZaslon.zavihekBesedila : 0),
            ),
        ],
      ),
      body: _telo(context),
      bottomNavigationBar: switch ([
        ?vrsticaNaslednjih(context, widget.spil, widget.baza, _odpri),
        ?_vrsticaGumbov(context),
        ?widget.spodaj,
      ]) {
        [] => null,
        [final en] => en,
        final vse => Column(mainAxisSize: MainAxisSize.min, children: vse),
      },
    );
  }

  Widget _vsebina(BuildContext context) {
    if (_prikaziBesedilo && _besedila.isNotEmpty) {
      return BesediloZRisanjem(
        vsebina: _besedila.first.vsebina,
        povecava: _pisava / BesediloZRisanjem.osnovnaPisava,
        pesem: widget.pesem.id,
        risbe: widget.baza.risbe,
      );
    }
    if (_pdfji.isNotEmpty) {
      if (!_pdfPrebran) return const Center(child: CircularProgressIndicator());
      final pdf = _pdf;
      if (pdf == null) {
        return const Center(child: Text('PDF še ni prenesen. Osveži iz baze, ko imaš internet.'));
      }
      return PdfZRisanjem(pdf: pdf, ime: _pdfji.first.driveId, pesem: widget.pesem.id, risbe: widget.baza.risbe);
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
            v.imaAkorde
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
