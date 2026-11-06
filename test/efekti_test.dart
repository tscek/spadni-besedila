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
import 'package:spadni_besedila/efekti.dart';
import 'package:spadni_besedila/midi/ukazi.dart';
import 'package:spadni_besedila/midi/xy.dart';
import 'package:spadni_besedila/nastavitve.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/uvodi.dart';
import 'package:spadni_besedila/zasloni/fx_panel.dart';
import 'package:spadni_besedila/zvok_spila.dart';

final _zvok = Uint8List.fromList([9, 8, 7]);

const _postavitev = PostavitevFx(
  strani: 2,
  gumbi: [
    GumbFx(id: 'aplavz', ime: 'Aplavz', efekt: 'e1', fadeOut: 0),
    GumbFx(id: 'veter', ime: 'Veter', efekt: 'e1', nacin: NacinFx.preklop, zanka: true, fadeOut: 100),
    GumbFx(id: 'sirena', ime: 'Sirena', efekt: 'e1', nacin: NacinFx.medPritiskom, fadeIn: 100, fadeOut: 100, mesto: 2),
    GumbFx(id: 'luc', ime: 'Luč', ukazi: 'PC 1 5', xy: true, mesto: 3),
    GumbFx(id: 'samo-a', ime: 'Samo A', efekt: 'e1', pesem: 'a', ustaviObMenjavi: true),
  ],
  xy: NastavitveXy(skupine: [SkupinaXy('Efekt', 'CC 2 20', 'CC 2 21')]),
);

void main() {
  late List<_Predvajalnik> predvajalniki;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Nastavitve.aplikacija = Nastavitve();
    predvajalniki = [];
    PredvajalnikZvoka.tovarna = () {
      final p = _Predvajalnik();
      predvajalniki.add(p);
      return p;
    };
    Efekti.aplikacija = Efekti();
    ZvokSpila.aplikacija = ZvokSpila();
  });

  test('postavitev FX: zapis, gumb pesmi zamenja splošnega, vrstni red za nožno stikalo', () {
    final p = PostavitevFx.izBesedila(_postavitev.vBesedilo());
    expect(p.strani, 2);
    expect(p.gumbi, hasLength(5));
    expect(p.gumb('veter')!.nacin, NacinFx.preklop);
    expect(p.gumb('veter')!.zanka, isTrue);
    expect(p.gumb('sirena')!.fadeIn, 100);
    expect(p.xy!.skupine.single.x, 'CC 2 20');
    // Na mestu 0: pri pesmi a njen gumb, drugje splošni.
    expect(p.na(0, 0, 'a')!.id, 'samo-a');
    expect(p.na(0, 0, 'b')!.id, 'aplavz');
    expect(p.poVrsti(0, 'b').map((g) => g.id), ['aplavz', 'sirena', 'luc']);
    expect(PostavitevFx.izBesedila('nesmisel').gumbi, isEmpty);
    expect(p.brezGumba('luc').gumbi, hasLength(4));
  });

  testWidgets('efekti: enkratno, preklop v zanki, med pritiskom s fade, obrezovanje, ustavi vse', (t) async {
    final e = Efekti.aplikacija;
    var postavitev = _postavitev;
    final midi = <String>[];
    e
      ..postavitev = (() => postavitev)
      ..bajti = ((id) async => (bajti: _zvok, vrsta: 'audio/mpeg'))
      ..midi = ((u) async => midi.add(u));
    await t.runAsync(e.pripravi);
    expect(predvajalniki, hasLength(4));

    // Enkratno: pritisk začne, ponoven pritisk začne znova od začetka.
    await t.runAsync(() => e.dogodek('aplavz', dol: true));
    final aplavz = predvajalniki.first;
    expect(aplavz.od, Duration.zero);
    expect(e.igra('aplavz'), isTrue);
    aplavz.poz.add(const Duration(seconds: 3));
    await t.pump();
    expect(e.stanje['aplavz']!.pozicija, const Duration(seconds: 3));
    await t.runAsync(() => e.dogodek('aplavz', dol: true));
    expect(e.igra('aplavz'), isTrue);
    // Konec posnetka ga ustavi.
    await t.runAsync(() async {
      aplavz.konecTok.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    expect(e.igra('aplavz'), isFalse);

    // Preklop v zanki: na koncu začne znova, drugi pritisk ustavi s fade out.
    await t.runAsync(() => e.dogodek('veter', dol: true));
    final veter = predvajalniki[1];
    await t.runAsync(() async {
      veter.od = null;
      veter.konecTok.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    expect(veter.od, Duration.zero);
    expect(e.igra('veter'), isTrue);
    await t.runAsync(() => e.dogodek('veter', dol: true));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    expect(veter.jakost, lessThan(1));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    expect(e.igra('veter'), isFalse);
    expect(veter.ustavljen, isTrue);

    // Med pritiskom: fade in ob pritisku, ob spustu fade out.
    await t.runAsync(() => e.dogodek('sirena', dol: true));
    final sirena = predvajalniki[2];
    expect(sirena.jakost, 0);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    expect(sirena.jakost, 1);
    await t.runAsync(() => e.dogodek('sirena', dol: false));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    expect(e.igra('sirena'), isFalse);

    // Samo MIDI: pošlje ukaze, zvoka ni.
    await t.runAsync(() => e.dogodek('luc', dol: true));
    expect(midi, ['PC 1 5']);
    expect(e.igra('luc'), isFalse);

    // Obrezovanje: začne pri »od«, pri »do« se ustavi; glasnost gumba krat glasnost vseh.
    postavitev = postavitev.zGumbom(
      const GumbFx(id: 'aplavz', ime: 'Aplavz', efekt: 'e1', od: 1.5, doo: 4, glasnost: 0.5),
    );
    e.nastaviGlasnost(0.5);
    await t.runAsync(() => e.dogodek('aplavz', dol: true));
    expect(aplavz.od, const Duration(milliseconds: 1500));
    expect(aplavz.jakost, 0.25);
    expect(e.stanje['aplavz']!.trajanje, const Duration(milliseconds: 2500));
    await t.runAsync(() async {
      aplavz.poz.add(const Duration(seconds: 4));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    expect(e.igra('aplavz'), isFalse);

    // Ustavi vse in zamenjava pesmi.
    e.nastaviGlasnost(1);
    await t.runAsync(() => e.dogodek('veter', dol: true));
    await t.runAsync(() => e.dogodek('samo-a', dol: true));
    await t.runAsync(e.obMenjaviPesmi);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    expect(e.igra('samo-a'), isFalse);
    expect(e.igra('veter'), isTrue);
    await t.runAsync(e.ustaviVse);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    expect(e.stanje, isEmpty);
  });

  testWidgets('FX na špilu: tablica pošlje ukaz, PC predvaja, vsi vidijo, kaj igra', (t) async {
    Efekti.aplikacija
      ..postavitev = (() => _postavitev)
      ..bajti = ((id) async => (bajti: _zvok, vrsta: 'audio/mpeg'));
    final tablica = ZvokSpila();
    final pc = ZvokSpila.aplikacija;
    final odTablice = <Map<String, dynamic>>[];
    final odPc = <Map<String, dynamic>>[];
    tablica.vodji = odTablice.add;
    pc.vsem = odPc.add;

    // Tablica (brez efektov) pritisne gumb: ukaz gre vodji.
    await Nastavitve.aplikacija.nastaviPredvajajEfekte(false);
    tablica.fx('aplavz', dol: true);
    expect(odTablice.single, {'akcija': 'fx', 'gumb': 'aplavz', 'dol': true});
    expect(Efekti.aplikacija.igra('aplavz'), isFalse);

    // Vodja brez efektov ga pošlje naprej sledilcem.
    await t.runAsync(() => pc.odSledilca(odTablice.single));
    expect(odPc.last, {'vrsta': 'zvokUkaz', 'akcija': 'fx', 'gumb': 'aplavz', 'dol': true});

    // Vodja (PC) z efekti ga predvaja in objavi stanje.
    await Nastavitve.aplikacija.nastaviPredvajajEfekte(true);
    pc.povezi();
    await t.runAsync(() async {
      await pc.odSledilca(odTablice.single);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    expect(Efekti.aplikacija.igra('aplavz'), isTrue);
    final stanje = odPc.lastWhere((m) => m['vrsta'] == 'zvok');
    expect((stanje['fx'] as Map).keys, ['aplavz']);

    // Tablica dobi stanje: gumb igra in kaže čas.
    await Nastavitve.aplikacija.nastaviPredvajajEfekte(false);
    await tablica.odVodje(jsonDecode(jsonEncode(stanje)) as Map<String, dynamic>);
    expect(tablica.stanjeFx('aplavz'), isNotNull);
    expect(tablica.igraKakFx, isTrue);

    // Ustavi vse in glasnost s tablice.
    tablica.fxGlasnost(0.4);
    expect(odTablice.last, {'akcija': 'fxGlasnost', 'g': 0.4});
    expect(tablica.glasnostFx, 0.4);
    tablica.fxUstaviVse();
    expect(odTablice.last, {'akcija': 'fxUstavi'});

    // XY pad brez MIDI na tablici: ukazi gredo prek špila.
    await tablica.posljiMidiZapis('PC 1 5', _knjiznica());
    expect(odTablice.last, {'akcija': 'midi', 'zapis': 'PC 1 5'});
    pc.odklopi();
    // Konec špila: tuje stanje pozabi (ob novem špilu ne kaže starega).
    tablica.pozabi();
    tablica.vodji = odTablice.add;
    expect(tablica.stanjeFx('aplavz'), isNull);
  });

  testWidgets('FX panel: gumbi igrajo, črta do konca, Ustavi vse; admin doda gumb', (t) async {
    final (baza, poslano, api) = await t.runAsync(_baza) as (Baza, List<Map<String, dynamic>>, Api);
    Efekti.aplikacija
      ..postavitev = (() => baza.fx)
      ..bajti = ((id) => baza.bajtiEfekta(api, id));
    FxPrikaz.odprt.value = true;
    FxPrikaz.urejam.value = false;
    FxPrikaz.stran.value = 0;
    await t.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: const [FxGumb()]),
          body: FxOkvir(baza: baza, api: () => api, pesem: 'b', child: const Text('Besedilo')),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('fx-panel')), findsOneWidget);
    expect(find.text('Aplavz'), findsOneWidget);
    expect(find.text('Samo A'), findsNothing);

    await t.runAsync(() async {
      await t.tap(find.text('Aplavz'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pump();
    expect(Efekti.aplikacija.igra('aplavz'), isTrue);
    expect(find.byKey(const ValueKey('fx-crta-aplavz')), findsOneWidget);

    // Gumb z XY odpre pad na zgornji polovici.
    await t.tap(find.text('Luč'));
    await t.pump();
    expect(find.byKey(const ValueKey('xy-polovica')), findsOneWidget);

    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('fx-ustavi-vse')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump();
    expect(Efekti.aplikacija.igra('aplavz'), isFalse);

    // Administrator: urejanje, prazno mesto, nov gumb.
    await t.tap(find.byKey(const ValueKey('fx-uredi')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('fx-prazno-0-5')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('fx-ime')), 'Bobni');
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('fx-shrani')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    final fx = PostavitevFx.izBesedila(poslano.lastWhere((p) => p['akcija'] == 'fx')['vsebina'] as String);
    expect(fx.na(0, 5, null)!.ime, 'Bobni');
    expect(baza.fx.gumbi, hasLength(6));
    expect(find.text('Bobni'), findsOneWidget);
    FxPrikaz.odprt.value = false;
    FxPrikaz.xy.value = false;
    FxPrikaz.urejam.value = false;
  });
}

KnjiznicaMidi _knjiznica() => _baza0().midi;

Baza _baza0() => Baza(shramba: _Pomnilnik());

Future<(Baza, List<Map<String, dynamic>>, Api)> _baza() async {
  final baza = Baza(shramba: _Pomnilnik());
  final poslano = <Map<String, dynamic>>[];
  var fx = _postavitev.vBesedilo();
  final api = Api(
    () async => 'z',
    url: 'https://example.com/exec',
    client: MockClient((r) async {
      if (r.method == 'GET') {
        final akcija = r.url.queryParameters['akcija'];
        poslano.add({'akcija': akcija, ...r.url.queryParameters});
        if (akcija == 'efekt') {
          return http.Response(jsonEncode({'id': 'e1', 'vrsta': 'audio/mpeg', 'base64': base64Encode(_zvok)}), 200);
        }
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'vloge': [
                {'Skupina': 's1', 'Vloga': 'Administrator'},
              ],
              'fx': fx,
              'tabele': {
                'Pesmi': [
                  {'ID': 'a', 'Koda': 1, 'Naslov': 'A', 'Aktivna': true},
                  {'ID': 'b', 'Koda': 2, 'Naslov': 'B', 'Aktivna': true},
                ],
                'Efekti': [
                  {'ID': 'e1', 'Ime': 'Aplavz', 'Datoteka': 'd1', 'Vrsta': 'audio/mpeg'},
                ],
              },
            }),
          ),
          200,
        );
      }
      final telo = jsonDecode(r.body) as Map<String, dynamic>;
      poslano.add(telo);
      if (telo['akcija'] == 'fx') {
        fx = telo['vsebina'] as String;
        return http.Response.bytes(utf8.encode(jsonEncode({'fx': fx})), 200);
      }
      return http.Response(jsonEncode({}), 200);
    }),
  );
  await baza.osvezi(api);
  poslano.clear();
  return (baza, poslano, api);
}

class _Predvajalnik implements PredvajalnikZvoka {
  final poz = StreamController<Duration>.broadcast();
  final konecTok = StreamController<void>.broadcast();
  Duration? od;
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
  Stream<void> get konec => konecTok.stream;

  @override
  Future<List<IzhodZvoka>> izhodi() async => const [];

  @override
  Future<void> nastaviIzhod(String id) async {}

  @override
  Future<void> transponiraj(int poltonov) async {}

  @override
  void zapri() {}
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
