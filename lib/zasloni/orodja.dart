import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../baza.dart';
import '../midi/midi.dart';
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

/// Lučki MIDI IN in OUT: zasvetita, ko ukaz pride ali gre ven.
class MidiLucki extends StatelessWidget {
  const MidiLucki({super.key});

  @override
  Widget build(BuildContext context) {
    final midi = Midi.aplikacija;
    return ListenableBuilder(
      listenable: midi,
      builder: (context, _) {
        if (!midi.vklopljen) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (midi.prekoVodje == null) ...[
                _Lucka(napis: 'IN', aktivnost: midi.aktivnostVhoda, barva: Colors.green),
                const SizedBox(width: 4),
              ],
              _Lucka(napis: 'OUT', aktivnost: midi.aktivnostIzhoda, barva: Colors.orange),
            ],
          ),
        );
      },
    );
  }
}

class _Lucka extends StatefulWidget {
  const _Lucka({required this.napis, required this.aktivnost, required this.barva});

  final String napis;
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _sveti ? widget.barva : Colors.transparent,
        border: Border.all(color: _sveti ? widget.barva : tema.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        widget.napis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: _sveti ? Colors.black : tema.onSurfaceVariant,
        ),
      ),
    );
  }
}

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
