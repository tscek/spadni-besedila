import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../chordpro.dart' as cp;
import '../midi/midi.dart';
import '../midi/ukazi.dart';
import '../models.dart';
import '../uvodi.dart';
import 'pesem_zaslon.dart' show BesediloPogled;
import 'urejanje_uvoda.dart' show casUvoda;

/// Učenje časov vrstic: playback teče na tej napravi, ob začetku vsake vrstice tapneš na besedilo
/// (ali pritisneš nožno stikalo: naslednja, dol ali potrdi). Časi se shranijo k pesmi.
class UcenjeCasovZaslon extends StatefulWidget {
  const UcenjeCasovZaslon({super.key, required this.baza, required this.api, required this.pesem});

  final Baza baza;
  final Api api;
  final String pesem;

  @override
  State<UcenjeCasovZaslon> createState() => _UcenjeCasovZaslonState();
}

class _UcenjeCasovZaslonState extends State<UcenjeCasovZaslon> {
  late final Pesem _p = widget.baza.pesem(widget.pesem)!;
  late final String _vsebina = (widget.baza.besedilaPesmi[widget.pesem] ?? const []).firstOrNull?.vsebina ?? '';
  late final List<cp.Vrstica> _vrstice = cp.razcleni(_vsebina);

  /// Indeksi vrstic z besedilom (te dobijo čas).
  late final List<int> _zBesedilom = [
    for (var i = 0; i < _vrstice.length; i++)
      if (_vrstice[i].vrsta == cp.VrstaVrstice.besedilo) i,
  ];
  late List<int?> _casi = List<int?>.filled(_vrstice.length, null);
  late int _zamik = _p.casiPlaybacka.zamik;

  /// Naslednja vrstica za tap (indeks v [_zBesedilom]).
  int _naslednja = 0;
  late final List<GlobalKey> _kljuci = [for (final _ in _vrstice) GlobalKey()];
  bool _nalagam = true;
  bool _shranjujem = false;
  bool _spremenjeno = false;
  String? _napaka;

  Predvajanje get _pl => Predvajanje.playback;

  @override
  void initState() {
    super.initState();
    final stari = _p.casiPlaybacka;
    if (stari.casi.length == _vrstice.length) _casi = [...stari.casi];
    _pl.addListener(_osvezi);
    _pl.pozicija.addListener(_osvezi);
    _pripravi();
  }

  @override
  void dispose() {
    _pl.removeListener(_osvezi);
    _pl.pozicija.removeListener(_osvezi);
    _pl.ustavi();
    super.dispose();
  }

  void _osvezi() {
    if (mounted) setState(() {});
  }

  Uint8List? _bajti;

  Future<void> _pripravi() async {
    try {
      _bajti = await widget.baza.zvok(widget.api, _p, VrstaZvoka.playback);
      if (_bajti == null) _napaka = 'Playbacka ni bilo mogoče prebrati.';
    } catch (e) {
      _napaka = 'Playbacka ni bilo mogoče prebrati: $e';
    }
    if (mounted) setState(() => _nalagam = false);
  }

  bool get _igra => _pl.igra == _p.id;

  /// Od začetka: časi se učijo znova od prve vrstice.
  Future<void> _zacni() async {
    final b = _bajti;
    if (b == null) return;
    setState(() => _naslednja = 0);
    _pl.igra = _p.id;
    await _pl.predvajajBajte(b, _p.zvokVrsta(VrstaZvoka.playback), transpozicija: _p.playbackTranspozicija);
  }

  void _tap() {
    if (!_igra || _naslednja >= _zBesedilom.length) return;
    final i = _zBesedilom[_naslednja];
    setState(() {
      _casi[i] = _pl.pozicija.value.inMilliseconds;
      _naslednja++;
      _spremenjeno = true;
    });
    if (_naslednja < _zBesedilom.length) _vidna(_zBesedilom[_naslednja]);
  }

  void _razveljavi() {
    if (_naslednja == 0) return;
    setState(() {
      _naslednja--;
      _casi[_zBesedilom[_naslednja]] = null;
      _spremenjeno = true;
    });
  }

  void _vidna(int i) {
    final c = _kljuci[i].currentContext;
    if (c != null) {
      Scrollable.ensureVisible(c, alignment: 0.3, duration: const Duration(milliseconds: 250));
    }
  }

  Future<void> _shrani() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _shranjujem = true);
    try {
      await widget.baza.shraniPesem(widget.api, {
        'ID': _p.id,
        'Koda': _p.koda,
        'Naslov': _p.naslov,
        'Playback časi': CasiVrstic(_casi, zamik: _zamik).vBesedilo(),
      });
      messenger.showSnackBar(const SnackBar(content: Text('Časi vrstic so shranjeni.')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
      if (mounted) setState(() => _shranjujem = false);
    }
  }

  bool _dejanje(DejanjeMidi d) {
    if (d == DejanjeMidi.naslednja || d == DejanjeMidi.dol || d == DejanjeMidi.potrdi) {
      _tap();
      return true;
    }
    if (d == DejanjeMidi.prejsnja || d == DejanjeMidi.gor) {
      _razveljavi();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final barve = Theme.of(context).colorScheme;
    final pogled = BesediloPogled.vrstice(context, _vsebina, 22);
    final igra = _igra;
    final trenutna = igra ? CasiVrstic(_casi).vrsticaOb(_pl.pozicija.value) : null;
    final naslednja = _naslednja < _zBesedilom.length ? _zBesedilom[_naslednja] : null;
    return NaMidi(
      dejanje: _dejanje,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Časi vrstic: ${_p.naslov}', overflow: TextOverflow.ellipsis),
          actions: [
            TextButton.icon(
              key: const ValueKey('ucenje-shrani'),
              onPressed: _spremenjeno && !_shranjujem ? _shrani : null,
              icon: const Icon(Icons.save),
              label: const Text('Shrani'),
            ),
          ],
        ),
        body: _nalagam
            ? const Center(child: CircularProgressIndicator())
            : _napaka != null
            ? Center(child: Text(_napaka!))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      igra
                          ? 'Tapni na besedilo ob začetku vsake vrstice (ali nožno stikalo). '
                                'Vrstica ${_naslednja + 1 > _zBesedilom.length ? _zBesedilom.length : _naslednja + 1} od ${_zBesedilom.length}.'
                          : 'Pritisni ▶ Od začetka, nato ob začetku vsake vrstice tapni na besedilo.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey('ucenje-tap'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _tap,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (var i = 0; i < pogled.length; i++)
                            Container(
                              key: _kljuci[i],
                              decoration: BoxDecoration(
                                color: i == trenutna ? Colors.blue.withValues(alpha: 0.18) : null,
                                border: i == naslednja && igra
                                    ? Border(left: BorderSide(color: barve.tertiary, width: 4))
                                    : null,
                              ),
                              padding: const EdgeInsets.only(left: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  SizedBox(
                                    width: 56,
                                    child: Text(
                                      _casi[i] == null ? '' : casUvoda(_casi[i]! / 1000),
                                      style: TextStyle(fontSize: 11, color: barve.outline),
                                    ),
                                  ),
                                  Expanded(child: pogled[i]),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('ucenje-zacni'),
                          onPressed: igra ? _pl.ustavi : _zacni,
                          icon: Icon(igra ? Icons.stop : Icons.play_arrow),
                          label: Text(igra ? 'Ustavi' : 'Od začetka'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('ucenje-razveljavi'),
                          onPressed: _naslednja > 0 ? _razveljavi : null,
                          icon: const Icon(Icons.undo),
                          label: const Text('Razveljavi zadnjo'),
                        ),
                        Text(igra ? casUvoda(_pl.pozicija.value.inMilliseconds / 1000) : ''),
                        const SizedBox(width: 8),
                        const Text('Zamik'),
                        DropdownButton<int>(
                          key: const ValueKey('ucenje-zamik'),
                          value: _zamik,
                          onChanged: (v) => setState(() {
                            _zamik = v ?? 0;
                            _spremenjeno = true;
                          }),
                          items: [
                            for (var z = -2000; z <= 2000; z += 250)
                              DropdownMenuItem(
                                value: z,
                                child: Text(
                                  '${z > 0 ? '+' : ''}${(z / 1000).toStringAsFixed(2).replaceAll('.', ',')} s',
                                ),
                              ),
                          ],
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
