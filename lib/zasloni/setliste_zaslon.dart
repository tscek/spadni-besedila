import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../baza.dart';
import '../midi/midi.dart';
import '../midi/ukazi.dart';
import '../models.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'naslednje.dart';
import 'oznake.dart';
import 'pesem_zaslon.dart';
import 'prehod.dart';
import 'spil_zaslon.dart';
import 'urejanje_pesmi.dart';
import 'urejanje_setliste.dart';

/// Seznam playlist (setlist) v mapi, najnovejše najprej.
class SetlisteZaslon extends StatelessWidget {
  const SetlisteZaslon({super.key, required this.baza, required this.prijava, this.spil, this.mapa});

  final Baza baza;
  final Prijava prijava;
  final Spil? spil;

  /// Mapa, katere playliste so na seznamu; null so vse.
  final String? mapa;

  Future<void> _nova(BuildContext context) async {
    final api = apiZaUrejanje(context, prijava);
    if (api == null) return;
    final navigator = Navigator.of(context);
    final nova = await navigator.push(
      MaterialPageRoute<Setlista>(
        builder: (_) => UrejanjeSetlisteZaslon(baza: baza, api: api, mapa: mapa),
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
      builder: (context, _) {
        final playliste = [
          for (final s in baza.setliste)
            if (mapa == null || s.mapa == mapa) s,
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(mapa == null ? 'Playliste' : 'Playliste: ${baza.mapa(mapa!)?.ime ?? mapa}'),
            actions: [if (spil case final spil?) SpilGumb(spil: spil, baza: baza, prijava: prijava)],
          ),
          floatingActionButton: baza.smeUrejati
              ? FloatingActionButton.extended(
                  onPressed: () => _nova(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Nova playlista'),
                )
              : null,
          body: playliste.isEmpty
              ? const Center(child: Text('Ni še nobene playliste.'))
              : ListView(
                  children: [
                    for (final s in playliste)
                      ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(s.ime),
                        subtitle: Text(
                          [
                            if (s.datum != null) datumBesedilo(s.datum!),
                            '${baza.pesmiSetlist[s.id]?.length ?? 0} pesmi',
                            if (mapa == null && s.mapa.isNotEmpty) baza.mapa(s.mapa)?.ime ?? '',
                            if (baza.skupine.length > 1)
                              ...baza.skupine.where((k) => k.id == s.skupina).map((k) => k.ime),
                          ].join(' · '),
                        ),
                        // Playlista postane čakalna vrsta; naslednja pesem je vedno s čakalne vrste.
                        onTap: () {
                          spil?.nastaviVrsto(_pesmiPlayliste(baza, s));
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SetlistaZaslon(setlista: s, baza: baza, prijava: prijava, spil: spil),
                            ),
                          );
                        },
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// ID-ji pesmi playliste od [od] naprej (brez pesmi, ki jih ni več v repertoarju).
List<String> _pesmiPlayliste(Baza baza, Setlista s, {int od = 0}) => [
  for (final v in (baza.pesmiSetlist[s.id] ?? const <SetlistaPesem>[]).skip(od))
    if (baza.pesem(v.pesem) != null) v.pesem,
];

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
                  tooltip: 'Uredi playlisto',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _uredi(context, s),
                ),
              IconButton(
                tooltip: 'Izvoz za SAZAS',
                icon: const Icon(Icons.ios_share),
                onPressed: () => izvozSazas(context, baza, s),
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
                  title: switch (baza.pesem(v.pesem)) {
                    final p? => NaslovZOznakami(pesem: p),
                    null => const Text('(pesmi ni več v repertoarju)'),
                  },
                  subtitle: v.opomba.isEmpty ? null : Text(v.opomba),
                  onTap: () => _igraj(context, s, i),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Igranje od pesmi [zacetek]: ta in vse za njo gredo v čakalno vrsto, odpre se kot vsaka pesem.
  /// Brez špila (npr. v testih) ostane igranje po setlisti.
  void _igraj(BuildContext context, Setlista s, int zacetek) {
    final spil = this.spil;
    final vrsta = baza.pesmiSetlist[s.id] ?? const <SetlistaPesem>[];
    final pesem = zacetek < vrsta.length ? baza.pesem(vrsta[zacetek].pesem) : null;
    if (spil == null || pesem == null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => IgranjeZaslon(setlista: s, baza: baza, prijava: prijava, zacetek: zacetek, spil: spil),
        ),
      );
      return;
    }
    spil.nastaviVrsto(_pesmiPlayliste(baza, s, od: zacetek));
    final pesmi = [for (final v in vrsta) ?baza.pesem(v.pesem)];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PesemZaslon(
          pesem: pesem,
          baza: baza,
          prijava: prijava,
          spil: spil,
          mapa: s.mapa.isEmpty ? PesemZaslon.vse : s.mapa,
          prednostne: pesmi,
          playlista: {for (final (j, v) in vrsta.indexed) v.pesem: (st: j + 1, opomba: v.opomba)},
        ),
      ),
    );
  }
}

/// Igranje po setlisti: pesem čez cel zaslon; pesmi playliste so v iskalniku označene, naprej in nazaj z nožnim stikalom ali podrsajem.
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
    final (v, pesemSetliste) = vrsta[i];
    final vmes = _vmes;
    final p = vmes ?? pesemSetliste;
    final izbrana = _izbrana(i, vrsta.length);
    final naslednja = izbrana ?? (i + 1 < vrsta.length ? vrsta[i + 1].$2 : null);
    return PesemZaslon(
      key: ValueKey('${p.id}-$i-${vmes != null}'),
      // Pesem s seznamčka: če je v setlisti, skoči nanjo, sicer se vrine za trenutno.
      odpri: (izbrana) {
        final j = vrsta.indexWhere((e) => e.$2.id == izbrana.id);
        j >= 0 ? _pojdi(j) : _vrini(izbrana);
      },
      // Iskalnik: pesmi playliste na vrhu; pesem playliste se odpre, druga postane naslednja (playlista ostane ista).
      prednostne: [for (final e in vrsta) e.$2],
      playlista: {for (final (j, e) in vrsta.indexed) e.$2.id: (st: j + 1, opomba: e.$1.opomba)},
      naslednja: naslednja,
      mapa: widget.setlista.mapa.isEmpty ? PesemZaslon.vse : widget.setlista.mapa,
      izIskalnika: (izbrana) {
        final j = vrsta.indexWhere((e) => e.$2.id == izbrana.id);
        if (j >= 0) return _pojdi(j);
        final spil = widget.spil;
        if (spil == null) return _vrini(izbrana);
        vCakalnoVrsto(context, spil, widget.baza, izbrana, naPrvo: true);
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
    );
  }
}

/// Seznam pesmi playliste z avtorji in trajanjem (za SAZAS); kopira se kot tabela (prilepi v Excel ali e-pošto).
Future<void> izvozSazas(BuildContext context, Baza baza, Setlista s) async {
  final pesmi = [for (final v in baza.pesmiSetlist[s.id] ?? const <SetlistaPesem>[]) ?baza.pesem(v.pesem)];
  final glava = ['Zap. št.', 'Naslov', 'Izvajalec', 'Avtor glasbe', 'Avtor besedila', 'Trajanje'];
  final vrstice = [
    for (final (i, p) in pesmi.indexed)
      ['${i + 1}', p.naslov, p.izvajalec, p.avtorGlasbe, p.avtorBesedila, PoljePesmi.trajanje.vrednost(p)],
  ];
  final tabela = [glava, ...vrstice].map((r) => r.join('\t')).join('\n');
  final manjka = pesmi.where((p) => p.avtorGlasbe.isEmpty || PoljePesmi.trajanje.vrednost(p).isEmpty).length;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('SAZAS: ${s.ime}'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                if (s.datum != null) datumBesedilo(s.datum!),
                if (s.nastop.isNotEmpty) s.nastop,
                '${pesmi.length} pesmi',
              ].join(' · '),
            ),
            if (manjka > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Pri $manjka pesmih manjka avtor glasbe ali trajanje (dopolniš ju v podatkih pesmi).',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 16,
                    headingRowHeight: 36,
                    dataRowMinHeight: 28,
                    dataRowMaxHeight: 40,
                    columns: [for (final g in glava) DataColumn(label: Text(g))],
                    rows: [
                      for (final r in vrstice) DataRow(cells: [for (final c in r) DataCell(Text(c))]),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zapri')),
        TextButton.icon(
          icon: const Icon(Icons.download),
          label: const Text('Shrani CSV'),
          onPressed: () async {
            // Podpičje in BOM, da Excel s slovenskimi nastavitvami pravilno razdeli stolpce in šumnike.
            String celica(String c) => c.contains(RegExp('[;"\n]')) ? '"${c.replaceAll('"', '""')}"' : c;
            final csv = '\uFEFF${[glava, ...vrstice].map((r) => r.map(celica).join(';')).join('\r\n')}';
            try {
              await FilePicker.saveFile(
                fileName: 'SAZAS ${s.ime}.csv',
                bytes: Uint8List.fromList(utf8.encode(csv)),
                mimeType: 'text/csv',
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
              }
            }
          },
        ),
        FilledButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Kopiraj tabelo'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: tabela));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tabela je kopirana. Prilepi jo v Excel ali e-pošto za SAZAS.')),
              );
            }
          },
        ),
      ],
    ),
  );
}
