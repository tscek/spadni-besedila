import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../baza.dart';
import '../models.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'pesem_zaslon.dart';
import 'urejanje_pesmi.dart' show apiZaUrejanje;

/// Kako se ureja celica v tabeli hitrega urejanja.
enum VrstaStolpca { besedilo, predlogi, izbira, stevilo, daNe }

class StolpecHitrega {
  const StolpecHitrega(this.ime, this.vrsta, this.sirina, {this.privzeto = true});

  /// Ime stolpca na listu Pesmi.
  final String ime;
  final VrstaStolpca vrsta;
  final double sirina;

  /// Ali je stolpec viden, dokler ga ne skriješ (»Stolpci«).
  final bool privzeto;
}

const stolpciHitrega = [
  StolpecHitrega('Izvajalec', VrstaStolpca.predlogi, 160),
  StolpecHitrega('Avtor glasbe', VrstaStolpca.predlogi, 150),
  StolpecHitrega('Avtor besedila', VrstaStolpca.predlogi, 150),
  StolpecHitrega('Vrsta', VrstaStolpca.predlogi, 110),
  StolpecHitrega('Zvrst', VrstaStolpca.predlogi, 110),
  StolpecHitrega('Tonaliteta', VrstaStolpca.izbira, 84),
  StolpecHitrega('Harmonika', VrstaStolpca.izbira, 110),
  StolpecHitrega('Tempo (BPM)', VrstaStolpca.stevilo, 84),
  StolpecHitrega('Trajanje', VrstaStolpca.besedilo, 76),
  StolpecHitrega('Status', VrstaStolpca.izbira, 90),
  StolpecHitrega('Ocena', VrstaStolpca.izbira, 84),
  StolpecHitrega('Mapa', VrstaStolpca.izbira, 120),
  StolpecHitrega('Oznaka', VrstaStolpca.predlogi, 100),
  StolpecHitrega('Aktivna', VrstaStolpca.daNe, 70),
  StolpecHitrega('MIDI ob odprtju', VrstaStolpca.predlogi, 140),
  StolpecHitrega('MIDI za uvod', VrstaStolpca.besedilo, 110),
  StolpecHitrega('Makro ob odprtju', VrstaStolpca.predlogi, 130, privzeto: false),
  StolpecHitrega('Makro ob zaprtju', VrstaStolpca.predlogi, 130, privzeto: false),
  StolpecHitrega('Pisava', VrstaStolpca.stevilo, 70, privzeto: false),
  StolpecHitrega('YouTube', VrstaStolpca.besedilo, 200, privzeto: false),
  StolpecHitrega('Povezava Tyros', VrstaStolpca.besedilo, 90, privzeto: false),
  StolpecHitrega('Prikaz', VrstaStolpca.izbira, 96),
  StolpecHitrega('Opombe', VrstaStolpca.besedilo, 220),
];

enum FilterHitrega {
  brezBesedila('Brez besedila'),
  brezAvtorjev('Brez avtorjev'),
  brezTempa('Brez tempa'),
  brezTonalitete('Brez tonalitete'),
  arhiv('Tudi arhiv');

  const FilterHitrega(this.ime);
  final String ime;
}

/// Hitro urejanje (samo administrator): vse pesmi v tabeli, urejanje celic in več pesmi hkrati,
/// shranjevanje vseh sprememb naenkrat.
class HitroUrejanjeZaslon extends StatefulWidget {
  const HitroUrejanjeZaslon({super.key, required this.baza, required this.prijava, this.spil});

  final Baza baza;
  final Prijava prijava;
  final Spil? spil;

  static const visinaVrstice = 40.0;
  static const sirinaNaslova = 230.0;

  @override
  State<HitroUrejanjeZaslon> createState() => _HitroUrejanjeZaslonState();
}

class _HitroUrejanjeZaslonState extends State<HitroUrejanjeZaslon> {
  /// Vidni stolpci ostanejo do konca seje aplikacije.
  static Set<String> _vidni = {
    for (final s in stolpciHitrega)
      if (s.privzeto) s.ime,
  };

  /// Neshranjene spremembe: ID pesmi → stolpec → nova vrednost.
  final Map<String, Map<String, Object>> _spremembe = {};
  final Set<String> _izbrane = {};
  final Set<FilterHitrega> _filtri = {};
  final _iskanje = TextEditingController();
  String? _razvrsti;
  bool _narascajoce = true;

  /// Celica, ki se ureja (ID pesmi, stolpec).
  (String, String)? _urejam;
  final _vnos = TextEditingController();
  final _fokus = FocusNode();

  final _levo = ScrollController();
  final _desno = ScrollController();
  final _vodoravno = ScrollController();
  bool _sinh = false;

  bool _shranjujem = false;
  double? _napredek;

  Baza get _baza => widget.baza;

  List<StolpecHitrega> get _stolpci => [
    for (final s in stolpciHitrega)
      if (_vidni.contains(s.ime)) s,
  ];

  int get _steviloSprememb => _spremembe.values.fold(0, (a, m) => a + m.length);

  @override
  void initState() {
    super.initState();
    _levo.addListener(() => _sinhroniziraj(_levo, _desno));
    _desno.addListener(() => _sinhroniziraj(_desno, _levo));
    _fokus.addListener(_obFokusu);
    _baza.addListener(_osvezi);
  }

  @override
  void dispose() {
    _baza.removeListener(_osvezi);
    _iskanje.dispose();
    _vnos.dispose();
    _fokus.dispose();
    _levo.dispose();
    _desno.dispose();
    _vodoravno.dispose();
    super.dispose();
  }

  void _osvezi() {
    if (mounted) setState(() {});
  }

  void _sinhroniziraj(ScrollController od, ScrollController na) {
    if (_sinh || !na.hasClients || !od.hasClients) return;
    _sinh = true;
    na.jumpTo(od.offset.clamp(0, na.position.maxScrollExtent));
    _sinh = false;
  }

  // ---------- Vrednosti ----------

  Object _izvirna(Pesem p, String stolpec) => switch (stolpec) {
    'Aktivna' => p.aktivna,
    'Status' => p.status.ime,
    'Ocena' => p.ocena == 0 ? '' : '${p.ocena}',
    _ => besedilo(p.vrstica[stolpec]),
  };

  Object _vrednost(Pesem p, String stolpec) => _spremembe[p.id]?[stolpec] ?? _izvirna(p, stolpec);

  bool _spremenjena(Pesem p, String stolpec) => _spremembe[p.id]?.containsKey(stolpec) ?? false;

  void _nastavi(Pesem p, String stolpec, Object v) {
    if (v == _izvirna(p, stolpec)) {
      _spremembe[p.id]?.remove(stolpec);
      if (_spremembe[p.id]?.isEmpty ?? false) _spremembe.remove(p.id);
    } else {
      (_spremembe[p.id] ??= {})[stolpec] = v;
    }
  }

  /// Možnosti za izbiro: (vrednost v tabeli, napis).
  List<(String, String)> _moznosti(String stolpec) => switch (stolpec) {
    'Tonaliteta' => [('', '–'), for (final t in tonalitete) (t, t)],
    'Harmonika' => [('', '–'), for (final h in _baza.harmonike) (h.ime, h.ime)],
    'Status' => [for (final s in StatusPesmi.values) (s.ime, s.ime)],
    'Ocena' => [('', '–'), for (var i = 1; i <= 5; i++) ('$i', '★' * i)],
    'Mapa' => [for (final m in _baza.mape) (m.id, m.ime)],
    'Prikaz' => [('', 'Samodejno'), ('PDF', 'PDF'), ('Besedilo', 'Besedilo')],
    _ => const [],
  };

  List<String> _predlogi(String stolpec) =>
      {if (stolpec == 'Vrsta') ..._baza.vrste.map((v) => v.ime), ..._baza.vrednosti(stolpec)}.toList();

  String _napis(String stolpec, Object v) {
    if (v is bool) return v ? 'Da' : 'Ne';
    final s = v.toString();
    if (s.isEmpty) return '';
    if (stolpec == 'Mapa') return _baza.mapa(s)?.ime ?? s;
    if (stolpec == 'Ocena') return '★' * (int.tryParse(s) ?? 0);
    return s.replaceAll('\n', ' ');
  }

  /// Napaka v vrednosti ali null.
  String? _preveri(String stolpec, String v) {
    if (v.isEmpty) return null;
    if (stolpec == 'Trajanje' && !RegExp(r'^\d{1,3}:\d{2}$').hasMatch(v)) {
      return 'Trajanje vpiši kot minute:sekunde, npr. 3:45.';
    }
    if ((stolpec == 'Tempo (BPM)' || stolpec == 'Pisava') && num.tryParse(v.replaceAll(',', '.')) == null) {
      return '$stolpec mora biti število.';
    }
    return null;
  }

  // ---------- Seznam ----------

  List<Pesem> get _vidne {
    final besedila = _baza.besedilaPesmi;
    final pdfji = _baza.pdfjiPesmi;
    final l = [
      for (final p in _baza.pesmi)
        if (p.ustreza(_iskanje.text) &&
            (!p.vArhivu || _filtri.contains(FilterHitrega.arhiv)) &&
            (!_filtri.contains(FilterHitrega.brezBesedila) ||
                ((besedila[p.id] ?? const []).isEmpty && (pdfji[p.id] ?? const []).isEmpty)) &&
            (!_filtri.contains(FilterHitrega.brezAvtorjev) || (p.avtorGlasbe.isEmpty && p.avtorBesedila.isEmpty)) &&
            (!_filtri.contains(FilterHitrega.brezTempa) || besedilo(p.vrstica['Tempo (BPM)']).isEmpty) &&
            (!_filtri.contains(FilterHitrega.brezTonalitete) || p.tonaliteta.isEmpty))
          p,
    ];
    final r = _razvrsti;
    int primerjaj(Pesem a, Pesem b) {
      if (r == null) return poenostavi(a.naslov).compareTo(poenostavi(b.naslov));
      final va = _napis(r, _vrednost(a, r));
      final vb = _napis(r, _vrednost(b, r));
      // Prazne na konec.
      if (va.isEmpty != vb.isEmpty) return va.isEmpty ? 1 : -1;
      final na = num.tryParse(va.replaceAll(',', '.'));
      final nb = num.tryParse(vb.replaceAll(',', '.'));
      final c = na != null && nb != null ? na.compareTo(nb) : poenostavi(va).compareTo(poenostavi(vb));
      return c != 0 ? c : poenostavi(a.naslov).compareTo(poenostavi(b.naslov));
    }

    l.sort((a, b) => _narascajoce ? primerjaj(a, b) : primerjaj(b, a));
    return l;
  }

  void _razvrstiPo(String? stolpec) => setState(() {
    if (_razvrsti == stolpec) {
      _narascajoce = !_narascajoce;
    } else {
      _razvrsti = stolpec;
      _narascajoce = true;
    }
  });

  // ---------- Urejanje celic ----------

  void _zacni(Pesem p, String stolpec) {
    setState(() {
      _urejam = (p.id, stolpec);
      _vnos.text = _vrednost(p, stolpec).toString();
      _vnos.selection = TextSelection(baseOffset: 0, extentOffset: _vnos.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fokus.requestFocus();
    });
  }

  void _obFokusu() {
    if (_fokus.hasFocus) return;
    final k = _urejam;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _fokus.hasFocus || k == null || _urejam != k) return;
      _potrdi();
    });
  }

  /// Potrdi urejano celico; [premik] gre v isti stolpec vrstico nižje (1) ali višje (-1).
  void _potrdi({int premik = 0}) {
    final k = _urejam;
    if (k == null) return;
    final p = _baza.pesem(k.$1);
    final v = _vnos.text.trim();
    final napaka = _preveri(k.$2, v);
    if (napaka != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(napaka)));
      _fokus.requestFocus();
      return;
    }
    setState(() {
      if (p != null) _nastavi(p, k.$2, v);
      _urejam = null;
    });
    if (premik == 0) return;
    final vidne = _vidne;
    final i = vidne.indexWhere((x) => x.id == k.$1) + premik;
    if (i < 0 || i >= vidne.length) return;
    _vidnaVrstica(i);
    _zacni(vidne[i], k.$2);
  }

  void _preklici() => setState(() => _urejam = null);

  void _vidnaVrstica(int i) {
    if (!_desno.hasClients) return;
    const h = HitroUrejanjeZaslon.visinaVrstice;
    final pos = _desno.position;
    final od = i * h;
    if (od < pos.pixels) {
      _desno.jumpTo(od);
    } else if (od + h > pos.pixels + pos.viewportDimension) {
      _desno.jumpTo((od + h - pos.viewportDimension).clamp(0, pos.maxScrollExtent));
    }
  }

  Future<void> _izberi(BuildContext celica, Pesem p, String stolpec) async {
    final box = celica.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final trenutna = _vrednost(p, stolpec).toString();
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        for (final (vrednost, napis) in _moznosti(stolpec))
          CheckedPopupMenuItem(value: vrednost, checked: vrednost == trenutna, child: Text(napis)),
      ],
    );
    if (v != null) setState(() => _nastavi(p, stolpec, v));
  }

  // ---------- Več pesmi ----------

  Future<void> _nastaviZaIzbrane() async {
    final r = await showDialog<(StolpecHitrega, Object)>(
      context: context,
      builder: (_) => _NastaviZaIzbrane(
        naslov: 'Nastavi za ${_izbrane.length} ${_pesmi(_izbrane.length)}',
        moznosti: _moznosti,
        predlogi: _predlogi,
      ),
    );
    if (r == null || !mounted) return;
    final (stolpec, v) = r;
    if (v is String) {
      final napaka = _preveri(stolpec.ime, v);
      if (napaka != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(napaka)));
        return;
      }
    }
    setState(() {
      for (final id in _izbrane) {
        final p = _baza.pesem(id);
        if (p != null) _nastavi(p, stolpec.ime, v);
      }
    });
  }

  /// Izbriše vse PDF-je izbranih pesmi (po potrditvi). Datoteke gredo na Drivu v koš.
  Future<void> _izbrisiPdfje() async {
    final pdfji = [for (final id in _izbrane) ...?_baza.pdfjiPesmi[id]];
    final messenger = ScaffoldMessenger.of(context);
    if (pdfji.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Izbrane pesmi nimajo PDF-jev')));
      return;
    }
    final pesmi = {for (final p in pdfji) p.pesem}.length;
    final da = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izbriši PDF-je?'),
        content: Text('${pdfji.length} PDF pri $pesmi ${_pesmi(pesmi)}. Datoteke gredo na Drivu v koš (30 dni).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Prekliči')),
          FilledButton(
            key: const ValueKey('hitro-izbrisi-pdf-potrdi'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Izbriši'),
          ),
        ],
      ),
    );
    if (da != true || !mounted) return;
    final api = apiZaUrejanje(context, widget.prijava, baza: _baza);
    if (api == null) return;
    try {
      await _baza.izbrisiPdfje(api, pdfji);
      messenger.showSnackBar(SnackBar(content: Text('Izbrisanih PDF: ${pdfji.length}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Brisanje ni uspelo: $e')));
    }
  }

  static String _pesmi(int n) => n % 100 == 1 ? 'pesem' : 'pesmi';

  // ---------- Shranjevanje ----------

  Future<void> _shrani() async {
    _potrdi();
    if (_urejam != null || _spremembe.isEmpty) return;
    final api = apiZaUrejanje(context, widget.prijava, baza: _baza);
    if (api == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final spremembe = [
      for (final e in _spremembe.entries) {'ID': e.key, ...e.value},
    ];
    setState(() {
      _shranjujem = true;
      _napredek = null;
    });
    try {
      await _baza.shraniPesmi(
        api,
        spremembe,
        napredek: (i, n) {
          if (mounted) setState(() => _napredek = i / n);
        },
      );
      if (!mounted) return;
      setState(_spremembe.clear);
      messenger.showSnackBar(SnackBar(content: Text('Shranjeno: ${spremembe.length} ${_pesmi(spremembe.length)}.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
    } finally {
      if (mounted) setState(() => _shranjujem = false);
    }
  }

  Future<bool> _zavrziVprasaj() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Zavržem spremembe?'),
          content: Text('Neshranjenih sprememb: $_steviloSprememb.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ne')),
            FilledButton(
              key: const ValueKey('hitro-zavrzi-potrdi'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Zavrzi'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _izberiStolpce() async {
    final vidni = {..._vidni};
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Stolpci'),
          content: SizedBox(
            width: 320,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in stolpciHitrega)
                  CheckboxListTile(
                    dense: true,
                    title: Text(s.ime),
                    value: vidni.contains(s.ime),
                    onChanged: (v) => setDialog(() => v == true ? vidni.add(s.ime) : vidni.remove(s.ime)),
                  ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zapri'))],
        ),
      ),
    );
    if (mounted) setState(() => _vidni = vidni);
  }

  Future<void> _odpri(Pesem p, List<Pesem> seznam) async {
    _potrdi();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PesemZaslon(
          pesem: p,
          baza: _baza,
          prijava: widget.prijava,
          spil: widget.spil,
          seznam: seznam,
          mapa: PesemZaslon.vse,
          hitroUrejanje: true,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // ---------- Prikaz ----------

  @override
  Widget build(BuildContext context) {
    final barve = Theme.of(context).colorScheme;
    final vidne = _vidne;
    final stolpci = _stolpci;
    final n = _steviloSprememb;
    final izbraneVidne = vidne.where((p) => _izbrane.contains(p.id)).length;
    return PopScope(
      canPop: _spremembe.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _zavrziVprasaj()) {
          setState(_spremembe.clear);
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hitro urejanje'),
          actions: [
            IconButton(
              key: const ValueKey('hitro-stolpci'),
              tooltip: 'Stolpci',
              icon: const Icon(Icons.view_column_outlined),
              onPressed: _izberiStolpce,
            ),
            IconButton(
              key: const ValueKey('hitro-zavrzi'),
              tooltip: 'Zavrzi spremembe',
              icon: const Icon(Icons.undo),
              onPressed: n == 0 || _shranjujem
                  ? null
                  : () async {
                      if (await _zavrziVprasaj()) setState(_spremembe.clear);
                    },
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                key: const ValueKey('hitro-shrani'),
                onPressed: n == 0 || _shranjujem ? null : _shrani,
                icon: const Icon(Icons.save),
                label: Text(n == 0 ? 'Shrani' : 'Shrani ($n)'),
              ),
            ),
          ],
          bottom: _shranjujem
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(value: _napredek),
                )
              : null,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                key: const ValueKey('hitro-iskanje'),
                controller: _iskanje,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Išči po naslovu ali izvajalcu',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _iskanje.text.isEmpty
                      ? null
                      : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(_iskanje.clear)),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final f in FilterHitrega.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        key: ValueKey('hitro-filter-${f.name}'),
                        label: Text(f.ime),
                        visualDensity: VisualDensity.compact,
                        selected: _filtri.contains(f),
                        onSelected: (v) => setState(() => v ? _filtri.add(f) : _filtri.remove(f)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _izbrane.isEmpty
                          ? '${vidne.length} ${_pesmi(vidne.length)} · dotik celice jo uredi, naslov odpre pesem'
                          : 'Izbranih: ${_izbrane.length}',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_izbrane.isNotEmpty) ...[
                    TextButton(
                      key: const ValueKey('hitro-nastavi'),
                      onPressed: _nastaviZaIzbrane,
                      child: const Text('Nastavi za izbrane'),
                    ),
                    TextButton(
                      key: const ValueKey('hitro-izbrisi-pdf'),
                      onPressed: _izbrisiPdfje,
                      child: const Text('Izbriši PDF'),
                    ),
                    TextButton(onPressed: () => setState(_izbrane.clear), child: const Text('Počisti izbiro')),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: HitroUrejanjeZaslon.sirinaNaslova,
                    child: Column(
                      children: [
                        _glavaNaslova(vidne, izbraneVidne, barve),
                        Expanded(
                          child: ListView.builder(
                            controller: _levo,
                            itemExtent: HitroUrejanjeZaslon.visinaVrstice,
                            itemCount: vidne.length,
                            itemBuilder: (context, i) => _naslov(vidne, i, barve),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Scrollbar(
                      controller: _vodoravno,
                      thumbVisibility: true,
                      notificationPredicate: (n) => n.depth == 0 && n.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _vodoravno,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: stolpci.fold<double>(0, (a, s) => a + s.sirina),
                          child: Column(
                            children: [
                              _glava(stolpci, barve),
                              Expanded(
                                child: ListView.builder(
                                  controller: _desno,
                                  itemExtent: HitroUrejanjeZaslon.visinaVrstice,
                                  itemCount: vidne.length,
                                  itemBuilder: (context, i) => _vrstica(vidne, i, stolpci, barve),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _puscica(String? stolpec) => _razvrsti != stolpec
      ? const SizedBox.shrink()
      : Icon(_narascajoce ? Icons.arrow_upward : Icons.arrow_downward, size: 14);

  Widget _glavaNaslova(List<Pesem> vidne, int izbraneVidne, ColorScheme barve) => Container(
    height: HitroUrejanjeZaslon.visinaVrstice,
    color: barve.surfaceContainerHigh,
    child: Row(
      children: [
        Checkbox(
          key: const ValueKey('hitro-izberi-vse'),
          tristate: true,
          value: izbraneVidne == 0 ? false : (izbraneVidne == vidne.length ? true : null),
          onChanged: (_) => setState(() {
            if (izbraneVidne == vidne.length) {
              _izbrane.removeAll(vidne.map((p) => p.id));
            } else {
              _izbrane.addAll(vidne.map((p) => p.id));
            }
          }),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _razvrstiPo(null),
            child: Row(
              children: [
                const Text('Naslov', style: TextStyle(fontWeight: FontWeight.bold)),
                _puscica(null),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _glava(List<StolpecHitrega> stolpci, ColorScheme barve) => Container(
    height: HitroUrejanjeZaslon.visinaVrstice,
    color: barve.surfaceContainerHigh,
    child: Row(
      children: [
        for (final s in stolpci)
          InkWell(
            onTap: () => _razvrstiPo(s.ime),
            child: Container(
              width: s.sirina,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      s.ime,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  _puscica(s.ime),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _naslov(List<Pesem> vidne, int i, ColorScheme barve) {
    final p = vidne[i];
    final izbrana = _izbrane.contains(p.id);
    return Container(
      key: ValueKey('hitro-naslov-${p.id}'),
      decoration: BoxDecoration(
        color: izbrana ? barve.primaryContainer.withValues(alpha: 0.6) : null,
        border: Border(bottom: BorderSide(color: barve.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Checkbox(
            key: ValueKey('hitro-izberi-${p.id}'),
            value: izbrana,
            onChanged: (v) => setState(() => v == true ? _izbrane.add(p.id) : _izbrane.remove(p.id)),
          ),
          Expanded(
            child: InkWell(
              key: ValueKey('hitro-odpri-${p.id}'),
              onTap: () => _odpri(p, vidne),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  p.naslov,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _spremembe.containsKey(p.id) ? FontWeight.bold : null,
                    color: p.vArhivu ? barve.outline : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vrstica(List<Pesem> vidne, int i, List<StolpecHitrega> stolpci, ColorScheme barve) {
    final p = vidne[i];
    final izbrana = _izbrane.contains(p.id);
    return Container(
      decoration: BoxDecoration(
        color: izbrana ? barve.primaryContainer.withValues(alpha: 0.6) : null,
        border: Border(bottom: BorderSide(color: barve.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(children: [for (final s in stolpci) _celica(p, s, barve)]),
    );
  }

  Widget _celica(Pesem p, StolpecHitrega s, ColorScheme barve) {
    final spremenjena = _spremenjena(p, s.ime);
    final urejam = _urejam == (p.id, s.ime);
    final v = _vrednost(p, s.ime);
    final Widget vsebina;
    if (urejam) {
      final predlogi = s.vrsta == VrstaStolpca.predlogi ? _predlogi(s.ime) : const <String>[];
      vsebina = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _preklici,
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _potrdi(premik: 1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _potrdi(premik: -1),
        },
        child: TextField(
          key: const ValueKey('hitro-vnos'),
          controller: _vnos,
          focusNode: _fokus,
          style: const TextStyle(fontSize: 13),
          keyboardType: s.vrsta == VrstaStolpca.stevilo ? TextInputType.number : TextInputType.text,
          textInputAction: TextInputAction.next,
          // Brez privzetega premika fokusa (»naprej«): urejanje se nadaljuje v isti stolpec vrstico nižje.
          onEditingComplete: () {},
          onSubmitted: (_) => _potrdi(premik: 1),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            suffixIconConstraints: const BoxConstraints(maxWidth: 24, maxHeight: 24),
            suffixIcon: predlogi.isEmpty
                ? null
                : PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    icon: const Icon(Icons.arrow_drop_down),
                    tooltip: 'Izberi obstoječo vrednost',
                    onSelected: (x) {
                      _vnos.text = x;
                      _potrdi();
                    },
                    itemBuilder: (_) => [for (final x in predlogi) PopupMenuItem(value: x, child: Text(x))],
                  ),
          ),
        ),
      );
    } else if (s.vrsta == VrstaStolpca.daNe) {
      vsebina = Checkbox(
        key: ValueKey('hitro-${p.id}-${s.ime}'),
        value: v == true,
        onChanged: (x) => setState(() => _nastavi(p, s.ime, x ?? false)),
      );
    } else {
      vsebina = Builder(
        builder: (celica) => InkWell(
          key: ValueKey('hitro-${p.id}-${s.ime}'),
          onTap: () => s.vrsta == VrstaStolpca.izbira ? _izberi(celica, p, s.ime) : _zacni(p, s.ime),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              _napis(s.ime, v),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
      );
    }
    return Container(
      width: s.sirina,
      decoration: BoxDecoration(
        color: spremenjena ? barve.tertiaryContainer : null,
        border: urejam
            ? Border.all(color: barve.primary, width: 2)
            : Border(right: BorderSide(color: barve.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: vsebina,
    );
  }
}

/// Izbira polja in vrednosti, ki se nastavi vsem izbranim pesmim.
class _NastaviZaIzbrane extends StatefulWidget {
  const _NastaviZaIzbrane({required this.naslov, required this.moznosti, required this.predlogi});

  final String naslov;
  final List<(String, String)> Function(String) moznosti;
  final List<String> Function(String) predlogi;

  @override
  State<_NastaviZaIzbrane> createState() => _NastaviZaIzbraneState();
}

class _NastaviZaIzbraneState extends State<_NastaviZaIzbrane> {
  var _stolpec = stolpciHitrega.first;
  Object _vrednost = '';
  final _vnos = TextEditingController();

  @override
  void dispose() {
    _vnos.dispose();
    super.dispose();
  }

  Widget _urejevalnik() {
    final s = _stolpec;
    switch (s.vrsta) {
      case VrstaStolpca.daNe:
        return SwitchListTile(
          key: const ValueKey('hitro-nastavi-dane'),
          contentPadding: EdgeInsets.zero,
          title: Text(s.ime),
          value: _vrednost == true,
          onChanged: (v) => setState(() => _vrednost = v),
        );
      case VrstaStolpca.izbira:
        final moznosti = widget.moznosti(s.ime);
        return DropdownButtonFormField<String>(
          key: ValueKey('hitro-nastavi-izbira-${s.ime}'),
          initialValue: moznosti.any((m) => m.$1 == _vrednost) ? _vrednost as String : null,
          decoration: const InputDecoration(labelText: 'Vrednost'),
          items: [for (final (v, napis) in moznosti) DropdownMenuItem(value: v, child: Text(napis))],
          onChanged: (v) => setState(() => _vrednost = v ?? ''),
        );
      case _:
        final predlogi = widget.predlogi(s.ime);
        return TextField(
          key: const ValueKey('hitro-nastavi-vnos'),
          controller: _vnos,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Vrednost (prazno izbriše)',
            suffixIcon: predlogi.isEmpty
                ? null
                : PopupMenuButton<String>(
                    icon: const Icon(Icons.arrow_drop_down),
                    tooltip: 'Izberi obstoječo vrednost',
                    onSelected: (v) => _vnos.text = v,
                    itemBuilder: (_) => [for (final v in predlogi) PopupMenuItem(value: v, child: Text(v))],
                  ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.naslov),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('hitro-nastavi-stolpec'),
            initialValue: _stolpec.ime,
            decoration: const InputDecoration(labelText: 'Polje'),
            items: [for (final s in stolpciHitrega) DropdownMenuItem(value: s.ime, child: Text(s.ime))],
            onChanged: (v) => setState(() {
              _stolpec = stolpciHitrega.firstWhere((s) => s.ime == v);
              _vrednost = _stolpec.vrsta == VrstaStolpca.daNe ? true : '';
              _vnos.clear();
            }),
          ),
          const SizedBox(height: 12),
          _urejevalnik(),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
      FilledButton(
        key: const ValueKey('hitro-nastavi-potrdi'),
        onPressed: () => Navigator.pop(context, (
          _stolpec,
          switch (_stolpec.vrsta) {
            VrstaStolpca.daNe || VrstaStolpca.izbira => _vrednost,
            _ => _vnos.text.trim(),
          },
        )),
        child: const Text('Nastavi'),
      ),
    ],
  );
}
