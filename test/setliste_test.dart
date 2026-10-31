import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/midi/midi.dart';
import 'package:spadni_besedila/midi/ukazi.dart';
import 'package:spadni_besedila/models.dart';
import 'package:spadni_besedila/prijava.dart';
import 'package:spadni_besedila/runda.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/spil/spil.dart';
import 'package:spadni_besedila/spil/streznik.dart';
import 'package:spadni_besedila/zasloni/pesem_zaslon.dart';
import 'package:spadni_besedila/zasloni/setliste_zaslon.dart';
import 'package:spadni_besedila/zasloni/spil_zaslon.dart';
import 'package:spadni_besedila/zasloni/urejanje_setliste.dart';

Map<String, dynamic> _podatki() => {
  'vloge': [
    {'Skupina': 's1', 'Vloga': 'Administrator'},
  ],
  'tabele': {
    'Pesmi': [
      for (final (id, koda, naslov) in [('a', 1002, 'BELO OBLEKO'), ('b', 1003, 'BOG TE ŽIVI'), ('c', 1004, 'ČEŠNJE')])
        {'ID': id, 'Koda': koda, 'Naslov': naslov, 'Aktivna': true, 'Skupine': 's1'},
    ],
    'Besedila': [
      for (final id in ['a', 'b', 'c']) {'ID': 't$id', 'Pesem': id, 'Besedilo': 'Besedilo $id'},
    ],
    'Setliste': [
      {'ID': 'x', 'Skupina': 's1', 'Ime': 'Poroka', 'Datum': '2026-11-06T23:00:00.000Z'},
      {'ID': 'y', 'Skupina': 's1', 'Ime': 'Stara', 'Datum': '2025-01-01'},
    ],
    'Setlista pesmi': [
      {'ID': '1', 'Setlista': 'x', 'Zaporedje': 2, 'Pesem': 'a', 'Opomba': ''},
      {'ID': '2', 'Setlista': 'x', 'Zaporedje': 1, 'Pesem': 'c', 'Opomba': 'brez uvoda'},
      {'ID': '3', 'Setlista': 'x', 'Zaporedje': 3, 'Pesem': 'b', 'Opomba': ''},
    ],
  },
};

class _Streznik implements StreznikVodje {
  final poslano = <Map<String, dynamic>>[];
  void Function(Map<String, dynamic>)? odSledilca;

  @override
  Future<String> zacni(
    Baza baza,
    void Function(int) obSpremembi, {
    void Function(Map<String, dynamic>)? obSporocilu,
  }) async {
    odSledilca = obSporocilu;
    return 'http://10.0.0.2:8765';
  }

  @override
  void poslji(String sporocilo) => poslano.add(jsonDecode(sporocilo) as Map<String, dynamic>);

  @override
  Future<void> ustavi() async {}
}

class _Sledilec extends Spil {
  _Sledilec() : super(iskalec: () => const Stream.empty());

  void dobi(StanjeSpila s) {
    vloga = VlogaSpila.sledilec;
    povezan = true;
    stanje = s;
    notifyListeners();
  }
}

Future<(Baza, Api, List<Map<String, dynamic>>)> _baza() async {
  final poslano = <Map<String, dynamic>>[];
  final api = Api(
    () async => 'z',
    url: 'https://example.com/exec',
    client: MockClient((r) async {
      if (r.method == 'GET') return http.Response.bytes(utf8.encode(jsonEncode(_podatki())), 200);
      final telo = jsonDecode(r.body) as Map<String, dynamic>;
      poslano.add(telo);
      final sl = telo['setlista'] as Map<String, dynamic>;
      if (telo['izbrisi'] == true) return http.Response(jsonEncode({'izbrisano': sl['ID']}), 200);
      final id = sl['ID'] ?? 'nova';
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'setlista': {...sl, 'ID': id},
            'pesmi': [
              for (final (i, p) in (telo['pesmi'] as List).indexed)
                {'ID': 'n$i', 'Setlista': id, 'Zaporedje': i + 1, ...(p as Map)},
            ],
          }),
        ),
        200,
      );
    }),
  );
  final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
  await baza.osvezi(api);
  return (baza, api, poslano);
}

void main() {
  test('setliste: vrstni red, datum po lokalnem času, shranjevanje in brisanje', () async {
    final (baza, api, poslano) = await _baza();
    expect(baza.setliste.map((s) => s.ime), ['Poroka', 'Stara']);
    expect(baza.pesmiSetlist['x']!.map((p) => p.pesem), ['c', 'a', 'b']);
    expect(datumIso(datumIz('2025-01-01')!), '2025-01-01');

    final nova = await baza.shraniSetlisto(
      api,
      {'Ime': 'Vaja', 'Datum': '2026-11-10', 'Skupina': 's1'},
      [(pesem: 'b', opomba: ''), (pesem: 'a', opomba: '2x refren')],
    );
    expect(nova.id, 'nova');
    expect(baza.pesmiSetlist['nova']!.map((p) => (p.pesem, p.opomba)), [('b', ''), ('a', '2x refren')]);
    expect(baza.setliste.first.ime, 'Vaja');

    // Ponovno shranjevanje zamenja pesmi, ne doda novih zraven.
    await baza.shraniSetlisto(api, {'ID': 'x', 'Ime': 'Poroka'}, [(pesem: 'a', opomba: '')]);
    expect(baza.pesmiSetlist['x']!.map((p) => p.pesem), ['a']);

    await baza.izbrisiSetlisto(api, 'x');
    expect(baza.setliste.any((s) => s.id == 'x'), isFalse);
    expect(baza.pesmiSetlist['x'], isNull);
    expect(poslano.last['izbrisi'], isTrue);
  });

  testWidgets('igranje po setlisti s seznamčkom: izbrana pesem se vrine, »na konec« pride po setlisti', (tester) async {
    late Baza baza;
    await tester.runAsync(() async => baza = (await _baza()).$1);
    final spil = Spil(streznik: () => null, iskalec: () => const Stream.empty());
    await tester.pumpWidget(
      MaterialApp(
        home: IgranjeZaslon(setlista: baza.setliste.first, baza: baza, prijava: Prijava(), spil: spil),
      ),
    );
    await tester.pumpAndSettle();
    expect(vNaslovu('ČEŠNJE'), findsOneWidget);

    spil.dodajNaslednjo(const Naslednja(pesem: 'b'));
    spil.dodajNaslednjo(const Naslednja(pesem: 'c', naKonec: true));
    await tester.pumpAndSettle();
    expect(find.text('BOG TE ŽIVI  (+1)'), findsOneWidget); // vrstica seznamčka

    await _naprej(tester);
    expect(vNaslovu('BOG TE ŽIVI'), findsOneWidget);
    expect(spil.naslednje.map((n) => n.pesem), ['c']); // odprta gre s seznamčka

    await _naprej(tester);
    expect(vNaslovu('BELO OBLEKO'), findsOneWidget); // spet po setlisti
    await _naprej(tester);
    expect(vNaslovu('BOG TE ŽIVI'), findsOneWidget);
    await _naprej(tester); // »na konec« pride po zadnji pesmi setliste
    expect(vNaslovu('ČEŠNJE'), findsOneWidget);
    expect(spil.naslednje, isEmpty);
  });

  test('časovnik runde je skupen: vodja ga pošlje, sledilec ga prevzame in pošlje gumbe vodji', () async {
    SharedPreferences.setMockInitialValues({});
    Runda.aplikacija = Runda();
    final baza = (await _baza()).$1;
    final streznik = _Streznik();
    final vodja = Spil(streznik: () => streznik);
    await vodja.zacniVoditi(baza);
    expect(streznik.poslano.last, {'vrsta': 'runda', 'pavza': null, 'tece': 0});
    await Runda.aplikacija.zacni(true);
    expect(streznik.poslano.last, {'vrsta': 'runda', 'pavza': true, 'tece': 0});
    // Sledilec pritisne ŠPILEJ: ukaz pride do vodje.
    streznik.odSledilca!({'vrsta': 'ukaz', 'ukaz': 'runda', 'akcija': 'zacni', 'pavza': false});
    await Future<void>.delayed(Duration.zero);
    expect(Runda.aplikacija.pavza, isFalse);
    expect(streznik.poslano.last['pavza'], isFalse);
    await vodja.ustavi();

    // Sledilec: stanje od vodje (teče že 90 s), gumbi gredo vodji.
    final sledilec = Runda();
    await sledilec.prevzemi({'vrsta': 'runda', 'pavza': false, 'tece': 90});
    expect(sledilec.pavza, isFalse);
    expect(sledilec.trenutno().inSeconds, inInclusiveRange(89, 92));
    final vodji = <Map<String, dynamic>>[];
    sledilec.vodji = vodji.add;
    await sledilec.zacni(true);
    expect(vodji.single, {'akcija': 'zacni', 'pavza': true});
    expect(sledilec.pavza, isFalse); // počaka na vodjo
  });

  testWidgets('playlista postane čakalna vrsta, pesem se odpre kot vsaka druga', (tester) async {
    late Baza baza;
    await tester.runAsync(() async => baza = (await _baza()).$1);
    final spil = Spil(streznik: () => null, iskalec: () => const Stream.empty());
    spil.dodajNaslednjo(const Naslednja(pesem: 'b'));
    await tester.pumpWidget(
      MaterialApp(
        home: SetlisteZaslon(baza: baza, prijava: Prijava(), spil: spil),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poroka'));
    await tester.pumpAndSettle();
    expect(spil.naslednje.map((n) => n.pesem), ['c', 'a', 'b']); // stara vrsta je zamenjana

    await tester.tap(find.text('BELO OBLEKO'));
    await tester.pumpAndSettle();
    expect(find.byType(IgranjeZaslon), findsNothing);
    expect(vNaslovu('BELO OBLEKO'), findsOneWidget);
    expect(spil.naslednje.map((n) => n.pesem), ['b']); // od izbrane naprej, odprta gre z vrste
    await _naprej(tester);
    expect(vNaslovu('BOG TE ŽIVI'), findsOneWidget);
    expect(spil.naslednje, isEmpty);
  });

  testWidgets('igranje po setlisti: naslednja in prejšnja pesem', (tester) async {
    late Baza baza;
    await tester.runAsync(() async => baza = (await _baza()).$1);
    final s = baza.setliste.first;
    await tester.pumpWidget(
      MaterialApp(
        home: IgranjeZaslon(setlista: s, baza: baza, prijava: Prijava()),
      ),
    );
    await tester.pumpAndSettle();
    expect(vNaslovu('ČEŠNJE'), findsOneWidget);
    expect(find.byTooltip('Naslednja pesem'), findsNothing); // brez spodnje vrstice playliste

    // Pesmi playliste so v iskalniku na vrhu, z ikono, številko in opombo.
    await tester.tap(find.byTooltip('Išči pesem'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('v-playlisti')), findsNWidgets(3));
    expect(find.textContaining('brez uvoda'), findsOneWidget);
    await tester.tap(find.byTooltip('Zapri'));
    await tester.pumpAndSettle();

    await _naprej(tester);
    expect(vNaslovu('BELO OBLEKO'), findsOneWidget);
    await _naprej(tester);
    expect(vNaslovu('BOG TE ŽIVI'), findsOneWidget);
    await _naprej(tester); // konec playliste: ostane zadnja
    expect(vNaslovu('BOG TE ŽIVI'), findsOneWidget);
    Midi.aplikacija.sprozi(DejanjeMidi.prejsnja);
    await tester.pumpAndSettle();
    expect(vNaslovu('BELO OBLEKO'), findsOneWidget);
  });

  testWidgets('urejanje setliste: dodaj s kodo in seznam setlist', (tester) async {
    late Baza baza;
    late Api api;
    await tester.runAsync(() async => (baza, api, _) = await _baza());
    final s = baza.setliste.first;
    await tester.pumpWidget(
      MaterialApp(
        home: UrejanjeSetlisteZaslon(baza: baza, api: api, setlista: s),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 pesmi. Vrstni red spremeniš z vlečenjem.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Dodaj s kodo'), '1003');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('4 pesmi. Vrstni red spremeniš z vlečenjem.'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: SetlisteZaslon(baza: baza, prijava: Prijava()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Poroka'), findsOneWidget);
    expect(find.textContaining('11. 2026 · 3 pesmi'), findsOneWidget);
  });

  testWidgets('vodja pošlje pesem iz setliste z mestom in tudi pesem izven setliste', (tester) async {
    late Baza baza;
    await tester.runAsync(() async => baza = (await _baza()).$1);
    final streznik = _Streznik();
    final spil = Spil(streznik: () => streznik);
    await spil.zacniVoditi(baza);
    await tester.pumpWidget(
      MaterialApp(
        home: IgranjeZaslon(setlista: baza.setliste.first, baza: baza, prijava: Prijava(), spil: spil),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Vodim, sledi 0'), findsOneWidget);
    expect(streznik.poslano.last, {'vrsta': 'stanje', 'pesem': 'c', 'setlista': 'x', 'indeks': 0});
    await _naprej(tester);
    expect(streznik.poslano.last, {'vrsta': 'stanje', 'pesem': 'a', 'setlista': 'x', 'indeks': 1});

    await tester.pumpWidget(
      MaterialApp(
        home: PesemZaslon(pesem: baza.pesem('b')!, baza: baza, prijava: Prijava(), spil: spil),
      ),
    );
    await tester.pumpAndSettle();
    expect(streznik.poslano.last, {'vrsta': 'stanje', 'pesem': 'b'});
  });

  testWidgets('sledilec samodejno pokaže pesem, ki jo izbere vodja', (tester) async {
    late Baza baza;
    await tester.runAsync(() async => baza = (await _baza()).$1);
    final spil = _Sledilec();
    final navigator = GlobalKey<NavigatorState>();
    final prijava = Prijava();
    SamodejnoSledenje(spil: spil, baza: baza, prijava: prijava, navigator: navigator);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: SetlisteZaslon(baza: baza, prijava: prijava, spil: spil),
      ),
    );
    expect(find.byTooltip('Špil'), findsOneWidget);

    spil.dobi(const StanjeSpila(pesem: 'b'));
    await tester.pumpAndSettle();
    expect(vNaslovu('BOG TE ŽIVI'), findsOneWidget);
    expect(find.byTooltip('Povezan z vodjo'), findsOneWidget);

    spil.dobi(const StanjeSpila(pesem: 'a', setlista: 'x', indeks: 1));
    await tester.pumpAndSettle();
    expect(vNaslovu('BELO OBLEKO'), findsOneWidget);
    expect(find.text('Sledim vodji · 2 / 3'), findsOneWidget);

    // Nazaj na seznam: sledenje ostane, naslednja pesem vodje se spet odpre.
    await tester.tap(find.text('Seznam'));
    await tester.pumpAndSettle();
    expect(find.text('Playliste'), findsOneWidget);
    spil.dobi(const StanjeSpila(pesem: 'c'));
    await tester.pumpAndSettle();
    expect(vNaslovu('ČEŠNJE'), findsOneWidget);
  });
}

/// Naslov pesmi v vrstici na vrhu zaslona.
Future<void> _naprej(WidgetTester tester) async {
  Midi.aplikacija.sprozi(DejanjeMidi.naslednja);
  await tester.pumpAndSettle();
}

Finder vNaslovu(String t) => find.descendant(of: find.byType(AppBar), matching: find.text(t));
