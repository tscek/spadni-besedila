import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../midi/midi.dart';
import '../midi/ukazi.dart';
import '../models.dart';
import '../posodobitev.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'midi_zaslon.dart';
import 'iskalnik_pesmi.dart';
import 'naslednje.dart';
import 'nastavitve_zaslon.dart';
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
  String _zvrst = '';

  /// Nožno stikalo na seznamu: gor in dol premikata izbiro, potrdi odpre pesem, iskalnik gre v iskanje.
  bool _dejanje(DejanjeMidi d) {
    final izbira = _izbira.currentState;
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
        _odpri(p, [p]);
      default:
        return false;
    }
    return true;
  }

  void _odpri(Pesem p, List<Pesem> seznam) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          PesemZaslon(pesem: p, baza: widget.baza, prijava: widget.prijava, spil: widget.spil, seznam: seznam),
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
    final zvrsti = baza.pesmi.map((p) => p.zvrst).where((z) => z.isNotEmpty).toSet().toList()..sort();
    final pesmi = baza.pesmi.where((p) => (_zvrst.isEmpty || p.zvrst == _zvrst) && p.ustreza(_iskanje.text)).toList();

    return NaMidi(dejanje: _dejanje, child: _zaslon(context, baza, zvrsti, pesmi));
  }

  Widget _zaslon(BuildContext context, Baza baza, List<String> zvrsti, List<Pesem> pesmi) {
    return Scaffold(
      bottomNavigationBar: ListenableBuilder(
        listenable: widget.spil,
        builder: (context, _) =>
            vrsticaNaslednjih(context, widget.spil, baza, (p) => _odpri(p, pesmi)) ?? const SizedBox.shrink(),
      ),
      floatingActionButton: baza.smeUrejati
          ? FloatingActionButton.extended(
              onPressed: _novaPesem,
              icon: const Icon(Icons.add),
              label: const Text('Nova pesem'),
            )
          : null,
      appBar: AppBar(
        title: const Text('Pesmi'),
        actions: [
          SpilGumb(spil: widget.spil, baza: baza, prijava: widget.prijava),
          IconButton(
            tooltip: 'Setliste',
            icon: const Icon(Icons.queue_music),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SetlisteZaslon(baza: widget.baza, prijava: widget.prijava, spil: widget.spil),
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
              PopupMenuItem(enabled: false, child: Text(widget.prijava.racun?.email ?? 'Ni prijave')),
              if (baza.zadnjaOsvezitev != null)
                PopupMenuItem(enabled: false, child: Text('Osveženo: ${_datum(baza.zadnjaOsvezitev!)}')),
              if (widget.prijava.racun != null)
                const PopupMenuItem(value: 'odjava', child: Text('Odjava'))
              else
                const PopupMenuItem(value: 'prijava', child: Text('Prijava')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'nastavitve', child: Text('Nastavitve')),
              const PopupMenuItem(value: 'midi', child: Text('Nastavitve MIDI')),
              const PopupMenuItem(value: 'midiKnjiznica', child: Text('MIDI ukazi in makri')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
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
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final z in ['', ...zvrsti])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(z.isEmpty ? 'Vse' : z),
                          selected: _zvrst == z,
                          onSelected: (_) => setState(() => _zvrst = z),
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
          if (baza.stanje != null || baza.napaka != null)
            MaterialBanner(
              content: Text(baza.napaka ?? baza.stanje!),
              leading: Icon(baza.napaka != null ? Icons.error_outline : Icons.downloading),
              actions: [TextButton(onPressed: baza.osvezujem ? null : _osvezi, child: const Text('Znova'))],
            ),
          Expanded(
            child: pesmi.isEmpty
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
        builder: (_) => UrejanjePesmiZaslon(baza: widget.baza, api: api),
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

  Widget _vrstica(BuildContext context, Pesem p, bool izbrana, List<Pesem> seznam) {
    final imaBesedilo = widget.baza.besedilaPesmi.containsKey(p.id);
    final imaPdf = widget.baza.pdfjiPesmi.containsKey(p.id);
    return ListTile(
      selected: izbrana,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      leading: SizedBox(
        width: 52,
        child: Text(
          p.koda,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(p.naslov),
      subtitle: Text([p.izvajalec, p.tonaliteta].where((s) => s.isNotEmpty).join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imaBesedilo) const Icon(Icons.notes, size: 18),
          if (imaPdf) const Icon(Icons.picture_as_pdf, size: 18),
        ],
      ),
      onTap: () => _odpri(p, seznam),
      onLongPress: () => dodajMedNaslednje(context, widget.spil, widget.baza, p),
    );
  }

  static String _datum(DateTime d) {
    final l = d.toLocal();
    String dv(int x) => x.toString().padLeft(2, '0');
    return '${dv(l.day)}.${dv(l.month)}.${l.year} ${dv(l.hour)}:${dv(l.minute)}';
  }
}
