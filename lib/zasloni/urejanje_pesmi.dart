import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../models.dart';
import '../prijava.dart';

/// Api za shranjevanje sprememb; brez prijave pokaže opozorilo in vrne null.
Api? apiZaUrejanje(BuildContext context, Prijava prijava) {
  if (prijava.prijavljen) return Api(prijava.zeton);
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Za urejanje se prijavi z Google računom (potreben je internet).')));
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

/// Vnos nove pesmi ali urejanje podatkov obstoječe. Ob uspehu vrne shranjeno [Pesem].
class UrejanjePesmiZaslon extends StatefulWidget {
  const UrejanjePesmiZaslon({super.key, required this.baza, required this.api, this.pesem});

  final Baza baza;
  final Api api;
  final Pesem? pesem;

  @override
  State<UrejanjePesmiZaslon> createState() => _UrejanjePesmiZaslonState();
}

class _UrejanjePesmiZaslonState extends State<UrejanjePesmiZaslon> {
  // Stolpec v listu Pesmi, številska tipkovnica, predlogi iz obstoječih pesmi.
  static const _polja = [
    ('Koda', true, false),
    ('Naslov', false, false),
    ('Izvajalec', false, true),
    ('Avtor glasbe', false, true),
    ('Avtor besedila', false, true),
    ('Zvrst', false, true),
    ('Vrsta', false, true),
    ('Tonaliteta', false, false),
    ('Harmonika', false, false),
    ('Tempo (BPM)', true, false),
    ('Opombe', false, false),
  ];

  late final Map<String, TextEditingController> _vnosi = {
    for (final (stolpec, _, _) in _polja)
      stolpec: TextEditingController(text: besedilo(widget.pesem?.vrstica[stolpec]))..addListener(_spremenjeno),
  };
  late bool _aktivna = widget.pesem?.aktivna ?? true;
  late final Set<String> _skupine = {
    ...?widget.pesem?.skupine,
    if (widget.pesem == null && widget.baza.urednikSkupine.isNotEmpty) widget.baza.urednikSkupine.first,
  };
  bool _spremembe = false;
  bool _shranjujem = false;

  void _spremenjeno() {
    if (!_spremembe) setState(() => _spremembe = true);
  }

  @override
  void dispose() {
    for (final c in _vnosi.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opozoriloKode() {
    final koda = _vnosi['Koda']!.text.trim();
    if (koda.isEmpty) return null;
    final ista = widget.baza.pesmi.where((p) => p.koda == koda && p.id != widget.pesem?.id);
    return ista.isEmpty ? null : 'Koda je že zasedena: ${ista.first.naslov}';
  }

  Future<void> _shrani() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_vnosi['Naslov']!.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Pesem mora imeti naslov.')));
      return;
    }
    if (_skupine.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Izberi vsaj eno skupino.')));
      return;
    }
    setState(() => _shranjujem = true);
    try {
      final pesem = await widget.baza.shraniPesem(widget.api, {
        if (widget.pesem != null) 'ID': widget.pesem!.id,
        for (final e in _vnosi.entries) e.key: e.value.text.trim(),
        'Aktivna': _aktivna,
        'Skupine': _skupine.join(','),
      });
      if (mounted) Navigator.pop(context, pesem);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
      if (mounted) setState(() => _shranjujem = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mojeSkupine = widget.baza.skupine.where((s) => widget.baza.urednikSkupine.contains(s.id)).toList();
    return PopScope(
      canPop: !_spremembe || _shranjujem,
      onPopInvokedWithResult: (umaknjen, _) async {
        if (umaknjen) return;
        final navigator = Navigator.of(context);
        if (await potrdiOdhod(context)) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.pesem == null ? 'Nova pesem' : 'Uredi pesem'),
          actions: [
            _shranjujem
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton.icon(onPressed: _shrani, icon: const Icon(Icons.save), label: const Text('Shrani')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final (stolpec, stevilo, predlogi) in _polja)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _vnosi[stolpec],
                  keyboardType: stevilo ? TextInputType.number : TextInputType.text,
                  textCapitalization: stolpec == 'Naslov'
                      ? TextCapitalization.characters
                      : TextCapitalization.sentences,
                  maxLines: stolpec == 'Opombe' ? null : 1,
                  onChanged: stolpec == 'Koda' ? (_) => setState(() {}) : null,
                  decoration: InputDecoration(
                    labelText: stolpec,
                    border: const OutlineInputBorder(),
                    errorText: stolpec == 'Koda' ? _opozoriloKode() : null,
                    suffixIcon: predlogi ? _predlogi(stolpec) : null,
                  ),
                ),
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
                        _spremembe = true;
                      }),
                    ),
                ],
              ),
            ],
            if (widget.pesem != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pesem je v repertoarju'),
                subtitle: const Text('Izklopljena pesem se ne prikazuje več v seznamu.'),
                value: _aktivna,
                onChanged: (v) => setState(() {
                  _aktivna = v;
                  _spremembe = true;
                }),
              ),
          ],
        ),
      ),
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
