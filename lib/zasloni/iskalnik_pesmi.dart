import 'package:flutter/foundation.dart' show mergeSort;
import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../filtri.dart';
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

/// Izbrani hitri filtri: en čip na polje (prazno = brez filtra).
typedef IzbraniFiltri = Map<PoljeFiltra, String>;

/// Hitri filtri izbrane mape (izbran filter ponoven dotik izklopi); [spredaj] so gumbi pred njimi.
/// Katera polja in čipi so prikazani, si član nastavi z gumbom na koncu vrstice, za vsako mapo posebej.
class HitriFiltri extends StatelessWidget {
  const HitriFiltri({
    super.key,
    required this.baza,
    required this.pesmi,
    required this.mapa,
    required this.izbrani,
    required this.spremeni,
    this.api,
    this.spredaj = const [],
    this.vse = false,
    this.vednoGumb = true,
  });

  final Baza baza;

  /// Gumb za nastavitev je tudi, ko ni nobenega čipa (sicer se prazna vrstica skrije).
  final bool vednoGumb;

  /// Pesmi, iz katerih se naberejo čipi.
  final List<Pesem> pesmi;

  /// Ključ mape (kot pri razvrščanju), pod katerim je shranjena izbira filtrov.
  final String mapa;
  final IzbraniFiltri izbrani;
  final void Function(IzbraniFiltri izbrani) spremeni;

  /// Za shranjevanje izbire pri članu (null = brez povezave, shrani se kasneje).
  final Api? Function()? api;
  final List<Widget> spredaj;

  /// Čip »Vse« na začetku (izklopi vse filtre).
  final bool vse;

  /// Prikazane skupine čipov: polje in njegovi vidni čipi.
  static List<(PoljeFiltra, List<String>)> skupine(Baza baza, List<Pesem> pesmi, String mapa) {
    final f = baza.filtri.za(mapa);
    return [
      for (final polje in f.polja)
        if ([
              for (final c in polje.cipi(pesmi, baza))
                if (!f.skrit(polje, c)) c,
            ]
            case final cipi
            when cipi.length > 1 ||
                (cipi.length == 1 && pesmi.any((p) => !polje.vrednosti(p, baza).contains(cipi.first))))
          (polje, cipi),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final skupine = HitriFiltri.skupine(baza, pesmi, mapa);
    if (!vednoGumb && skupine.isEmpty && spredaj.isEmpty) return const SizedBox.shrink();
    final barve = Theme.of(context).colorScheme;
    // Skupine gumbov izmenično svetle in temne, da se vidi, kje se začne naslednja.
    Widget cip(String ime, Color? barva, bool izbran, VoidCallback ob, {required int skupina, String kljuc = ''}) {
      final temna = skupina.isOdd;
      final crke = izbran ? barve.onPrimary : (temna ? barve.onInverseSurface : barve.onSurface);
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          key: ValueKey('filter-$kljuc$ime'),
          visualDensity: VisualDensity.compact,
          avatar: barva == null ? null : CircleAvatar(backgroundColor: barva, radius: 6),
          label: Text(ime, style: TextStyle(color: crke)),
          selected: izbran,
          showCheckmark: false,
          backgroundColor: temna ? barve.inverseSurface : barve.surfaceContainerLowest,
          selectedColor: barve.primary,
          side: BorderSide(color: temna ? barve.inverseSurface : barve.outlineVariant),
          onSelected: (_) => ob(),
        ),
      );
    }

    final nicIzbranih = izbrani.values.every((v) => v.isEmpty);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                ...spredaj,
                if (vse && skupine.isNotEmpty) cip('Vse', null, nicIzbranih, () => spremeni(const {}), skupina: 0),
                for (final (i, (polje, cipi)) in skupine.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  for (final c in cipi)
                    cip(
                      c,
                      switch (polje) {
                        PoljeFiltra.vrsta => barvaVrste(baza, c),
                        PoljeFiltra.harmonika => barvaHarmonike(baza, c),
                        _ => null,
                      },
                      izbrani[polje] == c,
                      () => spremeni({...izbrani, polje: izbrani[polje] == c ? '' : c}),
                      skupina: i,
                      kljuc: switch (polje) {
                        PoljeFiltra.vrsta => '0-',
                        PoljeFiltra.harmonika => '1-',
                        _ => '${polje.name}-',
                      },
                    ),
                ],
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('filtri-nastavi'),
            tooltip: 'Hitri filtri te mape',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.tune, size: 20),
            onPressed: () => _nastavi(context),
          ),
        ],
      ),
    );
  }

  Future<void> _nastavi(BuildContext context) async {
    final f = await showModalBottomSheet<FiltriMape>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => NastavitveFiltrov(baza: baza, pesmi: pesmi, zacetni: baza.filtri.za(mapa)),
    );
    if (f == null) return;
    await baza.shraniFiltre(api?.call(), mapa, f);
    // Izbran čip, ki ni več prikazan, se izklopi.
    final vidni = {for (final (p, c) in HitriFiltri.skupine(baza, pesmi, mapa)) p: c};
    spremeni({
      for (final e in izbrani.entries)
        if (vidni[e.key]?.contains(e.value) ?? false) e.key: e.value,
    });
  }
}

/// Izbira polj in čipov hitrih filtrov za eno mapo.
class NastavitveFiltrov extends StatefulWidget {
  const NastavitveFiltrov({super.key, required this.baza, required this.pesmi, required this.zacetni});

  final Baza baza;
  final List<Pesem> pesmi;
  final FiltriMape zacetni;

  @override
  State<NastavitveFiltrov> createState() => _NastavitveFiltrovState();
}

class _NastavitveFiltrovState extends State<NastavitveFiltrov> {
  late final List<PoljeFiltra> _polja = [...widget.zacetni.polja];
  late final Map<PoljeFiltra, Set<String>> _skriti = {
    for (final e in widget.zacetni.skriti.entries) e.key: {...e.value},
  };
  late var _prikaz = widget.zacetni.prikaz;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Nastavitve te mape. Veljajo zate na vseh napravah.', style: tema.textTheme.bodySmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  const Text('Najprej pokaži'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<PrikazMape>(
                        key: const ValueKey('filtri-prikaz'),
                        showSelectedIcon: false,
                        segments: [
                          for (final p in PrikazMape.values)
                            ButtonSegment(
                              value: p,
                              label: Text(p.ime, key: ValueKey('filtri-prikaz-${p.name}')),
                            ),
                        ],
                        selected: {_prikaz},
                        onSelectionChanged: (v) => setState(() => _prikaz = v.first),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Hitri filtri', style: tema.textTheme.titleSmall),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final polje in PoljeFiltra.values) ...[
                    CheckboxListTile(
                      key: ValueKey('filtri-polje-${polje.name}'),
                      dense: true,
                      title: Text(polje.ime),
                      value: _polja.contains(polje),
                      onChanged: (da) => setState(() {
                        if (da == true) {
                          _polja.add(polje);
                          _polja.sort((a, b) => a.index.compareTo(b.index));
                        } else {
                          _polja.remove(polje);
                        }
                      }),
                    ),
                    if (_polja.contains(polje))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final c in polje.cipi(widget.pesmi, widget.baza))
                              FilterChip(
                                key: ValueKey('filtri-cip-${polje.name}-$c'),
                                visualDensity: VisualDensity.compact,
                                label: Text(c),
                                selected: !(_skriti[polje]?.contains(c) ?? false),
                                onSelected: (vidno) => setState(() {
                                  final s = _skriti.putIfAbsent(polje, () => {});
                                  vidno ? s.remove(c) : s.add(c);
                                }),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  TextButton(
                    key: const ValueKey('filtri-privzeto'),
                    onPressed: () => Navigator.pop(context, const FiltriMape()),
                    child: const Text('Privzeto'),
                  ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
                  FilledButton(
                    key: const ValueKey('filtri-shrani'),
                    onPressed: () =>
                        Navigator.pop(context, FiltriMape(polja: _polja, skriti: _skriti, prikaz: _prikaz)),
                    child: const Text('Shrani'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plavajoče okno z iskalnikom pesmi (spodaj desno na zaslonu pesmi). Nad seznamom je gumb za pavzo
/// (pesem za pavzo v mapi: dotik v čakalno vrsto, pridržanje kot naslednja), hitra filtra po vrsti
/// in harmoniki (ob zaprtju se ponastavita) in razvrščanje. Že odigrane pesmi imajo samo naslov v nižji vrstici.
/// Mesto pesmi v playlisti: zaporedna številka (od 1) in opomba v playlisti.
typedef MestoVPlaylisti = ({int st, String opomba});

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
    this.playlista,
    this.vVrsti = const {},
    this.mapa = '',
    this.api,
  });

  final Baza baza;
  final List<Pesem> pesmi;

  /// Ključ mape, katere hitre filtre uporablja iskalnik.
  final String mapa;
  final Api? Function()? api;
  final void Function(Pesem) odpri;
  final void Function(Pesem)? pridrzi;
  final VoidCallback zapri;
  final Pesem? trenutna;
  final Pesem? pavza;

  /// Pesmi playliste (po ID): označene z ikono in številko spredaj.
  final Map<String, MestoVPlaylisti>? playlista;

  /// Pesmi v čakalni vrsti (ID → mesto od 1): obarvane, da jih ne izbereš še enkrat.
  final Map<String, int> vVrsti;

  static const visinaVrstice = 60.0;
  static const visinaOdigrane = 40.0;

  @override
  State<IskalnikPesmi> createState() => IskalnikPesmiState();
}

class IskalnikPesmiState extends State<IskalnikPesmi> {
  final _iskanje = TextEditingController();
  final _izbira = GlobalKey<IzbiraPesmiState>();
  IzbraniFiltri _izbrani = const {};

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
              ustrezaFiltrom(p, _izbrani, widget.baza) &&
              p.ustreza(_iskanje.text) &&
              // Igrane se ob listanju skrijejo (nastavitev); z vpisano besedo se najdejo.
              !(n.skrijIgrane &&
                  _iskanje.text.trim().isEmpty &&
                  _odigrana(p) &&
                  !widget.vVrsti.containsKey(p.id) &&
                  !(widget.playlista?.containsKey(p.id) ?? false)),
        )
        .toList();
    // Razvrščanje je stabilno, zato pesmi playliste z enako vrednostjo ostanejo na vrhu.
    if (n.razvrstiIskalnik case final polje?) mergeSort(pesmi, compare: polje.primerjaj);
    return pesmi;
  }

  Widget _vrstica(BuildContext context, Pesem p, bool izbrana) {
    final tema = Theme.of(context);
    final odigrana = _odigrana(p);
    final deli = poljaVPodnaslovu(context, widget.baza, p, Nastavitve.aplikacija.poljaIskalnika);
    final mesto = widget.playlista?[p.id];
    if (mesto != null && mesto.opomba.isNotEmpty) {
      deli.insert(
        0,
        TextSpan(
          text: deli.isEmpty ? mesto.opomba : '${mesto.opomba} · ',
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }
    final barva = odigrana ? tema.disabledColor : tema.colorScheme.primary;
    final vrsta = widget.vVrsti[p.id];
    return ListTile(
      key: vrsta == null ? null : ValueKey('v-vrsti-${p.id}'),
      tileColor: vrsta == null ? null : tema.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
      dense: odigrana,
      visualDensity: odigrana ? VisualDensity.compact : null,
      selected: izbrana,
      minLeadingWidth: 0,
      horizontalTitleGap: 8,
      leading: widget.playlista == null
          ? null
          : SizedBox(
              width: 44,
              child: mesto == null
                  ? null
                  : Row(
                      key: const ValueKey('v-playlisti'),
                      children: [
                        Icon(Icons.queue_music, size: 18, color: barva),
                        const SizedBox(width: 2),
                        Text('${mesto.st}', style: tema.textTheme.labelMedium?.copyWith(color: barva)),
                      ],
                    ),
            ),
      selectedTileColor: tema.colorScheme.secondaryContainer,
      title: NaslovZOznakami(
        pesem: p,
        slog: odigrana ? TextStyle(color: tema.disabledColor) : null,
      ),
      subtitle: odigrana || deli.isEmpty
          ? null
          : Text.rich(TextSpan(children: deli), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: vrsta != null
          ? Tooltip(
              message: 'V čakalni vrsti, $vrsta. mesto',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.playlist_add_check, size: 18, color: tema.colorScheme.tertiary),
                  Text('$vrsta', style: tema.textTheme.labelMedium?.copyWith(color: tema.colorScheme.tertiary)),
                ],
              ),
            )
          : Nastavitve.aplikacija.poljaIskalnika.contains(PoljePesmi.ocena) && p.ocena > 0 && !odigrana
          ? Zvezdice(ocena: p.ocena, velikost: 12)
          : null,
      onTap: () => widget.odpri(p),
      onLongPress: widget.pridrzi == null ? null : () => widget.pridrzi!(p),
    );
  }

  Widget _filtri(BuildContext context) {
    final pavza = widget.pavza;
    return HitriFiltri(
      baza: widget.baza,
      pesmi: widget.pesmi,
      mapa: widget.mapa,
      api: widget.api,
      vednoGumb: false,
      izbrani: _izbrani,
      spremeni: (i) => setState(() => _izbrani = i),
      spredaj: [
        if (pavza != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onLongPress: widget.pridrzi == null ? null : () => widget.pridrzi!(pavza),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                tooltip: 'Pavza: dotik na konec čakalne vrste, pridržanje kot naslednja',
                label: const Icon(Icons.pause, size: 18),
                onPressed: () => widget.odpri(pavza),
              ),
            ),
          ),
      ],
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
