import 'package:flutter/material.dart';

import '../baza.dart';
import '../models.dart';
import '../prijava.dart';
import 'pesem_zaslon.dart';
import 'urejanje_pesmi.dart';
import 'urejanje_setliste.dart';

/// Seznam setlist, najnovejše najprej.
class SetlisteZaslon extends StatelessWidget {
  const SetlisteZaslon({super.key, required this.baza, required this.prijava});

  final Baza baza;
  final Prijava prijava;

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
          builder: (_) => SetlistaZaslon(setlista: nova, baza: baza, prijava: prijava),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: baza,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Setliste')),
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
                          builder: (_) => SetlistaZaslon(setlista: s, baza: baza, prijava: prijava),
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
  const SetlistaZaslon({super.key, required this.setlista, required this.baza, required this.prijava});

  final Setlista setlista;
  final Baza baza;
  final Prijava prijava;

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
        builder: (_) => IgranjeZaslon(setlista: s, baza: baza, prijava: prijava, zacetek: zacetek),
      ),
    );
  }
}

/// Igranje po setlisti: pesem čez cel zaslon, spodaj prejšnja/naslednja.
class IgranjeZaslon extends StatefulWidget {
  const IgranjeZaslon({super.key, required this.setlista, required this.baza, required this.prijava, this.zacetek = 0});

  final Setlista setlista;
  final Baza baza;
  final Prijava prijava;
  final int zacetek;

  @override
  State<IgranjeZaslon> createState() => _IgranjeZaslonState();
}

class _IgranjeZaslonState extends State<IgranjeZaslon> {
  late int _i = widget.zacetek;

  List<(SetlistaPesem, Pesem)> get _vrsta => [
    for (final v in widget.baza.pesmiSetlist[widget.setlista.id] ?? const <SetlistaPesem>[])
      if (widget.baza.pesem(v.pesem) case final p?) (v, p),
  ];

  @override
  Widget build(BuildContext context) {
    final vrsta = _vrsta;
    if (vrsta.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Setlista je prazna.')),
      );
    }
    final i = _i.clamp(0, vrsta.length - 1);
    final (v, p) = vrsta[i];
    final naslednja = i + 1 < vrsta.length ? vrsta[i + 1].$2 : null;
    final tema = Theme.of(context);
    return PesemZaslon(
      key: ValueKey('${p.id}-$i'),
      pesem: p,
      baza: widget.baza,
      prijava: widget.prijava,
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
                  onPressed: i > 0 ? () => setState(() => _i = i - 1) : null,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${i + 1} / ${vrsta.length}${v.opomba.isEmpty ? '' : ' · ${v.opomba}'}',
                        style: tema.textTheme.labelLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        naslednja == null ? 'Konec setliste' : 'Naslednja: ${naslednja.koda} ${naslednja.naslov}',
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
                  onPressed: naslednja != null ? () => setState(() => _i = i + 1) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
