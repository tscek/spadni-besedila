import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../midi/ukazi.dart' show DejanjeMidi;
import '../tipkovnica.dart';

/// Ime tipke za prikaz (npr. »I«, »Arrow Up«).
String imeTipke(LogicalKeyboardKey k) => switch (k) {
  LogicalKeyboardKey.arrowUp => '↑',
  LogicalKeyboardKey.arrowDown => '↓',
  LogicalKeyboardKey.arrowLeft => '←',
  LogicalKeyboardKey.arrowRight => '→',
  LogicalKeyboardKey.numpadEnter => 'Enter (številčnica)',
  _ => k.keyLabel.isNotEmpty ? k.keyLabel : (k.debugName ?? 'Tipka ${k.keyId}'),
};

/// Bližnjice tipkovnice na tej napravi (tudi nožno stikalo BT, ki pošilja tipke).
class TipkovnicaZaslon extends StatelessWidget {
  const TipkovnicaZaslon({super.key, this.tipkovnica});

  final Tipkovnica? tipkovnica;

  @override
  Widget build(BuildContext context) {
    final t = tipkovnica ?? Tipkovnica.aplikacija;
    return PopScope(
      onPopInvokedWithResult: (_, _) => t.uci(null),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tipkovnica'),
          actions: [TextButton(onPressed: t.ponastavi, child: const Text('Privzeto'))],
        ),
        body: ListenableBuilder(
          listenable: t,
          builder: (context, _) => ListView(
            children: [
              const ListTile(
                subtitle: Text(
                  'Velja samo za to napravo. Za dejanje klikni Dodaj tipko in pritisni tipko na tipkovnici '
                  'ali nožnem stikalu BT. Gor in dol premikata besedilo ali izbiro v seznamu, levo in desno '
                  'odpreta prejšnjo ali naslednjo pesem, Enter potrdi izbiro.',
                ),
              ),
              for (final d in DejanjeMidi.values) _dejanje(context, t, d),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dejanje(BuildContext context, Tipkovnica t, DejanjeMidi d) {
    final ucim = t.ucim == d;
    final tipke = t.tipkeZa(d);
    return ListTile(
      key: ValueKey('tipka-${d.name}'),
      title: Text(d.oznaka),
      subtitle: ucim
          ? const Text('Pritisni tipko … (Esc prekliče)')
          : tipke.isEmpty
          ? const Text('ni nastavljeno')
          : Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final k in tipke)
                  InputChip(
                    label: Text(imeTipke(k)),
                    onDeleted: () => t.odstrani(k.keyId),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
      trailing: TextButton(onPressed: () => t.uci(ucim ? null : d), child: Text(ucim ? 'Prekliči' : 'Dodaj tipko')),
    );
  }
}
