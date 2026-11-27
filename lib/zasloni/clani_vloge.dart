import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../prijava.dart';

/// Vloge, ki jih aplikacija pozna (prazno = brez vloge, samo ogled).
const vlogeClanov = ['', 'Gledalec', 'Urejevalec', 'Administrator'];

/// Administrator: člani, njihov dostop do aplikacije (Nastopi) in vloge po zasedbah (list Vloge).
class ClaniVlogeZaslon extends StatefulWidget {
  const ClaniVlogeZaslon({super.key, required this.baza, required this.prijava});

  final Baza baza;
  final Prijava prijava;

  @override
  State<ClaniVlogeZaslon> createState() => _ClaniVlogeZaslonState();
}

class _ClaniVlogeZaslonState extends State<ClaniVlogeZaslon> {
  bool _shranjujem = false;

  Baza get baza => widget.baza;

  String _imeZasedbe(String id) => baza.skupine.where((s) => s.id == id).firstOrNull?.ime ?? id;

  Future<void> _uredi(({String id, String ime, bool dostop, List<String> zasedbe}) c) async {
    final u = baza.urejanjeClanov!;
    final zasedbe = {
      ...c.zasedbe,
      for (final v in u.vloge)
        if (v.clan == c.id) v.skupina,
    }.toList();
    final vloge = {
      for (final z in zasedbe)
        z:
            u.vloge.where((v) => v.clan == c.id && v.skupina == z).firstOrNull ??
            (clan: c.id, skupina: z, vloga: '', smeVoditi: false),
    };
    var dostop = c.dostop;
    final shrani = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, nastavi) => AlertDialog(
          title: Text(c.ime.isEmpty ? c.id : c.ime),
          content: SizedBox(
            width: 380,
            child: ListView(
              shrinkWrap: true,
              children: [
                SwitchListTile(
                  key: const ValueKey('clan-dostop'),
                  title: const Text('Dostop do aplikacije'),
                  subtitle: const Text('Se lahko prijavi (stolpec v Nastopih)'),
                  value: dostop,
                  onChanged: (v) => nastavi(() => dostop = v),
                ),
                if (zasedbe.isEmpty)
                  const ListTile(title: Text('Član ni v nobeni zasedbi (zasedbe se urejajo v Nastopih).')),
                for (final z in zasedbe) ...[
                  const Divider(),
                  ListTile(
                    title: Text(_imeZasedbe(z), style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: DropdownButton<String>(
                      key: ValueKey('clan-vloga-$z'),
                      value: vlogeClanov.contains(vloge[z]!.vloga) ? vloge[z]!.vloga : '',
                      items: [
                        for (final v in vlogeClanov)
                          DropdownMenuItem(value: v, child: Text(v.isEmpty ? 'Brez vloge' : v)),
                      ],
                      onChanged: (v) => nastavi(() {
                        final s = vloge[z]!;
                        vloge[z] = (clan: s.clan, skupina: s.skupina, vloga: v ?? '', smeVoditi: s.smeVoditi);
                      }),
                    ),
                  ),
                  CheckboxListTile(
                    key: ValueKey('clan-vodi-$z'),
                    title: const Text('Sme voditi špil'),
                    value: vloge[z]!.smeVoditi,
                    onChanged: vloge[z]!.vloga.isEmpty
                        ? null
                        : (v) => nastavi(() {
                            final s = vloge[z]!;
                            vloge[z] = (clan: s.clan, skupina: s.skupina, vloga: s.vloga, smeVoditi: v ?? false);
                          }),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Prekliči')),
            FilledButton(
              key: const ValueKey('clan-shrani'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Shrani'),
            ),
          ],
        ),
      ),
    );
    if (shrani != true || !mounted) return;
    setState(() => _shranjujem = true);
    final sporocila = ScaffoldMessenger.of(context);
    try {
      final api = Api(widget.prijava.zeton);
      await api.shraniClanVloge(c.id, [
        for (final v in vloge.values) {'skupina': v.skupina, 'vloga': v.vloga, 'smeVoditi': v.smeVoditi},
      ], dostop: dostop == c.dostop ? null : dostop);
      sporocila.showSnackBar(SnackBar(content: Text('Shranjeno: ${c.ime}. Osvežujem …')));
      await baza.osvezi(api);
    } catch (e) {
      sporocila.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
    } finally {
      if (mounted) setState(() => _shranjujem = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Člani in vloge'),
      bottom: _shranjujem
          ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator())
          : null,
    ),
    body: ListenableBuilder(
      listenable: baza,
      builder: (context, _) {
        final u = baza.urejanjeClanov;
        if (u == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Skripta še ne pošilja članov in vlog. Uvedi novo različico skripte (New version) in klikni Osveži.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final clani = [...u.clani]..sort((a, b) => a.ime.compareTo(b.ime));
        return ListView(
          children: [
            for (final c in clani)
              ListTile(
                key: ValueKey('clan-${c.id}'),
                leading: Icon(
                  c.dostop ? Icons.person : Icons.person_off_outlined,
                  color: c.dostop ? null : Theme.of(context).colorScheme.outline,
                ),
                title: Text(c.ime.isEmpty ? c.id : c.ime),
                subtitle: Text(
                  [
                    if (!c.dostop) 'brez dostopa',
                    for (final z in {
                      ...c.zasedbe,
                      for (final v in u.vloge)
                        if (v.clan == c.id) v.skupina,
                    })
                      '${_imeZasedbe(z)}: ${u.vloge.where((v) => v.clan == c.id && v.skupina == z).map((v) => '${v.vloga}${v.smeVoditi ? ' (vodi)' : ''}').firstOrNull ?? 'brez vloge'}',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _shranjujem ? null : () => _uredi(c),
              ),
          ],
        );
      },
    ),
  );
}
