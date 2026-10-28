import 'package:flutter/material.dart';

import 'api.dart';
import 'baza.dart';
import 'posodobitev.dart';
import 'prijava.dart';
import 'zasloni/prijava_zaslon.dart';
import 'zasloni/seznam_zaslon.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prijava = Prijava();
  final baza = Baza();
  final posodobitev = Posodobitev();
  await baza.nalozi();
  // Risbe se pošiljajo na strežnik sproti, kadar je član prijavljen.
  // Ob prijavi preverimo tudi, ali je na voljo nova različica aplikacije.
  var prijavljen = false;
  prijava.addListener(() {
    final api = prijava.racun != null ? Api(prijava.zeton) : null;
    baza.risbe.api = api;
    if (api != null && !prijavljen) posodobitev.preveri(api);
    prijavljen = api != null;
  });
  runApp(SpadniBesedila(prijava: prijava, baza: baza, posodobitev: posodobitev));
  // Prijava se preveri v ozadju; seznam pesmi iz lokalne kopije je takoj na voljo tudi brez interneta.
  prijava.zacni();
}

class SpadniBesedila extends StatelessWidget {
  const SpadniBesedila({super.key, required this.prijava, required this.baza, required this.posodobitev});

  final Prijava prijava;
  final Baza baza;
  final Posodobitev posodobitev;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Špadni besedila',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(colorSchemeSeed: Colors.amber, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: Colors.amber, brightness: Brightness.dark),
      home: ListenableBuilder(
        listenable: Listenable.merge([prijava, baza, posodobitev]),
        builder: (context, _) {
          if (prijava.racun == null && baza.pesmi.isEmpty) {
            return PrijavaZaslon(prijava: prijava, onPrijavljen: () => baza.osvezi(Api(prijava.zeton)));
          }
          return SeznamZaslon(prijava: prijava, baza: baza, posodobitev: posodobitev);
        },
      ),
    );
  }
}
