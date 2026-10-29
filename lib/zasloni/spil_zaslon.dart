import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../baza.dart';
import '../config.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'pesem_zaslon.dart';

/// Gumb vodje v vrstici igranja: zažene vodenje in pokaže naslov za sledilce.
class VodjaGumb extends StatelessWidget {
  const VodjaGumb({super.key, required this.spil, required this.baza, required this.obZacetku});

  final Spil spil;
  final Baza baza;

  /// Pokliče se, ko vodenje steče, da vodja takoj pošlje trenutno pesem.
  final VoidCallback obZacetku;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: spil,
      builder: (context, _) {
        final vodim = spil.vloga == VlogaSpila.vodja;
        return IconButton(
          iconSize: 28,
          tooltip: vodim ? 'Vodim špil (${spil.sledilcev} sledi)' : 'Vodi špil',
          icon: Badge(
            isLabelVisible: vodim,
            label: Text('${spil.sledilcev}'),
            child: Icon(vodim ? Icons.cast_connected : Icons.cast),
          ),
          onPressed: () async {
            if (!vodim) {
              await spil.zacniVoditi(baza);
              obZacetku();
            }
            if (context.mounted) await pokaziNaslovVodje(context, spil);
          },
        );
      },
    );
  }
}

/// Naslov in QR koda, s katero se sledilci povežejo z vodjo.
Future<void> pokaziNaslovVodje(BuildContext context, Spil spil) => showDialog<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: spil,
    builder: (context, _) {
      final naslov = spil.naslov;
      return AlertDialog(
        title: const Text('Vodim špil'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spil.napaka != null)
                Text(spil.napaka!, style: TextStyle(color: Theme.of(context).colorScheme.error))
              else if (naslov != null) ...[
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(data: naslov, size: 200),
                ),
                const SizedBox(height: 12),
                SelectableText(naslov, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                const Text(
                  'iPad: s kamero skeniraj kodo ali vpiši naslov v Safari.\n'
                  'Android: Meni → Sledi vodji in vpiši ta naslov.\n'
                  'Vsi morajo biti na istem WiFi-ju.',
                ),
                const SizedBox(height: 8),
                Text('Sledilcev: ${spil.sledilcev}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              spil.ustavi();
              Navigator.pop(context);
            },
            child: const Text('Končaj vodenje'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zapri')),
        ],
      );
    },
  ),
);

/// Vpraša za naslov vodje (zapomni si zadnjega) in začne slediti.
Future<void> zacniSlediti(
  BuildContext context, {
  required Spil spil,
  required Baza baza,
  required Prijava prijava,
}) async {
  const kljuc = 'zadnji_vodja';
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return;
  final c = TextEditingController(text: prefs.getString(kljuc) ?? '192.168.');
  final vnos = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sledi vodji'),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'Naslov vodje', helperText: 'Vodja ga vidi ob gumbu za vodenje'),
        onSubmitted: (s) => Navigator.pop(context, s),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
        TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Poveži')),
      ],
    ),
  );
  c.dispose();
  final ws = naslovWebSocket(vnos ?? '');
  if (ws == null || !context.mounted) return;
  await prefs.setString(kljuc, vnos!.trim());
  spil.sledi(ws);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SledilecZaslon(spil: spil, baza: baza, prijava: prijava),
    ),
  );
}

/// Iz vnosa, kot je "192.168.1.5", "192.168.1.5:8765" ali "http://192.168.1.5:8765", naredi naslov WebSocketa.
Uri? naslovWebSocket(String vnos) {
  var s = vnos.trim();
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp(r'^(https?|wss?)://'), '');
  s = s.split('/').first;
  if (!s.contains(':')) s = '$s:${Config.vrataVodje}';
  return Uri.tryParse('ws://$s/ws');
}

/// Sledilec: kaže pesem, ki jo je izbral vodja.
class SledilecZaslon extends StatelessWidget {
  const SledilecZaslon({super.key, required this.spil, required this.baza, required this.prijava, this.koren = false});

  final Spil spil;
  final Baza baza;
  final Prijava prijava;

  /// Prvi zaslon (iPad, odprt prek vodje): namesto »Nehaj slediti« ponudi seznam pesmi.
  final bool koren;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([spil, baza]),
      builder: (context, _) {
        final s = spil.stanje;
        final p = s == null ? null : baza.pesem(s.pesem);
        final vrstica = _vrstica(context, s);
        if (p == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Špil')),
            bottomNavigationBar: vrstica,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s == null
                      ? (spil.povezan ? 'Čakam, da vodja izbere pesem …' : 'Povezujem se z vodjo …')
                      : 'Te pesmi ni v tvoji kopiji. Osveži pesmi, ko imaš internet.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return PesemZaslon(key: ValueKey(s), pesem: p, baza: baza, prijava: prijava, spodaj: vrstica);
      },
    );
  }

  Widget _vrstica(BuildContext context, StanjeSpila? s) {
    final tema = Theme.of(context);
    final vrsta = s?.setlista == null ? null : baza.pesmiSetlist[s!.setlista];
    final i = s?.indeks;
    final naslednja = (vrsta != null && i != null && i + 1 < vrsta.length) ? baza.pesem(vrsta[i + 1].pesem) : null;
    final opomba = (vrsta != null && i != null && i < vrsta.length) ? vrsta[i].opomba : '';
    return Material(
      color: tema.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(
                spil.povezan ? Icons.cast_connected : Icons.cast,
                color: spil.povezan ? tema.colorScheme.primary : tema.colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        spil.povezan ? 'Sledim vodji' : 'Ni povezave z vodjo',
                        if (vrsta != null && i != null) '${i + 1} / ${vrsta.length}',
                        if (opomba.isNotEmpty) opomba,
                      ].join(' · '),
                      style: tema.textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (naslednja != null)
                      Text(
                        'Naslednja: ${naslednja.koda} ${naslednja.naslov}',
                        style: tema.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (!koren)
                TextButton(
                  onPressed: () {
                    spil.ustavi();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Nehaj slediti'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
