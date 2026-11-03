import 'package:flutter/material.dart';

import '../besedilo_si.dart';

/// Kaj prevzamemo s besedilo.si.
enum PrevzemBs { besedilo, naslov, izvajalec, avtorBesedila, avtorGlasbe }

/// Iskanje na besedilo.si, izbira zadetka in predogled. Vrne pesem in izbrane podatke ali null.
/// [obstojece]: trenutne vrednosti pri pesmi (vse je privzeto obkljukano; pri polnih piše, da jih zamenja).
Future<(PesemBs, Set<PrevzemBs>)?> uvozZBesediloSi(
  BuildContext context, {
  required BesediloSi vir,
  required String iskanje,
  required Map<PrevzemBs, String> obstojece,
}) async {
  final izbrana = await showDialog<PesemBs>(
    context: context,
    builder: (_) => _Iskanje(vir: vir, zacetno: iskanje),
  );
  if (izbrana == null || !context.mounted) return null;
  return showDialog<(PesemBs, Set<PrevzemBs>)>(
    context: context,
    builder: (_) => _Predogled(vir: vir, pesem: izbrana, obstojece: obstojece),
  );
}

class _Iskanje extends StatefulWidget {
  const _Iskanje({required this.vir, required this.zacetno});

  final BesediloSi vir;
  final String zacetno;

  @override
  State<_Iskanje> createState() => _IskanjeState();
}

class _IskanjeState extends State<_Iskanje> {
  late final _vnos = TextEditingController(text: widget.zacetno);
  List<PesemBs>? _zadetki;
  String? _napaka;
  bool _iscem = false;

  @override
  void initState() {
    super.initState();
    if (widget.zacetno.trim().isNotEmpty) _isci();
  }

  @override
  void dispose() {
    _vnos.dispose();
    super.dispose();
  }

  Future<void> _isci() async {
    setState(() {
      _iscem = true;
      _napaka = null;
    });
    try {
      final z = await widget.vir.isci(_vnos.text);
      if (mounted) setState(() => _zadetki = z);
    } catch (e) {
      if (mounted) setState(() => _napaka = 'Iskanje ni uspelo: $e');
    } finally {
      if (mounted) setState(() => _iscem = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = _zadetki;
    return AlertDialog(
      title: const Text('Poišči na besedilo.si'),
      content: SizedBox(
        width: 460,
        height: 440,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('besedilosi-iskanje'),
              controller: _vnos,
              autofocus: widget.zacetno.isEmpty,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _isci(),
              decoration: InputDecoration(
                hintText: 'Naslov pesmi',
                suffixIcon: IconButton(tooltip: 'Išči', icon: const Icon(Icons.search), onPressed: _isci),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _iscem
                  ? const Center(child: CircularProgressIndicator())
                  : _napaka != null
                  ? Center(child: Text(_napaka!))
                  : z == null
                  ? const SizedBox()
                  : z.isEmpty
                  ? const Center(child: Text('Ni zadetkov. Poskusi z delom naslova.'))
                  : ListView(
                      children: [
                        for (final p in z)
                          ListTile(
                            dense: true,
                            title: Text(p.naslov),
                            subtitle: Text(
                              [
                                p.izvajalec,
                                if (p.besedilo case final b? when b.isNotEmpty) b.split('\n').first,
                              ].where((x) => x.isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.pop(context, p),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči'))],
    );
  }
}

class _Predogled extends StatefulWidget {
  const _Predogled({required this.vir, required this.pesem, required this.obstojece});

  final BesediloSi vir;
  final PesemBs pesem;
  final Map<PrevzemBs, String> obstojece;

  @override
  State<_Predogled> createState() => _PredogledState();
}

class _PredogledState extends State<_Predogled> {
  PesemBs? _p;
  String? _napaka;
  final _izbrano = <PrevzemBs>{};

  @override
  void initState() {
    super.initState();
    widget.vir
        .podrobnosti(widget.pesem)
        .then((p) {
          if (!mounted) return;
          setState(() {
            _p = p;
            for (final k in PrevzemBs.values) {
              if (_vrednost(k).isNotEmpty) _izbrano.add(k);
            }
          });
        })
        .catchError((Object e) {
          if (mounted) setState(() => _napaka = 'Branje ni uspelo: $e');
        });
  }

  String _vrednost(PrevzemBs k) {
    final p = _p!;
    return switch (k) {
      PrevzemBs.besedilo => p.besedilo ?? '',
      PrevzemBs.naslov => p.naslov,
      PrevzemBs.izvajalec => p.izvajalec,
      PrevzemBs.avtorBesedila => p.avtorBesedila,
      PrevzemBs.avtorGlasbe => p.avtorGlasbe,
    };
  }

  static const _imena = {
    PrevzemBs.besedilo: 'Besedilo',
    PrevzemBs.naslov: 'Naslov',
    PrevzemBs.izvajalec: 'Izvajalec',
    PrevzemBs.avtorBesedila: 'Avtor besedila',
    PrevzemBs.avtorGlasbe: 'Avtor glasbe',
  };

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final tema = Theme.of(context);
    return AlertDialog(
      title: Text(widget.pesem.naslov),
      content: SizedBox(
        width: 460,
        height: 480,
        child: p == null
            ? Center(child: _napaka == null ? const CircularProgressIndicator() : Text(_napaka!))
            : ListView(
                children: [
                  for (final k in PrevzemBs.values)
                    if (_vrednost(k).isNotEmpty)
                      CheckboxListTile(
                        key: ValueKey('prevzem-${k.name}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _izbrano.contains(k),
                        onChanged: (v) => setState(() => v == true ? _izbrano.add(k) : _izbrano.remove(k)),
                        title: Text(_imena[k]!),
                        subtitle: Text(
                          [
                            k == PrevzemBs.besedilo
                                ? '${_vrednost(k).split('\n').where((v) => v.trim().isNotEmpty).length} vrstic'
                                : _vrednost(k),
                            if ((widget.obstojece[k] ?? '').trim().isNotEmpty) 'zamenja obstoječe',
                          ].join(' · '),
                        ),
                      ),
                  const Divider(),
                  if (p.besedilo case final b? when b.isNotEmpty)
                    Text(b, style: tema.textTheme.bodySmall)
                  else
                    const Text('Besedila ni bilo mogoče prebrati.'),
                  const SizedBox(height: 8),
                  Text('Vir: ${p.povezava}', style: tema.textTheme.labelSmall),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
        FilledButton(
          key: const ValueKey('prevzemi'),
          onPressed: p == null || _izbrano.isEmpty ? null : () => Navigator.pop(context, (p, {..._izbrano})),
          child: const Text('Prevzemi'),
        ),
      ],
    );
  }
}
