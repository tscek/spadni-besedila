import 'package:flutter/material.dart';

import '../baza.dart';
import '../models.dart';
import '../spil/spil.dart';
import 'spil_zaslon.dart';

/// Ime člana na tej napravi (na iPadu prek vodje tisti, ki ga je izbral).
Future<String> kdoSem(Baza baza) async {
  if (baza.imeClana.isNotEmpty) return baza.imeClana;
  final id = await clanNaSpilu();
  return baza.clani.where((c) => c.id == id).firstOrNull?.ime ?? '';
}

/// Ali sme ta naprava menjati pesem vsem (vodja, brez špila ali član, ki sme voditi).
bool smeMenjati(Spil spil, Baza baza) => spil.vloga != VlogaSpila.sledilec || baza.smeVoditi;

/// Ponudi, kako dodati pesem med naslednje. Dodajajo lahko vsi, seznamček vidijo vsi na špilu.
Future<void> dodajMedNaslednje(BuildContext context, Spil spil, Baza baza, Pesem p) async {
  final messenger = ScaffoldMessenger.of(context);
  final sme = smeMenjati(spil, baza);
  final izbira = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text('${p.koda}  ${p.naslov}', style: Theme.of(context).textTheme.titleMedium)),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Dodaj kot naslednjo'),
            subtitle: const Text('Pride na vrsto pred naslednjo pesmijo (tudi v setlisti)'),
            onTap: () => Navigator.pop(context, 'naslednja'),
          ),
          ListTile(
            leading: const Icon(Icons.low_priority),
            title: const Text('Dodaj na konec'),
            subtitle: const Text('V setlisti pride na vrsto po zadnji pesmi setliste'),
            onTap: () => Navigator.pop(context, 'naKonec'),
          ),
          if (sme && spil.vloga == VlogaSpila.sledilec)
            ListTile(
              leading: const Icon(Icons.cast),
              title: const Text('Pokaži vsem zdaj'),
              onTap: () => Navigator.pop(context, 'vsem'),
            ),
        ],
      ),
    ),
  );
  if (izbira == null) return;
  if (izbira == 'vsem') {
    spil.zamenjajVsem(StanjeSpila(pesem: p.id));
    return;
  }
  spil.dodajNaslednjo(Naslednja(pesem: p.id, kdo: await kdoSem(baza), naKonec: izbira == 'naKonec'));
  messenger.showSnackBar(SnackBar(content: Text('Dodano med naslednje: ${p.naslov}')));
}

String _opis(Naslednja n) => [if (n.naKonec) 'na konec setliste', if (n.kdo.isNotEmpty) n.kdo].join(' · ');

/// Vrstica nad spodnjim robom: kaj je naslednje na seznamčku; dotik odpre celoten seznamček.
Widget? vrsticaNaslednjih(BuildContext context, Spil? spil, Baza baza, void Function(Pesem) odpri) {
  if (spil == null || spil.naslednje.isEmpty) return null;
  final prva = spil.prvaNaslednja() ?? spil.naslednje.first;
  final p = baza.pesem(prva.pesem);
  final tema = Theme.of(context);
  final ostalih = spil.naslednje.length - 1;
  return Material(
    color: tema.colorScheme.secondaryContainer,
    child: InkWell(
      onTap: () => pokaziNaslednje(context, spil, baza, odpri),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.queue_music, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Naslednja: ${p == null ? prva.pesem : '${p.koda} ${p.naslov}'}'
                '${ostalih > 0 ? '  (+$ostalih)' : ''}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.expand_less),
            const SizedBox(width: 8),
          ],
        ),
      ),
    ),
  );
}

/// Seznamček naslednjih pesmi: dotik odpre pesem, X jo odstrani (vsak).
Future<void> pokaziNaslednje(BuildContext context, Spil spil, Baza baza, void Function(Pesem) odpri) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListenableBuilder(
          listenable: spil,
          builder: (context, _) {
            return ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('Naslednje pesmi')),
                if (spil.naslednje.isEmpty) const ListTile(title: Text('Seznamček je prazen.')),
                for (var i = 0; i < spil.naslednje.length; i++)
                  if (baza.pesem(spil.naslednje[i].pesem) case final p?)
                    ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text('${p.koda}  ${p.naslov}'),
                      subtitle: Text(_opis(spil.naslednje[i])),
                      onTap: () {
                        Navigator.pop(context);
                        odpri(p);
                      },
                      trailing: IconButton(
                        tooltip: 'Odstrani',
                        icon: const Icon(Icons.close),
                        onPressed: () => spil.odstraniNaslednjo(i),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
