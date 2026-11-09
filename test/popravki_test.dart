import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/models.dart';
import 'package:spadni_besedila/nastavitve.dart';
import 'package:spadni_besedila/odigrane.dart';
import 'package:spadni_besedila/posodobitev.dart';
import 'package:spadni_besedila/prijava.dart';
import 'package:spadni_besedila/risbe.dart' hide Orodje;
import 'package:spadni_besedila/runda.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/spil/spil.dart';
import 'package:spadni_besedila/zasloni/besedilo_risanje.dart';
import 'package:spadni_besedila/zasloni/iskalnik_pesmi.dart';
import 'package:spadni_besedila/zasloni/naslednje.dart';
import 'package:spadni_besedila/zasloni/oznake.dart' show kontrastnaBarva;
import 'package:spadni_besedila/zasloni/pesem_zaslon.dart';
import 'package:spadni_besedila/zasloni/seznam_zaslon.dart';
import 'package:spadni_besedila/zasloni/youtube.dart';

const _tabele = {
  'Pesmi': [
    {
      'ID': 'a',
      'Koda': 1,
      'Naslov': 'BELO OBLEKO',
      'Mapa': 'nz',
      'Harmonika': 'C-F-B',
      'Tonaliteta': 'F',
      'Vrsta': 'Valček',
      'Ocena': 4,
      'Aktivna': true,
    },
    {
      'ID': 'b',
      'Koda': 2,
      'Naslov': 'AVSENIK',
      'Mapa': 'nz',
      'Harmonika': 'B-Es-As',
      'Tonaliteta': 'B',
      'Vrsta': 'Polka',
      'Aktivna': true,
    },
    {
      'ID': 'c',
      'Koda': 3,
      'Naslov': 'ZABAVNA',
      'Mapa': 'zab',
      'Status': 'V delu',
      'Aktivna': true,
      'YouTube': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10s',
    },
    {'ID': 'd', 'Koda': 4, 'Naslov': 'STARA', 'Mapa': 'nz', 'Status': 'Arhiv', 'Aktivna': true},
    {'ID': 'e', 'Koda': 5, 'Naslov': '0 PAVZA', 'Mapa': 'nz', 'Aktivna': true},
  ],
  'Besedila': [
    {'ID': 't', 'Pesem': 'a', 'Besedilo': '[C]Belo obleko [G7]si že nosila\nla la la'},
  ],
  'Mape': [
    {'ID': 'zab', 'Ime': 'Zabavne', 'Vrstni red': 2},
    {'ID': 'nz', 'Ime': 'Narodno-zabavne', 'Vrstni red': 1, 'Pavza': 'e'},
  ],
  'Harmonike': [
    {'ID': 'h1', 'Ime': 'C-F-B', 'Barva': '#1E88E5', 'Vrstni red': 1},
    {'ID': 'h2', 'Ime': 'B-Es-As', 'Barva': '#E53935', 'Vrstni red': 2},
  ],
};

Future<(Baza, List<Map<String, dynamic>>)> _baza() async {
  final poslano = <Map<String, dynamic>>[];
  final baza = Baza(shramba: _Pomnilnik());
  await baza.osvezi(
    Api(
      () async => 'z',
      url: 'https://example.com/exec',
      client: MockClient((r) async => http.Response.bytes(utf8.encode(jsonEncode({'tabele': _tabele})), 200)),
    ),
  );
  return (baza, poslano);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Nastavitve.aplikacija = Nastavitve();
    Odigrane.aplikacija = Odigrane();
    Runda.aplikacija = Runda();
  });

  test('zasedbe: član v dveh izbere eno, pesmi in setliste po zasedbi', () async {
    final baza = Baza(shramba: _Pomnilnik());
    final podatki = {
      'clan': {
        'ID': 'C',
        'Zasedbe': ['s1', 's2'],
      },
      'tabele': {
        'Skupine': [
          {'ID': 's1', 'Ime': 'Špadni fantje'},
          {'ID': 's2', 'Ime': 'Trijorijo'},
        ],
        'Pesmi': [
          {'ID': 'a', 'Naslov': 'OBE', 'Skupine': 's1, s2', 'Aktivna': true},
          {'ID': 'b', 'Naslov': 'ŠPADNI', 'Skupine': 's1', 'Aktivna': true},
          {'ID': 'c', 'Naslov': 'TRIJORIJO', 'Skupine': 's2', 'Aktivna': true},
        ],
        'Setliste': [
          {'ID': 'x', 'Ime': 'Poroka', 'Skupina': 's2'},
        ],
      },
    };
    await baza.osvezi(
      Api(
        () async => 'z',
        url: 'https://example.com/exec',
        client: MockClient((r) async => http.Response.bytes(utf8.encode(jsonEncode(podatki)), 200)),
      ),
    );
    expect(baza.moraIzbratiZasedbo, isTrue);
    expect(baza.mojeZasedbe.map((z) => z.ime), ['Špadni fantje', 'Trijorijo']);
    expect(baza.pesmi.length, 3); // dokler ne izbere, vidi vse

    await baza.izberiZasedbo('s2');
    expect(baza.moraIzbratiZasedbo, isFalse);
    expect(baza.pesmi.map((p) => p.id), unorderedEquals(['a', 'c']));
    expect(baza.setliste.single.id, 'x');
    await baza.izberiZasedbo('s1');
    expect(baza.pesmi.map((p) => p.id), unorderedEquals(['a', 'b']));
    expect(baza.setliste, isEmpty);
    expect(Nastavitve.aplikacija.zasedba, 's1'); // zapomni se
  });

  test('mape, harmonike, status in razvrščanje po poljih', () async {
    final (baza, _) = await _baza();
    expect(baza.mape.map((m) => m.ime), ['Narodno-zabavne', 'Zabavne']);
    expect(baza.pesmiMape('nz').map((p) => p.id), ['a', 'b', 'e']); // arhivirana ni v mapi
    expect(baza.pesmiMape(null).map((p) => p.id), ['a', 'b', 'c', 'e']);
    expect(baza.mapa('nz')!.pavza, 'e');
    expect(baza.arhiv.single.id, 'd');
    expect(baza.harmonika('B-Es-As')?.argb, 0xFFE53935);
    expect(baza.pesem('c')!.status, StatusPesmi.vDelu);
    expect(baza.pesem('a')!.ocena, 4);

    final pesmi = baza.pesmiMape(null)..sort(PoljePesmi.naslov.primerjaj);
    expect(pesmi.map((p) => p.naslov), ['0 PAVZA', 'AVSENIK', 'BELO OBLEKO', 'ZABAVNA']);
    pesmi.sort(PoljePesmi.tonaliteta.primerjaj);
    expect(pesmi.first.tonaliteta, 'F'); // F je pred B, prazna na koncu
    expect(menjaHarmoniko(baza.pesem('a'), baza.pesem('b')), isTrue);
    expect(menjaHarmoniko(baza.pesem('a'), baza.pesem('c')), isFalse); // brez harmonike
  });

  test('klicaji na mestu: brez interneta počakajo, več na pesem, brisanje še neposlanega', () async {
    final (baza, _) = await _baza();
    final k1 = await baza.dodajKlicaj(null, 'a', 0, 0.5, 0.2, clan: 'C');
    final k2 = await baza.dodajKlicaj(null, 'a', 1, 0.1, 0.9, clan: 'C');
    expect(baza.pesem('a')!.klicaji, 2);
    expect(baza.pesmiSKlicaji.single.id, 'a');
    expect(baza.klicaji['a']!.first.x, 0.5);
    expect(baza.neposlano.map((n) => n['akcija']), ['klicaj', 'klicaj']);

    // Klicaj, ki še ni bil poslan, se ob brisanju samo umakne iz čakanja.
    await baza.izbrisiKlicaj(null, k2.id);
    expect(baza.pesem('a')!.klicaji, 1);
    expect(baza.neposlano, hasLength(1));

    final poslano = <Map<String, dynamic>>[];
    final api = Api(
      () async => 'z',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        final telo = jsonDecode(r.body) as Map<String, dynamic>;
        poslano.add(telo);
        final k = telo['klicaj'] as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(jsonEncode(telo['izbrisi'] == true ? {'izbrisano': k['ID']} : {'vrstica': k})),
          200,
        );
      }),
    );
    expect(await baza.posljiNeposlano(api), isNull);
    expect(poslano.single['akcija'], 'klicaj');
    expect((poslano.single['klicaj'] as Map)['ID'], k1.id);
    expect((poslano.single['klicaj'] as Map)['Član'], 'C');

    await baza.izbrisiKlicaj(api, k1.id);
    expect(poslano.last['izbrisi'], isTrue);
    expect(baza.pesem('a')!.zaVajo, isFalse);
    expect(baza.neposlano, isEmpty);
  });

  test('dnevnik odprtih pesmi počaka na internet in se pošlje v paketu', () async {
    final (baza, _) = await _baza();
    await baza.zabelezi(null, {'pesem': 'a', 'trajanje': 120});
    await baza.zabelezi(null, {'pesem': 'b', 'trajanje': 30});
    expect(baza.dnevnik, hasLength(2));
    final poslano = <Map<String, dynamic>>[];
    final api = Api(
      () async => 'z',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        poslano.add(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'zapisano': 2}), 200);
      }),
    );
    await baza.posljiDnevnik(api);
    expect(poslano.single['akcija'], 'dnevnik');
    expect((poslano.single['vrstice'] as List).map((v) => v['pesem']), ['a', 'b']);
    expect(baza.dnevnik, isEmpty);
  });

  test('odigrane pesmi in časovnik runde se zapomnijo', () async {
    await Odigrane.aplikacija.oznaci('a');
    final o = Odigrane();
    await o.nalozi();
    expect(o.je('a'), isTrue);
    expect(o.je('a', zdaj: DateTime.now().add(const Duration(hours: 13))), isFalse);

    final r = Runda.aplikacija;
    final t = DateTime(2026, 10, 30, 21);
    await r.zacni(false, zdaj: t);
    await r.zacni(true, zdaj: t.add(const Duration(minutes: 45)));
    expect(r.pavza, isTrue);
    expect(r.zgodovina.single.trajanje, const Duration(minutes: 45));
    expect(r.zgodovina.single.pavza, isFalse);
    final nova = Runda();
    await nova.nalozi();
    expect(nova.pavza, isTrue);
    expect(nova.zgodovina, hasLength(1));
    expect(casBesedilo(const Duration(minutes: 65, seconds: 7)), '1:05:07');
    await r.ponastavi();
    expect(r.zgodovina, isEmpty);
  });

  test('risba z oznakami in gumbi ostane enaka po shranjevanju', () {
    final r = Risba(
      oznake: {
        0: [Oznaka(obmocje: const Rect.fromLTRB(0.1, 0.2, 0.5, 0.25), barva: 0xFFFFEB3B)],
      },
      gumbi: {
        0: [GumbNaStrani(polozaj: const Offset(0.3, 0.4), napis: 'Solo', midi: 'PC 1 5', barva: 0xFF1976D2)],
      },
    );
    final k = Risba.izBesedila(r.vBesedilo());
    expect(k.oznake[0]!.single.obmocje, const Rect.fromLTRB(0.1, 0.2, 0.5, 0.25));
    expect(k.gumbi[0]!.single.napis, 'Solo');
    expect(k.gumbi[0]!.single.midi, 'PC 1 5');
    expect(k.prazna, isFalse);
    k.izbrisiStrani((s) => s == 0);
    expect(k.prazna, isTrue);
  });

  testWidgets('začetni meni map: mapa pokaže samo svoje pesmi, brez kode', (tester) async {
    late Baza baza;
    await tester.runAsync(() async => baza = (await _baza()).$1);
    await tester.pumpWidget(
      MaterialApp(
        home: SeznamZaslon(
          prijava: Prijava(),
          baza: baza,
          posodobitev: Posodobitev(),
          spil: Spil(streznik: () => null, iskalec: () => const Stream.empty()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mape'), findsOneWidget);
    expect(find.text('Narodno-zabavne'), findsOneWidget);
    expect(find.text('Arhiv'), findsOneWidget);

    await tester.tap(find.text('Narodno-zabavne'));
    await tester.pumpAndSettle();
    expect(find.text('BELO OBLEKO'), findsOneWidget);
    expect(find.text('ZABAVNA'), findsNothing);
    expect(find.text('STARA'), findsNothing);
    expect(find.text('1'), findsNothing); // koda ni prikazana

    // Pridržanje: čakalna vrsta in (za urejevalce) playlista, mapa, arhiv.
    await tester.longPress(find.text('AVSENIK'));
    await tester.pumpAndSettle();
    expect(find.text('Dodaj kot naslednjo'), findsOneWidget);
    expect(find.text('Dodaj na konec setliste'), findsNothing);
    await tester.tap(find.text('Dodaj v čakalno vrsto'));
    await tester.pumpAndSettle();

    // Hitri filter po harmoniki.
    await tester.tap(find.widgetWithText(FilterChip, 'B-Es-As'));
    await tester.pumpAndSettle();
    expect(find.text('BELO OBLEKO'), findsNothing);
    expect(find.text('AVSENIK'), findsWidgets);
    await tester.tap(find.widgetWithText(FilterChip, 'Vse'));
    await tester.pumpAndSettle();
    expect(find.text('BELO OBLEKO'), findsOneWidget);

    // Gumb +: nova čakalna vrsta jo izprazni.
    await tester.tap(find.byTooltip('Novo'));
    await tester.pumpAndSettle();
    expect(find.text('Nova pesem'), findsOneWidget);
    expect(find.text('Nova playlista'), findsOneWidget);
    await tester.tap(find.text('Nova čakalna vrsta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Izprazni'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vse'));
    await tester.pumpAndSettle();
    expect(find.text('ZABAVNA'), findsOneWidget);
  });

  testWidgets('zgornja vrstica: dolg naslov v dveh vrsticah, barva po izbiri', (tester) async {
    late Baza baza;
    await tester.runAsync(() async => baza = (await _baza()).$1);
    await Nastavitve.aplikacija.nastaviBarvoVrstice(zgoraj: true, barva: 0xFF000000);
    Future<Text> naslov(double sirina) async {
      tester.view.physicalSize = Size(sirina, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: PesemZaslon(key: UniqueKey(), pesem: baza.pesem('a')!, baza: baza, prijava: Prijava()),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<Text>(find.text('BELO OBLEKO'));
    }

    addTearDown(tester.view.reset);
    final siroko = await naslov(1000);
    expect(siroko.maxLines, 1);
    expect(siroko.style?.color, Colors.white); // bela na črni
    expect((await naslov(220)).maxLines, 2);
  });

  testWidgets('pisava pesmi je skupna; gumbe zanjo ima samo urednik', (tester) async {
    late Baza baza;
    await tester.runAsync(() async => baza = (await _baza()).$1);
    expect(Pesem.izVrstice({'ID': 'x', 'Pisava': '26'}).pisava, 26);
    expect(Pesem.izVrstice({'ID': 'x'}).pisava, 22);
    await Nastavitve.aplikacija.nastaviOrodje(Orodje.pisava, Mesto.zgoraj);
    await tester.pumpWidget(
      MaterialApp(
        home: PesemZaslon(pesem: baza.pesem('a')!, baza: baza, prijava: Prijava()),
      ),
    );
    await tester.pumpAndSettle();
    expect(baza.smeUrejati, isFalse);
    expect(find.byTooltip('Večja pisava'), findsNothing);
  });

  testWidgets('dolgo besedilo: puščica spodaj, dotik pomakne naprej; kratko gre celo na zaslon', (tester) async {
    late Baza baza;
    await tester.runAsync(() async => baza = (await _baza()).$1);
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget besedilo(String vsebina) => MaterialApp(
      home: Scaffold(
        body: BesediloZRisanjem(
          key: ValueKey(vsebina.length),
          vsebina: vsebina,
          pesem: 'a',
          risbe: baza.risbe,
          risanje: ValueNotifier(false),
          knjiznica: baza.midi,
        ),
      ),
    );
    await tester.pumpWidget(besedilo(List.generate(60, (i) => 'Vrstica številka $i').join('\n')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('puscica-naprej')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('puscica-naprej')));
    await tester.pumpAndSettle();
    final pomik = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first).controller!;
    expect(pomik.offset, greaterThan(400));

    await tester.pumpWidget(besedilo('Kratka pesem\nDve vrstici'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('puscica-naprej')), findsNothing);
  });

  testWidgets('pesem: pridržanje vklopi risanje, trojni dotik postavi klicaj', (tester) async {
    late Baza baza;
    await tester.runAsync(() async => baza = (await _baza()).$1);
    await tester.pumpWidget(
      MaterialApp(
        // Brez animacij klicaj ne utripa (sicer pumpAndSettle nikoli ne konča).
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: PesemZaslon(pesem: baza.pesem('a')!, baza: baza, prijava: Prijava()),
      ),
    );
    await tester.pumpAndSettle();
    // Spodnja vrstica: tonaliteta in harmonika levo, iskanje vedno desno.
    expect(find.text('F · C-F-B'), findsOneWidget);
    expect(find.byTooltip('Išči pesem'), findsOneWidget);

    final besedilo = find.text('la la la');
    for (var i = 0; i < 3; i++) {
      await tester.tap(besedilo);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(baza.pesem('a')!.klicaji, 1);
    expect(find.text('!'), findsWidgets);
    final k = baza.klicaji['a']!.single;
    expect(k.stran, 0);
    expect(k.x, inInclusiveRange(0, 1));
    await tester.pump(const Duration(seconds: 3)); // obvestilo izgine
    await tester.pumpAndSettle();

    // Pridržanje na klicaju: kdo in kdaj, brisanje.
    await tester.longPress(besedilo);
    await tester.pumpAndSettle();
    expect(find.textContaining('Dodal:'), findsOneWidget);
    await tester.tap(find.text('Izbriši'));
    await tester.pumpAndSettle();
    expect(baza.pesem('a')!.klicaji, 0);

    await tester.longPress(besedilo);
    await tester.pumpAndSettle();
    expect(find.text('Končano'), findsOneWidget);
    expect(find.byTooltip('Označi besedilo'), findsOneWidget);
    // Markiranje čez dve vrstici naredi oznako v vsaki vrstici.
    await tester.tap(find.byTooltip('Označi besedilo'));
    await tester.pump();
    final od = tester.getCenter(find.text('Belo obleko '));
    final doo = tester.getCenter(besedilo);
    final g = await tester.startGesture(od);
    for (var i = 1; i <= 5; i++) {
      await g.moveTo(Offset.lerp(od, doo, i / 5)!);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await g.up();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    Risba? risba;
    baza.risbe.nalozi('a').then((r) => risba = r);
    await tester.pump();
    expect(risba!.oznake[0], hasLength(2));
    // Oznaki sta vezani na vrstici besedila (ne na mesto na strani).
    expect(risba!.oznake[0]!.map((o) => (o.vrstica, o.besedilo)), [(0, 'Belo obleko si že nosila'), (1, 'la la la')]);
    await tester.tap(find.text('Končano'));
    await tester.pumpAndSettle();
    expect(find.text('Končano'), findsNothing);
  });

  testWidgets('oznaka ostane na svoji vrstici, tudi če se vrstice premaknejo; skupne vidijo vsi', (tester) async {
    late Baza baza;
    await tester.runAsync(() async {
      baza = (await _baza()).$1;
      // Osebna oznaka je bila narisana, ko je bila »la la la« prva vrstica; zdaj je druga.
      await baza.risbe.shrani(
        'a',
        Risba(
          oznake: {
            0: [Oznaka(obmocje: Rect.zero, barva: 0xFFFFEB3B, vrstica: 0, besedilo: 'la la la', od: 0, doo: 0.5)],
          },
        ),
      );
      // Skupna oznaka (refren) na prvi vrstici.
      await baza.risbeSkupne.shrani(
        'a',
        Risba(
          oznake: {
            0: [Oznaka(obmocje: Rect.zero, barva: 0xFF4CAF50, vrstica: 0, besedilo: 'Belo obleko si že nosila')],
          },
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PesemZaslon(pesem: baza.pesem('a')!, baza: baza, prijava: Prijava()),
      ),
    );
    await tester.pumpAndSettle();
    int oznakPod(String besedilo) => find
        .descendant(
          of: find.ancestor(of: find.text(besedilo), matching: find.byType(KeyedSubtree)).first,
          matching: find.byType(CustomPaint),
        )
        .evaluate()
        .length;
    expect(oznakPod('la la la'), 1);
    expect(oznakPod('Belo obleko '), 1);
  });

  testWidgets('iskalnik: pavza na vrhu, hitri filtri, zapre se ob dotiku mimo', (tester) async {
    late Baza baza;
    await tester.runAsync(() async => baza = (await _baza()).$1);
    await Odigrane.aplikacija.oznaci('b');
    await tester.pumpWidget(
      MaterialApp(
        home: PesemZaslon(pesem: baza.pesem('a')!, baza: baza, prijava: Prijava()),
      ),
    );
    await tester.pumpAndSettle();
    // Vrstica pod orodno vrstico: naslov in tonaliteta (naslova v orodni vrstici ni).
    expect(find.text('BELO OBLEKO'), findsOneWidget);
    // Naslov dobi preostalo širino, tonaliteta le svojo.
    expect(
      tester.getSize(find.text('BELO OBLEKO')).width,
      greaterThan(tester.getSize(find.descendant(of: find.byType(AppBar), matching: find.text('F'))).width),
    );
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(Expanded)), findsOneWidget);
    // Oblački: tonaliteta desno, harmonika (prazna se skrije) in BPM levo, zloženi navzdol.
    await Nastavitve.aplikacija.nastaviOblacke(const [
      Oblacek(vsebina: InfoVrstice.tonaliteta, velikost: 2),
      Oblacek(vsebina: InfoVrstice.ocena, levo: true),
      Oblacek(vsebina: InfoVrstice.naslov, levo: true, barva: 0xFF000000),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PesemZaslon(key: const ValueKey(2), pesem: baza.pesem('a')!, baza: baza, prijava: Prijava()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('F'), findsNWidgets(2));
    expect(find.descendant(of: find.byKey(const ValueKey('oblacki-desno')), matching: find.text('F')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('oblacki-levo')), matching: find.text('BELO OBLEKO')),
      findsOneWidget,
    );
    // Naslov v črnem oblačku je bel.
    final naslov = tester.widget<Text>(
      find.descendant(of: find.byKey(const ValueKey('oblacki-levo')), matching: find.text('BELO OBLEKO')),
    );
    expect(naslov.style?.color, kontrastnaBarva(const Color(0xFF000000)));
    await Nastavitve.aplikacija.nastaviOblacke(const []);
    await tester.tap(find.byTooltip('Išči pesem'));
    await tester.pumpAndSettle();
    final iskalnik = find.byType(IskalnikPesmi);
    expect(find.descendant(of: iskalnik, matching: find.byIcon(Icons.pause)), findsOneWidget);
    expect(find.descendant(of: iskalnik, matching: find.text('0 PAVZA')), findsNothing);
    // Igrana pesem je ob listanju skrita (privzeta nastavitev); z vpisano besedo se najde, samo z naslovom.
    expect(find.descendant(of: iskalnik, matching: find.text('AVSENIK')), findsNothing);
    expect(find.descendant(of: iskalnik, matching: find.text('Valček')), findsWidgets);
    await tester.enterText(find.descendant(of: iskalnik, matching: find.byType(TextField)), 'avs');
    await tester.pumpAndSettle();
    expect(find.descendant(of: iskalnik, matching: find.text('AVSENIK')), findsOneWidget);
    expect(find.descendant(of: iskalnik, matching: find.text('B')), findsNothing);
    await tester.enterText(find.descendant(of: iskalnik, matching: find.byType(TextField)), '');
    await Nastavitve.aplikacija.nastaviSkrijIgrane(false);
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: iskalnik, matching: find.widgetWithText(FilterChip, 'Polka')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: iskalnik, matching: find.text('AVSENIK')), findsOneWidget);
    expect(find.descendant(of: iskalnik, matching: find.text('BELO OBLEKO')), findsNothing);
    await Nastavitve.aplikacija.nastaviSkrijIgrane(true);

    // Dotik mimo iskalnika ga zapre; ob ponovnem odprtju filtrov ni več.
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();
    expect(find.byType(IskalnikPesmi), findsNothing);
    await tester.tap(find.byTooltip('Išči pesem'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(IskalnikPesmi), matching: find.text('BELO OBLEKO')), findsOneWidget);
  });

  test('YouTube: ID iz različnih povezav', () {
    expect(idYoutube('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10s'), 'dQw4w9WgXcQ');
    expect(idYoutube('youtu.be/dQw4w9WgXcQ?si=abc'), 'dQw4w9WgXcQ');
    expect(idYoutube('https://m.youtube.com/shorts/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(idYoutube('https://music.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(idYoutube(' dQw4w9WgXcQ '), 'dQw4w9WgXcQ');
    expect(idYoutube('https://www.youtube.com/@spadnifantje'), isNull);
    expect(idYoutube('https://example.com/watch?v=dQw4w9WgXcQ'), isNull);
    expect(idYoutube(''), isNull);
  });

  testWidgets('YouTube: gumb samo pri pesmi s povezavo, okno se odpre in zapre', (tester) async {
    YoutubePesmi.predvajalnikZaTest = (id) => Text('video $id');
    addTearDown(() => YoutubePesmi.predvajalnikZaTest = null);
    late Baza baza;
    await tester.runAsync(() async => baza = (await _baza()).$1);
    await tester.pumpWidget(
      MaterialApp(
        home: PesemZaslon(key: UniqueKey(), pesem: baza.pesem('b')!, baza: baza, prijava: Prijava()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('youtube')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: PesemZaslon(key: UniqueKey(), pesem: baza.pesem('c')!, baza: baza, prijava: Prijava()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('youtube')));
    await tester.pumpAndSettle();
    expect(find.text('video dQw4w9WgXcQ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('youtube-zapri')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('youtube-okno')), findsNothing);
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
