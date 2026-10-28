import 'package:flutter/material.dart';

import 'api.dart';
import 'baza.dart';
import 'prijava.dart';
import 'zasloni/prijava_zaslon.dart';
import 'zasloni/seznam_zaslon.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prijava = Prijava();
  final baza = Baza();
  await baza.nalozi();
  // Risbe se pošiljajo na strežnik sproti, kadar je član prijavljen.
  prijava.addListener(() => baza.risbe.api = prijava.racun != null ? Api(prijava.zeton) : null);
  runApp(SpadniBesedila(prijava: prijava, baza: baza));
  // Prijava se preveri v ozadju; seznam pesmi iz lokalne kopije je takoj na voljo tudi brez interneta.
  prijava.zacni();
}

class SpadniBesedila extends StatelessWidget {
  const SpadniBesedila({super.key, required this.prijava, required this.baza});

  final Prijava prijava;
  final Baza baza;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Špadni besedila',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(colorSchemeSeed: Colors.amber, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: Colors.amber, brightness: Brightness.dark),
      home: ListenableBuilder(
        listenable: Listenable.merge([prijava, baza]),
        builder: (context, _) {
          if (prijava.racun == null && baza.pesmi.isEmpty) {
            return PrijavaZaslon(prijava: prijava, onPrijavljen: () => baza.osvezi(Api(prijava.zeton)));
          }
          return SeznamZaslon(prijava: prijava, baza: baza);
        },
      ),
    );
  }
}
