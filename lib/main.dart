import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';
import 'config.dart';
import 'baza.dart';
import 'posodobitev.dart';
import 'prijava.dart';
import 'spil/spil.dart';
import 'zasloni/pesem_zaslon.dart';
import 'zasloni/prijava_zaslon.dart';
import 'midi/midi.dart';
import 'nastavitve.dart';
import 'odigrane.dart';
import 'runda.dart';
import 'zasloni/seznam_zaslon.dart';
import 'zasloni/spil_zaslon.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prijava = Prijava();
  final baza = Baza();
  final posodobitev = Posodobitev();
  final spil = Spil();
  await baza.nalozi();
  await Nastavitve.aplikacija.nalozi();
  await Odigrane.aplikacija.nalozi();
  await Runda.aplikacija.nalozi();
  Nastavitve.aplikacija.addListener(_zaslonPrizgan);
  if (Config.prekoVodje) {
    // iPad na špilu nima MIDI: gumbi in preizkusi gredo vodji, ki jih pošlje na svoje naprave.
    Midi.aplikacija.posiljajPrekoVodje(
      (ukazi) => apiNaSpilu(null).posljiMidi([
        for (final u in ukazi) {'zapis': u.ukaz.zapis, 'ime': u.ukaz.ime, 'izhod': u.izhod},
      ]),
    );
  } else {
    // MIDI naprave, če je MIDI na tej napravi vklopljen (Nastavitve → MIDI).
    Midi.aplikacija.nalozi().ignore();
  }
  // Risbe se pošiljajo na strežnik sproti, kadar je član prijavljen.
  // Ob prijavi preverimo tudi, ali je na voljo nova različica aplikacije.
  var prijavljen = false;
  prijava.addListener(() {
    if (Config.prekoVodje) return;
    final api = prijava.prijavljen ? Api(prijava.zeton) : null;
    baza.risbe.api = api;
    baza.risbeClanov.api = api;
    if (api != null && !prijavljen) {
      posodobitev.preveri(api);
      // Vodja: kar so člani narisali na zadnjem špilu, gre zdaj na Drive.
      if (baza.smeVoditi) baza.risbeClanov.posljiNeposlane().ignore();
      // Spremembe pesmi in besedil, shranjene brez interneta.
      if (baza.neposlano.isNotEmpty) baza.posljiNeposlano(api).ignore();
      // Prva prijava na novi napravi: takoj prenesi pesmi.
      if (baza.pesmi.isEmpty) baza.osvezi(api);
    }
    prijavljen = api != null;
  });
  if (Config.prekoVodje) {
    // iPad na špilu: aplikacija in podatki pridejo od vodje, sledimo mu takoj.
    // Risbe člana, ki se je na tem iPadu že predstavil (izbira imena), pridejo od vodje.
    final api = apiNaSpilu(await clanNaSpilu());
    baza.risbe.api = api;
    baza.osvezi(api);
    spil.sledi(Uri.parse('ws://${Uri.base.host}:${Uri.base.port}/ws'));
  } else {
    // Stalna vloga naprave (vodja ali sledilec), nastavljena z gumbom Špil.
    zacniPrivzetoVlogo(spil, baza);
  }
  final navigator = GlobalKey<NavigatorState>();
  if (!Config.prekoVodje) SamodejnoSledenje(spil: spil, baza: baza, prijava: prijava, navigator: navigator);
  // Vodja: sledilec s pravico je izbral pesem za vse; odpre se tudi pri vodji (in se tako pošlje vsem).
  spil.zahtevanaPesem.addListener(() {
    final s = spil.zahtevanaPesem.value;
    final p = s == null ? null : baza.pesem(s.pesem);
    if (p == null) return;
    spil.zahtevanaPesem.value = null;
    navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => PesemZaslon(pesem: p, baza: baza, prijava: prijava, spil: spil, stanje: s),
      ),
    );
  });
  // Povezava s ?pesem=<ID> (spletna različica): ko je pesem v lokalni kopiji, se odpre.
  if (Config.pesemIzPovezave case final id? when !Config.prekoVodje) {
    void odpriIzPovezave() {
      final p = baza.pesem(id);
      final nav = navigator.currentState;
      if (p == null || nav == null) return;
      baza.removeListener(odpriIzPovezave);
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => PesemZaslon(pesem: p, baza: baza, prijava: prijava, spil: spil),
        ),
      );
    }

    baza.addListener(odpriIzPovezave);
    WidgetsBinding.instance.addPostFrameCallback((_) => odpriIzPovezave());
  }
  // Med igranjem se zaslon ne sme ugasniti: ob zagonu in ob vsaki vrnitvi v aplikacijo.
  _zaslonPrizgan();
  AppLifecycleListener(onResume: _zaslonPrizgan);
  runApp(SpadniBesedila(prijava: prijava, baza: baza, posodobitev: posodobitev, spil: spil, navigator: navigator));
  // Prijava se preveri v ozadju; seznam pesmi iz lokalne kopije je takoj na voljo tudi brez interneta.
  prijava.zacni();
}

void _zaslonPrizgan() => WakelockPlus.toggle(enable: Nastavitve.aplikacija.zaslonPrizgan).catchError((_) {});

/// Brskalnik (Safari) dovoli prižgan zaslon šele po dotiku, zato ga ob dotiku zahtevamo znova, če ga še nima.
Future<void> _zaslonPrizganObDotiku() async {
  try {
    if (Nastavitve.aplikacija.zaslonPrizgan && !await WakelockPlus.enabled) await WakelockPlus.enable();
  } catch (_) {}
}

class SpadniBesedila extends StatelessWidget {
  const SpadniBesedila({
    super.key,
    required this.prijava,
    required this.baza,
    required this.posodobitev,
    required this.spil,
    this.navigator,
  });

  final Prijava prijava;
  final Baza baza;
  final Posodobitev posodobitev;
  final Spil spil;
  final GlobalKey<NavigatorState>? navigator;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: kIsWeb ? (_) => _zaslonPrizganObDotiku() : null,
      child: ListenableBuilder(listenable: Nastavitve.aplikacija, builder: (context, _) => _aplikacija()),
    );
  }

  Widget _aplikacija() {
    return MaterialApp(
      navigatorKey: navigator,
      title: 'Špadni besedila',
      debugShowCheckedModeBanner: false,
      themeMode: Nastavitve.aplikacija.svetlaTema ? ThemeMode.light : ThemeMode.dark,
      theme: ThemeData(colorSchemeSeed: Colors.amber, brightness: Brightness.light, fontFamily: 'Roboto'),
      darkTheme: ThemeData(colorSchemeSeed: Colors.amber, brightness: Brightness.dark, fontFamily: 'Roboto'),
      home: ListenableBuilder(
        listenable: Listenable.merge([prijava, baza, posodobitev]),
        builder: (context, _) {
          if (Config.prekoVodje) {
            return ZahtevajClana(
              baza: baza,
              child: SledilecZaslon(spil: spil, baza: baza, prijava: prijava, koren: true),
            );
          }
          if (!prijava.prijavljen && baza.pesmi.isEmpty) {
            return PrijavaZaslon(prijava: prijava);
          }
          return SeznamZaslon(prijava: prijava, baza: baza, posodobitev: posodobitev, spil: spil);
        },
      ),
    );
  }
}
