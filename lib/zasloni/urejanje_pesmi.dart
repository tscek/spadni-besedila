import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../besedilo_si.dart';
import '../baza.dart';
import '../chordpro.dart' as cp;
import '../midi/ukazi.dart';
import '../models.dart';
import '../prijava.dart';
import '../tap_tempo.dart';
import 'midi_zaslon.dart';
import 'oznake.dart';
import 'predogled.dart';
import 'prijava_zaslon.dart';
import 'urejanje_uvoda.dart';
import 'uvoz_besedilosi.dart';

/// Prijava: na Androidu sistemsko okno, v brskalniku zaslon z Googlovim gumbom.
Future<void> odpriPrijavo(NavigatorState navigator, Prijava prijava) async {
  if (!kIsWeb) return prijava.prijavi();
  await navigator.push(MaterialPageRoute<void>(builder: (_) => PrijavaZaslon(prijava: prijava, zapriObPrijavi: true)));
}

/// Api za shranjevanje sprememb; brez prijave pokaže opozorilo in vrne null.
/// Z [baza] lahko član s pravico urejanja ureja tudi brez prijave (brez interneta); spremembe počakajo na napravi.
Api? apiZaUrejanje(BuildContext context, Prijava prijava, {Baza? baza}) {
  if (prijava.prijavljen) return Api(prijava.zeton);
  if (baza?.smeUrejati ?? false) return Api(() async => throw StateError('Ni prijave'));
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
  const UrejanjePesmiZaslon({
    super.key,
    required this.baza,
    required this.api,
    this.pesem,
    this.zavihek = 0,
    this.mapa,
  });

  final Baza baza;
  final Api api;
  final Pesem? pesem;

  /// Mapa nove pesmi.
  final String? mapa;

  /// Zavihek, ki je odprt ob začetku (0 podatki, 1 besedilo, ...).
  final int zavihek;

  static const zavihekBesedila = 1;

  @override
  State<UrejanjePesmiZaslon> createState() => _UrejanjePesmiZaslonState();
}

enum _Vnos { besedilo, stevilo, predlogi, tonaliteta, harmonika, status, mapa, ocena, trajanje }

class _UrejanjePesmiZaslonState extends State<UrejanjePesmiZaslon> with OdprtoUrejanje {
  final _tapTempo = TapTempo();
  // Stolpec v listu Pesmi in način vnosa. Koda se novi pesmi dodeli sama.
  static const _polja = [
    ('Naslov', _Vnos.besedilo),
    ('Mapa', _Vnos.mapa),
    ('Status', _Vnos.status),
    ('Ocena', _Vnos.ocena),
    ('Izvajalec', _Vnos.predlogi),
    ('Avtor glasbe', _Vnos.predlogi),
    ('Avtor besedila', _Vnos.predlogi),
    ('Vrsta', _Vnos.predlogi),
    ('Zvrst', _Vnos.predlogi),
    ('Tonaliteta', _Vnos.tonaliteta),
    ('Harmonika', _Vnos.harmonika),
    ('Tempo (BPM)', _Vnos.stevilo),
    ('Trajanje', _Vnos.trajanje),
    ('Oznaka', _Vnos.predlogi),
    ('Opombe', _Vnos.besedilo),
  ];
  static const _poljaMidi = [
    ('MIDI ob odprtju', 'Ukazi pesmi ob odprtju (npr. cue na Multiplayu).'),
    ('MIDI za uvod', 'Uvod (npr. PC 1 23): pošlje se ob odprtju takoj za ukazi pesmi, znova z gumbom Uvod na pesmi.'),
    ('Makro ob odprtju', 'Pošlje se za ukazi pesmi.'),
    ('Makro ob zaprtju', 'Pošlje se, ko pesem zapreš ali odpreš naslednjo.'),
  ];

  late final Map<String, TextEditingController> _vnosi = {
    // Pisava (skupna vsem) se nastavi v predogledu.
    for (final stolpec in [..._polja.map((p) => p.$1), ..._poljaMidi.map((p) => p.$1), 'Pisava'])
      stolpec: TextEditingController(text: _zacetna(stolpec))..addListener(_spremenjenaPesem),
  };

  String _zacetna(String stolpec) {
    final p = widget.pesem;
    if (p == null) {
      return switch (stolpec) {
        'Mapa' => widget.mapa ?? '',
        'Status' => StatusPesmi.vDelu.ime,
        _ => '',
      };
    }
    if (stolpec == 'Status') return p.status.ime;
    if (stolpec == 'Ocena') return p.ocena == 0 ? '' : '${p.ocena}';
    // Stari zapis iz SongBooka (3|7|…) se pokaže kot CC / PC / Nota.
    if (_poljaMidi.any((m) => m.$1 == stolpec)) return berljivZapis(besedilo(p.vrstica[stolpec]));
    return besedilo(p.vrstica[stolpec]);
  }

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

  final Map<String, FocusNode> _fokusi = {};

  @override
  void dispose() {
    for (final c in _vnosi.values) {
      c.dispose();
    }
    for (final f in _fokusi.values) {
      f.dispose();
    }
    _vsebina.dispose();
    _opombeBesedila.dispose();
    super.dispose();
  }

  /// Opozorilo, če ima isti MIDI za uvod že druga pesem (dovoljeno je).
  String? _opozoriloUvoda() {
    final uvod = _vnosi['MIDI za uvod']!.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (uvod.isEmpty) return null;
    final iste = widget.baza.pesmi.where(
      (p) => p.id != widget.pesem?.id && p.midiZaUvod.toUpperCase().replaceAll(RegExp(r'\s+'), ' ') == uvod,
    );
    return iste.isEmpty ? null : 'Isti uvod ima že: ${iste.map((p) => p.naslov).join(', ')}';
  }

  /// Trajanje v obliki m:ss.
  String? _napakaTrajanja() {
    final t = _vnosi['Trajanje']!.text.trim();
    if (t.isEmpty || RegExp(r'^\d{1,2}:[0-5]\d$').hasMatch(t)) return null;
    return 'Vpiši minute in sekunde, npr. 3:45';
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
    if (_napakaTrajanja() != null) {
      tabs.animateTo(0);
      messenger.showSnackBar(const SnackBar(content: Text('Trajanje vpiši kot minute:sekunde, npr. 3:45.')));
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
      if (widget.baza.neposlano.isNotEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Ni povezave: shranjeno na napravi, poslano bo, ko bo internet.')),
        );
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

  /// Besedilo in podatki pesmi z besedilo.si; prevzeto se shrani z gumbom Shrani.
  Future<void> _uvozZBesediloSi(BuildContext zavihki) async {
    final tabs = DefaultTabController.of(zavihki);
    final messenger = ScaffoldMessenger.of(context);
    String v(String s) => _vnosi[s]!.text;
    final r = await uvozZBesediloSi(
      context,
      vir: BesediloSi(api: widget.api),
      iskanje: v('Naslov'),
      obstojece: {
        PrevzemBs.besedilo: _vsebina.text,
        PrevzemBs.naslov: v('Naslov'),
        PrevzemBs.izvajalec: v('Izvajalec'),
        PrevzemBs.avtorBesedila: v('Avtor besedila'),
        PrevzemBs.avtorGlasbe: v('Avtor glasbe'),
      },
    );
    if (r == null || !mounted) return;
    final (p, kaj) = r;
    setState(() {
      if (kaj.contains(PrevzemBs.naslov)) _vnosi['Naslov']!.text = p.naslov.toUpperCase();
      if (kaj.contains(PrevzemBs.izvajalec)) _vnosi['Izvajalec']!.text = p.izvajalec;
      if (kaj.contains(PrevzemBs.avtorBesedila)) _vnosi['Avtor besedila']!.text = p.avtorBesedila;
      if (kaj.contains(PrevzemBs.avtorGlasbe)) _vnosi['Avtor glasbe']!.text = p.avtorGlasbe;
      if (kaj.contains(PrevzemBs.besedilo) && p.besedilo != null) {
        _vsebina.text = p.besedilo!;
        _izbrisiBesedilo = false;
        if (_opombeBesedila.text.trim().isEmpty) _opombeBesedila.text = 'Vir: ${p.povezava}';
      }
    });
    if (kaj.contains(PrevzemBs.besedilo)) tabs.animateTo(UrejanjePesmiZaslon.zavihekBesedila);
    messenger.showSnackBar(const SnackBar(content: Text('Prevzeto z besedilo.si. Preglej in pritisni Shrani.')));
  }

  /// Označeno besedilo postane krepko (**…**) ali ni več krepko; brez izbire vstavi par zvezdic.
  void _krepko() {
    final v = _vsebina.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    if (sel.isCollapsed) return _vstavi('****', nazaj: 2);
    final (besedilo, izbira) = cp.preklopiKrepko(v.text, sel.start, sel.end);
    _vsebina.value = TextEditingValue(
      text: besedilo,
      selection: TextSelection(baseOffset: izbira.$1, extentOffset: izbira.$2),
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
                IconButton(
                  key: const ValueKey('besedilosi'),
                  tooltip: 'Uvozi z besedilo.si (besedilo, izvajalec, avtorji)',
                  icon: const Icon(Icons.travel_explore),
                  onPressed: () => _uvozZBesediloSi(context),
                ),
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
                  listenable: Listenable.merge([_vsebina, _vnosi['Pisava']!]),
                  builder: (context, _) => _vsebina.text.trim().isEmpty
                      ? const Center(child: Text('Pesem še nima besedila.'))
                      : PredogledBesedila(
                          vsebina: _vsebina.text,
                          pesem: widget.pesem?.id ?? '',
                          baza: widget.baza,
                          pisava: (double.tryParse(_vnosi['Pisava']!.text.replaceAll(',', '.')) ?? 22)
                              .clamp(12, 64)
                              .toDouble(),
                          obPisavi: (v) => _vnosi['Pisava']!.text = v.round().toString(),
                        ),
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

  Widget _polje(BuildContext context, String stolpec, _Vnos vnos) {
    final c = _vnosi[stolpec]!;
    void nastavi(String v) => setState(() => c.text = v);
    final okvir = InputDecoration(labelText: stolpec, border: const OutlineInputBorder());
    final Widget polje = switch (vnos) {
      // Vrste imajo barve (seznam vrst, skupen vsem).
      _Vnos.predlogi when stolpec == 'Vrsta' => Row(
        children: [
          Expanded(child: _ssPredlogi(stolpec)),
          IconButton(
            tooltip: 'Barve vrst',
            icon: Icon(Icons.palette_outlined, color: barvaVrste(widget.baza, c.text)),
            onPressed: () => _urediSeznam(vrste: true),
          ),
        ],
      ),
      _Vnos.predlogi => _ssPredlogi(stolpec),
      _Vnos.tonaliteta => DropdownButtonFormField<String>(
        initialValue: c.text.isEmpty ? null : c.text,
        decoration: okvir,
        isExpanded: true,
        items: [
          // Stara vrednost, ki je ni na seznamu, ostane izbrana, dokler je ne zamenjaš.
          if (c.text.isNotEmpty && !tonalitete.contains(c.text))
            DropdownMenuItem(value: c.text, child: Text('${c.text} (ni na seznamu)')),
          for (final t in tonalitete)
            DropdownMenuItem(value: t, child: Text(t == t.toLowerCase() ? '$t (mol)' : '$t (dur)')),
        ],
        onChanged: (v) => nastavi(v ?? ''),
      ),
      _Vnos.harmonika => Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: c.text,
              decoration: okvir,
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: '', child: Text('Brez')),
                if (c.text.isNotEmpty && widget.baza.harmonika(c.text) == null)
                  DropdownMenuItem(value: c.text, child: Text(c.text)),
                for (final h in widget.baza.harmonike)
                  DropdownMenuItem(
                    value: h.ime,
                    child: Row(
                      children: [
                        CircleAvatar(radius: 8, backgroundColor: h.argb == null ? Colors.grey : Color(h.argb!)),
                        const SizedBox(width: 8),
                        Text(h.ime),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => nastavi(v ?? ''),
            ),
          ),
          IconButton(
            tooltip: 'Uredi seznam harmonik',
            icon: const Icon(Icons.palette_outlined),
            onPressed: _urediSeznam,
          ),
        ],
      ),
      _Vnos.status => DropdownButtonFormField<String>(
        initialValue: StatusPesmi.iz(c.text).ime,
        decoration: okvir,
        items: [
          for (final st in StatusPesmi.values)
            DropdownMenuItem(
              value: st.ime,
              child: Row(children: [IkonaStatusa(st), const SizedBox(width: 8), Text(st.ime)]),
            ),
        ],
        onChanged: (v) => nastavi(v ?? StatusPesmi.narejen.ime),
      ),
      _Vnos.mapa => DropdownButtonFormField<String>(
        initialValue: c.text,
        decoration: okvir,
        items: [
          const DropdownMenuItem(value: '', child: Text('Brez mape')),
          if (c.text.isNotEmpty && widget.baza.mapa(c.text) == null)
            DropdownMenuItem(value: c.text, child: Text(c.text)),
          for (final m in widget.baza.mape) DropdownMenuItem(value: m.id, child: Text(m.ime)),
        ],
        onChanged: (v) => nastavi(v ?? ''),
      ),
      _Vnos.ocena => InputDecorator(
        decoration: okvir.copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
        child: Zvezdice(ocena: int.tryParse(c.text) ?? 0, velikost: 28, spremeni: (v) => nastavi(v == 0 ? '' : '$v')),
      ),
      _Vnos.besedilo || _Vnos.stevilo || _Vnos.trajanje => TextField(
        controller: c,
        keyboardType: switch (vnos) {
          _Vnos.stevilo => TextInputType.number,
          _Vnos.trajanje => TextInputType.datetime,
          _ => TextInputType.text,
        },
        textCapitalization: stolpec == 'Naslov' ? TextCapitalization.characters : TextCapitalization.sentences,
        maxLines: stolpec == 'Opombe' ? null : 1,
        onChanged: vnos == _Vnos.trajanje ? (_) => setState(() {}) : null,
        decoration: okvir.copyWith(
          hintText: vnos == _Vnos.trajanje ? 'npr. 3:45' : null,
          errorText: vnos == _Vnos.trajanje ? _napakaTrajanja() : null,
          suffixIcon: stolpec == 'Tempo (BPM)'
              ? IconButton(
                  key: const ValueKey('tap-tempo'),
                  tooltip: 'Tap tempo: tapkaj v ritmu',
                  icon: const Icon(Icons.touch_app_outlined),
                  onPressed: () {
                    final bpm = _tapTempo.udari();
                    if (bpm != null && bpm >= 20 && bpm <= 400) c.text = '$bpm';
                  },
                )
              : null,
        ),
      ),
    };
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: polje);
  }

  /// Vnos s predlogi že vpisanih vrednosti, ki se pokažejo med pisanjem.
  Widget _ssPredlogi(String stolpec) {
    final vrednosti = widget.baza.vrednosti(stolpec);
    return LayoutBuilder(
      builder: (context, meje) => RawAutocomplete<String>(
        textEditingController: _vnosi[stolpec],
        focusNode: _fokusi.putIfAbsent(stolpec, FocusNode.new),
        optionsBuilder: (v) {
          final q = poenostavi(v.text);
          if (q.isEmpty) return const Iterable<String>.empty();
          return vrednosti.where((x) => poenostavi(x).contains(q) && x != v.text).take(8);
        },
        fieldViewBuilder: (context, kontroler, fokus, potrdi) => TextField(
          controller: kontroler,
          focusNode: fokus,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => potrdi(),
          decoration: InputDecoration(
            labelText: stolpec,
            border: const OutlineInputBorder(),
            suffixIcon: _predlogi(stolpec),
          ),
        ),
        optionsViewBuilder: (context, izberi, moznosti) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: SizedBox(
              width: meje.maxWidth,
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [for (final m in moznosti) ListTile(dense: true, title: Text(m), onTap: () => izberi(m))],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Seznam harmonik ali vrst z barvami (skupen vsem); harmonikaš vidi barvo v čakalni vrsti.
  Future<void> _urediSeznam({bool vrste = false}) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _UrejanjeBarv(baza: widget.baza, api: widget.api, vrste: vrste),
    );
    if (mounted) setState(() {});
  }

  Widget _podatki(BuildContext context) {
    final mojeSkupine = widget.baza.skupine.where((s) => widget.baza.urednikSkupine.contains(s.id)).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (stolpec, vnos) in _polja) _polje(context, stolpec, vnos),
        if (widget.pesem != null)
          UrejanjeUvoda(baza: widget.baza, api: widget.api, pesem: widget.pesem!.id)
        else
          const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Zvočni uvod dodaš, ko pesem shraniš.')),
        if (widget.pesem != null && widget.pesem!.koda.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Koda: ${widget.pesem!.koda}', style: Theme.of(context).textTheme.bodySmall),
          ),
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
            subtitle: const Text('Izklopljena pesem se ne prikazuje več nikjer (za skrivanje raje uporabi Arhiv).'),
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
                key: const ValueKey('krepko'),
                tooltip: 'Krepko: označi besedilo in pritisni',
                icon: const Icon(Icons.format_bold),
                onPressed: _krepko,
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
    final pesem = widget.pesem;
    final pdfji = pesem == null ? const <PdfDatoteka>[] : widget.baza.pdfjiPesmi[pesem.id] ?? const [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pdfji.isEmpty) const Text('Pesem nima PDF-ja.'),
        for (final p in pdfji)
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: Text(p.vrsta.isEmpty ? 'PDF' : p.vrsta),
            subtitle: Text(
              [p.imeDatoteke, if (pdfji.length > 1) 'vrstni red ${p.vrstniRed}'].where((x) => x.isNotEmpty).join(' · '),
            ),
            trailing: IconButton(
              tooltip: 'Odstrani PDF',
              icon: const Icon(Icons.delete_outline),
              onPressed: _pdfDelo ? null : () => _izbrisiPdf(p),
            ),
          ),
        const SizedBox(height: 12),
        if (pesem == null)
          Text('PDF dodaš, ko pesem shraniš.', style: Theme.of(context).textTheme.bodySmall)
        else
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _pdfDelo ? null : _dodajPdf,
              icon: _pdfDelo
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file),
              label: const Text('Dodaj PDF'),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'PDF gre takoj na Drive (mapa PDF), drugi ga dobijo ob osvežitvi. Na pesmi se pokaže prvi PDF. '
          'Odstranjen PDF gre v koš na Drivu.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  bool _pdfDelo = false;

  Future<void> _dodajPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    final izbrane = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    if (izbrane.isEmpty || !mounted) return;
    final vrsta = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Kaj je v PDF-ju?'),
        children: [
          for (final v in const ['Besedilo', 'Note', 'Akordi'])
            SimpleDialogOption(onPressed: () => Navigator.pop(context, v), child: Text(v)),
        ],
      ),
    );
    if (vrsta == null) return;
    setState(() => _pdfDelo = true);
    try {
      final f = izbrane.first;
      await widget.baza.dodajPdf(widget.api, widget.pesem!.id, f.name, vrsta, await f.readAsBytes());
      messenger.showSnackBar(const SnackBar(content: Text('PDF je dodan.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('PDF-ja ni bilo mogoče dodati: $e')));
    } finally {
      if (mounted) setState(() => _pdfDelo = false);
    }
  }

  Future<void> _izbrisiPdf(PdfDatoteka p) async {
    final messenger = ScaffoldMessenger.of(context);
    final da = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Odstrani PDF?'),
        content: const Text('PDF bo odstranjen za vse člane (na Drivu gre v koš).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Prekliči')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Odstrani')),
        ],
      ),
    );
    if (da != true) return;
    setState(() => _pdfDelo = true);
    try {
      await widget.baza.izbrisiPdf(widget.api, p);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Odstranjevanje ni uspelo: $e')));
    } finally {
      if (mounted) setState(() => _pdfDelo = false);
    }
  }

  Widget _midi(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (stolpec, pomoc) in _poljaMidi) ...[
          // Uvod je podsekcija ukazov ob odprtju.
          Padding(
            padding: EdgeInsets.only(left: stolpec == 'MIDI za uvod' ? 24 : 0),
            child: PoljeMidi(oznaka: stolpec, vnos: _vnosi[stolpec]!, knjiznica: widget.baza.midi, pomoc: pomoc),
          ),
          if (stolpec == 'MIDI za uvod')
            ListenableBuilder(
              listenable: _vnosi[stolpec]!,
              builder: (context, _) => switch (_opozoriloUvoda()) {
                final o? => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(o, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
                null => const SizedBox.shrink(),
              },
            ),
        ],
        Text(
          'Ukaze in makre izbereš z +, lahko jih je več (ločeni s ;). Pošlje jih vsaka naprava, '
          'ki ima vklopljen MIDI (Nastavitve MIDI). Za vse pesmi veljata še makra '
          '»${KnjiznicaMidi.makroOdprtja}« in »${KnjiznicaMidi.makroZaprtja}« (MIDI ukazi in makri → Makri).',
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

/// Seznam harmonik z barvami: dodajanje, preimenovanje, barva in brisanje.
class _UrejanjeBarv extends StatefulWidget {
  const _UrejanjeBarv({required this.baza, required this.api, this.vrste = false});

  final Baza baza;
  final Api api;

  /// Seznam vrst (list Vrste) namesto harmonik.
  final bool vrste;

  @override
  State<_UrejanjeBarv> createState() => _UrejanjeBarvState();
}

class _UrejanjeBarvState extends State<_UrejanjeBarv> {
  List<Harmonika> get _seznam => widget.vrste ? widget.baza.vrste : widget.baza.harmonike;
  String get _tabela => widget.vrste ? 'Vrste' : 'Harmonike';

  static const _barve = [
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.green,
    Colors.teal,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.pink,
    Colors.brown,
  ];
  bool _shranjujem = false;

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Future<void> _uredi(Harmonika? h) async {
    final ime = TextEditingController(text: h?.ime ?? '');
    var barva = h?.barva ?? _hex(_barve[_seznam.length % _barve.length]);
    final rezultat = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, nastavi) => AlertDialog(
          title: Text(
            widget.vrste
                ? (h == null ? 'Nova vrsta' : 'Uredi vrsto')
                : (h == null ? 'Nova harmonika' : 'Uredi harmoniko'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ime,
                autofocus: true,
                decoration: InputDecoration(labelText: widget.vrste ? 'Ime (npr. Valček)' : 'Ime (npr. B-Es-As)'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _barve)
                    GestureDetector(
                      onTap: () => nastavi(() => barva = _hex(c)),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: c,
                        child: barva == _hex(c) ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            if (h != null) TextButton(onPressed: () => Navigator.pop(context, 'izbrisi'), child: const Text('Izbriši')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
            FilledButton(onPressed: () => Navigator.pop(context, 'shrani'), child: const Text('Shrani')),
          ],
        ),
      ),
    );
    final novo = ime.text.trim();
    ime.dispose();
    if (rezultat == null || (rezultat == 'shrani' && novo.isEmpty)) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _shranjujem = true);
    try {
      await widget.baza.shraniMidi(widget.api, _tabela, {
        if (h != null) 'ID': h.id,
        'Ime': novo,
        'Barva': barva,
        'Vrstni red': h?.vrstniRed ?? _seznam.length + 1,
      }, izbrisi: rezultat == 'izbrisi');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
    } finally {
      if (mounted) setState(() => _shranjujem = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.baza,
      builder: (context, _) => AlertDialog(
        title: Text(widget.vrste ? 'Vrste pesmi' : 'Harmonike'),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final h in _seznam)
                ListTile(
                  leading: CircleAvatar(radius: 12, backgroundColor: h.argb == null ? Colors.grey : Color(h.argb!)),
                  title: Text(h.ime),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _shranjujem ? null : () => _uredi(h),
                ),
              if (_seznam.isEmpty) ListTile(title: Text(widget.vrste ? 'Ni še vrst.' : 'Ni še harmonik.')),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _shranjujem ? null : () => _uredi(null),
            icon: const Icon(Icons.add),
            label: const Text('Dodaj'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zapri')),
        ],
      ),
    );
  }
}
