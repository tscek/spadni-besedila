import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/midi/midi.dart';
import 'package:spadni_besedila/midi/prenos.dart';
import 'package:spadni_besedila/nastavitve.dart';
import 'package:spadni_besedila/odigrane.dart';
import 'package:spadni_besedila/runda.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/spil/spil.dart';
import 'package:spadni_besedila/zasloni/nadzorna_plosca.dart';
import 'package:spadni_besedila/zasloni/iskalnik_pesmi.dart';
import 'package:spadni_besedila/zasloni/naslednje.dart';
import 'package:spadni_besedila/zasloni/pesem_zaslon.dart';

const _tabele = {
  'Pesmi': [
    {
      'ID': 'a',
      'Naslov': 'NAJINA NAVEZA',
      'Zvrst': 'Narodno-zabavna',
      'Vrsta': 'Valček',
      'Harmonika': 'B-Es-As',
      'Tempo (BPM)': 168,
      'Trajanje': '3:20',
    },
    {
      'ID': 'b',
      'Naslov': 'PLANINSKA LJUBEZEN',
      'Zvrst': 'Narodno-zabavna',
      'Vrsta': 'Polka',
      'Harmonika': 'C-F-B',
      'Tempo (BPM)': 120,
    },
    {'ID': 'c', 'Naslov': 'ZABAVNA', 'Zvrst': 'Zabavna', 'Vrsta': '', 'Tempo (BPM)': 100},
  ],
  'Harmonike': [
    {'ID': 'h1', 'Ime': 'C-F-B', 'Barva': '#F44336', 'Vrstni red': 1},
    {'ID': 'h2', 'Ime': 'B-Es-As', 'Barva': '#FFC107', 'Vrstni red': 2},
  ],
  'Vrste': [
    {'ID': 'v1', 'Ime': 'Valček', 'Barva': '#4CAF50', 'Vrstni red': 1},
    {'ID': 'v2', 'Ime': 'Polka', 'Barva': '#F44336', 'Vrstni red': 2},
  ],
};

Future<Baza> _baza() async {
  final baza = Baza(shramba: _Pomnilnik());
  await baza.osvezi(
    Api(
      () async => 'z',
      url: 'https://example.com/exec',
      client: MockClient((r) async => http.Response.bytes(utf8.encode(jsonEncode({'tabele': _tabele})), 200)),
    ),
  );
  return baza;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Nastavitve.aplikacija = Nastavitve();
    Odigrane.aplikacija = Odigrane();
    Runda.aplikacija = Runda();
    Midi.aplikacija = Midi(_Prenos());
  });

  test('statistika večera: runde, pavze, odigrane po vrstah in harmonikah, prejšnji špil odpade', () async {
    final baza = await _baza();
    final zdaj = DateTime.now();
    final z = zdaj.subtract(const Duration(hours: 2));
    final runda = Runda()
      ..zgodovina = [
        // najnovejši prvi
        Odsek(pavza: true, zacetek: z.add(const Duration(minutes: 50)), trajanje: const Duration(minutes: 15)),
        Odsek(pavza: false, zacetek: z, trajanje: const Duration(minutes: 50)),
        // prejšnji špil pred 9 urami
        Odsek(pavza: false, zacetek: zdaj.subtract(const Duration(hours: 9)), trajanje: const Duration(minutes: 40)),
      ]
      ..pavza = false
      ..zacetek = z.add(const Duration(minutes: 65));
    final stat = StatistikaSpila.izracunaj(
      baza: baza,
      runda: runda,
      odigrane: {
        'a': z.add(const Duration(minutes: 5)),
        'b': z.add(const Duration(minutes: 9)),
        'c': z.add(const Duration(minutes: 70)),
      },
      zdaj: zdaj,
      trenutna: 'a',
      trenutnaOd: zdaj.subtract(const Duration(minutes: 1)),
    );
    expect(stat.odseki.length, 3); // runda, pavza, runda (prejšnji špil ne)
    expect(stat.runda, 2);
    // b, c in trenutna a (njena stara oznaka se ne šteje dvakrat)
    expect(stat.pesmi.map((p) => p.id), ['b', 'c', 'a']);
    expect(stat.vRundi, 2); // c in a v drugi rundi
    expect(stat.vrste, {'Polka': 1, 'Brez': 1, 'Valček': 1});
    expect(stat.harmonike['Brez'], 1);
    expect(stat.zvrsti, {'Narodno-zabavna': 2, 'Zabavna': 1});
    expect(stat.tempo, [120, 100, 168]);
    expect(stat.zacetek, z);
  });

  for (final (ime, velikost) in [('pokončno', const Size(820, 1180)), ('ležeče', const Size(1180, 820))]) {
    testWidgets('nadzorna plošča $ime: naslov, odigrane, menjava harmonike utripa', (t) async {
      final baza = await t.runAsync(_baza);
      t.view.physicalSize = velikost;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final spil = Spil(streznik: () => null, iskalec: () => const Stream.empty());
      final zdaj = DateTime.now();
      Runda.aplikacija
        ..pavza = false
        ..zacetek = zdaj.subtract(const Duration(minutes: 30));
      await t.runAsync(
        () => Odigrane.aplikacija.prevzemi({
          'odigrane': {
            'c': zdaj.subtract(const Duration(minutes: 20)).toIso8601String(),
            'b': zdaj.subtract(const Duration(minutes: 10)).toIso8601String(),
          },
        }),
      );
      spil.prikazujem(const StanjeSpila(pesem: 'a'));
      spil.dodajNaslednjo(const Naslednja(pesem: 'b'));

      await t.pumpWidget(
        MaterialApp(
          home: NadzornaPlosca(spil: spil, baza: baza!),
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('NAJINA NAVEZA'), findsOneWidget);
      expect(find.text('PLANINSKA LJUBEZEN'), findsOneWidget);
      expect(find.byKey(const ValueKey('plosca-menjava')), findsOneWidget);
      expect(find.byType(UtripajocaVrstica), findsOneWidget);
      // b, c in trenutna a
      expect(t.widget<Text>(find.byKey(const ValueKey('plosca-odigranih'))).data, '3');
      expect(NadzornaPlosca.odprtih.value, 1);

      await t.pumpWidget(const SizedBox());
      expect(NadzornaPlosca.odprtih.value, 0);
    });
  }

  testWidgets('plošča: izbira naslednje in igraj zdaj brez odpiranja besedila', (t) async {
    final baza = await t.runAsync(_baza);
    t.view.physicalSize = const Size(1180, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final spil = Spil(streznik: () => null, iskalec: () => const Stream.empty());
    spil.prikazujem(const StanjeSpila(pesem: 'a'));
    await t.pumpWidget(
      MaterialApp(
        home: NadzornaPlosca(spil: spil, baza: baza!),
      ),
    );
    await t.pump();
    expect(t.widget<Text>(find.byKey(const ValueKey('plosca-naslednja'))).data, 'Ni izbrane');

    // Iskalnik: izbrana pesem postane naslednja.
    await t.tap(find.byKey(const ValueKey('plosca-izberi')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(IskalnikPesmi), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(IskalnikPesmi), matching: find.text('ZABAVNA')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(spil.naslednje.map((n) => n.pesem), ['c']);
    expect(t.widget<Text>(find.byKey(const ValueKey('plosca-naslednja'))).data, 'ZABAVNA');

    // Igraj zdaj: pesem je trenutna, besedilo se ne odpre.
    await t.tap(find.byKey(const ValueKey('plosca-igraj')));
    await t.pump();
    expect(spil.prikazano?.pesem, 'c');
    expect(spil.naslednje, isEmpty);
    expect(find.byType(PesemZaslon), findsNothing);
    expect(find.byKey(const ValueKey('plosca-naslov')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('plosca-naslov'))).data, 'ZABAVNA');

    await t.pumpWidget(const SizedBox());
  });
}

class _Prenos implements MidiPrenos {
  @override
  Future<List<NapravaMidi>> naprave() async => const [];
  @override
  Future<void> zacniIskanje() async {}
  @override
  void ustaviIskanje() {}
  @override
  Future<void> povezi(String id) async {}
  @override
  void prekini(String id) {}
  @override
  void poslji(Uint8List bajti, String id) {}
  @override
  Stream<void> get spremembe => const Stream.empty();
  @override
  Stream<(String, Uint8List)> get prejeto => const Stream.empty();
}

class _Pomnilnik implements Shramba {
  final _podatki = <String, Object>{};

  @override
  Future<String?> beriBesedilo(String kljuc) async => _podatki[kljuc] as String?;

  @override
  Future<void> pisiBesedilo(String kljuc, String vsebina) async => _podatki[kljuc] = vsebina;

  @override
  Future<Uint8List?> beriBajte(String kljuc) async => _podatki[kljuc] as Uint8List?;

  @override
  Future<void> pisiBajte(String kljuc, Uint8List bajti) async => _podatki[kljuc] = bajti;

  @override
  Future<void> izbrisi(String kljuc) async => _podatki.remove(kljuc);

  @override
  Future<Set<String>> kljuci(String predpona) async => {..._podatki.keys.where((k) => k.startsWith(predpona))};
}
