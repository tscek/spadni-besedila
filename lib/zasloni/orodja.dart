import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../baza.dart';
import '../midi/midi.dart';
import '../nastavitve.dart';
import '../runda.dart';
import 'midi_zaslon.dart';

/// Majhna ikona Bluetooth: modra, ko je povezana vsaj ena naprava Bluetooth MIDI. Dotik odpre nastavitve MIDI.
class BluetoothIkona extends StatelessWidget {
  const BluetoothIkona({super.key, required this.baza});

  final Baza baza;

  @override
  Widget build(BuildContext context) {
    final midi = Midi.aplikacija;
    // Brskalnik (iPad) nima Bluetooth MIDI.
    if (kIsWeb) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: midi,
      builder: (context, _) {
        final povezane = midi.vklopljen
            ? midi.naprave.where((n) => n.povezana && n.vrsta == 'Bluetooth').map((n) => n.ime).toList()
            : const <String>[];
        final opis = !midi.vklopljen
            ? 'MIDI je izklopljen'
            : povezane.isEmpty
            ? 'Ni povezane naprave Bluetooth'
            : 'Povezano: ${povezane.join(', ')}';
        return IconButton(
          tooltip: opis,
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MidiNastavitveZaslon(baza: baza))),
          icon: Icon(
            midi.vklopljen
                ? (povezane.isEmpty ? Icons.bluetooth : Icons.bluetooth_connected)
                : Icons.bluetooth_disabled,
            color: povezane.isEmpty ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.blue,
          ),
        );
      },
    );
  }
}

/// Pikici MIDI IN in OUT: zasvetita, ko ukaz pride ali gre ven. Dotik odpre MIDI monitor.
class MidiLucki extends StatelessWidget {
  const MidiLucki({super.key});

  @override
  Widget build(BuildContext context) {
    final midi = Midi.aplikacija;
    return ListenableBuilder(
      listenable: midi,
      builder: (context, _) {
        if (!midi.vklopljen) return const SizedBox.shrink();
        return InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MidiMonitorZaslon())),
          child: Tooltip(
            message: 'MIDI monitor (levo IN, desno OUT)',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (midi.prekoVodje == null) ...[
                    _Lucka(aktivnost: midi.aktivnostVhoda, barva: Colors.green),
                    const SizedBox(width: 5),
                  ],
                  _Lucka(aktivnost: midi.aktivnostIzhoda, barva: Colors.orange),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Lucka extends StatefulWidget {
  const _Lucka({required this.aktivnost, required this.barva});

  final ValueListenable<int> aktivnost;
  final Color barva;

  @override
  State<_Lucka> createState() => _LuckaState();
}

class _LuckaState extends State<_Lucka> {
  bool _sveti = false;
  Timer? _ugasni;

  @override
  void initState() {
    super.initState();
    widget.aktivnost.addListener(_prizgi);
  }

  @override
  void dispose() {
    widget.aktivnost.removeListener(_prizgi);
    _ugasni?.cancel();
    super.dispose();
  }

  void _prizgi() {
    setState(() => _sveti = true);
    _ugasni?.cancel();
    _ugasni = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _sveti = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _sveti ? widget.barva : Colors.transparent,
        border: Border.all(color: _sveti ? widget.barva : tema.outline, width: 1.5),
      ),
    );
  }
}

/// Zgodovina prejetih in poslanih MIDI ukazov.
class MidiMonitorZaslon extends StatelessWidget {
  const MidiMonitorZaslon({super.key});

  @override
  Widget build(BuildContext context) {
    final midi = Midi.aplikacija;
    String cas(DateTime t) {
      String dv(int x, [int n = 2]) => x.toString().padLeft(n, '0');
      return '${dv(t.hour)}:${dv(t.minute)}:${dv(t.second)}.${dv(t.millisecond, 3)}';
    }

    return ListenableBuilder(
      listenable: midi,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('MIDI monitor'),
          actions: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: const MidiLucki()),
            IconButton(tooltip: 'Počisti', icon: const Icon(Icons.delete_sweep), onPressed: midi.pocistiMonitor),
          ],
        ),
        body: midi.monitor.isEmpty
            ? const Center(child: Text('Še ni bilo MIDI ukazov.'))
            : ListView.builder(
                itemCount: midi.monitor.length,
                itemBuilder: (context, i) {
                  final z = midi.monitor[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      z.vhod ? Icons.call_received : Icons.call_made,
                      color: z.vhod ? Colors.green : Colors.orange,
                    ),
                    title: Text(z.opis, style: const TextStyle(fontFamily: 'monospace')),
                    subtitle: Text(
                      [
                        cas(z.cas),
                        if (z.vhod) 'IN',
                        if (!z.vhod) z.naprave.isEmpty ? 'OUT · ni naprave' : 'OUT · ${z.naprave.join(', ')}',
                      ].join(' · '),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Gumb za runde in pavze: obarva se v barvi teka in kaže čas. Dotik odpre okno z gumboma.
class RundaGumb extends StatelessWidget {
  const RundaGumb({super.key, required this.baza});

  final Baza baza;

  @override
  Widget build(BuildContext context) {
    final runda = Runda.aplikacija;
    return ListenableBuilder(
      listenable: Listenable.merge([runda, Nastavitve.aplikacija]),
      builder: (context, _) {
        final n = Nastavitve.aplikacija;
        final pavza = runda.pavza;
        if (pavza == null) {
          return IconButton(
            tooltip: 'Runda / pavza',
            icon: const Icon(Icons.timer_outlined),
            onPressed: () => oknoRunde(context, baza),
          );
        }
        final barva = Color(pavza ? n.pavza.barva : n.igranje.barva);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: barva,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => oknoRunde(context, baza),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(pavza ? Icons.pause : Icons.music_note, size: 18, color: Colors.white),
                    const SizedBox(width: 4),
                    const CasRunde(barva: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Čas trenutne runde ali pavze (osveži se vsako sekundo), v barvi teka.
class CasRunde extends StatefulWidget {
  const CasRunde({super.key, this.barva});

  /// Privzeto barva gumba, ki teče.
  final Color? barva;

  @override
  State<CasRunde> createState() => _CasRundeState();
}

class _CasRundeState extends State<CasRunde> {
  late final Timer _casovnik;

  @override
  void initState() {
    super.initState();
    _casovnik = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _casovnik.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = Runda.aplikacija;
    final n = Nastavitve.aplikacija;
    if (r.pavza == null) return const SizedBox.shrink();
    return Text(
      casBesedilo(r.trenutno()),
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: widget.barva ?? Color(r.pavza! ? n.pavza.barva : n.igranje.barva),
      ),
    );
  }
}

/// Okno z gumboma PAVZA in ŠPILEJ!!, pretekli odseki in ponastavitev.
Future<void> oknoRunde(BuildContext context, Baza baza) => showDialog<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: Runda.aplikacija,
    builder: (context, _) {
      final r = Runda.aplikacija;
      final n = Nastavitve.aplikacija;
      void zacni(bool pavzo) {
        final g = pavzo ? n.pavza : n.igranje;
        r.zacni(pavzo);
        if (g.midi.isNotEmpty) Midi.aplikacija.poslji(baza.midi.razsiri(g.midi), knjiznica: baza.midi);
        Navigator.pop(context);
      }

      Widget gumb(bool pavzo) {
        final g = pavzo ? n.pavza : n.igranje;
        return Expanded(
          child: SizedBox(
            height: 72,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Color(g.barva),
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              onPressed: () => zacni(pavzo),
              child: Text(g.napis),
            ),
          ),
        );
      }

      return AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Runda in pavza')),
            if (r.pavza != null) const CasRunde(),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [gumb(true), const SizedBox(width: 12), gumb(false)]),
              const SizedBox(height: 12),
              if (r.zgodovina.isEmpty)
                const Text('Pretekle runde in pavze se pokažejo tukaj.')
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final o in r.zgodovina)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            o.pavza ? Icons.pause : Icons.music_note,
                            color: Color(o.pavza ? n.pavza.barva : n.igranje.barva),
                          ),
                          title: Text('${o.pavza ? n.pavza.napis : n.igranje.napis}  ${casBesedilo(o.trajanje)}'),
                          subtitle: Text('od ${o.zacetek.hour}:${o.zacetek.minute.toString().padLeft(2, '0')}'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: r.zgodovina.isEmpty && r.pavza == null ? null : r.ponastavi,
            child: const Text('Ponastavi vse'),
          ),
          if (r.pavza != null) TextButton(onPressed: r.ustavi, child: const Text('Ustavi')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zapri')),
        ],
      );
    },
  ),
);

/// Trenutna ura (ure:minute).
class Ura extends StatefulWidget {
  const Ura({super.key});

  @override
  State<Ura> createState() => _UraState();
}

class _UraState extends State<Ura> {
  late final Timer _casovnik;

  @override
  void initState() {
    super.initState();
    _casovnik = Timer.periodic(const Duration(seconds: 10), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _casovnik.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DateTime.now();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text('${t.hour}:${t.minute.toString().padLeft(2, '0')}', style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
