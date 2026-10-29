import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../chordpro.dart' as cp;
import '../models.dart';
import '../prijava.dart';
import 'midi_zaslon.dart';
import 'pesem_zaslon.dart';
import 'prijava_zaslon.dart';

/// Prijava: na Androidu sistemsko okno, v brskalniku zaslon z Googlovim gumbom.
Future<void> odpriPrijavo(NavigatorState navigator, Prijava prijava) async {
  if (!kIsWeb) return prijava.prijavi();
  await navigator.push(MaterialPageRoute<void>(builder: (_) => PrijavaZaslon(prijava: prijava, zapriObPrijavi: true)));
}

/// Api za shranjevanje sprememb; brez prijave pokaže opozorilo in vrne null.
Api? apiZaUrejanje(BuildContext context, Prijava prijava) {
  if (prijava.prijavljen) return Api(prijava.zeton);
  final navigator = Navigator.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Za urejanje se prijavi z Google računom (potreben je internet).'),
      action: SnackBarAction(label: 'Prijava', onPressed: () => odpriPrijavo(navigator, prijava)),
    ),
  );
  return null;
}

/// Vpraša, ali res zapustiti zaslon z neshranjenimi spremembami.
Future<bool> potrdiOdhod(BuildContext context) async {
  final odg = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Zavrži spremembe?'),
      content: const Text('Sprememb še nisi shranil.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Nadaljuj z urejanjem')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Zavrži')),
      ],
    ),
  );
  return odg ?? false;
}

/// Šteje odprte urejevalnike, da jih sledenje vodji na špilu ne zapre sredi urejanja.
mixin OdprtoUrejanje<T extends StatefulWidget> on State<T> {
  static int odprtih = 0;

  @override
  void initState() {
    super.initState();
    odprtih++;
  }

  @override
  void dispose() {
    odprtih--;
    super.dispose();
  }
}

/// Vse o pesmi na enem zaslonu: podatki, besedilo s predogledom, PDF-ji in MIDI.
/// En gumb Shrani shrani vse spremenjeno. Ob uspehu vrne shranjeno [Pesem].
class UrejanjePesmiZaslon extends StatefulWidget {
  const UrejanjePesmiZaslon({super.key, required this.baza, required this.api, this.pesem, this.zavihek = 0});

  final Baza baza;
  final Api api;
  final Pesem? pesem;

  /// Zavihek, ki je odprt ob začetku (0 podatki, 1 besedilo, ...).
  final int zavihek;

  static const zavihekBesedila = 1;

  @override
  State<UrejanjePesmiZaslon> createState() => _UrejanjePesmiZaslonState();
}

class _UrejanjePesmiZaslonState extends State<UrejanjePesmiZaslon> with OdprtoUrejanje {
  // Stolpec v listu Pesmi, številska tipkovnica, predlogi iz obstoječih pesmi.
  static const _polja = [
    ('Koda', true, false),
    ('Naslov', false, false),
    ('Izvajalec', false, true),
    ('Avtor glasbe', false, true),
    ('Avtor besedila', false, true),
    ('Zvrst', false, true),
    ('Vrsta', false, true),
    ('Tonaliteta', false, false),
    ('Harmonika', false, false),
    ('Tempo (BPM)', true, false),
    ('Opombe', false, false),
  ];
  static const _poljaMidi = [
    ('MIDI ob odprtju', 'Ukazi pesmi ob odprtju (npr. cue na Multiplayu).'),
    ('Makro ob odprtju', 'Pošlje se za ukazi pesmi.'),
    ('Makro ob zaprtju', 'Pošlje se, ko pesem zapreš ali odpreš naslednjo.'),
  ];

  late final Map<String, TextEditingController> _vnosi = {
    for (final stolpec in [..._polja.map((p) => p.$1), ..._poljaMidi.map((p) => p.$1)])
      stolpec: TextEditingController(text: besedilo(widget.pesem?.vrstica[stolpec]))..addListener(_spremenjenaPesem),
  };
  late bool _aktivna = widget.pesem?.aktivna ?? true;
  late final Set<String> _skupine = {
    ...?widget.pesem?.skupine,
    if (widget.pesem == null && widget.baza.urednikSkupine.isNotEmpty) widget.baza.urednikSkupine.first,
  };

  late final BesediloPesmi? _besedilo = widget.pesem == null
      ? null
      : widget.baza.besedilaPesmi[widget.pesem!.id]?.firstOrNull;
  late final _vsebina = TextEditingController(text: _besedilo?.vsebina ?? '')..addListener(_spremenjenoBesedilo);
  late final _opombeBesedila = TextEditingController(text: _besedilo?.opombe ?? '')..addListener(_spremenjenoBesedilo);
  late String _vrsta = BesediloPesmi.vrste.contains(_besedilo?.vrsta) ? _besedilo!.vrsta : BesediloPesmi.vrste.first;

  /// Ali ima član na besedilu risbe (opozorilo, da se ob spremembi vrstic lahko zamaknejo).
  bool _risbeNaBesedilu = false;

  bool _spremembePesmi = false;
  bool _spremembeBesedila = false;
  bool _izbrisiBesedilo = false;
  bool _shranjujem = false;

  bool get _spremembe => _spremembePesmi || _spremembeBesedila;

  @override
  void initState() {
    super.initState();
    final p = widget.pesem;
    if (p != null) {
      widget.baza.risbe.nalozi(p.id).then((r) {
        final ima = (r.poteze[0]?.isNotEmpty ?? false) || (r.opombe[0]?.isNotEmpty ?? false);
        if (ima && mounted) setState(() => _risbeNaBesedilu = true);
      });
    }
  }

  void _spremenjenaPesem() {
    if (!_spremembePesmi) setState(() => _spremembePesmi = true);
  }

  void _spremenjenoBesedilo() {
    if (!_spremembeBesedila) setState(() => _spremembeBesedila = true);
  }

  @override
  void dispose() {
    for (final c in _vnosi.values) {
      c.dispose();
    }
    _vsebina.dispose();
    _opombeBesedila.dispose();
    super.dispose();
  }

  String? _opozoriloKode() {
    final koda = _vnosi['Koda']!.text.trim();
    if (koda.isEmpty) return null;
    final ista = widget.baza.pesmi.where((p) => p.koda == koda && p.id != widget.pesem?.id);
    return ista.isEmpty ? null : 'Koda je že zasedena: ${ista.first.naslov}';
  }

  /// [zavihki] je kontekst pod DefaultTabController, da ob napaki pokaže zavihek s podatki.
  Future<void> _shrani(BuildContext zavihki) async {
    final messenger = ScaffoldMessenger.of(context);
    final tabs = DefaultTabController.of(zavihki);
    if (_vnosi['Naslov']!.text.trim().isEmpty) {
      tabs.animateTo(0);
      messenger.showSnackBar(const SnackBar(content: Text('Pesem mora imeti naslov.')));
      return;
    }
    if (_skupine.isEmpty) {
      tabs.animateTo(0);
      messenger.showSnackBar(const SnackBar(content: Text('Izberi vsaj eno skupino.')));
      return;
    }
    setState(() => _shranjujem = true);
    try {
      var pesem = widget.pesem;
      if (_spremembePesmi || pesem == null) {
        pesem = await widget.baza.shraniPesem(widget.api, {
          if (widget.pesem != null) 'ID': widget.pesem!.id,
          for (final e in _vnosi.entries) e.key: e.value.text.trim(),
          'Aktivna': _aktivna,
          'Skupine': _skupine.join(','),
        });
        _spremembePesmi = false;
      }
      final prazno = _vsebina.text.trim().isEmpty;
      // Novo prazno besedilo ne pošiljamo; obstoječe izpraznjeno pomeni brisanje.
      if (_spremembeBesedila && !(prazno && _besedilo == null)) {
        await widget.baza.shraniBesedilo(widget.api, {
          if (_besedilo != null) 'ID': _besedilo.id,
          'Pesem': pesem.id,
          'Vrsta': _vrsta,
          'Besedilo': _izbrisiBesedilo || prazno ? '' : _vsebina.text.trimRight(),
          'Opombe': _opombeBesedila.text.trim(),
        });
      }
      if (mounted) Navigator.pop(context, pesem);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
      if (mounted) setState(() => _shranjujem = false);
    }
  }

  Future<void> _potrdiBrisanje() async {
    final da = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izbriši besedilo?'),
        content: const Text('Besedilo bo ob shranjevanju izbrisano za vse člane. PDF pesmi ostane.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Prekliči')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Izbriši')),
        ],
      ),
    );
    if (da ?? false) {
      _vsebina.clear();
      setState(() => _izbrisiBesedilo = true);
    }
  }

  /// Vstavi besedilo na mesto kazalca; kazalec postavi [nazaj] znakov pred konec vstavljenega.
  void _vstavi(String s, {int nazaj = 0}) {
    final v = _vsebina.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final nov = v.text.replaceRange(sel.start, sel.end, s);
    _vsebina.value = TextEditingValue(
      text: nov,
      selection: TextSelection.collapsed(offset: sel.start + s.length - nazaj),
    );
  }

  void _pretvori() {
    final novo = cp.akordiNadBesedilom(_vsebina.text);
    if (novo == _vsebina.text.replaceAll('\r\n', '\n')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ni vrstic z akordi nad besedilom.')));
      return;
    }
    _vsebina.text = novo;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Akordi so vstavljeni v besedilo.')));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_spremembe || _shranjujem,
      onPopInvokedWithResult: (umaknjen, _) async {
        if (umaknjen) return;
        final navigator = Navigator.of(context);
        if (await potrdiOdhod(context)) navigator.pop();
      },
      child: DefaultTabController(
        length: 5,
        initialIndex: widget.zavihek,
        child: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text(widget.pesem == null ? 'Nova pesem' : widget.pesem!.naslov),
              actions: [
                _shranjujem
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : TextButton.icon(
                        onPressed: () => _shrani(context),
                        icon: const Icon(Icons.save),
                        label: const Text('Shrani'),
                      ),
              ],
              bottom: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Podatki'),
                  Tab(text: 'Besedilo'),
                  Tab(text: 'Predogled'),
                  Tab(text: 'PDF'),
                  Tab(text: 'MIDI'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _podatki(context),
                _urejanjeBesedila(context),
                ListenableBuilder(
                  listenable: _vsebina,
                  builder: (context, _) => _vsebina.text.trim().isEmpty
                      ? const Center(child: Text('Pesem še nima besedila.'))
                      : BesediloPogled(vsebina: _vsebina.text, velikost: 20),
                ),
                _pdfji(context),
                _midi(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _polje(String stolpec, bool stevilo, bool predlogi) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _vnosi[stolpec],
      keyboardType: stevilo ? TextInputType.number : TextInputType.text,
      textCapitalization: stolpec == 'Naslov' ? TextCapitalization.characters : TextCapitalization.sentences,
      maxLines: stolpec == 'Opombe' ? null : 1,
      onChanged: stolpec == 'Koda' ? (_) => setState(() {}) : null,
      decoration: InputDecoration(
        labelText: stolpec,
        border: const OutlineInputBorder(),
        errorText: stolpec == 'Koda' ? _opozoriloKode() : null,
        suffixIcon: predlogi ? _predlogi(stolpec) : null,
      ),
    ),
  );

  Widget _podatki(BuildContext context) {
    final mojeSkupine = widget.baza.skupine.where((s) => widget.baza.urednikSkupine.contains(s.id)).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (stolpec, stevilo, predlogi) in _polja) _polje(stolpec, stevilo, predlogi),
        if (mojeSkupine.length > 1) ...[
          Text('Skupine', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 8,
            children: [
              for (final s in mojeSkupine)
                FilterChip(
                  label: Text(s.ime),
                  selected: _skupine.contains(s.id),
                  onSelected: (da) => setState(() {
                    da ? _skupine.add(s.id) : _skupine.remove(s.id);
                    _spremembePesmi = true;
                  }),
                ),
            ],
          ),
        ],
        if (widget.pesem != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pesem je v repertoarju'),
            subtitle: const Text('Izklopljena pesem se ne prikazuje več v seznamu.'),
            value: _aktivna,
            onChanged: (v) => setState(() {
              _aktivna = v;
              _spremembePesmi = true;
            }),
          ),
      ],
    );
  }

  Widget _urejanjeBesedila(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              DropdownButton<String>(
                value: _vrsta,
                items: [for (final v in BesediloPesmi.vrste) DropdownMenuItem(value: v, child: Text(v))],
                onChanged: (v) => setState(() {
                  _vrsta = v!;
                  _spremembeBesedila = true;
                }),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Vstavi akord [ ]',
                icon: const Icon(Icons.music_note),
                onPressed: () => _vstavi('[]', nazaj: 1),
              ),
              IconButton(
                tooltip: 'Vstavi oznako (npr. Refren)',
                icon: const Icon(Icons.label_outline),
                onPressed: () => _vstavi('{c: Refren}\n'),
              ),
              IconButton(
                tooltip: 'Pretvori akorde nad besedilom',
                icon: const Icon(Icons.auto_fix_high),
                onPressed: _pretvori,
              ),
              if (_besedilo != null)
                IconButton(
                  tooltip: 'Izbriši besedilo',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _potrdiBrisanje,
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Akord napiši v oglatih oklepajih pred zlog: [C]Belo obleko [G7]si že nosila. '
            'Oznaka kitice: {c: Refren}. Besedilo s spleta, kjer so akordi v vrstici nad besedilom, '
            'prilepi in pritisni čarobno palico.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        if (_risbeNaBesedilu)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              'Na besedilu imaš risbe. Če dodaš ali odstraniš vrstice, se risbe pod spremembo zamaknejo.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _vsebina,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Besedilo pesmi'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: TextField(
            controller: _opombeBesedila,
            decoration: const InputDecoration(
              labelText: 'Opombe k besedilu',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _pdfji(BuildContext context) {
    final pdfji = widget.pesem == null ? const <PdfDatoteka>[] : widget.baza.pdfjiPesmi[widget.pesem!.id] ?? const [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pdfji.isEmpty) const Text('Pesem nima PDF-ja.'),
        for (final p in pdfji)
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: Text(p.vrsta.isEmpty ? 'PDF' : p.vrsta),
            subtitle: Text('Vrstni red ${p.vrstniRed}'),
          ),
        const SizedBox(height: 12),
        Text(
          'Dodajanje in menjava PDF-jev iz aplikacije pride kasneje. Do takrat jih dodaš v mapo PDF na Drivu.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _midi(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (stolpec, pomoc) in _poljaMidi)
          PoljeMidi(oznaka: stolpec, vnos: _vnosi[stolpec]!, knjiznica: widget.baza.midi, pomoc: pomoc),
        Text(
          'Ukaze in makre izbereš z +, lahko jih je več (ločeni s ;). Pošlje jih vsaka naprava, '
          'ki ima vklopljen MIDI (Nastavitve MIDI).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget? _predlogi(String stolpec) {
    final vrednosti = widget.baza.vrednosti(stolpec);
    if (vrednosti.isEmpty) return null;
    return PopupMenuButton<String>(
      tooltip: 'Izberi obstoječo vrednost',
      icon: const Icon(Icons.arrow_drop_down),
      onSelected: (v) => _vnosi[stolpec]!.text = v,
      itemBuilder: (_) => [for (final v in vrednosti) PopupMenuItem(value: v, child: Text(v))],
    );
  }
}
