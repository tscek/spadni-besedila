import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../baza.dart';
import '../chordpro.dart' as cp;
import '../models.dart';
import 'pdf_risanje.dart';

class PesemZaslon extends StatefulWidget {
  const PesemZaslon({super.key, required this.pesem, required this.baza});

  final Pesem pesem;
  final Baza baza;

  @override
  State<PesemZaslon> createState() => _PesemZaslonState();
}

class _PesemZaslonState extends State<PesemZaslon> {
  static const _kljucPisave = 'velikost_pisave';
  double _pisava = 22;
  bool _prikaziBesedilo = true;
  File? _pdf;

  List<BesediloPesmi> get _besedila => widget.baza.besedilaPesmi[widget.pesem.id] ?? const [];
  List<PdfDatoteka> get _pdfji => widget.baza.pdfjiPesmi[widget.pesem.id] ?? const [];

  @override
  void initState() {
    super.initState();
    _prikaziBesedilo = _besedila.isNotEmpty;
    if (_pdfji.isNotEmpty) {
      widget.baza.datotekaPdf(_pdfji.first.driveId).then((f) {
        if (mounted) setState(() => _pdf = f);
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

  @override
  Widget build(BuildContext context) {
    final p = widget.pesem;
    final imaOboje = _besedila.isNotEmpty && _pdfji.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text('${p.koda}  ${p.naslov}'),
        actions: [
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
        ],
      ),
      body: _vsebina(context),
    );
  }

  Widget _vsebina(BuildContext context) {
    if (_prikaziBesedilo && _besedila.isNotEmpty) {
      return BesediloPogled(vsebina: _besedila.first.vsebina, velikost: _pisava);
    }
    if (_pdfji.isNotEmpty) {
      final f = _pdf;
      if (f == null) return const Center(child: CircularProgressIndicator());
      if (!f.existsSync()) {
        return const Center(child: Text('PDF še ni prenesen. Osveži iz baze, ko imaš internet.'));
      }
      return PdfZRisanjem(pot: f.path, pesem: widget.pesem.id, risbe: widget.baza.risbe);
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
