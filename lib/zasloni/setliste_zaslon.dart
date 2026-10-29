import 'package:flutter/material.dart';

import '../baza.dart';
import '../midi/midi.dart';
import '../midi/ukazi.dart';
import '../models.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'pesem_zaslon.dart';
import 'prehod.dart';
import 'spil_zaslon.dart';
import 'urejanje_pesmi.dart';
import 'urejanje_setliste.dart';

/// Seznam setlist, najnovejše najprej.
class SetlisteZaslon extends StatelessWidget {
  const SetlisteZaslon({super.key, required this.baza, required this.prijava, this.spil});

  final Baza baza;
  final Prijava prijava;
  final Spil? spil;

  Future<void> _nova(BuildContext context) async {
    final api = apiZaUrejanje(context, prijava);
    if (api == null) return;
    final navigator = Navigator.of(context);
    final nova = await navigator.push(
      MaterialPageRoute<Setlista>(
        builder: (_) => UrejanjeSetlisteZaslon(baza: baza, api: api),
      ),
    );
    if (nova != null) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => SetlistaZaslon(setlista: nova, baza: baza, prijava: prijava, spil: spil),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: baza,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Setliste'),
          actions: [if (spil case final spil?) SpilGumb(spil: spil, baza: baza, prijava: prijava)],
        ),
        floatingActionButton: baza.smeUrejati
            ? FloatingActionButton.extended(
                onPressed: () => _nova(context),
                icon: const Icon(Icons.add),
                label: const Text('Nova setlista'),
              )
            : null,
        body: baza.setliste.isEmpty
            ? const Center(child: Text('Ni še nobene setliste.'))
            : ListView(
                children: [
                  for (final s in baza.setliste)
                    ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(s.ime),
                      subtitle: Text(
                        [
                          if (s.datum != null) datumBesedilo(s.datum!),
                          '${baza.pesmiSetlist[s.id]?.length ?? 0} pesmi',
                          if (baza.skupine.length > 1)
                            ...baza.skupine.where((k) => k.id == s.skupina).map((k) => k.ime),
                        ].join(' · '),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SetlistaZaslon(setlista: s, baza: baza, prijava: prijava, spil: spil),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Pesmi ene setliste po vrsti; tap začne igranje od te pesmi.
class SetlistaZaslon extends StatelessWidget {
  const SetlistaZaslon({super.key, required this.setlista, required this.baza, required this.prijava, this.spil});

  final Setlista setlista;
  final Baza baza;
  final Prijava prijava;
  final Spil? spil;

  Future<void> _uredi(BuildContext context, Setlista s) async {
    final api = apiZaUrejanje(context, prijava);
    if (api == null) return;
    final navigator = Navigator.of(context);
    final rezultat = await navigator.push(
      MaterialPageRoute<Setlista>(
        builder: (_) => UrejanjeSetlisteZaslon(baza: baza, api: api, setlista: s),
      ),
    );
    // Izbrisana setlista: nazaj na seznam.
    if (rezultat == null && !baza.setliste.any((x) => x.id == s.id)) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: baza,
      builder: (context, _) {
        final s = baza.setliste.where((x) => x.id == setlista.id).firstOrNull ?? setlista;
        final vrsta = baza.pesmiSetlist[s.id] ?? const [];
        return Scaffold(
          appBar: AppBar(
            title: Text(s.ime),
            actions: [
              if (spil case final spil?) SpilGumb(spil: spil, baza: baza, prijava: prijava),
              if (baza.smeUrejatiSetlisto(s))
                IconButton(
                  tooltip: 'Uredi setlisto',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _uredi(context, s),
                ),
            ],
          ),
          floatingActionButton: vrsta.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _igraj(context, s, 0),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Začni'),
                ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              if (s.datum != null || s.opombe.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    [if (s.datum != null) datumBesedilo(s.datum!), s.opombe].where((x) => x.isNotEmpty).join(' · '),
                  ),
                ),
              for (final (i, v) in vrsta.indexed)
                ListTile(
                  leading: SizedBox(width: 28, child: Text('${i + 1}.', textAlign: TextAlign.right)),
                  title: Text(_naslov(v)),
                  subtitle: v.opomba.isEmpty ? null : Text(v.opomba),
                  onTap: () => _igraj(context, s, i),
                ),
            ],
          ),
        );
      },
    );
  }

  String _naslov(SetlistaPesem v) {
    final p = baza.pesem(v.pesem);
    return p == null ? '(pesmi ni več v repertoarju)' : '${p.koda}  ${p.naslov}';
  }

  void _igraj(BuildContext context, Setlista s, int zacetek) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IgranjeZaslon(setlista: s, baza: baza, prijava: prijava, zacetek: zacetek, spil: spil),
      ),
    );
  }
}

/// Igranje po setlisti: pesem čez cel zaslon, spodaj prejšnja/naslednja.
class IgranjeZaslon extends StatefulWidget {
  const IgranjeZaslon({
    super.key,
    required this.setlista,
    required this.baza,
    required this.prijava,
    this.zacetek = 0,
    this.spil,
  });

  final Setlista setlista;
  final Baza baza;
  final Prijava prijava;
  final int zacetek;

  /// Če je podan in naprava vodi, se vsaka zamenjava pesmi (z mestom v setlisti) pošlje sledilcem.
  final Spil? spil;

  @override
  State<IgranjeZaslon> createState() => _IgranjeZaslonState();
}

class _IgranjeZaslonState extends State<IgranjeZaslon> {
  late int _i = widget.zacetek;

  /// Pesem izven setliste, vrinjena za [_i] (s seznamčka ali iz iskalnika); naslednja je spet [_i] + 1.
  Pesem? _vmes;

  /// Smer zadnje zamenjave pesmi za animacijo: 1 naprej (od desne), -1 nazaj (od leve).
  int _smer = 0;

  void _pojdi(int i, {int smer = 0}) => setState(() {
    _i = i;
    _vmes = null;
    _smer = smer;
  });

  void _vrini(Pesem p, {int smer = 0}) => setState(() {
    _vmes = p;
    _smer = smer;
  });

  List<(SetlistaPesem, Pesem)> get _vrsta => [
    for (final v in widget.baza.pesmiSetlist[widget.setlista.id] ?? const <SetlistaPesem>[])
      if (widget.baza.pesem(v.pesem) case final p?) (v, p),
  ];

  /// Kaj pride naslednje: izbrana pesem s seznamčka (tiste »na konec« šele po zadnji pesmi setliste) ali naslednja v setlisti.
  Pesem? _izbrana(int i, int dolzina) {
    final n = widget.spil?.prvaNaslednja(naKonec: i + 1 >= dolzina);
    return n == null ? null : widget.baza.pesem(n.pesem);
  }

  void _naprej(int i, int dolzina) {
    final izbrana = _izbrana(i, dolzina);
    if (izbrana != null) {
      _vrini(izbrana, smer: 1);
    } else if (i + 1 < dolzina) {
      _pojdi(i + 1, smer: 1);
    }
  }

  void _nazaj(int i) {
    if (_vmes != null) {
      _pojdi(i, smer: -1);
    } else if (i > 0) {
      _pojdi(i - 1, smer: -1);
    }
  }

  /// Nožno stikalo: naslednja in prejšnja pesem v setlisti, izbrana pesem s seznamčka.
  bool _dejanje(DejanjeMidi d, int i, int dolzina) {
    switch (d) {
      case DejanjeMidi.naslednja:
        _naprej(i, dolzina);
      case DejanjeMidi.prejsnja:
        _nazaj(i);
      case DejanjeMidi.izbrana:
        if (widget.spil?.prvaNaslednja() case final n?) {
          if (widget.baza.pesem(n.pesem) case final p?) _vrini(p, smer: 1);
        }
      default:
        return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: widget.spil ?? widget.baza, builder: (context, _) => _zaslon(context));
  }

  Widget _zaslon(BuildContext context) {
    final vrsta = _vrsta;
    if (vrsta.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Setlista je prazna.')),
      );
    }
    final i = _i.clamp(0, vrsta.length - 1);
    return NaMidi(
      dejanje: (d) => _dejanje(d, i, vrsta.length),
      child: PrehodPesmi(smer: _smer, child: _pesem(context, vrsta, i)),
    );
  }

  Widget _pesem(BuildContext context, List<(SetlistaPesem, Pesem)> vrsta, int i) {
    final tema = Theme.of(context);
    final (v, pesemSetliste) = vrsta[i];
    final vmes = _vmes;
    final p = vmes ?? pesemSetliste;
    final izbrana = _izbrana(i, vrsta.length);
    final naslednja = izbrana ?? (i + 1 < vrsta.length ? vrsta[i + 1].$2 : null);
    return PesemZaslon(
      key: ValueKey('${p.id}-$i-${vmes != null}'),
      // Pesem iz iskalnika ali seznamčka: če je v setlisti, skoči nanjo, sicer se vrine za trenutno.
      odpri: (izbrana) {
        final j = vrsta.indexWhere((e) => e.$2.id == izbrana.id);
        j >= 0 ? _pojdi(j) : _vrini(izbrana);
      },
      pesem: p,
      baza: widget.baza,
      prijava: widget.prijava,
      spil: widget.spil,
      // Indeks v celotni setlisti (tudi pesmi, ki jih ni več v repertoarju), da se ujema pri sledilcih.
      stanje: vmes != null
          ? StanjeSpila(pesem: vmes.id)
          : StanjeSpila(
              pesem: p.id,
              setlista: widget.setlista.id,
              indeks: (widget.baza.pesmiSetlist[widget.setlista.id] ?? const <SetlistaPesem>[]).indexOf(v),
            ),
      spodaj: Material(
        color: tema.colorScheme.surfaceContainer,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                IconButton(
                  iconSize: 36,
                  tooltip: 'Prejšnja pesem',
                  icon: const Icon(Icons.skip_previous),
                  onPressed: i > 0 || vmes != null ? () => _nazaj(i) : null,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        vmes != null
                            ? 'Izven setliste (za ${i + 1} / ${vrsta.length})'
                            : '${i + 1} / ${vrsta.length}${v.opomba.isEmpty ? '' : ' · ${v.opomba}'}',
                        style: tema.textTheme.labelLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        naslednja == null
                            ? 'Konec setliste'
                            : '${izbrana != null ? 'Izbrana' : 'Naslednja'}: ${naslednja.koda} ${naslednja.naslov}',
                        style: tema.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  iconSize: 36,
                  tooltip: 'Naslednja pesem',
                  icon: const Icon(Icons.skip_next),
                  onPressed: naslednja != null ? () => _naprej(i, vrsta.length) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
