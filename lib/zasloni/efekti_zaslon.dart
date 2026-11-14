import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../efekti.dart';
import '../nastavitve.dart';
import '../uvodi.dart';
import 'urejanje_uvoda.dart' show vrstaZvoka;

/// Zvočni efekti: nastavitve te naprave in knjižnica (ureja administrator).
class EfektiZaslon extends StatefulWidget {
  const EfektiZaslon({super.key, required this.baza, required this.api});

  final Baza baza;
  final Api? Function() api;

  /// Največja velikost datoteke efekta.
  static const najvec = 15 * 1024 * 1024;

  @override
  State<EfektiZaslon> createState() => _EfektiZaslonState();
}

class _EfektiZaslonState extends State<EfektiZaslon> {
  List<IzhodZvoka>? _izhodi;
  bool _delam = false;
  bool _prenasam = false;
  PredvajalnikZvoka? _poslusanje;
  String? _igra;

  @override
  void initState() {
    super.initState();
    widget.baza.addListener(_osvezi);
    if (!kIsWeb) {
      Predvajanje.playback
          .izhodi()
          .then((i) {
            if (mounted) setState(() => _izhodi = i);
          })
          .catchError((_) {
            if (mounted) setState(() => _izhodi = const []);
          });
    }
  }

  @override
  void dispose() {
    widget.baza.removeListener(_osvezi);
    _poslusanje?.ustavi();
    _poslusanje?.zapri();
    super.dispose();
  }

  void _osvezi() {
    if (mounted) setState(() {});
  }

  Future<void> _hrani(bool da) async {
    final messenger = ScaffoldMessenger.of(context);
    await Nastavitve.aplikacija.nastaviHraniEfekte(da);
    setState(() {});
    if (!da) {
      await widget.baza.izbrisiLokalneEfekte();
      return;
    }
    final api = widget.api();
    if (api == null) return;
    setState(() => _prenasam = true);
    try {
      final neuspeli = await widget.baza.prenesiEfekte(api);
      messenger.showSnackBar(
        SnackBar(content: Text(neuspeli == 0 ? 'Efekti: vse preneseno.' : 'Efekti: neuspešnih prenosov: $neuspeli.')),
      );
    } finally {
      if (mounted) setState(() => _prenasam = false);
    }
  }

  Api? _apiZaUrejanje() {
    final api = widget.api();
    if (api == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Za urejanje knjižnice se prijavi (potreben je internet).')));
    }
    return api;
  }

  /// Doda enega ali več efektov (ime je ime datoteke, preimenuješ ga kasneje).
  Future<void> _dodaj() async {
    final messenger = ScaffoldMessenger.of(context);
    final api = _apiZaUrejanje();
    if (api == null) return;
    final izbrane = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'webm', 'flac'],
    );
    if (izbrane.isEmpty || !mounted) return;
    setState(() => _delam = true);
    final napake = <String>[];
    try {
      for (final f in izbrane) {
        final bajti = await f.readAsBytes();
        if (bajti.length > EfektiZaslon.najvec) {
          napake.add('${f.name}: prevelika (največ 15 MB)');
          continue;
        }
        final ime = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
        try {
          await widget.baza.shraniEfekt(api, ime: ime, bajti: bajti, vrsta: vrstaZvoka(f.name));
        } catch (e) {
          napake.add('${f.name}: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _delam = false);
    }
    messenger.showSnackBar(
      SnackBar(content: Text(napake.isEmpty ? 'Efekti so dodani.' : 'Ni uspelo: ${napake.join('; ')}')),
    );
  }

  Future<void> _preimenuj(Efekt e) async {
    final vnos = TextEditingController(text: e.ime);
    final ime = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ime efekta'),
        content: TextField(controller: vnos, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
          FilledButton(onPressed: () => Navigator.pop(context, vnos.text), child: const Text('Shrani')),
        ],
      ),
    );
    vnos.dispose();
    if (ime == null || ime.trim().isEmpty || ime.trim() == e.ime || !mounted) return;
    final api = _apiZaUrejanje();
    if (api == null) return;
    await _poskusi(() => widget.baza.shraniEfekt(api, id: e.id, ime: ime.trim()));
  }

  Future<void> _izbrisi(Efekt e) async {
    final uporabljen = widget.baza.fx.gumbi.where((g) => g.efekt == e.id).map((g) => g.ime).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Izbrišem efekt »${e.ime}«?'),
        content: Text(
          uporabljen.isEmpty
              ? 'Datoteka gre v koš na Drivu.'
              : 'Uporabljajo ga gumbi: ${uporabljen.join(', ')}. Ti gumbi ostanejo brez zvoka.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ne')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Izbriši')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = _apiZaUrejanje();
    if (api == null) return;
    await _poskusi(() => widget.baza.izbrisiEfekt(api, e.id));
  }

  Future<void> _poskusi(Future<Object?> Function() f) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _delam = true);
    try {
      await f();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Ni uspelo: $e')));
    } finally {
      if (mounted) setState(() => _delam = false);
    }
  }

  /// Poslušanje na tej napravi (ne gre na PC).
  Future<void> _poslusaj(Efekt e) async {
    final messenger = ScaffoldMessenger.of(context);
    final p = _poslusanje ??= PredvajalnikZvoka.tovarna();
    if (_igra == e.id) {
      await p.ustavi();
      setState(() => _igra = null);
      return;
    }
    try {
      final b = await widget.baza.bajtiEfekta(widget.api(), e.id);
      if (b == null) throw StateError('ni na voljo brez interneta');
      await p.odpri(b.bajti, b.vrsta);
      await p.glasnost(1);
      await p.predvajaj(Duration.zero);
      if (mounted) setState(() => _igra = e.id);
      unawaited(
        p.konec.first.then((_) {
          if (mounted && _igra == e.id) setState(() => _igra = null);
        }),
      );
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('Efekta ni bilo mogoče predvajati: $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = Nastavitve.aplikacija;
    final admin = widget.baza.jeAdministrator;
    final efekti = widget.baza.efekti;
    final izhodi = _izhodi;
    return Scaffold(
      appBar: AppBar(title: const Text('Zvočni efekti (FX)')),
      floatingActionButton: admin
          ? FloatingActionButton.extended(
              key: const ValueKey('efekti-dodaj'),
              onPressed: _delam ? null : _dodaj,
              icon: const Icon(Icons.library_add),
              label: const Text('Dodaj efekte'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          const ListTile(title: Text('Na tej napravi')),
          SwitchListTile(
            key: const ValueKey('efekti-predvajaj'),
            title: const Text('Predvajaj efekte na tej napravi'),
            subtitle: const Text(
              'Privzeto samo računalnik. Gumbi FX na drugih napravah na špilu sprožijo efekt tu. '
              'Brez špila efekti vedno igrajo na napravi, kjer pritisneš gumb.',
            ),
            value: n.predvajajEfekte,
            onChanged: (da) async {
              await n.nastaviPredvajajEfekte(da);
              if (da) unawaited(Efekti.aplikacija.pripravi());
              setState(() {});
            },
          ),
          SwitchListTile(
            key: const ValueKey('efekti-fx-midi'),
            title: const Text('FX MIDI iz te naprave'),
            subtitle: const Text(
              'Na špilu gre ves MIDI s FX (gumbi FX, XY pad in njegovi gumbi) z vseh naprav sem in ga pošlje ta naprava. '
              'Vklopi na eni napravi (privzeto računalnik).',
            ),
            value: n.fxMidiTu,
            onChanged: (da) async {
              await n.nastaviFxMidiTu(da);
              setState(() {});
            },
          ),
          SwitchListTile(
            key: const ValueKey('efekti-hrani'),
            title: const Text('Hrani efekte lokalno'),
            subtitle: Text(
              _prenasam
                  ? 'Prenašam …'
                  : 'Ob osvežitvi prenese vse efekte na napravo (hiter odziv, deluje brez interneta)',
            ),
            value: n.hraniEfekte,
            onChanged: _prenasam ? null : _hrani,
          ),
          if (!kIsWeb && (izhodi == null || izhodi.isNotEmpty))
            ListTile(
              title: const Text('Izhod za efekte'),
              subtitle: const Text('Npr. ozvočenje (USB zvočna kartica)'),
              trailing: izhodi == null
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : DropdownButton<String>(
                      key: const ValueKey('efekti-izhod'),
                      value: izhodi.any((i) => i.id == n.izhodEfektov) ? n.izhodEfektov : '',
                      onChanged: (id) async {
                        await n.nastaviIzhodEfektov(id ?? '');
                        setState(() {});
                      },
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Privzeti izhod sistema')),
                        for (final i in izhodi)
                          DropdownMenuItem(
                            value: i.id,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Text(i.ime, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                      ],
                    ),
            ),
          const Divider(),
          ListTile(
            title: const Text('Knjižnica'),
            subtitle: Text(
              admin
                  ? 'Skupna vsem. Dodaj datoteke (mp3, wav …, največ 15 MB), nato jih v panelu FX dodeli gumbom.'
                  : 'Skupna vsem; ureja jo administrator.',
            ),
            trailing: _delam ? const CircularProgressIndicator() : null,
          ),
          if (efekti.isEmpty) const ListTile(dense: true, title: Text('Knjižnica je prazna.')),
          for (final e in efekti)
            ListTile(
              key: ValueKey('efekt-${e.id}'),
              leading: IconButton(
                tooltip: _igra == e.id ? 'Ustavi' : 'Poslušaj',
                icon: Icon(_igra == e.id ? Icons.stop : Icons.play_arrow),
                onPressed: () => _poslusaj(e),
              ),
              title: Text(e.ime),
              subtitle: Text(
                widget.baza.fx.gumbi.where((g) => g.efekt == e.id).map((g) => g.ime).join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: admin
                  ? PopupMenuButton<String>(
                      onSelected: (v) => v == 'ime' ? _preimenuj(e) : _izbrisi(e),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'ime', child: Text('Preimenuj')),
                        PopupMenuItem(value: 'izbrisi', child: Text('Izbriši')),
                      ],
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}
