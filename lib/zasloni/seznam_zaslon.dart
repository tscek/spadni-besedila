import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../filtri.dart';
import '../midi/midi.dart';
import '../midi/ukazi.dart';
import '../models.dart';
import '../nastavitve.dart';
import '../odigrane.dart';
import '../posodobitev.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'mape.dart';
import 'midi_zaslon.dart';
import 'hitro_urejanje.dart';
import 'iskalnik_pesmi.dart';
import 'naslednje.dart';
import 'nastavitve_zaslon.dart';
import 'oznake.dart';
import 'orodja.dart';
import 'pesem_zaslon.dart';
import 'setliste_zaslon.dart';
import 'spil_zaslon.dart';
import 'stanje_naprave.dart';
import 'neposlano.dart';
import 'urejanje_pesmi.dart';
import 'urejanje_setliste.dart';
import 'fx_panel.dart';

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
  /// Opozorilo o članih brez vloge je skrito do naslednjega zagona.
  bool _skritoBrezVloge = false;

  final _iskanje = TextEditingController();
  final _iskanjeFokus = FocusNode();
  final _izbira = GlobalKey<IzbiraPesmiState>();
  IzbraniFiltri _izbrani = const {};

  /// Ali je odprta mapa (sicer je na zaslonu izbira mape).
  bool _vMapi = false;

  /// Odprta mapa; null so vse mape.
  String? _mapa;
  bool _arhiv = false;

  /// Mapa »Za vajo«: vse pesmi s klicaji.
  bool _klicaji = false;

  /// Okno za izbiro zasedbe je odprto (da se ne odpre dvakrat).
  bool _izbiramZasedbo = false;

  /// Član v več zasedbah izbere, katere pesmi gleda; izbira se zapomni na napravi.
  Future<void> _izberiZasedbo() async {
    final baza = widget.baza;
    _izbiramZasedbo = true;
    final id = await showDialog<String>(
      context: context,
      barrierDismissible: !baza.moraIzbratiZasedbo,
      builder: (context) => SimpleDialog(
        title: const Text('Zasedba'),
        children: [
          for (final z in baza.mojeZasedbe)
            ListTile(
              title: Text(z.ime),
              trailing: z.id == baza.zasedba ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, z.id),
            ),
        ],
      ),
    );
    _izbiramZasedbo = false;
    if (id != null) await baza.izberiZasedbo(id);
  }

  void _odpriMapo(String? mapa, {bool arhiv = false, bool klicaji = false}) => setState(() {
    _vMapi = true;
    _mapa = mapa;
    _arhiv = arhiv;
    _klicaji = klicaji;
    _izbrani = const {};
    _iskanje.clear();
  });

  String get _imeMape => _arhiv
      ? 'Arhiv'
      : _klicaji
      ? 'Za vajo'
      : _mapa == null
      ? 'Vse pesmi'
      : widget.baza.mapa(_mapa!)?.ime ?? 'Pesmi';

  /// Ključ, pod katerim si odprta mapa zapomni razvrščanje.
  String get _kljucMape => _arhiv
      ? 'arhiv'
      : _klicaji
      ? 'klicaji'
      : _mapa ?? PesemZaslon.vse;

  /// Prava mapa (ne arhiv ali »Za vajo«), v kateri išče iskalnik in v katero gre nova pesem.
  bool get _pravaMapa => _vMapi && !_arhiv && !_klicaji;

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
  void _odpri(Pesem p, List<Pesem> seznam, {bool izMape = true}) {
    if (pokaziVsemKotSledilec(context, spil: widget.spil, baza: widget.baza, prijava: widget.prijava, pesem: p)) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PesemZaslon(
          pesem: p,
          baza: widget.baza,
          prijava: widget.prijava,
          spil: widget.spil,
          seznam: seznam,
          mapa: izMape && _pravaMapa ? (_mapa ?? PesemZaslon.vse) : p.mapa,
        ),
      ),
    );
  }

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
    if (baza.moraIzbratiZasedbo && !_izbiramZasedbo) {
      _izbiramZasedbo = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _izberiZasedbo();
      });
    }
    final vMapi = _arhiv
        ? baza.arhiv
        : _klicaji
        ? baza.pesmiSKlicaji
        : baza.pesmiMape(_mapa);
    final n = Nastavitve.aplikacija;
    final (polje, padajoce) = n.razvrscanjeMape(_kljucMape);
    final pesmi = vMapi.where((p) => ustrezaFiltrom(p, _izbrani, baza) && p.ustreza(_iskanje.text)).toList()
      ..sort((a, b) => padajoce ? polje.primerjaj(b, a) : polje.primerjaj(a, b));

    return PopScope(
      canPop: !_vMapi,
      onPopInvokedWithResult: (umaknjen, _) {
        if (!umaknjen) setState(() => _vMapi = false);
      },
      child: NaMidi(
        dejanje: _dejanje,
        child: ListenableBuilder(
          listenable: Listenable.merge([n, Odigrane.aplikacija, baza]),
          builder: (context, _) => _zaslon(context, baza, vMapi, pesmi),
        ),
      ),
    );
  }

  /// Razvrščanje si vsaka mapa zapomni posebej.
  Widget _razvrscanje() {
    final n = Nastavitve.aplikacija;
    final (izbrano, padajoce) = n.razvrscanjeMape(_kljucMape);
    return PopupMenuButton<PoljePesmi>(
      tooltip: 'Razvrsti',
      icon: const Icon(Icons.sort),
      onSelected: (polje) => n.nastaviRazvrscanje(polje, polje == izbrano && !padajoce, mapa: _kljucMape),
      itemBuilder: (_) => [
        for (final polje in PoljePesmi.values)
          CheckedPopupMenuItem(
            value: polje,
            checked: polje == izbrano,
            child: Text(
              '${polje == PoljePesmi.koda ? 'Vrstni red v bazi' : polje.ime}'
              '${polje == izbrano ? ' ${padajoce ? '↓' : '↑'}' : ''}',
            ),
          ),
      ],
    );
  }

  /// Začetni zaslon: izbira mape.
  Widget _mape(BuildContext context, Baza baza) {
    final tema = Theme.of(context);
    Widget mapa(
      IconData ikona,
      String ime,
      int stevilo,
      VoidCallback odpri, {
      Color? barva,
      String opis = '',
      VoidCallback? uredi,
    }) => Card(
      child: ListTile(
        leading: Icon(ikona, color: barva ?? tema.colorScheme.primary, size: 28),
        title: Text(ime, style: tema.textTheme.titleMedium),
        subtitle: opis.isEmpty ? null : Text(opis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$stevilo'),
            if (uredi != null)
              IconButton(tooltip: 'Uredi mapo', onPressed: uredi, icon: const Icon(Icons.edit_outlined)),
          ],
        ),
        onTap: odpri,
        onLongPress: uredi,
      ),
    );
    void uredi(Mapa? m) {
      final api = apiZaUrejanje(context, widget.prijava, baza: baza);
      if (api != null) urediMapo(context, baza, api, mapa: m);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final m in baza.mape)
          mapa(
            ikonaMape(m),
            m.ime,
            baza.pesmiMape(m.id).length,
            () => _odpriMapo(m.id),
            barva: m.argb == null ? null : Color(m.argb!),
            opis: m.opis,
            uredi: baza.jeAdministrator ? () => uredi(m) : null,
          ),
        mapa(Icons.library_music_outlined, 'Vse', baza.pesmiMape(null).length, () => _odpriMapo(null)),
        if (baza.pesmiSKlicaji.isNotEmpty)
          Card(
            child: ListTile(
              leading: const Klicaj(velikost: 24),
              title: Text('Za vajo (klicaji)', style: tema.textTheme.titleMedium),
              trailing: Text('${baza.pesmiSKlicaji.length}'),
              onTap: () => _odpriMapo(null, klicaji: true),
            ),
          ),
        if (baza.arhiv.isNotEmpty)
          mapa(Icons.archive_outlined, 'Arhiv', baza.arhiv.length, () => _odpriMapo(null, arhiv: true)),
        // Mape ureja samo administrator.
        if (baza.jeAdministrator)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('nova-mapa'),
                onPressed: () => uredi(null),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Nova mapa'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _zaslon(BuildContext context, Baza baza, List<Pesem> vMapi, List<Pesem> pesmi) {
    final filtri = HitriFiltri(
      baza: baza,
      pesmi: vMapi,
      mapa: _kljucMape,
      api: () => widget.prijava.prijavljen ? Api(widget.prijava.zeton) : null,
      izbrani: _izbrani,
      vse: true,
      spremeni: (i) => setState(() => _izbrani = i),
    );
    // Vrstica z gumbom za nastavitev filtrov je vedno, razen na iPadu prek vodje brez pesmi.
    final imaFiltre = vMapi.isNotEmpty;
    return Scaffold(
      bottomNavigationBar: ListenableBuilder(
        listenable: widget.spil,
        builder: (context, _) =>
            vrsticaNaslednjih(context, widget.spil, baza, (p) => _odpri(p, pesmi, izMape: false)) ??
            const SizedBox.shrink(),
      ),
      floatingActionButton: _vMapi
          ? FloatingActionButton(tooltip: 'Novo', onPressed: _novo, child: const Icon(Icons.add))
          : null,
      appBar: AppBar(
        leading: _vMapi
            ? IconButton(
                tooltip: 'Mape',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _vMapi = false),
              )
            : null,
        title: Text(
          _vMapi
              ? _imeMape
              : baza.mojeZasedbe.length > 1
              ? baza.mojeZasedbe.where((z) => z.id == baza.zasedba).firstOrNull?.ime ?? 'Mape'
              : 'Mape',
        ),
        actions: [
          IkonaNeposlanih(baza: baza, prijava: widget.prijava),
          if (_vMapi) _razvrscanje(),
          RundaGumb(baza: baza),
          // FX (efekti in XY pad) je na dosegu tudi v seznamu (če ni skrit v nastavitvah orodne vrstice).
          ListenableBuilder(
            listenable: Nastavitve.aplikacija,
            builder: (context, _) =>
                (baza.fx.gumbi.isNotEmpty || (baza.fx.xy?.nastavljen ?? false) || baza.jeAdministrator) &&
                    Nastavitve.aplikacija.mesto(Orodje.xyPad) != Mesto.skrito
                ? const FxGumb()
                : const SizedBox.shrink(),
          ),
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
                  mapa: _pravaMapa ? _mapa : null,
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
              if (v == 'zasedba') _izberiZasedbo();
              if (v == 'nastavitve') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NastavitveZaslon(baza: baza, prijava: widget.prijava),
                  ),
                );
              }
              if (v == 'hitro') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => HitroUrejanjeZaslon(baza: baza, prijava: widget.prijava, spil: widget.spil),
                  ),
                );
              }
              if (v == 'stanje') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StanjeNapraveZaslon(baza: baza, prijava: widget.prijava, spil: widget.spil),
                  ),
                );
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
              if (baza.mojeZasedbe.length > 1)
                PopupMenuItem(
                  value: 'zasedba',
                  child: Text(
                    'Zamenjaj zasedbo (${baza.mojeZasedbe.where((z) => z.id == baza.zasedba).firstOrNull?.ime ?? '-'})',
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'odigrane',
                enabled: Odigrane.aplikacija.stevilo > 0,
                child: Text('Počisti odigrane (${Odigrane.aplikacija.stevilo})'),
              ),
              const PopupMenuItem(value: 'nastavitve', child: Text('Nastavitve')),
              const PopupMenuItem(value: 'midi', child: Text('Nastavitve MIDI')),
              const PopupMenuItem(value: 'midiKnjiznica', child: Text('MIDI ukazi in makri')),
              if (baza.jeAdministrator) const PopupMenuItem(value: 'hitro', child: Text('Hitro urejanje (bulk edit)')),
              const PopupMenuItem(value: 'stanje', child: Text('Stanje naprave')),
            ],
          ),
        ],
        bottom: !_vMapi
            ? null
            : PreferredSize(
                preferredSize: Size.fromHeight(imaFiltre ? 108 : 64),
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
                    if (imaFiltre) filtri,
                  ],
                ),
              ),
      ),
      body: FxOkvir(
        baza: baza,
        api: () => widget.prijava.prijavljen ? Api(widget.prijava.zeton) : null,
        child: Column(
          children: [
            ..._posodobitev(),
            ..._pogled(),
            if (baza.neposlano.isNotEmpty && baza.cakaPovezavo && baza.stanje == null && !baza.osvezujem)
              MaterialBanner(
                leading: const Icon(Icons.cloud_upload_outlined),
                content: Text('Spremembe, ki čakajo na internet: ${baza.neposlano.length}'),
                actions: [TextButton(onPressed: _osvezi, child: const Text('Pošlji'))],
              ),
            if (baza.brezVloge && !_skritoBrezVloge && baza.zadnjaOsvezitev != null)
              MaterialBanner(
                leading: const Icon(Icons.person_off_outlined),
                content: const Text(
                  'Nimaš vloge na listu Vloge, zato si v aplikaciji samo gledalec (ne urejaš pesmi in skupnih risb). '
                  'Povej administratorju.',
                ),
                actions: [
                  TextButton(onPressed: () => setState(() => _skritoBrezVloge = true), child: const Text('V redu')),
                ],
              ),
            if (baza.claniBrezVloge.isNotEmpty && !_skritoBrezVloge)
              MaterialBanner(
                leading: const Icon(Icons.person_off_outlined),
                content: Text('Brez vloge na listu Vloge (samo gledalci): ${baza.claniBrezVloge.join(', ')}'),
                actions: [
                  TextButton(onPressed: () => setState(() => _skritoBrezVloge = true), child: const Text('V redu')),
                ],
              ),
            if (baza.stanje != null || baza.napaka != null)
              MaterialBanner(
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(baza.napaka ?? baza.stanje!),
                    if (baza.osvezujem) ...[const SizedBox(height: 6), LinearProgressIndicator(value: baza.napredek)],
                  ],
                ),
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
      ),
    );
  }

  /// Gumb +: nova pesem, nova playlista ali nova (prazna) čakalna vrsta.
  Future<void> _novo() async {
    final baza = widget.baza;
    final izbira = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              enabled: baza.smeUrejati && _pravaMapa,
              leading: const Icon(Icons.music_note),
              title: const Text('Nova pesem'),
              subtitle: Text(_pravaMapa ? 'V mapo $_imeMape' : 'Najprej odpri mapo'),
              onTap: () => Navigator.pop(context, 'pesem'),
            ),
            ListTile(
              enabled: baza.smeUrejati,
              leading: const Icon(Icons.queue_music),
              title: const Text('Nova playlista'),
              subtitle: Text(_pravaMapa && _mapa != null ? 'V mapo $_imeMape' : 'Brez mape'),
              onTap: () => Navigator.pop(context, 'playlista'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_remove),
              title: const Text('Nova čakalna vrsta'),
              subtitle: Text('Izprazni čakalno vrsto (zdaj ${widget.spil.naslednje.length} pesmi)'),
              onTap: () => Navigator.pop(context, 'vrsta'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (izbira) {
      case 'pesem':
        await _novaPesem();
      case 'playlista':
        final api = apiZaUrejanje(context, widget.prijava);
        if (api == null) return;
        final navigator = Navigator.of(context);
        final nova = await navigator.push(
          MaterialPageRoute<Setlista>(
            builder: (_) => UrejanjeSetlisteZaslon(baza: baza, api: api, mapa: _pravaMapa ? _mapa : null),
          ),
        );
        if (nova != null) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => SetlistaZaslon(setlista: nova, baza: baza, prijava: widget.prijava, spil: widget.spil),
            ),
          );
        }
      case 'vrsta':
        if (widget.spil.naslednje.isEmpty) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Nova čakalna vrsta?'),
            content: Text('Iz čakalne vrste gre ${widget.spil.naslednje.length} pesmi (pri vseh na špilu).'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Prekliči')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Izprazni')),
            ],
          ),
        );
        if (ok == true) widget.spil.pocistiNaslednje();
    }
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

  /// Administrator je poslal nastavitve pogleda: prevzemi ali ne (vpraša le enkrat za vsako pošiljko).
  List<Widget> _pogled() {
    final baza = widget.baza;
    final pogled = baza.pogled;
    if (!baza.novPogled || pogled == null) return const [];
    final n = Nastavitve.aplikacija;
    return [
      MaterialBanner(
        leading: const Icon(Icons.palette_outlined),
        content: const Text(
          'Administrator je poslal nastavitve pogleda (vrstice, pisava, seznam …). Jih uporabiš na tej napravi?',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await n.oznaciPogled(pogled);
              if (mounted) setState(() {});
            },
            child: const Text('Ne'),
          ),
          TextButton(
            onPressed: () async {
              await n.uvoziPogled(pogled);
              await n.oznaciPogled(pogled);
              try {
                if ((jsonDecode(pogled) as Map)['filtri'] case final String f) {
                  await baza.shraniMojoNastavitev(
                    widget.prijava.prijavljen ? Api(widget.prijava.zeton) : null,
                    FiltriClana.kljuc,
                    f,
                  );
                }
              } catch (_) {}
              if (mounted) setState(() {});
            },
            child: const Text('Uporabi'),
          ),
        ],
      ),
    ];
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
    final deli = poljaVPodnaslovu(context, widget.baza, p, polja.toList());
    final imaPodnaslov = polja.any((x) => x != PoljePesmi.status && x != PoljePesmi.ocena);
    return ListTile(
      selected: izbrana,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      title: NaslovZOznakami(pesem: p),
      subtitle: imaPodnaslov ? Text.rich(TextSpan(children: deli), maxLines: 1, overflow: TextOverflow.ellipsis) : null,
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
