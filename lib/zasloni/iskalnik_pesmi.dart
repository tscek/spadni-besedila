import 'package:flutter/material.dart';

import '../models.dart';

/// Seznam pesmi z izbrano vrstico, po katerem se premikaš tudi z nožnim stikalom (gor, dol, potrdi).
class IzbiraPesmi extends StatefulWidget {
  const IzbiraPesmi({super.key, required this.pesmi, required this.odpri, this.zacetna, this.vrstica});

  final List<Pesem> pesmi;
  final void Function(Pesem) odpri;

  /// Pesem, ki je na začetku izbrana.
  final Pesem? zacetna;

  /// Prikaz vrstice; privzeto koda in naslov.
  final Widget Function(BuildContext context, Pesem p, bool izbrana)? vrstica;

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
    final visina = (pozicija.maxScrollExtent + pozicija.viewportDimension) / widget.pesmi.length;
    final zgoraj = i * visina;
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
    title: Text('${p.koda}  ${p.naslov}', overflow: TextOverflow.ellipsis),
    onTap: () => widget.odpri(p),
  );

  @override
  Widget build(BuildContext context) {
    final vrstica = widget.vrstica ?? _privzetaVrstica;
    return ListView.builder(
      controller: _drsnik,
      itemCount: widget.pesmi.length,
      // Enaka višina vrstic, da se izbrana vrstica natančno pokaže.
      prototypeItem: widget.pesmi.isEmpty ? null : vrstica(context, widget.pesmi.first, false),
      itemBuilder: (context, i) => vrstica(context, widget.pesmi[i], i == _izbrana),
    );
  }
}

/// Plavajoče okno z iskalnikom pesmi (spodaj desno na zaslonu pesmi).
class IskalnikPesmi extends StatefulWidget {
  const IskalnikPesmi({super.key, required this.pesmi, required this.odpri, required this.zapri, this.trenutna});

  final List<Pesem> pesmi;
  final void Function(Pesem) odpri;
  final VoidCallback zapri;
  final Pesem? trenutna;

  @override
  State<IskalnikPesmi> createState() => IskalnikPesmiState();
}

class IskalnikPesmiState extends State<IskalnikPesmi> {
  final _iskanje = TextEditingController();
  final _izbira = GlobalKey<IzbiraPesmiState>();

  void premakni(int koraki) => _izbira.currentState?.premakni(koraki);
  bool potrdi() => _izbira.currentState?.potrdi() ?? false;

  @override
  void dispose() {
    _iskanje.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pesmi = widget.pesmi.where((p) => p.ustreza(_iskanje.text)).toList();
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
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
                IconButton(tooltip: 'Zapri', icon: const Icon(Icons.close), onPressed: widget.zapri),
              ],
            ),
          ),
          Expanded(
            child: pesmi.isEmpty
                ? const Center(child: Text('Ni zadetkov.'))
                : IzbiraPesmi(key: _izbira, pesmi: pesmi, odpri: widget.odpri, zacetna: widget.trenutna),
          ),
        ],
      ),
    );
  }
}
