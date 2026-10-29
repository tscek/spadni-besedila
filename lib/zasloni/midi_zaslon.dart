import 'package:flutter/material.dart';

import '../baza.dart';
import '../midi/midi.dart';
import '../midi/prenos.dart';
import '../midi/ukazi.dart';
import '../prijava.dart';
import 'urejanje_pesmi.dart';

/// Barva gumba MIDI po imenu iz baze (prazno: privzeta).
ButtonStyle? barvaGumba(String barva) {
  final c = switch (barva) {
    'rdeča' => Colors.red,
    'oranžna' => Colors.orange,
    'rumena' => Colors.amber,
    'zelena' => Colors.green,
    'modra' => Colors.blue,
    'vijolična' => Colors.purple,
    _ => null,
  };
  if (c == null) return null;
  return FilledButton.styleFrom(backgroundColor: c.shade700, foregroundColor: Colors.white);
}

/// Pošlje ukaze in javi, če MIDI na tej napravi ni vklopljen ali ni kam poslati.
Future<void> preizkusiMidi(BuildContext context, KnjiznicaMidi k, String zapis) async {
  final messenger = ScaffoldMessenger.of(context);
  final midi = Midi.aplikacija;
  final ukazi = k.razsiri(zapis);
  if (ukazi.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Ni ukazov za pošiljanje.')));
    return;
  }
  if (!midi.vklopljen) {
    messenger.showSnackBar(const SnackBar(content: Text('MIDI je na tej napravi izklopljen (Nastavitve MIDI).')));
    return;
  }
  await midi.poslji(ukazi, knjiznica: k);
  final brez = ukazi.where((u) => midi.napraveZa(u.izhod).isEmpty).length;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        brez == 0 ? 'Poslano: ${ukazi.length} ukazov.' : 'Poslano, a $brez od ${ukazi.length} ukazov ni imelo naprave.',
      ),
    ),
  );
}

/// Nastavitve MIDI na tej napravi: vklop, naprave in preslikava izhodov.
class MidiNastavitveZaslon extends StatelessWidget {
  const MidiNastavitveZaslon({super.key, required this.baza});

  final Baza baza;

  @override
  Widget build(BuildContext context) {
    final midi = Midi.aplikacija;
    return Scaffold(
      appBar: AppBar(title: const Text('Nastavitve MIDI')),
      body: ListenableBuilder(
        listenable: midi,
        builder: (context, _) {
          final tema = Theme.of(context);
          final imenaNaprav = {...midi.shranjeneNaprave, ...midi.naprave.map((n) => n.ime)}.toList()..sort();
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              SwitchListTile(
                title: const Text('Pošiljaj MIDI s te naprave'),
                subtitle: const Text('Ob odprtju in zaprtju pesmi ter z gumbi. Velja samo za to napravo.'),
                value: midi.vklopljen,
                onChanged: midi.vklopi,
              ),
              if (midi.napaka case final n?)
                ListTile(
                  leading: Icon(Icons.error_outline, color: tema.colorScheme.error),
                  title: Text(n),
                ),
              if (midi.vklopljen) ...[
                const Divider(),
                ListTile(
                  title: Text('Naprave', style: tema.textTheme.titleMedium),
                  subtitle: const Text('Vklopljene naprave se ob zagonu povežejo same.'),
                  trailing: midi.iscem
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton.icon(
                          onPressed: midi.isci,
                          icon: const Icon(Icons.search),
                          label: const Text('Išči'),
                        ),
                ),
                if (midi.naprave.isEmpty)
                  const ListTile(
                    title: Text('Ni najdenih naprav'),
                    subtitle: Text('Vklopi napravo MIDI (Bluetooth ali USB) in pritisni Išči.'),
                  ),
                for (final n in midi.naprave) _naprava(midi, n),
                const Divider(),
                ListTile(
                  title: Text('Izhodi', style: tema.textTheme.titleMedium),
                  subtitle: const Text('Ukaz gre na izhod, ki ga ima nastavljenega, sicer na Privzeti.'),
                ),
                for (final izhod in baza.midi.izhodi) _izhod(midi, izhod, imenaNaprav),
                const Divider(),
                ListTile(
                  title: Text('Nožno stikalo (MIDI vhod)', style: tema.textTheme.titleMedium),
                  subtitle: Text(
                    'Pritisni Nauči in nato stikalo. '
                    'Nazadnje prejeto: ${midi.zadnjePrejeto ?? 'še nič'}',
                  ),
                ),
                for (final d in DejanjeMidi.values) _vhod(context, midi, d),
              ],
              const Divider(),
              ListTile(title: Text('Nazadnje poslano', style: tema.textTheme.titleMedium)),
              if (midi.dnevnik.isEmpty) const ListTile(title: Text('Še nič.')),
              for (final p in midi.dnevnik)
                ListTile(
                  dense: true,
                  title: Text(p.opis),
                  subtitle: Text(
                    '${_cas(p.cas)} · ${p.izhod} → ${p.naprave.isEmpty ? 'ni naprave' : p.naprave.join(', ')}',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _cas(DateTime t) =>
      '${t.hour}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  Widget _naprava(Midi midi, NapravaMidi n) => SwitchListTile(
    secondary: Icon(n.vrsta == 'Bluetooth' ? Icons.bluetooth : Icons.usb),
    title: Text(n.ime),
    subtitle: Text([if (n.vrsta.isNotEmpty) n.vrsta, n.povezana ? 'povezana' : 'ni povezana'].join(' · ')),
    value: midi.shranjeneNaprave.contains(n.ime),
    onChanged: (da) => midi.povezi(n, da),
  );

  Widget _vhod(BuildContext context, Midi midi, DejanjeMidi d) {
    final ucim = midi.ucim == d;
    final sprozilec = midi.vhod[d];
    return ListTile(
      title: Text(d.oznaka),
      subtitle: Text(ucim ? 'Pritisni stikalo …' : sprozilec ?? 'ni nastavljeno'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: () => midi.uci(ucim ? null : d), child: Text(ucim ? 'Prekliči' : 'Nauči')),
          if (sprozilec != null)
            IconButton(tooltip: 'Odstrani', icon: const Icon(Icons.close), onPressed: () => midi.nastaviVhod(d, null)),
        ],
      ),
    );
  }

  Widget _izhod(Midi midi, String izhod, List<String> imenaNaprav) {
    final privzeti = izhod == privzetiIzhod;
    final moznosti = <String, String>{
      vsePovezane: privzeti ? 'Vse povezane naprave' : 'Kot Privzeti',
      for (final i in imenaNaprav) i: i,
      nePosiljaj: 'Ne pošiljaj',
    };
    final izbrano = midi.izhodi[izhod] ?? vsePovezane;
    return ListTile(
      title: Text(izhod),
      trailing: DropdownButton<String>(
        value: moznosti.containsKey(izbrano) ? izbrano : vsePovezane,
        items: [for (final e in moznosti.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => midi.nastaviIzhod(izhod, v ?? vsePovezane),
      ),
    );
  }
}

/// Ukazi, makri in imena kanalov zasedbe (skupni za vse, shranjeni v bazi).
class MidiKnjiznicaZaslon extends StatelessWidget {
  const MidiKnjiznicaZaslon({super.key, required this.baza, required this.prijava});

  final Baza baza;
  final Prijava prijava;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: ListenableBuilder(
        listenable: baza,
        builder: (context, _) {
          final k = baza.midi;
          return Scaffold(
            appBar: AppBar(
              title: const Text('MIDI ukazi in makri'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Ukazi'),
                  Tab(text: 'Makri'),
                  Tab(text: 'Gumbi'),
                  Tab(text: 'Kanali'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _seznam([
                  for (final u in k.ukazi)
                    ListTile(
                      title: Text(u.ime),
                      subtitle: Text(
                        [u.opis(k.imeKanala(u.kanal)), if (u.izhod.isNotEmpty) 'izhod ${u.izhod}'].join(' · '),
                      ),
                      trailing: _gumbPoslji(context, k, u.ime),
                      onTap: () => _urediUkaz(context, u),
                    ),
                ], 'Ni še ukazov.'),
                _seznam([
                  for (final m in k.makri)
                    ListTile(
                      title: Text(m.ime),
                      subtitle: Text([m.koraki.join(' · '), if (m.izhod.isNotEmpty) 'izhod ${m.izhod}'].join('\n')),
                      isThreeLine: m.izhod.isNotEmpty,
                      trailing: _gumbPoslji(context, k, m.ime),
                      onTap: () => _urediMakro(context, m),
                    ),
                ], 'Ni še makrov.'),
                _seznam([
                  for (final g in [
                    ...k.gumbi.where((g) => g.pesem.isEmpty),
                    ...k.gumbi.where((g) => g.pesem.isNotEmpty),
                  ])
                    ListTile(
                      title: Text(g.ime),
                      subtitle: Text('${_pesemGumba(g)} · ${g.ukazi}'),
                      trailing: _gumbPoslji(context, k, g.ukazi),
                      onTap: () => _urediGumb(context, g),
                    ),
                ], 'Ni še gumbov. Gumb pošlje ukaze ali makre in ga sprožiš tudi z nožnim stikalom.'),
                _seznam([
                  for (var c = 1; c <= 16; c++)
                    ListTile(
                      leading: CircleAvatar(child: Text('$c')),
                      title: Text(k.imeKanala(c).isEmpty ? '—' : k.imeKanala(c)),
                      onTap: () => _urediKanal(context, c),
                    ),
                ], ''),
              ],
            ),
            floatingActionButton: Builder(
              builder: (context) => FloatingActionButton(
                tooltip: 'Dodaj',
                onPressed: () => switch (DefaultTabController.of(context).index) {
                  1 => _urediMakro(context, null),
                  2 => _urediGumb(context, null),
                  _ => _urediUkaz(context, null),
                },
                child: const Icon(Icons.add),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _seznam(List<Widget> vrstice, String prazno) => vrstice.isEmpty
      ? Center(child: Text(prazno))
      : ListView(padding: const EdgeInsets.only(bottom: 88), children: vrstice);

  Widget _gumbPoslji(BuildContext context, KnjiznicaMidi k, String ime) => IconButton(
    tooltip: 'Pošlji',
    icon: const Icon(Icons.play_arrow),
    onPressed: () => preizkusiMidi(context, k, ime),
  );

  /// Shrani na strežnik; ob napaki pokaže sporočilo in vrne false.
  Future<bool> _shrani(
    BuildContext context,
    String tabela,
    Map<String, dynamic> vrstica, {
    bool izbrisi = false,
  }) async {
    final api = apiZaUrejanje(context, prijava);
    if (api == null) return false;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await baza.shraniMidi(api, tabela, vrstica, izbrisi: izbrisi);
      return true;
    } catch (e) {
      final s = e.toString();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            s.contains('Neznana akcija')
                ? 'Skripta še ne zna shraniti MIDI ukazov. Uvedi novo različico skripte.'
                : 'Shranjevanje ni uspelo: $s',
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _urediUkaz(BuildContext context, MidiUkaz? u) async {
    final nov = await showDialog<(MidiUkaz, bool)>(
      context: context,
      builder: (_) => _UkazDialog(baza: baza, ukaz: u),
    );
    if (nov == null || !context.mounted) return;
    final (ukaz, izbrisi) = nov;
    await _shrani(context, 'MIDI ukazi', ukaz.vVrstico(), izbrisi: izbrisi);
  }

  Future<void> _urediMakro(BuildContext context, Makro? m) async {
    final nov = await Navigator.of(context).push(
      MaterialPageRoute<(Makro, bool)>(
        builder: (_) => _MakroZaslon(baza: baza, makro: m),
      ),
    );
    if (nov == null || !context.mounted) return;
    final (makro, izbrisi) = nov;
    await _shrani(context, 'Makri', makro.vVrstico(), izbrisi: izbrisi);
  }

  String _pesemGumba(MidiGumb g) {
    if (g.pesem.isEmpty) return 'pri vseh pesmih';
    final p = baza.pesem(g.pesem);
    return p == null ? 'pesem ni v repertoarju' : '${p.koda} ${p.naslov}';
  }

  Future<void> _urediGumb(BuildContext context, MidiGumb? g) async {
    final nov = await showDialog<(MidiGumb, bool)>(
      context: context,
      builder: (_) => _GumbDialog(baza: baza, gumb: g),
    );
    if (nov == null || !context.mounted) return;
    final (gumb, izbrisi) = nov;
    await _shrani(context, 'MIDI gumbi', gumb.vVrstico(), izbrisi: izbrisi);
  }

  Future<void> _urediKanal(BuildContext context, int kanal) async {
    final vnos = TextEditingController(text: baza.midi.imeKanala(kanal));
    final ime = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Kanal $kanal'),
        content: TextField(
          controller: vnos,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Kaj je na tem kanalu (npr. Luči)'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
          TextButton(onPressed: () => Navigator.pop(context, vnos.text), child: const Text('Shrani')),
        ],
      ),
    );
    if (ime == null || !context.mounted) return;
    await _shrani(context, 'MIDI kanali', {'ID': '$kanal', 'Ime': ime.trim()});
  }
}

/// Polje za izhod s predlogi že uporabljenih izhodov; prazno pomeni Privzeti.
Widget _poljeIzhoda(TextEditingController vnos, List<String> izhodi) => TextField(
  controller: vnos,
  decoration: InputDecoration(
    labelText: 'Izhod',
    hintText: privzetiIzhod,
    helperText: 'Prazno: kot makro oziroma Privzeti',
    suffixIcon: PopupMenuButton<String>(
      tooltip: 'Izberi izhod',
      icon: const Icon(Icons.arrow_drop_down),
      onSelected: (v) => vnos.text = v == privzetiIzhod ? '' : v,
      itemBuilder: (_) => [for (final i in izhodi) PopupMenuItem(value: i, child: Text(i))],
    ),
  ),
);

class _UkazDialog extends StatefulWidget {
  const _UkazDialog({required this.baza, this.ukaz});

  final Baza baza;
  final MidiUkaz? ukaz;

  @override
  State<_UkazDialog> createState() => _UkazDialogState();
}

class _UkazDialogState extends State<_UkazDialog> {
  late final _ime = TextEditingController(text: widget.ukaz?.ime ?? '');
  late VrstaUkaza _vrsta = widget.ukaz?.vrsta ?? VrstaUkaza.cc;
  late int _kanal = widget.ukaz?.kanal ?? 1;
  late final _stevilka = TextEditingController(text: '${widget.ukaz?.stevilka ?? 0}');
  late final _vrednost = TextEditingController(text: '${widget.ukaz?.vrednost ?? 127}');
  late final _izhod = TextEditingController(text: widget.ukaz?.izhod ?? '');
  late final _opombe = TextEditingController(text: widget.ukaz?.opombe ?? '');
  String? _napaka;

  MidiUkaz? _ukaz() {
    final st = int.tryParse(_stevilka.text.trim());
    final vr = _vrsta == VrstaUkaza.pc ? 0 : int.tryParse(_vrednost.text.trim());
    if (_ime.text.trim().isEmpty) {
      setState(() => _napaka = 'Vpiši ime ukaza.');
      return null;
    }
    if (st == null || st < 0 || st > 127 || vr == null || vr < 0 || vr > 127) {
      setState(() => _napaka = 'Številka in vrednost morata biti od 0 do 127.');
      return null;
    }
    return MidiUkaz(
      id: widget.ukaz?.id ?? '',
      skupina: widget.ukaz?.skupina ?? '',
      ime: _ime.text.trim(),
      vrsta: _vrsta,
      kanal: _kanal,
      stevilka: st,
      vrednost: _vrsta == VrstaUkaza.pc ? 127 : vr,
      izhod: _izhod.text.trim(),
      opombe: _opombe.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.baza.midi;
    final smeUrejati = widget.baza.smeUrejati;
    final stevilka = switch (_vrsta) {
      VrstaUkaza.pc => 'Program',
      VrstaUkaza.cc => 'Kontroler (CC)',
      VrstaUkaza.nota => 'Nota',
    };
    return AlertDialog(
      title: Text(widget.ukaz == null ? 'Nov ukaz' : 'Ukaz'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ime,
              decoration: const InputDecoration(labelText: 'Ime (npr. Delay ON)'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<VrstaUkaza>(
              segments: [for (final v in VrstaUkaza.values) ButtonSegment(value: v, label: Text(v.oznaka))],
              selected: {_vrsta},
              onSelectionChanged: (s) => setState(() => _vrsta = s.first),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _kanal,
              decoration: const InputDecoration(labelText: 'Kanal'),
              items: [
                for (var c = 1; c <= 16; c++)
                  DropdownMenuItem(value: c, child: Text(k.imeKanala(c).isEmpty ? '$c' : '$c · ${k.imeKanala(c)}')),
              ],
              onChanged: (v) => setState(() => _kanal = v ?? 1),
            ),
            TextField(
              controller: _stevilka,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: '$stevilka (0–127)'),
            ),
            if (_vrsta != VrstaUkaza.pc)
              TextField(
                controller: _vrednost,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _vrsta == VrstaUkaza.nota ? 'Hitrost (0–127)' : 'Vrednost (0–127)',
                ),
              ),
            _poljeIzhoda(_izhod, k.izhodi),
            TextField(
              controller: _opombe,
              decoration: const InputDecoration(labelText: 'Opombe'),
            ),
            if (_napaka case final n?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(n, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.ukaz != null && smeUrejati)
          TextButton(onPressed: () => Navigator.pop(context, (widget.ukaz!, true)), child: const Text('Izbriši')),
        TextButton(
          onPressed: () {
            final u = _ukaz();
            if (u != null) preizkusiMidi(context, k, u.zapis);
          },
          child: const Text('Preizkusi'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
        if (smeUrejati)
          FilledButton(
            onPressed: () {
              final u = _ukaz();
              if (u != null) Navigator.pop(context, (u, false));
            },
            child: const Text('Shrani'),
          ),
      ],
    );
  }
}

class _GumbDialog extends StatefulWidget {
  const _GumbDialog({required this.baza, this.gumb});

  final Baza baza;
  final MidiGumb? gumb;

  @override
  State<_GumbDialog> createState() => _GumbDialogState();
}

class _GumbDialogState extends State<_GumbDialog> {
  late final _ime = TextEditingController(text: widget.gumb?.ime ?? '');
  late final _ukazi = TextEditingController(text: widget.gumb?.ukazi ?? '');
  late final _koda = TextEditingController(text: widget.baza.pesem(widget.gumb?.pesem ?? '')?.koda ?? '');
  late final _zaporedje = TextEditingController(text: '${widget.gumb?.zaporedje ?? ''}');
  late String _barva = widget.gumb?.barva ?? '';
  String? _napaka;

  @override
  void dispose() {
    for (final c in [_ime, _ukazi, _koda, _zaporedje]) {
      c.dispose();
    }
    super.dispose();
  }

  MidiGumb? _gumb() {
    final koda = _koda.text.trim();
    final pesem = koda.isEmpty ? null : widget.baza.pesmi.where((p) => p.koda == koda).firstOrNull;
    final napaka = _ime.text.trim().isEmpty
        ? 'Vpiši ime gumba.'
        : _ukazi.text.trim().isEmpty
        ? 'Dodaj vsaj en ukaz ali makro.'
        : koda.isNotEmpty && pesem == null
        ? 'Pesmi s kodo $koda ni.'
        : null;
    setState(() => _napaka = napaka);
    if (napaka != null) return null;
    return MidiGumb(
      id: widget.gumb?.id ?? '',
      skupina: widget.gumb?.skupina ?? '',
      pesem: pesem?.id ?? '',
      ime: _ime.text.trim(),
      ukazi: _ukazi.text.trim(),
      barva: _barva,
      zaporedje: int.tryParse(_zaporedje.text.trim()) ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final smeUrejati = widget.baza.smeUrejati;
    return AlertDialog(
      title: Text(widget.gumb == null ? 'Nov gumb' : 'Gumb'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ime,
                decoration: const InputDecoration(labelText: 'Ime (npr. Solo kitara)'),
              ),
              const SizedBox(height: 16),
              PoljeMidi(oznaka: 'Ukazi in makri', vnos: _ukazi, knjiznica: widget.baza.midi),
              TextField(
                controller: _koda,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Koda pesmi',
                  helperText: 'Prazno: gumb je pri vseh pesmih (ti so pred gumbi pesmi).',
                ),
              ),
              TextField(
                controller: _zaporedje,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Zaporedje', helperText: 'Manjše je bolj levo.'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final b in ['', ...MidiGumb.barve])
                    ChoiceChip(
                      label: Text(b.isEmpty ? 'privzeta' : b),
                      selected: _barva == b,
                      onSelected: (_) => setState(() => _barva = b),
                    ),
                ],
              ),
              if (_napaka case final n?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(n, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.gumb != null && smeUrejati)
          TextButton(onPressed: () => Navigator.pop(context, (widget.gumb!, true)), child: const Text('Izbriši')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
        if (smeUrejati)
          FilledButton(
            onPressed: () {
              final g = _gumb();
              if (g != null) Navigator.pop(context, (g, false));
            },
            child: const Text('Shrani'),
          ),
      ],
    );
  }
}

class _MakroZaslon extends StatefulWidget {
  const _MakroZaslon({required this.baza, this.makro});

  final Baza baza;
  final Makro? makro;

  @override
  State<_MakroZaslon> createState() => _MakroZaslonState();
}

class _MakroZaslonState extends State<_MakroZaslon> {
  late final _ime = TextEditingController(text: widget.makro?.ime ?? '');
  late final _izhod = TextEditingController(text: widget.makro?.izhod ?? '');
  late final List<String> _koraki = [...?widget.makro?.koraki];

  Makro get _makro => Makro(
    id: widget.makro?.id ?? '',
    skupina: widget.makro?.skupina ?? '',
    ime: _ime.text.trim(),
    koraki: _koraki,
    izhod: _izhod.text.trim(),
  );

  Future<void> _dodaj() async {
    final korak = await izberiMidi(context, widget.baza.midi, brez: _ime.text.trim());
    if (korak != null) setState(() => _koraki.add(korak));
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.baza.midi;
    final smeUrejati = widget.baza.smeUrejati;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.makro == null ? 'Nov makro' : 'Makro'),
        actions: [
          IconButton(
            tooltip: 'Preizkusi',
            icon: const Icon(Icons.play_arrow),
            onPressed: () => preizkusiMidi(context, k, _koraki.join('; ')),
          ),
          if (widget.makro != null && smeUrejati)
            IconButton(
              tooltip: 'Izbriši makro',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => Navigator.pop(context, (widget.makro!, true)),
            ),
          if (smeUrejati)
            TextButton(
              onPressed: () {
                if (_ime.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vpiši ime makra.')));
                  return;
                }
                Navigator.pop(context, (_makro, false));
              },
              child: const Text('Shrani'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _ime,
            decoration: const InputDecoration(labelText: 'Ime makra', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          _poljeIzhoda(_izhod, k.izhodi),
          const SizedBox(height: 16),
          Text('Koraki (po vrsti)', style: Theme.of(context).textTheme.titleSmall),
          for (var i = 0; i < _koraki.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_koraki[i]),
              subtitle: Text(_opisKoraka(k, _koraki[i])),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Gor',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: i == 0 ? null : () => setState(() => _koraki.insert(i - 1, _koraki.removeAt(i))),
                  ),
                  IconButton(
                    tooltip: 'Odstrani',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _koraki.removeAt(i)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(onPressed: _dodaj, icon: const Icon(Icons.add), label: const Text('Dodaj ukaz')),
          ),
        ],
      ),
    );
  }
}

/// Kratek opis, kaj korak (ime ukaza, makra ali neposreden ukaz) pošlje.
String _opisKoraka(KnjiznicaMidi k, String korak) {
  if (k.makro(korak) != null) return 'makro';
  final u = k.ukaz(korak) ?? razcleniUkaz(korak);
  if (u == null) return 'neznan ukaz';
  return u.opis(k.imeKanala(u.kanal));
}

/// Izbira ukaza ali makra po imenu; vpišeš lahko tudi neposreden ukaz (npr. CC 9 12 127).
Future<String?> izberiMidi(BuildContext context, KnjiznicaMidi k, {String brez = ''}) => showDialog<String>(
  context: context,
  builder: (_) => _IzbiraMidi(knjiznica: k, brez: brez),
);

class _IzbiraMidi extends StatefulWidget {
  const _IzbiraMidi({required this.knjiznica, required this.brez});

  final KnjiznicaMidi knjiznica;
  final String brez;

  @override
  State<_IzbiraMidi> createState() => _IzbiraMidiState();
}

class _IzbiraMidiState extends State<_IzbiraMidi> {
  final _iskanje = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final k = widget.knjiznica;
    final q = _iskanje.text.trim().toLowerCase();
    final imena = k.imena.where((i) => i != widget.brez && i.toLowerCase().contains(q)).toList();
    final neposreden = razcleniUkaz(_iskanje.text);
    return AlertDialog(
      title: const Text('Dodaj ukaz ali makro'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _iskanje,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Išči ali vpiši npr. CC 9 12 127',
              ),
            ),
            if (neposreden != null)
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(_iskanje.text.trim()),
                subtitle: Text(neposreden.opis(k.imeKanala(neposreden.kanal))),
                onTap: () => Navigator.pop(context, _iskanje.text.trim()),
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final i in imena)
                    ListTile(
                      dense: true,
                      title: Text(i),
                      subtitle: Text(_opisKoraka(k, i)),
                      onTap: () => Navigator.pop(context, i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči'))],
    );
  }
}

/// Polje pesmi z ukazi (ločenimi s ;), z izbiro iz knjižnice in predogledom, kaj se pošlje.
class PoljeMidi extends StatelessWidget {
  const PoljeMidi({super.key, required this.oznaka, required this.vnos, required this.knjiznica, this.pomoc});

  final String oznaka;
  final TextEditingController vnos;
  final KnjiznicaMidi knjiznica;
  final String? pomoc;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: ListenableBuilder(
        listenable: vnos,
        builder: (context, _) {
          final ukazi = knjiznica.razsiri(vnos.text);
          final neznani = razdeliZapis(vnos.text).where((d) => knjiznica.razsiri(d).isEmpty).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: vnos,
                decoration: InputDecoration(
                  labelText: oznaka,
                  helperText: pomoc,
                  helperMaxLines: 3,
                  border: const OutlineInputBorder(),
                  errorText: neznani.isEmpty ? null : 'Neznano: ${neznani.join(', ')}',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Dodaj ukaz ali makro',
                        icon: const Icon(Icons.add),
                        onPressed: () async {
                          final i = await izberiMidi(context, knjiznica);
                          if (i == null) return;
                          final t = vnos.text.trim();
                          vnos.text = t.isEmpty ? i : '$t; $i';
                        },
                      ),
                      IconButton(
                        tooltip: 'Preizkusi',
                        icon: const Icon(Icons.play_arrow),
                        onPressed: ukazi.isEmpty ? null : () => preizkusiMidi(context, knjiznica, vnos.text),
                      ),
                    ],
                  ),
                ),
              ),
              for (final u in ukazi)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Text(
                    '${u.ukaz.ime.isEmpty ? '' : '${u.ukaz.ime}: '}${u.ukaz.opis(knjiznica.imeKanala(u.ukaz.kanal))}'
                    '${u.izhod == privzetiIzhod ? '' : ' → ${u.izhod}'}',
                    style: tema.textTheme.bodySmall,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
