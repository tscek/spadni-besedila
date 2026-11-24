import 'package:flutter/material.dart';

import '../baza.dart';
import '../spil/preizkus.dart';
import '../spil/spil.dart';

/// Preizkus pred špilom: ta naprava in (pri vodji) vse povezane naprave na enem mestu.
class PreizkusZaslon extends StatefulWidget {
  const PreizkusZaslon({super.key, required this.baza, required this.spil});

  final Baza baza;
  final Spil spil;

  @override
  State<PreizkusZaslon> createState() => _PreizkusZaslonState();
}

class _PreizkusZaslonState extends State<PreizkusZaslon> {
  PorociloNaprave? _moje;

  @override
  void initState() {
    super.initState();
    _preveri();
  }

  Future<void> _preveri() async {
    if (widget.spil.vloga == VlogaSpila.vodja) widget.spil.zahtevajPorocila();
    final r = await porociloTeNaprave(widget.baza);
    if (mounted) setState(() => _moje = r);
  }

  Widget _vrstica(String kdo, PorociloNaprave? r, {String? opomba}) {
    final tema = Theme.of(context);
    final tezave = r?.tezave ?? const <String>[];
    final ok = r != null && tezave.isEmpty;
    return ListTile(
      leading: Icon(
        r == null
            ? Icons.hourglass_empty
            : ok
            ? Icons.check_circle
            : Icons.warning_amber,
        color: r == null
            ? null
            : ok
            ? Colors.green
            : tema.colorScheme.error,
      ),
      title: Text(kdo),
      subtitle: Text(
        r == null
            ? (opomba ?? 'Čakam na poročilo …')
            : [if (tezave.isNotEmpty) tezave.join(' · '), r.povzetek].join('\n'),
      ),
      isThreeLine: r != null && tezave.isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final spil = widget.spil;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preizkus pred špilom'),
        actions: [IconButton(tooltip: 'Preveri znova', icon: const Icon(Icons.refresh), onPressed: _preveri)],
      ),
      body: ListenableBuilder(
        listenable: spil,
        builder: (context, _) {
          final vodja = spil.vloga == VlogaSpila.vodja;
          final brezPorocila = [
            for (final k in spil.povezani)
              if (!spil.porocila.containsKey(k)) k,
          ];
          return ListView(
            children: [
              _vrstica('Ta naprava${vodja ? ' (vodja)' : ''}', _moje),
              if (spil.vloga == VlogaSpila.sledilec)
                ListTile(
                  leading: Icon(
                    spil.povezan ? Icons.check_circle : Icons.warning_amber,
                    color: spil.povezan ? Colors.green : Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('Povezava z vodjo'),
                  subtitle: Text(spil.povezan ? 'Povezan' : 'Ni povezave'),
                ),
              if (vodja) ...[
                const Divider(),
                ListTile(
                  title: Text('Povezane naprave: ${spil.povezani.length}'),
                  subtitle: spil.povezani.isEmpty ? const Text('Nihče še ne sledi.') : null,
                ),
                for (final MapEntry(key: k, value: r) in spil.porocila.entries) _vrstica(k, r),
                for (final k in brezPorocila)
                  _vrstica(k, null, opomba: 'Ni poslala poročila (starejša različica ali čakam) …'),
                for (final k in spil.odpadli)
                  ListTile(
                    leading: Icon(Icons.link_off, color: Theme.of(context).colorScheme.error),
                    title: Text(k),
                    subtitle: const Text('Ni več povezan'),
                  ),
              ],
              if (spil.vloga == VlogaSpila.nic)
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Za preizkus vseh naprav zaženi Vodim (vodja) in počakaj, da se drugi povežejo.'),
                ),
            ],
          );
        },
      ),
    );
  }
}
