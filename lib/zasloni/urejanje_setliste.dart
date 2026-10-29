import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../models.dart';
import 'urejanje_pesmi.dart';

/// Nova setlista ali urejanje obstoječe. Ob shranjevanju vrne [Setlista], ob brisanju null.
class UrejanjeSetlisteZaslon extends StatefulWidget {
  const UrejanjeSetlisteZaslon({super.key, required this.baza, required this.api, this.setlista});

  final Baza baza;
  final Api api;
  final Setlista? setlista;

  @override
  State<UrejanjeSetlisteZaslon> createState() => _UrejanjeSetlisteZaslonState();
}

class _Vnos {
  _Vnos(this.pesem, [this.opomba = '']);
  final Pesem pesem;
  String opomba;
}

class _UrejanjeSetlisteZaslonState extends State<UrejanjeSetlisteZaslon> {
  late final _ime = TextEditingController(text: widget.setlista?.ime ?? '')..addListener(_spremenjeno);
  late final _opombe = TextEditingController(text: widget.setlista?.opombe ?? '')..addListener(_spremenjeno);
  final _koda = TextEditingController();
  late DateTime? _datum = widget.setlista?.datum;
  late String _skupina =
      widget.setlista?.skupina ?? (widget.baza.urednikSkupine.isNotEmpty ? widget.baza.urednikSkupine.first : '');
  late final List<_Vnos> _pesmi = [
    for (final v in widget.baza.pesmiSetlist[widget.setlista?.id] ?? const <SetlistaPesem>[])
      if (widget.baza.pesem(v.pesem) case final p?) _Vnos(p, v.opomba),
  ];
  bool _spremembe = false;
  bool _shranjujem = false;

  void _spremenjeno() {
    if (!_spremembe) setState(() => _spremembe = true);
  }

  @override
  void dispose() {
    _ime.dispose();
    _opombe.dispose();
    _koda.dispose();
    super.dispose();
  }

  void _dodaj(Pesem p) => setState(() {
    _pesmi.add(_Vnos(p));
    _spremembe = true;
  });

  /// Hiter vnos s kodo pesmi (kot v SongBooku): vpiši kodo in pritisni Enter.
  void _dodajKodo(String koda) {
    final k = koda.trim();
    if (k.isEmpty) return;
    final p = widget.baza.pesmi.where((p) => p.koda == k).firstOrNull;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pesmi s kodo $k ni.')));
    } else {
      _dodaj(p);
      _koda.clear();
    }
  }

  Future<void> _izberi() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: _IzbiraPesmi(baza: widget.baza, izbrane: {for (final v in _pesmi) v.pesem.id}, onIzbrana: _dodaj),
      ),
    );
  }

  Future<void> _opomba(_Vnos v) async {
    final c = TextEditingController(text: v.opomba);
    final nova = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(v.pesem.naslov),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Opomba (npr. brez uvoda, 2x refren)'),
          onSubmitted: (s) => Navigator.pop(context, s),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
          TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('V redu')),
        ],
      ),
    );
    c.dispose();
    if (nova != null) {
      setState(() {
        v.opomba = nova.trim();
        _spremembe = true;
      });
    }
  }

  Future<void> _izberiDatum() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _datum ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _datum = d;
        _spremembe = true;
      });
    }
  }

  Future<void> _shrani() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_ime.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Setlista mora imeti ime.')));
      return;
    }
    setState(() => _shranjujem = true);
    try {
      final s = await widget.baza.shraniSetlisto(
        widget.api,
        {
          if (widget.setlista != null) 'ID': widget.setlista!.id,
          'Ime': _ime.text.trim(),
          'Datum': _datum == null ? '' : datumIso(_datum!),
          'Opombe': _opombe.text.trim(),
          'Skupina': _skupina,
        },
        [for (final v in _pesmi) (pesem: v.pesem.id, opomba: v.opomba)],
      );
      if (mounted) Navigator.pop(context, s);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
      if (mounted) setState(() => _shranjujem = false);
    }
  }

  Future<void> _izbrisi() async {
    final da = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izbriši setlisto?'),
        content: const Text('Setlista bo izbrisana za vse člane. Pesmi ostanejo v repertoarju.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Prekliči')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Izbriši')),
        ],
      ),
    );
    if (!(da ?? false) || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _shranjujem = true);
    try {
      await widget.baza.izbrisiSetlisto(widget.api, widget.setlista!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Brisanje ni uspelo: $e')));
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
          title: Text(widget.setlista == null ? 'Nova setlista' : 'Uredi setlisto'),
          actions: [
            if (widget.setlista != null && !_shranjujem)
              IconButton(tooltip: 'Izbriši setlisto', icon: const Icon(Icons.delete_outline), onPressed: _izbrisi),
            _shranjujem
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton.icon(onPressed: _shrani, icon: const Icon(Icons.save), label: const Text('Shrani')),
          ],
        ),
        body: ReorderableListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          header: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _ime,
                  decoration: const InputDecoration(labelText: 'Ime (npr. Poroka Novak)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _izberiDatum,
                        icon: const Icon(Icons.event),
                        label: Text(_datum == null ? 'Datum' : datumBesedilo(_datum!)),
                      ),
                    ),
                    if (mojeSkupine.length > 1) ...[
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: mojeSkupine.any((s) => s.id == _skupina) ? _skupina : null,
                        items: [for (final s in mojeSkupine) DropdownMenuItem(value: s.id, child: Text(s.ime))],
                        onChanged: (v) => setState(() {
                          _skupina = v!;
                          _spremembe = true;
                        }),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _opombe,
                  decoration: const InputDecoration(labelText: 'Opombe', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _koda,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (k) {
                          _dodajKodo(k);
                        },
                        decoration: InputDecoration(
                          labelText: 'Dodaj s kodo',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: () => _dodajKodo(_koda.text)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: _izberi,
                      icon: const Icon(Icons.search),
                      label: const Text('Izberi'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _pesmi.isEmpty ? 'Ni še pesmi.' : '${_pesmi.length} pesmi. Vrstni red spremeniš z vlečenjem.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          itemCount: _pesmi.length,
          onReorderItem: (staro, novo) => setState(() {
            _pesmi.insert(novo, _pesmi.removeAt(staro));
            _spremembe = true;
          }),
          itemBuilder: (context, i) {
            final v = _pesmi[i];
            return ListTile(
              key: ObjectKey(v),
              leading: SizedBox(width: 28, child: Text('${i + 1}.', textAlign: TextAlign.right)),
              title: Text('${v.pesem.koda}  ${v.pesem.naslov}'),
              subtitle: v.opomba.isEmpty ? null : Text(v.opomba),
              onTap: () => _opomba(v),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Odstrani',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _pesmi.removeAt(i);
                      _spremembe = true;
                    }),
                  ),
                  ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                ],
              ),
            );
          },
          buildDefaultDragHandles: false,
        ),
      ),
    );
  }
}

/// Iskanje in dodajanje pesmi v setlisto; ostane odprto za več pesmi.
class _IzbiraPesmi extends StatefulWidget {
  const _IzbiraPesmi({required this.baza, required this.izbrane, required this.onIzbrana});

  final Baza baza;
  final Set<String> izbrane;
  final void Function(Pesem) onIzbrana;

  @override
  State<_IzbiraPesmi> createState() => _IzbiraPesmiState();
}

class _IzbiraPesmiState extends State<_IzbiraPesmi> {
  final _iskanje = TextEditingController();

  @override
  void dispose() {
    _iskanje.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zadetki = widget.baza.pesmi.where((p) => p.ustreza(_iskanje.text)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _iskanje,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Išči po kodi, naslovu ali izvajalcu',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: 'Končano',
                icon: const Icon(Icons.check),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: zadetki.length,
            itemBuilder: (context, i) {
              final p = zadetki[i];
              final dodana = widget.izbrane.contains(p.id);
              return ListTile(
                leading: SizedBox(
                  width: 52,
                  child: Text(p.koda, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                title: Text(p.naslov),
                subtitle: p.izvajalec.isEmpty ? null : Text(p.izvajalec),
                trailing: Icon(dodana ? Icons.check_circle : Icons.add_circle_outline),
                onTap: () {
                  widget.onIzbrana(p);
                  setState(() => widget.izbrane.add(p.id));
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
