import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../chordpro.dart' as cp;
import '../models.dart';
import 'pesem_zaslon.dart';
import 'urejanje_pesmi.dart';

/// Vnos ali urejanje besedila pesmi z akordi v oglatih oklepajih. Ob uspehu vrne true.
class UrejanjeBesedilaZaslon extends StatefulWidget {
  const UrejanjeBesedilaZaslon({super.key, required this.baza, required this.api, required this.pesem, this.besedilo});

  final Baza baza;
  final Api api;
  final Pesem pesem;
  final BesediloPesmi? besedilo;

  @override
  State<UrejanjeBesedilaZaslon> createState() => _UrejanjeBesedilaZaslonState();
}

class _UrejanjeBesedilaZaslonState extends State<UrejanjeBesedilaZaslon> with OdprtoUrejanje {
  late final _vsebina = TextEditingController(text: widget.besedilo?.vsebina ?? '')..addListener(_spremenjeno);
  late final _opombe = TextEditingController(text: widget.besedilo?.opombe ?? '')..addListener(_spremenjeno);
  late String _vrsta = BesediloPesmi.vrste.contains(widget.besedilo?.vrsta)
      ? widget.besedilo!.vrsta
      : BesediloPesmi.vrste.first;
  bool _spremembe = false;
  bool _shranjujem = false;

  void _spremenjeno() {
    if (!_spremembe) setState(() => _spremembe = true);
  }

  @override
  void dispose() {
    _vsebina.dispose();
    _opombe.dispose();
    super.dispose();
  }

  /// Vstavi besedilo na mesto kazalca; kazalec postavi [nazaj] znakov pred konec vstavljenega.
  void _vstavi(String s, {int nazaj = 0}) {
    final v = _vsebina.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final nov = v.text.replaceRange(sel.start, sel.end, s);
    _vsebina.value = TextEditingValue(
      text: nov,
      selection: TextSelection.collapsed(offset: sel.start + s.length - nazaj),
    );
  }

  void _pretvori() {
    final novo = cp.akordiNadBesedilom(_vsebina.text);
    if (novo == _vsebina.text.replaceAll('\r\n', '\n')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ni vrstic z akordi nad besedilom.')));
      return;
    }
    _vsebina.text = novo;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Akordi so vstavljeni v besedilo.')));
  }

  Future<void> _shrani({bool izbrisi = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!izbrisi && _vsebina.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Besedilo je prazno.')));
      return;
    }
    setState(() => _shranjujem = true);
    try {
      await widget.baza.shraniBesedilo(widget.api, {
        if (widget.besedilo != null) 'ID': widget.besedilo!.id,
        'Pesem': widget.pesem.id,
        'Vrsta': _vrsta,
        'Besedilo': izbrisi ? '' : _vsebina.text.trimRight(),
        'Opombe': _opombe.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
      if (mounted) setState(() => _shranjujem = false);
    }
  }

  Future<void> _izbrisi() async {
    final da = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izbriši besedilo?'),
        content: const Text('Besedilo bo izbrisano za vse člane. PDF pesmi ostane.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Prekliči')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Izbriši')),
        ],
      ),
    );
    if (da ?? false) await _shrani(izbrisi: true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_spremembe || _shranjujem,
      onPopInvokedWithResult: (umaknjen, _) async {
        if (umaknjen) return;
        final navigator = Navigator.of(context);
        if (await potrdiOdhod(context)) navigator.pop();
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.pesem.naslov),
            actions: [
              if (widget.besedilo != null && !_shranjujem)
                IconButton(tooltip: 'Izbriši besedilo', icon: const Icon(Icons.delete_outline), onPressed: _izbrisi),
              _shranjujem
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton.icon(onPressed: _shrani, icon: const Icon(Icons.save), label: const Text('Shrani')),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Uredi'),
                Tab(text: 'Predogled'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _urejanje(context),
              ListenableBuilder(
                listenable: _vsebina,
                builder: (context, _) => BesediloPogled(vsebina: _vsebina.text, velikost: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _urejanje(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              DropdownButton<String>(
                value: _vrsta,
                items: [for (final v in BesediloPesmi.vrste) DropdownMenuItem(value: v, child: Text(v))],
                onChanged: (v) => setState(() {
                  _vrsta = v!;
                  _spremembe = true;
                }),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Vstavi akord [ ]',
                icon: const Icon(Icons.music_note),
                onPressed: () => _vstavi('[]', nazaj: 1),
              ),
              IconButton(
                tooltip: 'Vstavi oznako (npr. Refren)',
                icon: const Icon(Icons.label_outline),
                onPressed: () => _vstavi('{c: Refren}\n'),
              ),
              IconButton(
                tooltip: 'Pretvori akorde nad besedilom',
                icon: const Icon(Icons.auto_fix_high),
                onPressed: _pretvori,
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Akord napiši v oglatih oklepajih pred zlog: [C]Belo obleko [G7]si že nosila. '
            'Oznaka kitice: {c: Refren}. Besedilo s spleta, kjer so akordi v vrstici nad besedilom, '
            'prilepi in pritisni čarobno palico.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _vsebina,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Besedilo pesmi'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: TextField(
            controller: _opombe,
            decoration: const InputDecoration(labelText: 'Opombe', border: OutlineInputBorder(), isDense: true),
          ),
        ),
      ],
    );
  }
}
