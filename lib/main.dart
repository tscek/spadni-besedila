import 'package:flutter/material.dart';

import 'api.dart';
import 'config.dart';
import 'baza.dart';
import 'posodobitev.dart';
import 'prijava.dart';
import 'spil/spil.dart';
import 'zasloni/prijava_zaslon.dart';
import 'zasloni/seznam_zaslon.dart';
import 'zasloni/spil_zaslon.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prijava = Prijava();
  final baza = Baza();
  final posodobitev = Posodobitev();
  final spil = Spil();
  await baza.nalozi();
  // Risbe se pošiljajo na strežnik sproti, kadar je član prijavljen.
  // Ob prijavi preverimo tudi, ali je na voljo nova različica aplikacije.
  var prijavljen = false;
  prijava.addListener(() {
    final api = prijava.prijavljen ? Api(prijava.zeton) : null;
    baza.risbe.api = api;
    if (api != null && !prijavljen) {
      posodobitev.preveri(api);
      // Prva prijava na novi napravi: takoj prenesi pesmi.
      if (baza.pesmi.isEmpty) baza.osvezi(api);
    }
    prijavljen = api != null;
  });
  if (Config.prekoVodje) {
    // iPad na špilu: aplikacija in podatki pridejo od vodje, sledimo mu takoj.
    baza.osvezi(Api(prijava.zeton));
    spil.sledi(Uri.parse('ws://${Uri.base.host}:${Uri.base.port}/ws'));
  }
  runApp(SpadniBesedila(prijava: prijava, baza: baza, posodobitev: posodobitev, spil: spil));
  // Prijava se preveri v ozadju; seznam pesmi iz lokalne kopije je takoj na voljo tudi brez interneta.
  prijava.zacni();
}

class SpadniBesedila extends StatelessWidget {
  const SpadniBesedila({
    super.key,
    required this.prijava,
    required this.baza,
    required this.posodobitev,
    required this.spil,
  });

  final Prijava prijava;
  final Baza baza;
  final Posodobitev posodobitev;
  final Spil spil;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Špadni besedila',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(colorSchemeSeed: Colors.amber, brightness: Brightness.light, fontFamily: 'Roboto'),
      darkTheme: ThemeData(colorSchemeSeed: Colors.amber, brightness: Brightness.dark, fontFamily: 'Roboto'),
      home: ListenableBuilder(
        listenable: Listenable.merge([prijava, baza, posodobitev]),
        builder: (context, _) {
          if (Config.prekoVodje) {
            return SledilecZaslon(spil: spil, baza: baza, prijava: prijava, koren: true);
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
