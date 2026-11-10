import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../filtri.dart';
import '../models.dart';
import '../nastavitve.dart';
import '../prijava.dart';
import '../snemanje.dart';
import '../uvodi.dart';
import 'efekti_zaslon.dart';
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
                onTap: () => _posljiPogled(context, Api(prijava.zeton), baza),
              ),
              _ObracanjeZaVse(baza: baza, api: Api(prijava.zeton)),
              _Tyros(baza: baza, api: Api(prijava.zeton)),
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
              key: const ValueKey('skrij-igrane'),
              title: const Text('V iskalniku skrij igrane pesmi'),
              subtitle: const Text('Ob listanju jih ni; ko vpišeš besedo, jih iskalnik najde.'),
              value: n.skrijIgrane,
              onChanged: n.nastaviSkrijIgrane,
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
              title: const Text('Usmeritev zaslona'),
              subtitle: const Text('Zaklep na tej napravi (Android; na iPadu v nadzornem centru)'),
              trailing: DropdownButton<Usmeritev>(
                key: const ValueKey('usmeritev'),
                value: n.usmeritev,
                onChanged: (u) => u == null ? null : n.nastaviUsmeritev(u),
                items: [for (final u in Usmeritev.values) DropdownMenuItem(value: u, child: Text(u.ime))],
              ),
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
            _ZvokNastavitve(baza: baza, prijava: prijava),
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
Future<void> _posljiPogled(BuildContext context, Api api, Baza baza) async {
  final messenger = ScaffoldMessenger.of(context);
  final da = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Pošlji nastavitve pogleda?'),
      content: const Text(
        'Vsi člani bodo ob naslednji osvežitvi vprašani, ali prevzamejo tvoje nastavitve pogleda. '
        'Zraven so tvoji hitri filtri po mapah. Povečave posameznih pesmi, zasedba in MIDI ostanejo njihovi.',
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
    // Zraven gredo tudi moji hitri filtri po mapah (prejemnik jih ob prevzemu shrani k sebi).
    final filtri = baza.mojeNastavitve[FiltriClana.kljuc];
    final vsebina = filtri == null
        ? await n.izvoziPogled()
        : jsonEncode({...(jsonDecode(await n.izvoziPogled()) as Map), 'filtri': filtri});
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

/// Zvočni uvodi, playback ter zvočni vhod in izhoda naprave.
class _ZvokNastavitve extends StatefulWidget {
  const _ZvokNastavitve({required this.baza, this.prijava});

  final Baza baza;
  final Prijava? prijava;

  @override
  State<_ZvokNastavitve> createState() => _ZvokNastavitveState();
}

class _ZvokNastavitveState extends State<_ZvokNastavitve> {
  List<IzhodZvoka>? _izhodi;
  List<VhodZvoka>? _vhodi;
  String? _vhod;
  final _prenasam = <VrstaZvoka>{};

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _naprave();
  }

  Future<void> _naprave() async {
    List<IzhodZvoka> izhodi = const [];
    List<VhodZvoka> vhodi = const [];
    try {
      izhodi = await Predvajanje.uvodi.izhodi();
    } catch (_) {}
    try {
      vhodi = await SnemanjeSpila.aplikacija.vhodi();
    } catch (_) {}
    final vhod = await SnemanjeSpila.aplikacija.shranjenVhod();
    if (!mounted) return;
    setState(() {
      _izhodi = izhodi;
      _vhodi = vhodi;
      _vhod = vhod;
    });
  }

  Future<void> _hrani(VrstaZvoka v, bool da) async {
    final messenger = ScaffoldMessenger.of(context);
    await Nastavitve.aplikacija.nastaviHrani(v, da);
    if (!da) {
      await widget.baza.izbrisiLokalneZvoke(v);
      return;
    }
    final prijava = widget.prijava;
    if (prijava == null || !prijava.prijavljen) return;
    setState(() => _prenasam.add(v));
    try {
      final neuspeli = await widget.baza.prenesiZvoke(Api(prijava.zeton), v);
      messenger.showSnackBar(
        SnackBar(
          content: Text(neuspeli == 0 ? '${v.ime}: vse preneseno.' : '${v.ime}: neuspešnih prenosov: $neuspeli.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _prenasam.remove(v));
    }
  }

  Widget _izbiraIzhoda(VrstaZvoka v) {
    final n = Nastavitve.aplikacija;
    final izhodi = _izhodi;
    return ListTile(
      title: Text(v == VrstaZvoka.uvod ? 'Izhod za uvode' : 'Izhod za playback'),
      subtitle: Text(v == VrstaZvoka.uvod ? 'Npr. slušalke' : 'Npr. ozvočenje (USB zvočna kartica)'),
      trailing: izhodi == null
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : DropdownButton<String>(
              key: ValueKey('izhod-${v.kaj}'),
              value: izhodi.any((i) => i.id == n.izhod(v)) ? n.izhod(v) : '',
              onChanged: (id) => setState(() => n.nastaviIzhod(v, id ?? '')),
              items: [
                const DropdownMenuItem(value: '', child: Text('Privzeti izhod sistema')),
                for (final i in izhodi)
                  DropdownMenuItem(
                    value: i.id,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(i.ime, overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = Nastavitve.aplikacija;
    final izhodi = _izhodi;
    final vhodi = _vhodi;
    return Column(
      children: [
        const ListTile(title: Text('Zvok, uvodi in playback'), subtitle: Text('Velja samo za to napravo.')),
        for (final v in VrstaZvoka.values) ...[
          SwitchListTile(
            key: ValueKey('predvajaj-${v.kaj}'),
            title: Text(v == VrstaZvoka.uvod ? 'Predvajaj uvode na tej napravi' : 'Predvajaj playback na tej napravi'),
            subtitle: Text(
              v == VrstaZvoka.uvod
                  ? 'Zvočni uvod pesmi ob odprtju, ko je uho v orodni vrstici vklopljeno'
                  : 'Gumb ▶/■ v orodni vrstici pri pesmih s playbackom (tudi nožno stikalo)',
            ),
            value: n.predvajaj(v),
            onChanged: (da) => setState(() => n.nastaviPredvajaj(v, da)),
          ),
          SwitchListTile(
            key: ValueKey('hrani-${v.kaj}'),
            title: Text(v == VrstaZvoka.uvod ? 'Hrani uvode lokalno' : 'Hrani playback lokalno'),
            subtitle: Text(
              _prenasam.contains(v)
                  ? 'Prenašam …'
                  : 'Ob osvežitvi prenese vse na napravo (deluje brez interneta); sicer se predvaja s spleta',
            ),
            value: n.hrani(v),
            onChanged: _prenasam.contains(v) ? null : (da) => setState(() => _hrani(v, da)),
          ),
          if (!kIsWeb && (izhodi == null || izhodi.isNotEmpty)) _izbiraIzhoda(v),
        ],
        ListTile(
          key: const ValueKey('nastavitve-efekti'),
          leading: const Icon(Icons.graphic_eq),
          title: const Text('Zvočni efekti (FX)'),
          subtitle: const Text('Knjižnica efektov, predvajanje na tej napravi, hrani lokalno, izhod'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EfektiZaslon(
                baza: widget.baza,
                api: () => widget.prijava?.prijavljen ?? false ? Api(widget.prijava!.zeton) : null,
              ),
            ),
          ),
        ),
        if (!kIsWeb)
          ListTile(
            title: const Text('Zvočni vhod'),
            subtitle: const Text('Za snemanje uvodov, playbacka in špila'),
            trailing: vhodi == null
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : DropdownButton<String>(
                    key: const ValueKey('vhod-zvoka'),
                    value: vhodi.any((v) => v.id == _vhod) ? _vhod : '',
                    onChanged: (v) async {
                      await SnemanjeSpila.aplikacija.nastaviVhod(v == null || v.isEmpty ? null : v);
                      setState(() => _vhod = v);
                    },
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Privzeti vhod sistema')),
                      for (final v in vhodi)
                        DropdownMenuItem(
                          value: v.id,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(v.ime, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}

/// Administrator: ali sledilci obračajo pesmi za vse (naslednja, prejšnja), tudi neprijavljeni iPadi.
class _ObracanjeZaVse extends StatefulWidget {
  const _ObracanjeZaVse({required this.baza, required this.api});

  final Baza baza;
  final Api api;

  @override
  State<_ObracanjeZaVse> createState() => _ObracanjeZaVseState();
}

class _ObracanjeZaVseState extends State<_ObracanjeZaVse> {
  bool _shranjujem = false;

  Future<void> _shrani({required bool vsi, required bool neprijavljeni}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _shranjujem = true);
    try {
      await widget.baza.shraniObracanje(widget.api, vsi: vsi, neprijavljeni: neprijavljeni);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
    } finally {
      if (mounted) setState(() => _shranjujem = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.baza.obracanje;
    return Column(
      children: [
        SwitchListTile(
          key: const ValueKey('obracajo-vsi'),
          secondary: const Icon(Icons.swap_horiz),
          title: const Text('Vsak lahko obrne pesem za vse'),
          subtitle: const Text(
            'Na špilu naslednja in prejšnja (podrsaj, nožno stikalo, čakalna vrsta) na kateri koli napravi '
            'zamenjata pesem vsem. Izklopljeno: obrača le vodja. Velja za vse naprave.',
          ),
          value: o.vsi,
          onChanged: _shranjujem ? null : (v) => _shrani(vsi: v, neprijavljeni: v && o.neprijavljeni),
        ),
        if (o.vsi)
          SwitchListTile(
            key: const ValueKey('obracajo-neprijavljeni'),
            secondary: const SizedBox(width: 24),
            title: const Text('Tudi neprijavljene naprave (iPadi prek Safarija)'),
            subtitle: const Text('iPadi dobijo nastavitev, ko se znova povežejo z vodjo.'),
            value: o.neprijavljeni,
            onChanged: _shranjujem ? null : (v) => _shrani(vsi: true, neprijavljeni: v),
          ),
      ],
    );
  }
}

/// Klaviatura Tyros (administrator, skupno vsem): kanal in ali gre pred Program Change banka (CC 0).
class _Tyros extends StatefulWidget {
  const _Tyros({required this.baza, required this.api});

  final Baza baza;
  final Api api;

  @override
  State<_Tyros> createState() => _TyrosState();
}

class _TyrosState extends State<_Tyros> {
  bool _shranjujem = false;

  Future<void> _shrani({required int kanal, required bool banka}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _shranjujem = true);
    try {
      await widget.baza.shraniTyros(widget.api, kanal: kanal, banka: banka);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
    } finally {
      if (mounted) setState(() => _shranjujem = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.baza.tyros;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.piano_outlined),
          title: const Text('Tyros: MIDI kanal'),
          subtitle: const Text(
            'Za preset ob odprtju pesmi (polje Povezava Tyros). Pošilja le naprava, ki ima to vklopljeno '
            'v Nastavitvah MIDI.',
          ),
          trailing: DropdownButton<int>(
            key: const ValueKey('tyros-kanal'),
            value: t.kanal,
            onChanged: _shranjujem ? null : (v) => _shrani(kanal: v ?? 1, banka: t.banka),
            items: [for (var k = 1; k <= 16; k++) DropdownMenuItem(value: k, child: Text('$k'))],
          ),
        ),
        SwitchListTile(
          key: const ValueKey('tyros-banka'),
          secondary: const SizedBox(width: 24),
          title: const Text('Tyros: pred programom pošlji banko (CC 0)'),
          subtitle: const Text('Izklopi, če klaviatura izbere napačen preset.'),
          value: t.banka,
          onChanged: _shranjujem ? null : (v) => _shrani(kanal: t.kanal, banka: v),
        ),
      ],
    );
  }
}
