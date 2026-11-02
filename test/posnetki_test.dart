import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/zasloni/posnetki.dart';

class _Snemalnik implements Snemalnik {
  bool tece = false;

  @override
  Future<bool> dovoljenje() async => true;

  @override
  Future<void> zacni() async => tece = true;

  @override
  Future<Posneto?> ustavi() async {
    tece = false;
    return (bajti: Uint8List.fromList([1, 2, 3, 4]), vrsta: 'audio/mp4', sekund: 7);
  }

  @override
  Future<void> prekini() async => tece = false;

  @override
  Future<void> zapri() async {}
}

http.Response _odg(String telo, int koda) => http.Response.bytes(utf8.encode(telo), koda);

void main() {
  late List<Map<String, dynamic>> poslano;
  late bool povezava;
  var slik = 0;
  var staraSkripta = false;

  Api api() => Api(
    () async => 'z',
    url: 'https://example.com/exec',
    client: MockClient((r) async {
      if (!povezava) throw http.ClientException('Ni povezave');
      if (r.method == 'GET' && r.url.queryParameters['akcija'] == 'slikeClanov') {
        slik++;
        return _odg(
          jsonEncode({
            'c1': {
              'slika': 'Člani_Images/t.jpg',
              'base64': base64Encode([7, 7, 7]),
            },
          }),
          200,
        );
      }
      if (r.method == 'GET' && r.url.queryParameters['akcija'] == 'posnetek') {
        return _odg(
          jsonEncode({
            'base64': base64Encode([9, 9]),
          }),
          200,
        );
      }
      if (r.method == 'GET') {
        return _odg(
          jsonEncode({
            'clan': {'ID': 'c1'},
            'tabele': {
              'Pesmi': [
                {'ID': 'a', 'Koda': 1, 'Naslov': 'BELO OBLEKO', 'Aktivna': true},
              ],
              'Člani': [
                {'ID': 'c1', 'Ime': 'Tomaž', 'Slika': 'Člani_Images/t.jpg'},
                {'ID': 'c2', 'Ime': 'Jože'},
              ],
              'Posnetki': [
                {
                  'ID': 'p2',
                  'Pesem': 'a',
                  'Član': 'c2',
                  'Skupno': true,
                  'Ime': 'Uvod',
                  'Drive ID': 'd2',
                  'Trajanje (s)': 12,
                },
              ],
            },
          }),
          200,
        );
      }
      final telo = jsonDecode(r.body) as Map<String, dynamic>;
      poslano.add(telo);
      if (staraSkripta) return _odg(jsonEncode({'napaka': 'Neznana akcija'}), 200);
      if (telo['akcija'] == 'posnetek') {
        return _odg(
          jsonEncode({
            'vrstica': {...telo['posnetek'] as Map, 'Drive ID': 'd1'},
          }),
          200,
        );
      }
      return _odg(jsonEncode({'izbrisano': telo['id']}), 200);
    }),
  );

  setUp(() {
    poslano = [];
    povezava = true;
    staraSkripta = false;
  });

  test('posnetek ostane na napravi, na strežnik gre z zvokom, skupnega drugega člana se prenese', () async {
    final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
    await baza.osvezi(api());
    expect(baza.napaka, isNull);
    expect(baza.posnetki['a']!.single.ime, 'Uvod');
    expect(baza.smeIzbrisatiPosnetek(baza.posnetki['a']!.single), isFalse);

    povezava = false;
    final p = await baza.dodajPosnetek(
      api(),
      'a',
      Uint8List.fromList([1, 2, 3]),
      skupno: false,
      ime: 'Vaja',
      vrsta: 'audio/mp4',
      trajanje: 5,
    );
    expect(baza.posnetki['a']!.map((x) => x.id), contains(p.id));
    expect(baza.neposlano.single['akcija'], 'posnetek');
    expect(await baza.zvokPosnetka(null, p), [1, 2, 3]);

    povezava = true;
    expect(await baza.posljiNeposlano(api()), isNull);
    expect(poslano.single['akcija'], 'posnetek');
    expect(base64Decode(poslano.single['base64'] as String), [1, 2, 3]);
    expect(baza.posnetki['a']!.firstWhere((x) => x.id == p.id).driveId, 'd1');

    // Skupni posnetek drugega člana se prenese ob prvem poslušanju.
    expect(await baza.zvokPosnetka(api(), baza.posnetki['a']!.firstWhere((x) => x.id == 'p2')), [9, 9]);

    await baza.izbrisiPosnetek(api(), p.id);
    expect(poslano.last, containsPair('akcija', 'posnetekIzbrisi'));
    expect(baza.posnetki['a']!.map((x) => x.id), ['p2']);
  });

  testWidgets('snemalnik: posname skupni posnetek in ga pokaže na seznamu', (tester) async {
    final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
    await tester.runAsync(() => baza.osvezi(api()));
    final snemalnik = _Snemalnik();
    Snemalnik.tovarna = () => snemalnik;
    povezava = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OknoPosnetkov(baza: baza, api: null, pesem: 'a'),
        ),
      ),
    );
    expect(find.text('Uvod'), findsOneWidget);
    await tester.tap(find.text('Skupno'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('snemaj')));
    await tester.pump();
    expect(snemalnik.tece, isTrue);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('ustavi-snemanje')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(milliseconds: 300));
    // Ob ustavitvi ponudi privzeti naslov, ki ga lahko popraviš.
    expect(find.byKey(const ValueKey('naslov-posnetka')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('naslov-posnetka')), 'Refren počasi');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('shrani-posnetek')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));
    final nov = baza.posnetki['a']!.firstWhere((p) => p.id != 'p2');
    expect(nov.ime, 'Refren počasi');
    expect(nov.skupno, isTrue);
    expect(nov.trajanje, 7);
    expect(find.textContaining('čaka na pošiljanje'), findsOneWidget);
    expect(find.textContaining('Posnel: Tomaž'), findsOneWidget);
    expect(find.textContaining('Posnel: Jože'), findsOneWidget);

    // Preimenovanje neposlanega posnetka popravi kar čakajoči zapis.
    await tester.runAsync(() => baza.preimenujPosnetek(null, nov.id, 'Refren'));
    expect(baza.neposlano.single['podatki']['Ime'], 'Refren');
    expect(baza.posnetki['a']!.firstWhere((p) => p.id == nov.id).ime, 'Refren');
  });

  test('preimenovanje poslanega posnetka gre na strežnik', () async {
    final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
    await baza.osvezi(api());
    povezava = false;
    await baza.preimenujPosnetek(api(), 'p2', 'Uvod počasi');
    expect(baza.posnetki['a']!.single.ime, 'Uvod počasi');
    povezava = true;
    await baza.posljiNeposlano(api());
    expect(poslano.last, containsPair('akcija', 'posnetekIme'));
    expect(poslano.last['ime'], 'Uvod počasi');
  });

  test('stara skripta: posnetek ostane viden in na napravi, osvežitev dela, pošlje se po novi skripti', () async {
    final shramba = ShrambaIdb(newIdbFactoryMemory());
    final baza = Baza(shramba: shramba);
    await baza.osvezi(api());
    staraSkripta = true;
    final p = await baza.dodajPosnetek(
      api(),
      'a',
      Uint8List.fromList([5]),
      skupno: true,
      ime: 'Vaja',
      vrsta: 'audio/mp4',
      trajanje: 3,
    );
    await baza.osvezi(api());
    expect(baza.napaka, isNull);
    expect(baza.posnetki['a']!.map((x) => x.id), contains(p.id));

    // Po ponovnem zagonu aplikacije je še vedno tam.
    final znova = Baza(shramba: shramba);
    await znova.nalozi();
    expect(znova.posnetki['a']!.map((x) => x.id), contains(p.id));

    staraSkripta = false;
    poslano.clear();
    await znova.osvezi(api());
    expect(poslano.map((t) => t['akcija']), contains('posnetek'));
    expect(znova.neposlano, isEmpty);
  });

  test('sličice članov se prenesejo le, ko se slika v Nastopih spremeni', () async {
    slik = 0;
    final shramba = ShrambaIdb(newIdbFactoryMemory());
    final baza = Baza(shramba: shramba);
    await baza.osvezi(api());
    expect(baza.slikeClanov['c1'], [7, 7, 7]);
    await baza.osvezi(api());
    expect(slik, 1);
    final znova = Baza(shramba: shramba);
    await znova.nalozi();
    expect(znova.slikeClanov['c1'], [7, 7, 7]);
  });
}
