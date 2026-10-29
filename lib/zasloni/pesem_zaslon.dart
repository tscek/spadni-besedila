import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../baza.dart';
import '../chordpro.dart' as cp;
import '../models.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'pdf_risanje.dart';
import 'spil_zaslon.dart';
import 'urejanje_besedila.dart';
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

  @override
  State<PesemZaslon> createState() => _PesemZaslonState();
}

class _PesemZaslonState extends State<PesemZaslon> {
  static const _kljucPisave = 'velikost_pisave';
  double _pisava = 22;
  bool _prikaziBesedilo = true;
  Uint8List? _pdf;
  bool _pdfPrebran = false;

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
      if (mounted) widget.spil?.prikazujem(widget.stanje ?? StanjeSpila(pesem: widget.pesem.id));
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

  Future<void> _spremeniPisavo(double d) async {
    setState(() => _pisava = (_pisava + d).clamp(12, 64));
    (await SharedPreferences.getInstance()).setDouble(_kljucPisave, _pisava);
  }

  Future<void> _urediPesem() async {
    final api = apiZaUrejanje(context, widget.prijava);
    if (api == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<Pesem>(
        builder: (_) => UrejanjePesmiZaslon(baza: widget.baza, api: api, pesem: _pesem),
      ),
    );
  }

  Future<void> _urediBesedilo() async {
    final api = apiZaUrejanje(context, widget.prijava);
    if (api == null) return;
    final shranjeno = await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) =>
            UrejanjeBesedilaZaslon(baza: widget.baza, api: api, pesem: _pesem, besedilo: _besedila.firstOrNull),
      ),
    );
    if (shranjeno ?? false) setState(() => _prikaziBesedilo = _besedila.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: widget.baza, builder: (context, _) => _zaslon(context));
  }

  Widget _zaslon(BuildContext context) {
    final p = _pesem;
    final imaOboje = _besedila.isNotEmpty && _pdfji.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text('${p.koda}  ${p.naslov}'),
        actions: [
          if (widget.spil case final spil?) SpilGumb(spil: spil, baza: widget.baza, prijava: widget.prijava),
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
            PopupMenuButton<String>(
              tooltip: 'Urejanje',
              icon: const Icon(Icons.edit),
              onSelected: (v) => v == 'pesem' ? _urediPesem() : _urediBesedilo(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'pesem', child: Text('Uredi podatke pesmi')),
                PopupMenuItem(value: 'besedilo', child: Text(_besedila.isEmpty ? 'Dodaj besedilo' : 'Uredi besedilo')),
              ],
            ),
        ],
      ),
      body: _vsebina(context),
      bottomNavigationBar: widget.spodaj,
    );
  }

  Widget _vsebina(BuildContext context) {
    if (_prikaziBesedilo && _besedila.isNotEmpty) {
      return BesediloPogled(vsebina: _besedila.first.vsebina, velikost: _pisava);
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
          onPressed: _urediBesedilo,
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

  @override
  Widget build(BuildContext context) {
    final barve = Theme.of(context).colorScheme;
    final besedilo = TextStyle(fontSize: velikost, height: 1.25);
    final akord = TextStyle(fontSize: velikost * 0.8, fontWeight: FontWeight.bold, color: barve.primary);
    final komentar = TextStyle(fontSize: velikost * 0.8, fontStyle: FontStyle.italic, color: barve.secondary);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
      ],
    );
  }
}
