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
import 'package:spadni_besedila/midi/ukazi.dart';
import 'package:spadni_besedila/nastavitve.dart';
import 'package:spadni_besedila/odigrane.dart';
import 'package:spadni_besedila/prijava.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/zasloni/hitro_urejanje.dart';
import 'package:spadni_besedila/zasloni/pesem_zaslon.dart';

const _tabele = {
  'Pesmi': [
    {'ID': 'a', 'Koda': 1, 'Naslov': 'BELO OBLEKO', 'Mapa': 'nz', 'Tonaliteta': 'F', 'Aktivna': true},
    {'ID': 'b', 'Koda': 2, 'Naslov': 'AVSENIK', 'Mapa': 'nz', 'Tempo (BPM)': 100, 'Aktivna': true},
    {'ID': 'c', 'Koda': 3, 'Naslov': 'CVETKA', 'Mapa': 'nz', 'Aktivna': true},
  ],
  'Besedila': [
    {'ID': 't', 'Pesem': 'a', 'Besedilo': 'Belo obleko si že nosila'},
  ],
  'Mape': [
    {'ID': 'nz', 'Ime': 'Narodno-zabavne', 'Vrstni red': 1},
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
  });

  test('shraniPesmi pošlje samo spremembe v enem klicu', () async {
    final baza = await _baza();
    final poslano = <Map<String, dynamic>>[];
    final api = Api(
      () async => 'z',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        final telo = jsonDecode(r.body) as Map<String, dynamic>;
        poslano.add(telo);
        final vrstice = [
          for (final p in (telo['pesmi'] as List).cast<Map<String, dynamic>>())
            {...(_tabele['Pesmi']! as List).cast<Map<String, dynamic>>().firstWhere((r) => r['ID'] == p['ID']), ...p},
        ];
        return http.Response.bytes(utf8.encode(jsonEncode({'vrstice': vrstice})), 200);
      }),
    );
    await baza.shraniPesmi(api, [
      {'ID': 'a', 'Tempo (BPM)': '120'},
      {'ID': 'b', 'Izvajalec': 'Avseniki'},
    ]);
    expect(poslano.single['akcija'], 'pesmi');
    expect(poslano.single['pesmi'], [
      {'ID': 'a', 'Tempo (BPM)': '120'},
      {'ID': 'b', 'Izvajalec': 'Avseniki'},
    ]);
    expect(baza.pesem('a')!.vrstica['Tempo (BPM)'], '120');
    expect(baza.pesem('a')!.tonaliteta, 'F');
    expect(baza.pesem('b')!.izvajalec, 'Avseniki');
  });

  test('stara skripta: shraniPesmi shrani vsako pesem posebej s celo vrstico', () async {
    final baza = await _baza();
    final akcije = <String>[];
    final api = Api(
      () async => 'z',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        final telo = jsonDecode(r.body) as Map<String, dynamic>;
        akcije.add(telo['akcija'] as String);
        if (telo['akcija'] == 'pesmi') return http.Response(jsonEncode({'napaka': 'Neznana akcija'}), 200);
        return http.Response.bytes(utf8.encode(jsonEncode({'vrstica': telo['pesem']})), 200);
      }),
    );
    final napredek = <int>[];
    await baza.shraniPesmi(api, [
      {'ID': 'a', 'Zvrst': 'Valček'},
      {'ID': 'c', 'Zvrst': 'Polka'},
    ], napredek: (i, _) => napredek.add(i));
    expect(akcije, ['pesmi', 'pesem', 'pesem']);
    expect(napredek, [1, 2]);
    expect(baza.pesem('a')!.zvrst, 'Valček');
    expect(baza.pesem('a')!.naslov, 'BELO OBLEKO');
    expect(baza.pesem('c')!.zvrst, 'Polka');
  });

  testWidgets('tabela: urejanje celice, Enter gre v naslednjo vrstico, nastavi za izbrane, filter', (t) async {
    final baza = await _baza();
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: HitroUrejanjeZaslon(baza: baza, prijava: Prijava()),
      ),
    );
    await t.pumpAndSettle();
    // Razvrščeno po naslovu: AVSENIK, BELO OBLEKO, CVETKA.
    expect(find.text('AVSENIK'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('hitro-a-Tempo (BPM)')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('hitro-vnos')), '120');
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pumpAndSettle();
    // Urejanje se nadaljuje v isti stolpec pri naslednji pesmi (CVETKA).
    expect(find.byKey(const ValueKey('hitro-vnos')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('hitro-vnos')), 'abc');
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pumpAndSettle();
    expect(find.text('Tempo (BPM) mora biti število.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('hitro-vnos')), '');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.text('120'), findsOneWidget);
    expect(find.text('Shrani (1)'), findsOneWidget);

    // Dve pesmi izbrani, obema isti izvajalec.
    await t.tap(find.byKey(const ValueKey('hitro-izberi-a')));
    await t.tap(find.byKey(const ValueKey('hitro-izberi-c')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('hitro-nastavi')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('hitro-nastavi-vnos')), 'Ansambel');
    await t.tap(find.byKey(const ValueKey('hitro-nastavi-potrdi')));
    await t.pumpAndSettle();
    expect(find.text('Ansambel'), findsNWidgets(2));
    expect(find.text('Shrani (3)'), findsOneWidget);

    // Izbira s seznama (tonaliteta) in vrnitev na izvirno vrednost ni sprememba.
    await t.tap(find.byKey(const ValueKey('hitro-c-Tonaliteta')));
    await t.pumpAndSettle();
    await t.tap(find.text('G').last);
    await t.pumpAndSettle();
    expect(find.text('Shrani (4)'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('hitro-c-Tonaliteta')));
    await t.pumpAndSettle();
    await t.tap(find.text('–').last);
    await t.pumpAndSettle();
    expect(find.text('Shrani (3)'), findsOneWidget);

    // Filter brez besedila skrije BELO OBLEKO.
    await t.tap(find.byKey(const ValueKey('hitro-filter-brezBesedila')));
    await t.pumpAndSettle();
    expect(find.text('BELO OBLEKO'), findsNothing);
    expect(find.text('CVETKA'), findsOneWidget);
  });

  testWidgets('pesem iz hitrega urejanja: naprej po vrstnem redu tabele', (t) async {
    final baza = await _baza();
    final seznam = [baza.pesem('c')!, baza.pesem('a')!];
    await t.pumpWidget(
      MaterialApp(
        home: PesemZaslon(pesem: seznam.first, baza: baza, prijava: Prijava(), seznam: seznam, hitroUrejanje: true),
      ),
    );
    await t.pumpAndSettle();
    Midi.aplikacija.sprozi(DejanjeMidi.naslednja);
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('BELO OBLEKO')), findsOneWidget);
    Midi.aplikacija.sprozi(DejanjeMidi.prejsnja);
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('CVETKA')), findsOneWidget);
  });
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
