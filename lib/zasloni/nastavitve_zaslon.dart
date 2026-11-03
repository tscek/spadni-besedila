import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../models.dart';
import '../nastavitve.dart';
import '../prijava.dart';
import 'deli_aplikacijo.dart';
import 'pdf_risanje.dart';
import 'midi_zaslon.dart';
import 'tipkovnica_zaslon.dart';

/// Osebne nastavitve na tej napravi.
class NastavitveZaslon extends StatelessWidget {
  const NastavitveZaslon({super.key, required this.baza, this.prijava});

  final Baza baza;

  /// Za deljenje aplikacije (samo administrator).
  final Prijava? prijava;

  @override
  Widget build(BuildContext context) {
    final n = Nastavitve.aplikacija;
    return Scaffold(
      appBar: AppBar(title: const Text('Nastavitve')),
      body: ListenableBuilder(
        listenable: n,
        builder: (context, _) => ListView(
          children: [
            if (prijava case final prijava? when baza.jeAdministrator) ...[
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Deli aplikacijo'),
                subtitle: const Text('Povezave za Android, Windows in splet (vidi le administrator)'),
                onTap: () => deliAplikacijo(context, Api(prijava.zeton)),
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Pošlji moje nastavitve pogleda vsem'),
                subtitle: const Text(
                  'Vrstice, barve, pisava, seznam, iskalnik, orodja. Ostali jih ob osvežitvi lahko prevzamejo.',
                ),
                onTap: () => _posljiPogled(context, Api(prijava.zeton)),
              ),
            ],
            const ListTile(title: Text('Velja samo za to napravo.')),
            ListTile(
              title: const Text('Povečave PDF-jev'),
              subtitle: const Text(
                'Ščip na PDF-ju se zapomni za tisto pesem. Pisavo besedila nastavi urednik pri pesmi in je enaka za vse.',
              ),
              trailing: TextButton(onPressed: n.ponastaviPovecavePesmi, child: const Text('Ponastavi')),
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
            ListTile(
              key: const ValueKey('nastavitve-tipkovnica'),
              title: const Text('Tipkovnica'),
              subtitle: const Text('Bližnjice za tipkovnico in nožno stikalo BT (npr. i = iskalnik)'),
              trailing: const Icon(Icons.keyboard_outlined),
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const TipkovnicaZaslon())),
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
              title: Text('Vrstica pod orodno vrstico pri pesmi'),
              subtitle: Text(
                'Trije deli; prazni se umaknejo, kratki (npr. tonaliteta) vzamejo le svojo širino, '
                'daljši (npr. naslov) preostanek. Vse »Nič« skrije vrstico.',
              ),
            ),
            for (final (i, ime) in [(0, 'Levo'), (1, 'Sredina'), (2, 'Desno')])
              ListTile(
                title: Text(ime),
                trailing: DropdownButton<InfoVrstice>(
                  value: n.zgoraj[i],
                  onChanged: (v) => v == null ? null : n.nastaviZgoraj(i, v),
                  items: [for (final v in InfoVrstice.values) DropdownMenuItem(value: v, child: Text(v.ime))],
                ),
              ),
            IzbiraBarve(
              naslov: 'Barva vrstice z naslovom',
              barva: n.barvaZgoraj,
              izberi: (b) => n.nastaviBarvoVrstice(zgoraj: true, barva: b),
            ),
            const Divider(),
            ListTile(
              title: const Text('Oblački na besedilu'),
              subtitle: const Text('V zgornjem levem ali desnem kotu pesmi, zloženi navzdol'),
              trailing: TextButton.icon(
                key: const ValueKey('dodaj-oblacek'),
                icon: const Icon(Icons.add),
                label: const Text('Dodaj'),
                onPressed: () async {
                  final o = await _urediOblacek(context, const Oblacek(vsebina: InfoVrstice.tonaliteta));
                  if (o != null) await n.nastaviOblacke([...n.oblacki, o]);
                },
              ),
            ),
            for (final (i, o) in n.oblacki.indexed)
              ListTile(
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: o.barva == null ? Theme.of(context).colorScheme.primaryContainer : Color(o.barva!),
                ),
                title: Text(o.vsebina.ime),
                subtitle: Text('${Oblacek.velikosti[o.velikost]} · ${o.levo ? 'levo' : 'desno'}'),
                onTap: () async {
                  final nov = await _urediOblacek(context, o);
                  if (nov != null) await n.nastaviOblacke([...n.oblacki]..[i] = nov);
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Višje',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: i == 0
                          ? null
                          : () => n.nastaviOblacke(
                              [...n.oblacki]
                                ..removeAt(i)
                                ..insert(i - 1, o),
                            ),
                    ),
                    IconButton(
                      tooltip: 'Odstrani',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => n.nastaviOblacke([...n.oblacki]..removeAt(i)),
                    ),
                  ],
                ),
              ),
            const Divider(),
            const ListTile(
              title: Text('Spodnja vrstica pri pesmi'),
              subtitle: Text('Trije deli; prazni se umaknejo. Iskanje je vedno desno'),
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
            IzbiraBarve(
              naslov: 'Barva spodnje vrstice',
              barva: n.barvaSpodaj,
              izberi: (b) => n.nastaviBarvoVrstice(zgoraj: false, barva: b),
            ),
            ListTile(
              title: const Text('Iskalnik pesmi: podatki pod naslovom'),
              subtitle: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final polje in PoljePesmi.values)
                    if (polje != PoljePesmi.naslov && polje != PoljePesmi.spremenjeno && polje != PoljePesmi.koda)
                      FilterChip(
                        label: Text(polje.ime),
                        selected: n.poljaIskalnika.contains(polje),
                        onSelected: (da) => n.nastaviPoljaIskalnika([
                          for (final x in PoljePesmi.values)
                            if (x == polje ? da : n.poljaIskalnika.contains(x)) x,
                        ]),
                      ),
                ],
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
              subtitle: const Text(
                'Siva ikona predvajanja na vseh seznamih (velja 12 ur); takrat gre pesem tudi v dnevnik igranja',
              ),
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

/// Administrator pošlje svoje nastavitve pogleda; drugi jih ob osvežitvi lahko prevzamejo.
Future<void> _posljiPogled(BuildContext context, Api api) async {
  final messenger = ScaffoldMessenger.of(context);
  final da = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Pošlji nastavitve pogleda?'),
      content: const Text(
        'Vsi člani bodo ob naslednji osvežitvi vprašani, ali prevzamejo tvoje nastavitve pogleda. '
        'Povečave posameznih pesmi, zasedba in MIDI ostanejo njihovi.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Prekliči')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pošlji')),
      ],
    ),
  );
  if (da != true) return;
  try {
    final n = Nastavitve.aplikacija;
    final vsebina = await n.izvoziPogled();
    await api.posljiPogled(vsebina);
    await n.oznaciPogled(vsebina);
    messenger.showSnackBar(const SnackBar(content: Text('Nastavitve pogleda so poslane.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Pošiljanje ni uspelo: $e')));
  }
}

/// Barva ozadja vrstice: privzeta (tema) ali ena od ponujenih.
class IzbiraBarve extends StatelessWidget {
  const IzbiraBarve({super.key, required this.naslov, required this.barva, required this.izberi});

  final String naslov;
  final int? barva;
  final void Function(int?) izberi;

  static const barve = [
    0xFF1565C0,
    0xFF00838F,
    0xFF2E7D32,
    0xFF9E9D24,
    0xFFF9A825,
    0xFFEF6C00,
    0xFFC62828,
    0xFFAD1457,
    0xFF6A1B9A,
    0xFF37474F,
    0xFF000000,
    0xFFFFFFFF,
  ];

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    Widget krog(int? b) => InkWell(
      customBorder: const CircleBorder(),
      onTap: () => izberi(b),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: b == null ? tema.colorScheme.surfaceContainer : Color(b),
          border: Border.all(
            color: b == barva ? tema.colorScheme.primary : tema.dividerColor,
            width: b == barva ? 3 : 1,
          ),
        ),
        child: b == null ? const Icon(Icons.format_color_reset, size: 16) : null,
      ),
    );
    return ListTile(
      title: Text(naslov),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: [krog(null), for (final b in barve) krog(b)]),
      ),
    );
  }
}

/// Okno za urejanje oblačka: podatek, velikost, kot in barva.
Future<Oblacek?> _urediOblacek(BuildContext context, Oblacek zacetni) => showDialog<Oblacek>(
  context: context,
  builder: (context) {
    var o = zacetni;
    return StatefulBuilder(
      builder: (context, nastavi) => AlertDialog(
        title: const Text('Oblaček'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<InfoVrstice>(
                  initialValue: o.vsebina,
                  decoration: const InputDecoration(labelText: 'Podatek'),
                  items: [
                    for (final v in InfoVrstice.values)
                      if (v != InfoVrstice.nic) DropdownMenuItem(value: v, child: Text(v.ime)),
                  ],
                  onChanged: (v) => v == null ? null : nastavi(() => o = o.kopija(vsebina: v)),
                ),
                const SizedBox(height: 16),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final (i, ime) in Oblacek.velikosti.indexed) ButtonSegment(value: i, label: Text(ime)),
                  ],
                  selected: {o.velikost},
                  onSelectionChanged: (v) => nastavi(() => o = o.kopija(velikost: v.first)),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, icon: Icon(Icons.north_west), label: Text('Levo')),
                    ButtonSegment(value: false, icon: Icon(Icons.north_east), label: Text('Desno')),
                  ],
                  selected: {o.levo},
                  onSelectionChanged: (v) => nastavi(() => o = o.kopija(levo: v.first)),
                ),
                IzbiraBarve(
                  naslov: 'Barva oblačka',
                  barva: o.barva,
                  izberi: (b) => nastavi(() => o = o.kopija(barva: () => b)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
          FilledButton(
            key: const ValueKey('shrani-oblacek'),
            onPressed: () => Navigator.pop(context, o),
            child: const Text('Shrani'),
          ),
        ],
      ),
    );
  },
);
