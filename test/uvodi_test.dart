import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/nastavitve.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/uvodi.dart';
import 'package:spadni_besedila/zasloni/urejanje_uvoda.dart';

final _zvok = Uint8List.fromList([1, 2, 3, 4]);

Map<String, dynamic> _tabele({String uvod = 'd1'}) => {
  'Pesmi': [
    {
      'ID': 'a',
      'Koda': 1,
      'Naslov': 'BELO OBLEKO',
      'Aktivna': true,
      'Uvod': uvod,
      'Uvod vrsta': 'audio/mpeg',
      'Uvod od': 1.5,
      'Uvod do': 4,
    },
    {'ID': 'b', 'Koda': 2, 'Naslov': 'BREZ UVODA', 'Aktivna': true},
  ],
};

/// Baza z enim uvodom; strežnik beleži poslano.
Future<(Baza, _Pomnilnik, List<Map<String, dynamic>>, Api)> _baza() async {
  final shramba = _Pomnilnik();
  final baza = Baza(shramba: shramba);
  final poslano = <Map<String, dynamic>>[];
  final api = Api(
    () async => 'z',
    url: 'https://example.com/exec',
    client: MockClient((r) async {
      if (r.method == 'GET') {
        final akcija = r.url.queryParameters['akcija'];
        poslano.add({'akcija': akcija, ...r.url.queryParameters});
        if (akcija == 'uvod') {
          return http.Response(jsonEncode({'vrsta': 'audio/mpeg', 'base64': base64Encode(_zvok)}), 200);
        }
        return http.Response.bytes(utf8.encode(jsonEncode({'tabele': _tabele()})), 200);
      }
      final telo = jsonDecode(r.body) as Map<String, dynamic>;
      poslano.add(telo);
      if (telo['akcija'] == 'uvod') {
        final vrstica = {
          ...(_tabele()['Pesmi'] as List).cast<Map<String, dynamic>>().firstWhere((r) => r['ID'] == telo['pesem']),
          'Uvod': telo['base64'] == null ? '' : 'd2',
          'Uvod od': telo['od'] ?? '',
          'Uvod do': telo['do'] ?? '',
        };
        return http.Response.bytes(utf8.encode(jsonEncode({'vrstica': vrstica})), 200);
      }
      if (telo['akcija'] == 'pesem') {
        final p = telo['pesem'] as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'vrstica': {...(_tabele()['Pesmi'] as List).first as Map<String, dynamic>, ...p},
            }),
          ),
          200,
        );
      }
      return http.Response(jsonEncode({}), 200);
    }),
  );
  await baza.osvezi(api);
  poslano.clear();
  return (baza, shramba, poslano, api);
}

void main() {
  late _Predvajalnik predvajalnik;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Nastavitve.aplikacija = Nastavitve();
    predvajalnik = _Predvajalnik();
    PredvajalnikZvoka.tovarna = () => predvajalnik;
    Uvodi.aplikacija = Uvodi();
  });

  test('podatki uvoda pri pesmi', () async {
    final (baza, _, _, _) = await _baza();
    final p = baza.pesem('a')!;
    expect(p.uvod, 'd1');
    expect(p.uvodOd, 1.5);
    expect(p.uvodDo, 4);
    expect(baza.pesem('b')!.uvod, isEmpty);
    expect(baza.pesem('b')!.uvodDo, isNull);
  });

  test('brez »Hrani uvode lokalno« se uvod prebere s spleta enkrat na sejo in ne shrani na napravo', () async {
    final (baza, shramba, poslano, api) = await _baza();
    expect(await baza.zvokUvoda(api, baza.pesem('a')!), _zvok);
    expect(await baza.zvokUvoda(api, baza.pesem('a')!), _zvok);
    expect(poslano.where((p) => p['akcija'] == 'uvod'), hasLength(1));
    expect(await shramba.kljuci('uvodi/'), isEmpty);
    expect(await baza.zvokUvoda(api, baza.pesem('b')!), isNull);
  });

  test('hrani uvode lokalno: prenese manjkajoče, pobriše stare, ob izklopu pobriše vse', () async {
    final (baza, shramba, poslano, api) = await _baza();
    await Nastavitve.aplikacija.nastaviHraniUvode(true);
    await shramba.pisiBajte('uvodi/star', _zvok);
    expect(await baza.prenesiUvode(api), 0);
    expect(await shramba.kljuci('uvodi/'), {'uvodi/d1'});
    // Že prenesen se ne prenaša znova.
    await baza.prenesiUvode(api);
    expect(poslano.where((p) => p['akcija'] == 'uvod'), hasLength(1));
    await baza.izbrisiLokalneUvode();
    expect(await shramba.kljuci('uvodi/'), isEmpty);
  });

  test('shrani in izbriši uvod', () async {
    final (baza, _, poslano, api) = await _baza();
    final p = await baza.shraniUvod(api, 'a', _zvok, vrsta: 'audio/mp4', od: 0.5, doo: 3);
    expect(poslano.single['akcija'], 'uvod');
    expect(poslano.single['od'], 0.5);
    expect(poslano.single['do'], 3);
    expect(base64Decode(poslano.single['base64'] as String), _zvok);
    expect(p.uvod, 'd2');
    expect(baza.pesem('a')!.uvod, 'd2');
    // Pravkar shranjen je že v seji (ni prenosa).
    expect(await baza.zvokUvoda(null, baza.pesem('a')!), _zvok);
    await baza.shraniUvod(api, 'a', null);
    expect(poslano.last.containsKey('base64'), isFalse);
    expect(baza.pesem('a')!.uvod, isEmpty);
  });

  test('ob odprtju: igra samo, ko je uho vklopljeno in naprava predvaja uvode; od–do s pojemanjem', () async {
    final (baza, _, _, api) = await _baza();
    final p = baza.pesem('a')!;
    final n = Nastavitve.aplikacija;
    await n.nastaviPredvajajUvode(false);
    await Uvodi.aplikacija.obOdprtju(baza, api, p);
    expect(predvajalnik.od, isNull);

    await n.nastaviPredvajajUvode(true);
    await n.nastaviUvode(false);
    await Uvodi.aplikacija.obOdprtju(baza, api, p);
    expect(predvajalnik.od, isNull);

    await n.nastaviUvode(true);
    await n.nastaviIzhodZvoka('usb');
    await Uvodi.aplikacija.obOdprtju(baza, api, p);
    expect(predvajalnik.od, const Duration(milliseconds: 1500));
    expect(predvajalnik.izhod, 'usb');
    expect(Uvodi.aplikacija.igra, 'a');

    // 0,4 s pred koncem (4 s) je glasnost pol manjša, na koncu se ustavi.
    predvajalnik.poz.add(const Duration(milliseconds: 3600));
    await Future<void>.delayed(Duration.zero);
    expect(predvajalnik.jakost, closeTo(0.5, 0.01));
    predvajalnik.poz.add(const Duration(milliseconds: 4000));
    await Future<void>.delayed(Duration.zero);
    expect(predvajalnik.ustavljen, isTrue);
    expect(Uvodi.aplikacija.igra, isNull);
  });

  test('zaprtje pesmi ustavi le njen uvod', () async {
    final (baza, _, _, api) = await _baza();
    await Nastavitve.aplikacija.nastaviPredvajajUvode(true);
    await Uvodi.aplikacija.obOdprtju(baza, api, baza.pesem('a')!);
    await Uvodi.aplikacija.obZaprtju(baza.pesem('b')!);
    expect(Uvodi.aplikacija.igra, 'a');
    await Uvodi.aplikacija.obZaprtju(baza.pesem('a')!);
    expect(Uvodi.aplikacija.igra, isNull);
    expect(predvajalnik.ustavljen, isTrue);
  });

  testWidgets('urejanje uvoda: posnemi, obreži, shrani; pri obstoječem samo od–do', (t) async {
    final (baza, _, poslano, api) = await t.runAsync(_baza) as (Baza, _Pomnilnik, List<Map<String, dynamic>>, Api);
    SnemalnikUvoda.tovarna = _Snemalnik.new;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [UrejanjeUvoda(baza: baza, api: api, pesem: 'b')],
          ),
        ),
      ),
    );
    expect(find.textContaining('Ni uvoda'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('uvod-snemaj')));
    await t.pump();
    expect(find.text('Ustavi snemanje'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('uvod-snemaj')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('uvod-obseg')), findsOneWidget);
    expect(find.textContaining('še ni shranjen'), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('uvod-shrani')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pump();
    final uvod = poslano.singleWhere((p) => p['akcija'] == 'uvod');
    expect(uvod['pesem'], 'b');
    expect(uvod['od'], 0);
    expect(uvod.containsKey('do'), isFalse);
    expect(find.byKey(const ValueKey('uvod-shrani')), findsNothing);

    // Obstoječ uvod (a): sprememba obsega shrani samo od–do v pesem.
    poslano.clear();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [UrejanjeUvoda(key: UniqueKey(), baza: baza, api: api, pesem: 'a')],
          ),
        ),
      ),
    );
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(find.textContaining('od 0:01,5 do 0:04,0'), findsOneWidget);
    final slider = t.widget<RangeSlider>(find.byKey(const ValueKey('uvod-obseg')));
    slider.onChanged!(const RangeValues(2, 10));
    await t.pump();
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('uvod-shrani')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pump();
    final pesem = poslano.singleWhere((p) => p['akcija'] == 'pesem')['pesem'] as Map;
    expect(pesem['Uvod od'], 2);
    expect(pesem['Uvod do'], '');
    expect(poslano.where((p) => p['akcija'] == 'uvod' && p.containsKey('base64')), isEmpty);
  });
}

class _Predvajalnik implements PredvajalnikZvoka {
  final poz = StreamController<Duration>.broadcast();
  final _konec = StreamController<void>.broadcast();
  Duration? od;
  String? izhod;
  double jakost = 1;
  bool ustavljen = false;

  @override
  Future<Duration?> odpri(Uint8List bajti, String vrsta) async => const Duration(seconds: 10);

  @override
  Future<void> predvajaj(Duration od) async {
    this.od = od;
    ustavljen = false;
  }

  @override
  Future<void> ustavi() async => ustavljen = true;

  @override
  Future<void> glasnost(double g) async => jakost = g;

  @override
  Stream<Duration> get pozicija => poz.stream;

  @override
  Stream<void> get konec => _konec.stream;

  @override
  Future<List<IzhodZvoka>> izhodi() async => [(id: 'usb', ime: 'USB')];

  @override
  Future<void> nastaviIzhod(String id) async => izhod = id;

  @override
  void zapri() {}
}

class _Snemalnik implements SnemalnikUvoda {
  @override
  Future<bool> dovoljenje() async => true;

  @override
  Future<void> zacni() async {}

  @override
  Future<PosnetUvod?> ustavi() async => (bajti: _zvok, vrsta: 'audio/mp4');

  @override
  Future<void> zapri() async {}
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
