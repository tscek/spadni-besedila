import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../midi/midi.dart';
import '../midi/ukazi.dart';
import '../models.dart';
import '../nastavitve.dart';
import '../odigrane.dart';
import '../posodobitev.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'midi_zaslon.dart';
import 'iskalnik_pesmi.dart';
import 'naslednje.dart';
import 'nastavitve_zaslon.dart';
import 'oznake.dart';
import 'pesem_zaslon.dart';
import 'setliste_zaslon.dart';
import 'spil_zaslon.dart';
import 'urejanje_pesmi.dart';

class SeznamZaslon extends StatefulWidget {
  const SeznamZaslon({
    super.key,
    required this.prijava,
    required this.baza,
    required this.posodobitev,
    required this.spil,
  });

  final Prijava prijava;
  final Baza baza;
  final Posodobitev posodobitev;
  final Spil spil;

  @override
  State<SeznamZaslon> createState() => _SeznamZaslonState();
}

class _SeznamZaslonState extends State<SeznamZaslon> {
  final _iskanje = TextEditingController();
  final _iskanjeFokus = FocusNode();
  final _izbira = GlobalKey<IzbiraPesmiState>();
  String _vrsta = '';

  /// Ali je odprta mapa (sicer je na zaslonu izbira mape).
  bool _vMapi = false;

  /// Odprta mapa; null so vse mape.
  String? _mapa;
  bool _arhiv = false;

  void _odpriMapo(String? mapa, {bool arhiv = false}) => setState(() {
    _vMapi = true;
    _mapa = mapa;
    _arhiv = arhiv;
    _vrsta = '';
    _iskanje.clear();
  });

  String get _imeMape => _arhiv
      ? 'Arhiv'
      : _mapa == null
      ? 'Vse pesmi'
      : widget.baza.mapa(_mapa!)?.ime ?? 'Pesmi';

  /// Nožno stikalo na seznamu: gor in dol premikata izbiro, potrdi odpre pesem, iskalnik gre v iskanje.
  bool _dejanje(DejanjeMidi d) {
    final izbira = _izbira.currentState;
    if (!_vMapi && d != DejanjeMidi.izbrana) return false;
    switch (d) {
      case DejanjeMidi.gor || DejanjeMidi.prejsnja:
        izbira?.premakni(-1);
      case DejanjeMidi.dol || DejanjeMidi.naslednja:
        izbira?.premakni(1);
      case DejanjeMidi.potrdi:
        _iskanjeFokus.unfocus();
        izbira?.potrdi();
      case DejanjeMidi.iskalnik:
        _iskanjeFokus.requestFocus();
      case DejanjeMidi.izbrana:
        final p = widget.baza.pesem(widget.spil.prvaNaslednja()?.pesem ?? '');
        if (p == null) return false;
        _odpri(p, [p], izMape: false);
      default:
        return false;
    }
    return true;
  }

  /// Odpre pesem; iskalnik v pesmi išče v odprti mapi (pod »Vse« po vseh), sicer v mapi pesmi.
  void _odpri(Pesem p, List<Pesem> seznam, {bool izMape = true}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PesemZaslon(
        pesem: p,
        baza: widget.baza,
        prijava: widget.prijava,
        spil: widget.spil,
        seznam: seznam,
        mapa: izMape && _vMapi && !_arhiv ? (_mapa ?? PesemZaslon.vse) : p.mapa,
      ),
    ),
  );

  @override
  void dispose() {
    _iskanjeFokus.dispose();
    _iskanje.dispose();
    super.dispose();
  }

  void _osvezi() {
    if (!widget.prijava.prijavljen) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Za osvežitev se prijavi z Google računom (potreben je internet).')));
      _prijava().then((_) {
        if (widget.prijava.prijavljen) _osveziZApi();
      });
      return;
    }
    _osveziZApi();
  }

  /// V brskalniku prijava potrebuje Googlov gumb, zato odpre zaslon za prijavo.
  Future<void> _prijava() => odpriPrijavo(Navigator.of(context), widget.prijava);

  void _osveziZApi() {
    final api = Api(widget.prijava.zeton);
    widget.baza.osvezi(api);
    widget.posodobitev.preveri(api);
  }

  @override
  Widget build(BuildContext context) {
    final baza = widget.baza;
    final vMapi = _arhiv ? baza.arhiv : baza.pesmiMape(_mapa);
    final vrste = vMapi.map((p) => p.vrsta).where((z) => z.isNotEmpty).toSet().toList()..sort();
    final n = Nastavitve.aplikacija;
    final pesmi = vMapi.where((p) => (_vrsta.isEmpty || p.vrsta == _vrsta) && p.ustreza(_iskanje.text)).toList()
      ..sort((a, b) => n.padajoce ? n.razvrsti.primerjaj(b, a) : n.razvrsti.primerjaj(a, b));

    return PopScope(
      canPop: !_vMapi,
      onPopInvokedWithResult: (umaknjen, _) {
        if (!umaknjen) setState(() => _vMapi = false);
      },
      child: NaMidi(
        dejanje: _dejanje,
        child: ListenableBuilder(
          listenable: Listenable.merge([n, Odigrane.aplikacija]),
          builder: (context, _) => _zaslon(context, baza, vrste, pesmi),
        ),
      ),
    );
  }

  Widget _razvrscanje() {
    final n = Nastavitve.aplikacija;
    return PopupMenuButton<PoljePesmi>(
      tooltip: 'Razvrsti',
      icon: const Icon(Icons.sort),
      onSelected: (polje) => n.nastaviRazvrscanje(polje, polje == n.razvrsti && !n.padajoce),
      itemBuilder: (_) => [
        for (final polje in PoljePesmi.values)
          CheckedPopupMenuItem(
            value: polje,
            checked: polje == n.razvrsti,
            child: Text(polje == n.razvrsti ? '${polje.ime} ${n.padajoce ? '↓' : '↑'}' : polje.ime),
          ),
      ],
    );
  }

  /// Začetni zaslon: izbira mape.
  Widget _mape(BuildContext context, Baza baza) {
    final tema = Theme.of(context);
    Widget mapa(IconData ikona, String ime, int stevilo, VoidCallback odpri) => Card(
      child: ListTile(
        leading: Icon(ikona, color: tema.colorScheme.primary),
        title: Text(ime, style: tema.textTheme.titleMedium),
        trailing: Text('$stevilo'),
        onTap: odpri,
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final m in baza.mape)
          mapa(Icons.folder_outlined, m.ime, baza.pesmiMape(m.id).length, () => _odpriMapo(m.id)),
        mapa(Icons.library_music_outlined, 'Vse', baza.pesmiMape(null).length, () => _odpriMapo(null)),
        if (baza.arhiv.isNotEmpty)
          mapa(Icons.archive_outlined, 'Arhiv', baza.arhiv.length, () => _odpriMapo(null, arhiv: true)),
      ],
    );
  }

  Widget _zaslon(BuildContext context, Baza baza, List<String> vrste, List<Pesem> pesmi) {
    return Scaffold(
      bottomNavigationBar: ListenableBuilder(
        listenable: widget.spil,
        builder: (context, _) =>
            vrsticaNaslednjih(context, widget.spil, baza, (p) => _odpri(p, pesmi, izMape: false)) ??
            const SizedBox.shrink(),
      ),
      floatingActionButton: baza.smeUrejati && _vMapi && !_arhiv
          ? FloatingActionButton.extended(
              onPressed: _novaPesem,
              icon: const Icon(Icons.add),
              label: const Text('Nova pesem'),
            )
          : null,
      appBar: AppBar(
        leading: _vMapi
            ? IconButton(
                tooltip: 'Mape',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _vMapi = false),
              )
            : null,
        title: Text(_vMapi ? _imeMape : 'Mape'),
        actions: [
          if (_vMapi) _razvrscanje(),
          SpilGumb(spil: widget.spil, baza: baza, prijava: widget.prijava),
          IconButton(
            tooltip: 'Setliste',
            icon: const Icon(Icons.queue_music),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SetlisteZaslon(
                  baza: widget.baza,
                  prijava: widget.prijava,
                  spil: widget.spil,
                  mapa: _vMapi && !_arhiv ? _mapa : null,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Osveži iz baze',
            icon: baza.osvezujem
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            onPressed: baza.osvezujem ? null : _osvezi,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'odjava') widget.prijava.odjavi();
              if (v == 'odigrane') Odigrane.aplikacija.ponastavi();
              if (v == 'prijava') _prijava();
              if (v == 'nastavitve') {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NastavitveZaslon(baza: baza)));
              }
              if (v == 'midi') {
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MidiNastavitveZaslon(baza: baza)));
              }
              if (v == 'midiKnjiznica') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MidiKnjiznicaZaslon(baza: baza, prijava: widget.prijava),
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(widget.prijava.email ?? 'Ni prijave')),
              if (baza.zadnjaOsvezitev != null)
                PopupMenuItem(enabled: false, child: Text('Osveženo: ${_datum(baza.zadnjaOsvezitev!)}')),
              if (widget.prijava.email != null)
                const PopupMenuItem(value: 'odjava', child: Text('Odjava'))
              else
                const PopupMenuItem(value: 'prijava', child: Text('Prijava')),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'odigrane',
                enabled: Odigrane.aplikacija.stevilo > 0,
                child: Text('Počisti odigrane (${Odigrane.aplikacija.stevilo})'),
              ),
              const PopupMenuItem(value: 'nastavitve', child: Text('Nastavitve')),
              const PopupMenuItem(value: 'midi', child: Text('Nastavitve MIDI')),
              const PopupMenuItem(value: 'midiKnjiznica', child: Text('MIDI ukazi in makri')),
            ],
          ),
        ],
        bottom: !_vMapi
            ? null
            : PreferredSize(
                preferredSize: Size.fromHeight(vrste.isEmpty ? 64 : 112),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: TextField(
                        controller: _iskanje,
                        focusNode: _iskanjeFokus,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _izbira.currentState?.potrdi(),
                        decoration: InputDecoration(
                          hintText: 'Išči po kodi, naslovu ali izvajalcu',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _iskanje.text.isEmpty
                              ? null
                              : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(_iskanje.clear)),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    if (vrste.isNotEmpty)
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            for (final z in ['', ...vrste])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(z.isEmpty ? 'Vse' : z),
                                  selected: _vrsta == z,
                                  onSelected: (_) => setState(() => _vrsta = z),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
      body: Column(
        children: [
          ..._posodobitev(),
          if (baza.neposlano.isNotEmpty && baza.stanje == null && !baza.osvezujem)
            MaterialBanner(
              leading: const Icon(Icons.cloud_upload_outlined),
              content: Text('Spremembe, ki čakajo na internet: ${baza.neposlano.length}'),
              actions: [TextButton(onPressed: _osvezi, child: const Text('Pošlji'))],
            ),
          if (baza.stanje != null || baza.napaka != null)
            MaterialBanner(
              content: Text(baza.napaka ?? baza.stanje!),
              leading: Icon(baza.napaka != null ? Icons.error_outline : Icons.downloading),
              actions: [TextButton(onPressed: baza.osvezujem ? null : _osvezi, child: const Text('Znova'))],
            ),
          Expanded(
            child: !_vMapi
                ? _mape(context, baza)
                : pesmi.isEmpty
                ? Center(child: Text(baza.pesmi.isEmpty ? 'Ni pesmi. Osveži iz baze.' : 'Ni zadetkov.'))
                : IzbiraPesmi(
                    key: _izbira,
                    pesmi: pesmi,
                    odpri: (p) => _odpri(p, pesmi),
                    vrstica: (context, p, izbrana) => _vrstica(context, p, izbrana, pesmi),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _novaPesem() async {
    final api = apiZaUrejanje(context, widget.prijava);
    if (api == null) return;
    final navigator = Navigator.of(context);
    final pesem = await navigator.push(
      MaterialPageRoute<Pesem>(
        builder: (_) => UrejanjePesmiZaslon(baza: widget.baza, api: api, mapa: _mapa),
      ),
    );
    if (pesem != null) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => PesemZaslon(pesem: pesem, baza: widget.baza, prijava: widget.prijava, spil: widget.spil),
        ),
      );
    }
  }

  List<Widget> _posodobitev() {
    final p = widget.posodobitev;
    if (!p.naVoljo) return const [];
    final napredek = p.napredek;
    return [
      MaterialBanner(
        leading: const Icon(Icons.system_update),
        content: Text(
          p.napaka ??
              (napredek != null ? 'Prenašam posodobitev … $napredek %' : 'Na voljo je nova različica (${p.nova}).'),
        ),
        actions: [
          TextButton(
            onPressed: napredek != null ? null : p.namesti,
            child: Text(p.napaka != null ? 'Poskusi znova' : 'Posodobi'),
          ),
        ],
      ),
      if (napredek != null) LinearProgressIndicator(value: napredek / 100),
    ];
  }

  /// Vrstica seznama s podatki, izbranimi v nastavitvah; vse vrstice so enako visoke.
  Widget _vrstica(BuildContext context, Pesem p, bool izbrana, List<Pesem> seznam) {
    final n = Nastavitve.aplikacija;
    final polja = n.poljaSeznama.where((x) => x != PoljePesmi.naslov);
    final besedila = [
      for (final x in polja)
        if (x != PoljePesmi.status && x != PoljePesmi.ocena && x != PoljePesmi.harmonika)
          if (x.vrednost(p) case final v when v.isNotEmpty) v,
    ];
    final harmonika = polja.contains(PoljePesmi.harmonika) && p.harmonika.isNotEmpty;
    final imaPodnaslov = polja.any((x) => x != PoljePesmi.status && x != PoljePesmi.ocena);
    return ListTile(
      selected: izbrana,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      title: NaslovZOznakami(pesem: p),
      subtitle: imaPodnaslov
          ? Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: besedila.join(' · ')),
                  if (harmonika) ...[
                    if (besedila.isNotEmpty) const TextSpan(text: ' · '),
                    TextSpan(
                      text: p.harmonika,
                      style: TextStyle(color: barvaHarmonike(widget.baza, p.harmonika), fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (polja.contains(PoljePesmi.ocena) && p.ocena > 0) Zvezdice(ocena: p.ocena, velikost: 14),
          if (polja.contains(PoljePesmi.status)) IkonaStatusa(p.status),
          if (n.ikoneSeznama && widget.baza.besedilaPesmi.containsKey(p.id)) const Icon(Icons.notes, size: 18),
          if (n.ikoneSeznama && widget.baza.pdfjiPesmi.containsKey(p.id)) const Icon(Icons.picture_as_pdf, size: 18),
        ],
      ),
      onTap: () => _odpri(p, seznam),
      onLongPress: () => meniPesmi(context, widget.spil, widget.baza, widget.prijava, p),
    );
  }

  static String _datum(DateTime d) {
    final l = d.toLocal();
    String dv(int x) => x.toString().padLeft(2, '0');
    return '${dv(l.day)}.${dv(l.month)}.${l.year} ${dv(l.hour)}:${dv(l.minute)}';
  }
}
