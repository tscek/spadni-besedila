import 'package:flutter/foundation.dart' show mergeSort;
import 'package:flutter/material.dart';

import '../baza.dart';
import '../models.dart';
import '../nastavitve.dart';
import '../odigrane.dart';
import 'oznake.dart';

/// Seznam pesmi z izbrano vrstico, po katerem se premikaš tudi z nožnim stikalom (gor, dol, potrdi).
class IzbiraPesmi extends StatefulWidget {
  const IzbiraPesmi({
    super.key,
    required this.pesmi,
    required this.odpri,
    this.pridrzi,
    this.zacetna,
    this.vrstica,
    this.visina,
  });

  final List<Pesem> pesmi;
  final void Function(Pesem) odpri;

  /// Pridržana vrstica (privzeta vrstica).
  final void Function(Pesem)? pridrzi;

  /// Pesem, ki je na začetku izbrana.
  final Pesem? zacetna;

  /// Prikaz vrstice; privzeto naslov z oznakami, izvajalec in tonaliteta.
  final Widget Function(BuildContext context, Pesem p, bool izbrana)? vrstica;

  /// Višina vrstice, če vrstice niso enako visoke (sicer so vse kot prva).
  final double Function(Pesem p)? visina;

  @override
  State<IzbiraPesmi> createState() => IzbiraPesmiState();
}

class IzbiraPesmiState extends State<IzbiraPesmi> {
  final _drsnik = ScrollController();
  int? _izbrana;

  Pesem? get izbrana => _izbrana == null || _izbrana! >= widget.pesmi.length ? null : widget.pesmi[_izbrana!];

  @override
  void initState() {
    super.initState();
    final i = widget.zacetna == null ? -1 : widget.pesmi.indexWhere((p) => p.id == widget.zacetna!.id);
    if (i >= 0) {
      _izbrana = i;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pokazi(animiraj: false));
    }
  }

  @override
  void didUpdateWidget(IzbiraPesmi oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ob spremembi iskanja ostane izbrana prva pesem s seznama.
    if (oldWidget.pesmi.length != widget.pesmi.length || (_izbrana ?? 0) >= widget.pesmi.length) {
      _izbrana = widget.pesmi.isEmpty ? null : 0;
    }
  }

  @override
  void dispose() {
    _drsnik.dispose();
    super.dispose();
  }

  /// Premakne izbiro za [koraki] (negativno gor).
  void premakni(int koraki) {
    if (widget.pesmi.isEmpty) return;
    setState(() => _izbrana = ((_izbrana ?? (koraki > 0 ? -1 : 0)) + koraki).clamp(0, widget.pesmi.length - 1));
    _pokazi();
  }

  /// Odpre izbrano pesem; vrne false, če ni nobene izbrane.
  bool potrdi() {
    final p = izbrana;
    if (p == null) return false;
    widget.odpri(p);
    return true;
  }

  void _pokazi({bool animiraj = true}) {
    final i = _izbrana;
    if (i == null || !_drsnik.hasClients) return;
    final pozicija = _drsnik.position;
    final double zgoraj;
    final double visina;
    if (widget.visina case final v?) {
      zgoraj = widget.pesmi.take(i).fold(0.0, (s, p) => s + v(p));
      visina = v(widget.pesmi[i]);
    } else {
      visina = (pozicija.maxScrollExtent + pozicija.viewportDimension) / widget.pesmi.length;
      zgoraj = i * visina;
    }
    double? cilj;
    if (zgoraj < pozicija.pixels) cilj = zgoraj;
    if (zgoraj + visina > pozicija.pixels + pozicija.viewportDimension) {
      cilj = zgoraj + visina - pozicija.viewportDimension;
    }
    if (cilj == null) return;
    cilj = cilj.clamp(0, pozicija.maxScrollExtent);
    if (animiraj) {
      _drsnik.animateTo(cilj, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    } else {
      _drsnik.jumpTo(cilj);
    }
  }

  Widget _privzetaVrstica(BuildContext context, Pesem p, bool izbrana) => ListTile(
    selected: izbrana,
    selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
    title: NaslovZOznakami(pesem: p),
    subtitle: p.izvajalec.isEmpty && p.tonaliteta.isEmpty
        ? const Text(' ')
        : Text([p.izvajalec, p.tonaliteta].where((x) => x.isNotEmpty).join(' · '), maxLines: 1),
    onTap: () => widget.odpri(p),
    onLongPress: widget.pridrzi == null ? null : () => widget.pridrzi!(p),
  );

  @override
  Widget build(BuildContext context) {
    final vrstica = widget.vrstica ?? _privzetaVrstica;
    if (widget.visina case final v?) {
      return ListView.builder(
        controller: _drsnik,
        itemCount: widget.pesmi.length,
        itemBuilder: (context, i) =>
            SizedBox(height: v(widget.pesmi[i]), child: vrstica(context, widget.pesmi[i], i == _izbrana)),
      );
    }
    return ListView.builder(
      controller: _drsnik,
      itemCount: widget.pesmi.length,
      // Enaka višina vrstic, da se izbrana vrstica natančno pokaže.
      prototypeItem: widget.pesmi.isEmpty ? null : vrstica(context, widget.pesmi.first, false),
      itemBuilder: (context, i) => vrstica(context, widget.pesmi[i], i == _izbrana),
    );
  }
}

/// Plavajoče okno z iskalnikom pesmi (spodaj desno na zaslonu pesmi). Na vrhu je vedno »Pavza«
/// (pesem za pavzo v mapi), nad seznamom hitra filtra po vrsti in harmoniki (ob zaprtju se ponastavita)
/// in razvrščanje. Že odigrane pesmi imajo samo naslov v nižji vrstici.
class IskalnikPesmi extends StatefulWidget {
  const IskalnikPesmi({
    super.key,
    required this.baza,
    required this.pesmi,
    required this.odpri,
    required this.zapri,
    this.pridrzi,
    this.trenutna,
    this.pavza,
  });

  final Baza baza;
  final List<Pesem> pesmi;
  final void Function(Pesem) odpri;
  final void Function(Pesem)? pridrzi;
  final VoidCallback zapri;
  final Pesem? trenutna;
  final Pesem? pavza;

  static const visinaVrstice = 60.0;
  static const visinaOdigrane = 40.0;

  @override
  State<IskalnikPesmi> createState() => IskalnikPesmiState();
}

class IskalnikPesmiState extends State<IskalnikPesmi> {
  final _iskanje = TextEditingController();
  final _izbira = GlobalKey<IzbiraPesmiState>();
  String _vrsta = '';
  String _harmonika = '';

  void premakni(int koraki) => _izbira.currentState?.premakni(koraki);
  bool potrdi() => _izbira.currentState?.potrdi() ?? false;

  @override
  void dispose() {
    _iskanje.dispose();
    super.dispose();
  }

  bool _odigrana(Pesem p) => p.id != widget.pavza?.id && Odigrane.aplikacija.je(p.id);

  List<Pesem> _pesmi() {
    final n = Nastavitve.aplikacija;
    final pavza = widget.pavza;
    final pesmi = widget.pesmi
        .where(
          (p) =>
              p.id != pavza?.id &&
              (_vrsta.isEmpty || p.vrsta == _vrsta) &&
              (_harmonika.isEmpty || p.harmonika == _harmonika) &&
              p.ustreza(_iskanje.text),
        )
        .toList();
    // Razvrščanje je stabilno, zato pesmi playliste z enako vrednostjo ostanejo na vrhu.
    if (n.razvrstiIskalnik case final polje?) mergeSort(pesmi, compare: polje.primerjaj);
    return [?pavza, ...pesmi];
  }

  Widget _vrstica(BuildContext context, Pesem p, bool izbrana) {
    final tema = Theme.of(context);
    if (p.id == widget.pavza?.id) {
      return ListTile(
        selected: izbrana,
        selectedTileColor: tema.colorScheme.secondaryContainer,
        leading: const Icon(Icons.pause_circle_outline),
        title: const Text('Pavza', style: TextStyle(fontWeight: FontWeight.bold)),
        onTap: () => widget.odpri(p),
      );
    }
    final odigrana = _odigrana(p);
    final deli = poljaVPodnaslovu(context, widget.baza, p, Nastavitve.aplikacija.poljaIskalnika);
    return ListTile(
      dense: odigrana,
      visualDensity: odigrana ? VisualDensity.compact : null,
      selected: izbrana,
      selectedTileColor: tema.colorScheme.secondaryContainer,
      title: NaslovZOznakami(
        pesem: p,
        slog: odigrana ? TextStyle(color: tema.disabledColor) : null,
      ),
      subtitle: odigrana || deli.isEmpty
          ? null
          : Text.rich(TextSpan(children: deli), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Nastavitve.aplikacija.poljaIskalnika.contains(PoljePesmi.ocena) && p.ocena > 0 && !odigrana
          ? Zvezdice(ocena: p.ocena, velikost: 12)
          : null,
      onTap: () => widget.odpri(p),
      onLongPress: widget.pridrzi == null ? null : () => widget.pridrzi!(p),
    );
  }

  Widget _filtri(BuildContext context) {
    final vrste = widget.pesmi.map((p) => p.vrsta).where((v) => v.isNotEmpty).toSet().toList()..sort();
    final imena = widget.pesmi.map((p) => p.harmonika).where((v) => v.isNotEmpty).toSet();
    // Harmonike v vrstnem redu s seznama harmonik, neznane na koncu.
    final harmonike = [
      for (final h in widget.baza.harmonike)
        if (imena.contains(h.ime)) h.ime,
      ...imena.where((i) => widget.baza.harmonika(i) == null),
    ];
    if (vrste.length < 2 && harmonike.length < 2) return const SizedBox.shrink();
    Widget cip(String ime, Color? barva, bool izbran, VoidCallback ob) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        visualDensity: VisualDensity.compact,
        avatar: barva == null ? null : CircleAvatar(backgroundColor: barva, radius: 6),
        label: Text(ime),
        selected: izbran,
        showCheckmark: false,
        onSelected: (_) => setState(ob),
      ),
    );
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          if (vrste.length > 1)
            for (final v in vrste) cip(v, barvaVrste(widget.baza, v), _vrsta == v, () => _vrsta = _vrsta == v ? '' : v),
          if (vrste.length > 1 && harmonike.length > 1) const VerticalDivider(width: 12),
          if (harmonike.length > 1)
            for (final h in harmonike)
              cip(h, barvaHarmonike(widget.baza, h), _harmonika == h, () => _harmonika = _harmonika == h ? '' : h),
        ],
      ),
    );
  }

  Widget _razvrscanje() {
    final n = Nastavitve.aplikacija;
    return PopupMenuButton<PoljePesmi?>(
      tooltip: 'Razvrsti',
      icon: Icon(Icons.sort, color: n.razvrstiIskalnik == null ? null : Theme.of(context).colorScheme.primary),
      onSelected: (v) => setState(() => n.nastaviRazvrscanjeIskalnika(v)),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(value: null, checked: n.razvrstiIskalnik == null, child: const Text('Kot v mapi')),
        for (final polje in PoljePesmi.values)
          if (polje != PoljePesmi.koda)
            CheckedPopupMenuItem(value: polje, checked: n.razvrstiIskalnik == polje, child: Text(polje.ime)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pesmi = _pesmi();
    final tema = Theme.of(context);
    return Material(
      elevation: 8,
      // Bel okvir, da okno izstopa od besedila.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tema.brightness == Brightness.dark ? Colors.white : Colors.black54, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _iskanje,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => potrdi(),
                    decoration: const InputDecoration(
                      hintText: 'Išči pesem',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
                _razvrscanje(),
                IconButton(tooltip: 'Zapri', icon: const Icon(Icons.close), onPressed: widget.zapri),
              ],
            ),
          ),
          _filtri(context),
          Expanded(
            child: pesmi.isEmpty
                ? const Center(child: Text('Ni zadetkov.'))
                : ListenableBuilder(
                    listenable: Odigrane.aplikacija,
                    builder: (context, _) => IzbiraPesmi(
                      key: _izbira,
                      pesmi: pesmi,
                      odpri: widget.odpri,
                      pridrzi: widget.pridrzi,
                      zacetna: widget.trenutna,
                      vrstica: _vrstica,
                      visina: (p) => _odigrana(p) ? IskalnikPesmi.visinaOdigrane : IskalnikPesmi.visinaVrstice,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
