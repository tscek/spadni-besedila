import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../baza.dart';
import '../config.dart';
import '../models.dart';
import '../nastavitve.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'oznake.dart';
import 'spil_zaslon.dart';
import 'urejanje_pesmi.dart';

/// Ime člana na tej napravi (na iPadu prek vodje tisti, ki ga je izbral).
Future<String> kdoSem(Baza baza) async {
  if (baza.imeClana.isNotEmpty) return baza.imeClana;
  final id = await clanNaSpilu();
  return baza.clani.where((c) => c.id == id).firstOrNull?.ime ?? '';
}

/// Ali sme ta naprava menjati pesem vsem (vodja, brez špila ali član, ki sme voditi).
bool smeMenjati(Spil spil, Baza baza) => spil.vloga != VlogaSpila.sledilec || baza.smeVoditi;

/// Meni ob pridržanju pesmi na seznamu: čakalna vrsta (vsi), playlista, mapa in arhiv (urejevalci).
Future<void> meniPesmi(BuildContext context, Spil spil, Baza baza, Prijava prijava, Pesem p) async {
  final sme = smeMenjati(spil, baza);
  final ureja = baza.smeUrejatiPesem(p);
  final izbira = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(p.naslov, style: Theme.of(context).textTheme.titleMedium)),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Dodaj kot naslednjo'),
              subtitle: const Text('Na prvo mesto v čakalni vrsti'),
              onTap: () => Navigator.pop(context, 'prvo'),
            ),
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: const Text('Dodaj v čakalno vrsto'),
              subtitle: const Text('Na zadnje mesto v čakalni vrsti'),
              onTap: () => Navigator.pop(context, 'vrsta'),
            ),
            if (sme && spil.vloga == VlogaSpila.sledilec)
              ListTile(
                leading: const Icon(Icons.cast),
                title: const Text('Pokaži vsem zdaj'),
                onTap: () => Navigator.pop(context, 'vsem'),
              ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Kopiraj povezavo'),
              subtitle: const Text('Odpre pesem v spletni različici'),
              onTap: () => Navigator.pop(context, 'povezava'),
            ),
            if (p.zaVajo)
              ListTile(
                leading: const Klicaj(velikost: 22),
                title: Text(p.klicaji > 1 ? 'Odstrani klicaje (${p.klicaji})' : 'Odstrani klicaj'),
                onTap: () => Navigator.pop(context, 'klicaji'),
              ),
            if (ureja) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.library_add),
                title: const Text('Dodaj na playlisto'),
                onTap: () => Navigator.pop(context, 'playlista'),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text('Premakni v drugo mapo'),
                subtitle: Text(baza.mapa(p.mapa)?.ime ?? 'Brez mape'),
                onTap: () => Navigator.pop(context, 'mapa'),
              ),
              ListTile(
                leading: Icon(p.vArhivu ? Icons.unarchive_outlined : Icons.archive_outlined),
                title: Text(p.vArhivu ? 'Vrni iz arhiva' : 'Arhiviraj'),
                subtitle: Text(
                  p.vArhivu ? 'Pesem bo spet vidna v svoji mapi' : 'Pesem ni več vidna v mapah, ostane v arhivu',
                ),
                onTap: () => Navigator.pop(context, 'arhiv'),
              ),
              if (baza.mapa(p.mapa) case final m? when m.pavza != p.id)
                ListTile(
                  leading: const Icon(Icons.pause_circle_outline),
                  title: const Text('Nastavi kot pavzo mape'),
                  subtitle: Text('Izbira »Pavza« v iskalniku (${m.ime}) odpre to pesem'),
                  onTap: () => Navigator.pop(context, 'pavza'),
                ),
            ],
          ],
        ),
      ),
    ),
  );
  if (izbira == null || !context.mounted) return;
  switch (izbira) {
    case 'klicaji':
      final api = apiZaKlicaje(baza, prijava);
      for (final k in List.of(baza.klicaji[p.id] ?? const <KlicajPesmi>[])) {
        await baza.izbrisiKlicaj(api, k.id);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Klicaji odstranjeni: ${p.naslov}')));
      }
    case 'pavza':
      final m = baza.mapa(p.mapa)!;
      final messenger = ScaffoldMessenger.of(context);
      final api = apiZaUrejanje(context, prijava, baza: baza);
      if (api == null) return;
      try {
        await baza.shraniMidi(api, 'Mape', {'ID': m.id, 'Ime': m.ime, 'Vrstni red': m.vrstniRed, 'Pavza': p.id});
        messenger.showSnackBar(SnackBar(content: Text('Pavza v mapi ${m.ime}: ${p.naslov}')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
      }
    case 'vsem':
      spil.zamenjajVsem(StanjeSpila(pesem: p.id));
    case 'povezava':
      await Clipboard.setData(ClipboardData(text: Config.povezavaDoPesmi(p.id)));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Povezava kopirana: ${p.naslov}')));
      }
    case 'prvo' || 'vrsta':
      await vCakalnoVrsto(context, spil, baza, p, naPrvo: izbira == 'prvo');
    case 'playlista':
      await _naPlaylisto(context, baza, prijava, p);
    case 'mapa':
      final mapa = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Premakni v mapo'),
          children: [
            for (final m in baza.mape)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, m.id),
                child: Text(m.ime, style: TextStyle(fontWeight: m.id == p.mapa ? FontWeight.bold : null)),
              ),
          ],
        ),
      );
      if (mapa == null || mapa == p.mapa || !context.mounted) return;
      await _shrani(context, baza, prijava, p, {'Mapa': mapa}, 'Premaknjeno v ${baza.mapa(mapa)?.ime ?? mapa}');
    case 'arhiv':
      final status = p.vArhivu ? StatusPesmi.narejen : StatusPesmi.arhiv;
      await _shrani(context, baza, prijava, p, {
        'Status': status.ime,
      }, p.vArhivu ? 'Vrnjeno iz arhiva: ${p.naslov}' : 'Arhivirano: ${p.naslov}');
  }
}

/// Povezava za klicaje in dnevnik: na iPadu prek vodje, sicer s prijavo; brez nje se počaka (null).
Api? apiZaKlicaje(Baza baza, Prijava prijava) => Config.prekoVodje
    ? baza.risbe.api
    : prijava.prijavljen
    ? Api(prijava.zeton)
    : null;

/// Shrani nekaj podatkov pesmi (naslov gre zraven, ker ga skripta zahteva).
Future<void> _shrani(BuildContext context, Baza baza, Prijava prijava, Pesem p, Zapis podatki, String sporocilo) async {
  final messenger = ScaffoldMessenger.of(context);
  final api = apiZaUrejanje(context, prijava, baza: baza);
  if (api == null) return;
  try {
    await baza.shraniPesem(api, {'ID': p.id, 'Naslov': p.naslov, ...podatki});
    messenger.showSnackBar(SnackBar(content: Text(sporocilo)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
  }
}

/// Doda pesem na konec izbrane playliste (playliste iz mape pesmi).
Future<void> _naPlaylisto(BuildContext context, Baza baza, Prijava prijava, Pesem p) async {
  final messenger = ScaffoldMessenger.of(context);
  final playliste = [
    for (final s in baza.setliste)
      if (baza.smeUrejatiSetlisto(s) && (s.mapa.isEmpty || s.mapa == p.mapa)) s,
  ];
  if (playliste.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('V tej mapi ni playliste, ki bi jo lahko urejal.')));
    return;
  }
  final s = await showDialog<Setlista>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Dodaj na playlisto'),
      children: [
        for (final s in playliste)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, s),
            child: Text([s.ime, if (s.datum != null) datumBesedilo(s.datum!)].join(' · ')),
          ),
      ],
    ),
  );
  if (s == null || !context.mounted) return;
  final api = apiZaUrejanje(context, prijava);
  if (api == null) return;
  final vrsta = baza.pesmiSetlist[s.id] ?? const <SetlistaPesem>[];
  try {
    await baza.shraniSetlisto(
      api,
      {'ID': s.id, 'Ime': s.ime},
      [for (final v in vrsta) (pesem: v.pesem, opomba: v.opomba), (pesem: p.id, opomba: '')],
    );
    messenger.showSnackBar(SnackBar(content: Text('${p.naslov} je na playlisti ${s.ime}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
  }
}

/// Iskalnik v pesmi: pesem gre v čakalno vrsto (dotik na konec, pridržanje na prvo mesto).
Future<void> vCakalnoVrsto(BuildContext context, Spil spil, Baza baza, Pesem p, {bool naPrvo = false}) async {
  final messenger = ScaffoldMessenger.of(context);
  spil.dodajNaslednjo(
    Naslednja(pesem: p.id, kdo: await kdoSem(baza)),
    naPrvo: naPrvo,
  );
  messenger.showSnackBar(SnackBar(content: Text('${naPrvo ? 'Naslednja' : 'V čakalni vrsti'}: ${p.naslov}')));
}

String _opis(Naslednja n) => [if (n.naKonec) 'na konec setliste', if (n.kdo.isNotEmpty) n.kdo].join(' · ');

/// Napis pesmi v čakalni vrsti s podatki, izbranimi v nastavitvah.
String napisVrste(Pesem p) => [
  for (final polje in Nastavitve.aplikacija.poljaVrste)
    if (polje.vrednost(p) case final v when v.isNotEmpty) v,
].join(' · ');

/// Harmonikaš mora za [naslednja] zamenjati harmoniko (obe pesmi imata harmoniko vpisano).
bool menjaHarmoniko(Pesem? trenutna, Pesem? naslednja) =>
    trenutna != null &&
    naslednja != null &&
    trenutna.harmonika.isNotEmpty &&
    naslednja.harmonika.isNotEmpty &&
    trenutna.harmonika != naslednja.harmonika;

/// Vrstica nad spodnjim robom: kaj je naslednje na seznamčku; dotik odpre celoten seznamček.
/// Če je v napisu harmonika in jo je treba za naslednjo pesem zamenjati, napis utripa v barvi harmonike.
Widget? vrsticaNaslednjih(BuildContext context, Spil? spil, Baza baza, void Function(Pesem) odpri, {Pesem? trenutna}) {
  if (spil == null || spil.naslednje.isEmpty) return null;
  final prva = spil.prvaNaslednja() ?? spil.naslednje.first;
  final p = baza.pesem(prva.pesem);
  final tema = Theme.of(context);
  final ostalih = spil.naslednje.length - 1;
  final zdaj = trenutna ?? baza.pesem(spil.prikazano?.pesem ?? spil.stanje?.pesem ?? '');
  final utripa = Nastavitve.aplikacija.poljaVrste.contains(PoljePesmi.harmonika) && menjaHarmoniko(zdaj, p);
  final napis = Text(
    '${p == null ? prva.pesem : napisVrste(p)}${ostalih > 0 ? '  (+$ostalih)' : ''}',
    overflow: TextOverflow.ellipsis,
  );
  return Material(
    color: tema.colorScheme.secondaryContainer,
    child: InkWell(
      onTap: () => pokaziNaslednje(context, spil, baza, odpri),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: 12),
            if (p != null) OznakePesmi(pesem: p),
            Icon(utripa ? Icons.swap_horiz : Icons.queue_music, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: utripa
                  ? Utripanje(barva: barvaHarmonike(baza, p!.harmonika) ?? Colors.orange, child: napis)
                  : napis,
            ),
            const Icon(Icons.expand_less),
            const SizedBox(width: 8),
          ],
        ),
      ),
    ),
  );
}

/// Besedilo, ki utripa v [barva] (npr. menjava harmonike).
class Utripanje extends StatefulWidget {
  const Utripanje({super.key, required this.barva, required this.child});

  final Color barva;
  final Widget child;

  @override
  State<Utripanje> createState() => _UtripanjeState();
}

class _UtripanjeState extends State<Utripanje> with SingleTickerProviderStateMixin {
  late final _animacija = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _animacija.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final osnovna = DefaultTextStyle.of(context).style.color ?? Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _animacija,
      builder: (context, child) => DefaultTextStyle.merge(
        style: TextStyle(color: Color.lerp(osnovna, widget.barva, _animacija.value), fontWeight: FontWeight.bold),
        child: child!,
      ),
      child: widget.child,
    );
  }
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
                const ListTile(title: Text('Čakalna vrsta')),
                if (spil.naslednje.isEmpty) const ListTile(title: Text('Čakalna vrsta je prazna.')),
                for (var i = 0; i < spil.naslednje.length; i++)
                  if (baza.pesem(spil.naslednje[i].pesem) case final p?)
                    ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: NaslovZOznakami(pesem: p),
                      subtitle: Text(
                        [
                          napisVrste(p).replaceFirst(p.naslov, '').replaceFirst(RegExp(r'^ · '), ''),
                          _opis(spil.naslednje[i]),
                        ].where((x) => x.isNotEmpty).join(' · '),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        odpri(p);
                      },
                      trailing: Config.samoKlicaji
                          ? null
                          : IconButton(
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
