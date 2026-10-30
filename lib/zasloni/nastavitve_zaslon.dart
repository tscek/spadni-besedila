import 'package:flutter/material.dart';

import '../baza.dart';
import '../models.dart';
import '../nastavitve.dart';
import 'pdf_risanje.dart';
import 'midi_zaslon.dart';

/// Osebne nastavitve na tej napravi.
class NastavitveZaslon extends StatelessWidget {
  const NastavitveZaslon({super.key, required this.baza});

  final Baza baza;

  @override
  Widget build(BuildContext context) {
    final n = Nastavitve.aplikacija;
    return Scaffold(
      appBar: AppBar(title: const Text('Nastavitve')),
      body: ListenableBuilder(
        listenable: n,
        builder: (context, _) => ListView(
          children: [
            const ListTile(title: Text('Velja samo za to napravo.')),
            ListTile(
              title: const Text('Velikost pisave besedila (ali ščip na besedilu)'),
              subtitle: Slider(
                value: n.pisava,
                min: 12,
                max: 64,
                divisions: 26,
                label: n.pisava.round().toString(),
                onChanged: n.nastaviPisavo,
              ),
            ),
            SwitchListTile(
              title: const Text('Akordi nad besedilom'),
              subtitle: const Text(
                'Izklopi, če akordov ne potrebuješ (npr. pevci). Risbe na besedilu se lahko zamaknejo.',
              ),
              value: n.akordi,
              onChanged: n.nastaviAkorde,
            ),
            SwitchListTile(
              title: const Text('Najprej PDF'),
              subtitle: const Text('Pri pesmi z besedilom in PDF-jem se najprej pokaže PDF'),
              value: n.pdfNajprej,
              onChanged: n.nastaviPdfNajprej,
            ),
            SwitchListTile(title: const Text('Svetla tema'), value: n.svetlaTema, onChanged: n.nastaviSvetloTemo),
            const Divider(),
            SwitchListTile(
              title: const Text('Sledi pesmim vodje'),
              subtitle: const Text('Ko slediš, se pesem, ki jo izbere vodja, odpre sama'),
              value: n.samodejnoSledenje,
              onChanged: n.nastaviSamodejnoSledenje,
            ),
            SwitchListTile(
              title: const Text('Zaslon ostane prižgan'),
              subtitle: const Text('Med uporabo aplikacije se zaslon ne ugasne'),
              value: n.zaslonPrizgan,
              onChanged: n.nastaviZaslonPrizgan,
            ),
            const ListTile(title: Text('Vloga na špilu'), subtitle: Text('Vodja, sledilec ali sama: gumb Špil')),
            const Divider(),
            const ListTile(
              title: Text('Orodni vrstici pri pesmi'),
              subtitle: Text('Kaj je zgoraj, kaj v vrstici spodaj in kaj skrito'),
            ),
            for (final o in Orodje.values)
              ListTile(
                title: Text(o.opis),
                trailing: DropdownButton<Mesto>(
                  value: n.mesto(o),
                  onChanged: (m) => m == null ? null : n.nastaviOrodje(o, m),
                  items: [for (final m in Mesto.values) DropdownMenuItem(value: m, child: Text(m.ime))],
                ),
              ),
            const Divider(),
            const ListTile(
              title: Text('Spodnja vrstica pri pesmi'),
              subtitle: Text('Trije deli; iskanje je vedno desno'),
            ),
            for (final (i, ime) in [(0, 'Levo'), (1, 'Sredina'), (2, 'Desno')])
              ListTile(
                title: Text(ime),
                trailing: DropdownButton<InfoVrstice>(
                  value: n.spodaj[i],
                  onChanged: (v) => v == null ? null : n.nastaviSpodaj(i, v),
                  items: [for (final v in InfoVrstice.values) DropdownMenuItem(value: v, child: Text(v.ime))],
                ),
              ),
            const Divider(),
            ListTile(
              title: const Text('Vrstica na seznamu pesmi'),
              subtitle: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final polje in PoljePesmi.values)
                    if (polje != PoljePesmi.naslov && polje != PoljePesmi.spremenjeno)
                      FilterChip(
                        label: Text(polje.ime),
                        selected: n.poljaSeznama.contains(polje),
                        onSelected: (da) => n.nastaviPoljaSeznama([
                          for (final x in PoljePesmi.values)
                            if (x == polje ? da : n.poljaSeznama.contains(x)) x,
                        ]),
                      ),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Ikoni besedila in PDF-ja na seznamu'),
              value: n.ikoneSeznama,
              onChanged: n.nastaviIkoneSeznama,
            ),
            ListTile(
              title: const Text('Napis v čakalni vrsti'),
              subtitle: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final polje in PoljePesmi.values)
                    if (polje != PoljePesmi.spremenjeno)
                      FilterChip(
                        label: Text(polje.ime),
                        selected: n.poljaVrste.contains(polje),
                        onSelected: (da) => n.nastaviPoljaVrste([
                          for (final x in PoljePesmi.values)
                            if (x == polje ? da : n.poljaVrste.contains(x)) x,
                        ]),
                      ),
                ],
              ),
            ),
            const ListTile(
              dense: true,
              subtitle: Text('Če je izbrana harmonika, napis utripa v barvi harmonike, ko jo je treba zamenjati.'),
            ),
            ListTile(
              title: const Text('Pesem je odigrana, ko je odprta'),
              subtitle: const Text('Siva ikona predvajanja na vseh seznamih (velja 12 ur)'),
              trailing: DropdownButton<int>(
                value: n.minuteOdigrane,
                onChanged: (v) => v == null ? null : n.nastaviMinuteOdigrane(v),
                items: [
                  for (final m in const [0, 1, 2, 3, 4, 5, 10])
                    DropdownMenuItem(value: m, child: Text(m == 0 ? 'nikoli' : '$m min')),
                ],
              ),
            ),
            const Divider(),
            const ListTile(title: Text('Runda in pavza'), subtitle: Text('Gumba v oknu ure zgoraj')),
            _GumbRundeNastavitev(baza: baza, pavza: true),
            _GumbRundeNastavitev(baza: baza, pavza: false),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.piano),
              title: const Text('Nastavitve MIDI'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MidiNastavitveZaslon(baza: baza))),
            ),
          ],
        ),
      ),
    );
  }
}

/// Napis, barva in MIDI ukaz enega gumba v oknu runde.
class _GumbRundeNastavitev extends StatefulWidget {
  const _GumbRundeNastavitev({required this.baza, required this.pavza});

  final Baza baza;
  final bool pavza;

  @override
  State<_GumbRundeNastavitev> createState() => _GumbRundeNastavitevState();
}

class _GumbRundeNastavitevState extends State<_GumbRundeNastavitev> {
  GumbRunde get _g => widget.pavza ? Nastavitve.aplikacija.pavza : Nastavitve.aplikacija.igranje;
  late final _napis = TextEditingController(text: _g.napis);
  late final _midi = TextEditingController(text: _g.midi)..addListener(_shrani);

  void _shrani({int? barva}) => Nastavitve.aplikacija.nastaviGumbRunde(
    widget.pavza,
    _g.kopija(napis: _napis.text.trim().isEmpty ? null : _napis.text.trim(), midi: _midi.text.trim(), barva: barva),
  );

  @override
  void dispose() {
    _napis.dispose();
    _midi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _napis,
                  decoration: InputDecoration(
                    labelText: widget.pavza ? 'Gumb za pavzo' : 'Gumb za igranje',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _shrani(),
                ),
              ),
              const SizedBox(width: 8),
              for (final b in barveGumbov)
                GestureDetector(
                  onTap: () => _shrani(barva: b.toARGB32()),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: b,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _g.barva == b.toARGB32() ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          PoljeMidi(oznaka: 'MIDI ob kliku (neobvezno)', vnos: _midi, knjiznica: widget.baza.midi),
        ],
      ),
    );
  }
}
