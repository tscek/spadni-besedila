import 'package:flutter/material.dart';

import '../baza.dart';
import '../nastavitve.dart';
import 'midi_zaslon.dart';

/// Osebne nastavitve na tej napravi.
class NastavitveZaslon extends StatelessWidget {
  const NastavitveZaslon({super.key, required this.baza});

  final Baza baza;

  @override
  Widget build(BuildContext context) {
    final n = Nastavitve.aplikacija;
    return Scaffold(
      appBar: AppBar(title: const Text('Nastavitve')),
      body: ListenableBuilder(
        listenable: n,
        builder: (context, _) => ListView(
          children: [
            const ListTile(title: Text('Velja samo za to napravo.')),
            ListTile(
              title: const Text('Velikost pisave besedila'),
              subtitle: Slider(
                value: n.pisava,
                min: 12,
                max: 64,
                divisions: 26,
                label: n.pisava.round().toString(),
                onChanged: n.nastaviPisavo,
              ),
            ),
            SwitchListTile(
              title: const Text('Akordi nad besedilom'),
              subtitle: const Text(
                'Izklopi, če akordov ne potrebuješ (npr. pevci). Risbe na besedilu se lahko zamaknejo.',
              ),
              value: n.akordi,
              onChanged: n.nastaviAkorde,
            ),
            SwitchListTile(
              title: const Text('Najprej PDF'),
              subtitle: const Text('Pri pesmi z besedilom in PDF-jem se najprej pokaže PDF'),
              value: n.pdfNajprej,
              onChanged: n.nastaviPdfNajprej,
            ),
            SwitchListTile(title: const Text('Svetla tema'), value: n.svetlaTema, onChanged: n.nastaviSvetloTemo),
            const Divider(),
            SwitchListTile(
              title: const Text('Sledi pesmim vodje'),
              subtitle: const Text('Ko slediš, se pesem, ki jo izbere vodja, odpre sama'),
              value: n.samodejnoSledenje,
              onChanged: n.nastaviSamodejnoSledenje,
            ),
            SwitchListTile(
              title: const Text('Zaslon ostane prižgan'),
              subtitle: const Text('Med uporabo aplikacije se zaslon ne ugasne'),
              value: n.zaslonPrizgan,
              onChanged: n.nastaviZaslonPrizgan,
            ),
            const ListTile(title: Text('Vloga na špilu'), subtitle: Text('Vodja, sledilec ali sama: gumb Špil zgoraj')),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.piano),
              title: const Text('Nastavitve MIDI'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MidiNastavitveZaslon(baza: baza))),
            ),
          ],
        ),
      ),
    );
  }
}
