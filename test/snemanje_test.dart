import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/config.dart';
import 'package:spadni_besedila/models.dart';
import 'package:spadni_besedila/runda.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/snemanje.dart';
import 'package:spadni_besedila/spil/spil.dart';

class _Snemalnik implements SnemalnikKosov {
  final poti = <String>[];
  String? tece;

  @override
  Future<bool> dovoljenje() async => true;
  @override
  Future<List<VhodZvoka>> vhodi() async => [(id: 'usb', ime: 'USB mešalka')];
  @override
  Future<void> zacni(String pot, {String? vhod}) async {
    tece = pot;
    poti.add(pot);
  }

  @override
  Future<void> ustavi() async => tece = null;
  @override
  Future<void> zapri() async {}
}

http.Response _odg(Object o) => http.Response.bytes(utf8.encode(jsonEncode(o)), 200);

void main() {
  late List<Map<String, dynamic>> poslano;
  late Map<String, Uint8List> datoteke;
  late _Snemalnik snemalnik;

  Api api() => Api(
    () async => 'z',
    url: 'https://example.com/exec',
    client: MockClient((r) async {
      if (r.method == 'GET') {
        return _odg({
          'clan': {'ID': 'C', 'Ime': 'Tomaž'},
          'vloge': [
            {'Skupina': 's1', 'Vloga': 'Administrator', 'Sme voditi': true},
          ],
          'tabele': {
            'Pesmi': [
              {'ID': 'a', 'Koda': 1, 'Naslov': 'BELO OBLEKO', 'Aktivna': true},
            ],
          },
        });
      }
      poslano.add(jsonDecode(r.body) as Map<String, dynamic>);
      return _odg({'ok': true});
    }),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Runda.aplikacija = Runda();
    poslano = [];
    datoteke = {};
    snemalnik = _Snemalnik();
    SnemalnikKosov.tovarna = () => snemalnik;
    SnemanjeSpila.potKosa = (id, i) async {
      final pot = '/kosi/${id}_$i.m4a';
      datoteke[pot] = Uint8List.fromList([i, 1, 2]);
      return pot;
    };
    SnemanjeSpila.beriKos = (pot) async => datoteke[pot];
    SnemanjeSpila.izbrisiKos = (pot) async => datoteke.remove(pot);
  });

  test('snemanje po kosih: PAVZA ustavi kos, ŠPILEJ!! začne novega, vse gre na Drive in se pobriše', () async {
    final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
    await baza.osvezi(api());
    Api? povezava;
    final s = SnemanjeSpila()
      ..baza = baza
      ..api = (() => povezava)
      ..imeNaprave = 'windows';
    await s.zacni(naslov: '');
    expect(s.aktivno, isTrue);
    expect(s.naprava, 'Tomaž (windows)');
    expect(s.naslov, startsWith('Špil '));
    expect(snemalnik.tece, isNotNull);

    await Runda.aplikacija.zacni(true);
    await Future<void>.delayed(Duration.zero);
    expect(s.pavza, isTrue);
    expect(snemalnik.tece, isNull);
    await Runda.aplikacija.zacni(false);
    await Future<void>.delayed(Duration.zero);
    expect(s.pavza, isFalse);
    expect(snemalnik.poti, hasLength(2));

    await s.zakljuci();
    expect(s.aktivno, isFalse);
    // Brez prijave kosi počakajo na napravi.
    expect(s.cakajo, 2);
    expect(datoteke, hasLength(2));

    povezava = api();
    await s.poslji();
    expect(poslano.map((p) => p['akcija']), ['snemanje', 'snemanjeKos', 'snemanjeKos', 'snemanje']);
    expect(poslano.first['snemanje']['Stanje'], 'snema');
    expect(poslano.last['snemanje']['Stanje'], 'posneto');
    expect(poslano[1]['i'], 0);
    expect(base64Decode(poslano[2]['base64'] as String), [1, 1, 2]);
    expect(s.vrsta, isEmpty);
    expect(datoteke, isEmpty);
  });

  test('administrator na sledilcu začne in konča snemanje na vodji; sledilec vidi, kje se snema', () async {
    final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
    await baza.osvezi(api());
    SnemanjeSpila.aplikacija = SnemanjeSpila()
      ..baza = baza
      ..imeNaprave = 'android';
    final vodja = Spil()..baza = baza;
    final sledilec = Spil()..baza = baza;
    addTearDown(() async {
      await sledilec.ustavi();
      await vodja.ustavi();
    });
    await vodja.zacniVoditi(baza);
    sledilec.sledi(Uri.parse('ws://127.0.0.1:${Config.vrataVodje}/ws'));
    for (var i = 0; i < 100 && SnemanjeSpila.aplikacija.vodji == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // V testu sta vodja in sledilec v istem procesu: ukaz gre prek WebSocketa vodji, ta začne snemati.
    await SnemanjeSpila.aplikacija.zacni(naslov: 'Poroka, Ajdovščina');
    for (var i = 0; i < 100 && !SnemanjeSpila.aplikacija.snemaTu; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(SnemanjeSpila.aplikacija.aktivno, isTrue);
    expect(SnemanjeSpila.aplikacija.naslov, 'Poroka, Ajdovščina');
    expect(SnemanjeSpila.aplikacija.vJson(), containsPair('naprava', 'Tomaž (android)'));

    await SnemanjeSpila.aplikacija.zakljuci();
    for (var i = 0; i < 100 && SnemanjeSpila.aplikacija.snemaTu; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(SnemanjeSpila.aplikacija.aktivno, isFalse);
  });

  test('povezava na YouTube: čas pesmi v videu brez pavz', () {
    final s = Snemanje.izVrstice({
      'ID': 'x',
      'Naslov': 'Poroka',
      'Začetek': '2026-11-07T19:00:00Z',
      'YouTube ID': 'abc',
      'Kosi': jsonEncode([
        {'i': 0, 'z': '2026-11-07T19:00:00Z', 't': 600},
        {'i': 1, 'z': '2026-11-07T19:30:00Z', 't': 600},
      ]),
    });
    expect(s.vsebuje(DateTime.parse('2026-11-07T19:35:00Z')), isTrue);
    expect(s.vsebuje(DateTime.parse('2026-11-07T21:00:00Z')), isFalse);
    // 5 min v drugem kosu = 10 min prvega + 5 min.
    expect(s.povezava(DateTime.parse('2026-11-07T19:35:00Z')), 'https://youtu.be/abc?t=900');
    // V pavzi: začetek naslednjega kosa.
    expect(s.odmik(DateTime.parse('2026-11-07T19:20:00Z')), 600);
  });
}
