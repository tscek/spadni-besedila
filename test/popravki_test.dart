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
import 'package:spadni_besedila/risbe.dart';
import 'package:spadni_besedila/runda.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/spil/spil.dart';
import 'package:spadni_besedila/zasloni/iskalnik_pesmi.dart';
import 'package:spadni_besedila/zasloni/naslednje.dart';
import 'package:spadni_besedila/zasloni/pesem_zaslon.dart';
import 'package:spadni_besedila/zasloni/seznam_zaslon.dart';

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
    {'ID': 'c', 'Koda': 3, 'Naslov': 'ZABAVNA', 'Mapa': 'zab', 'Status': 'V delu', 'Aktivna': true},
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
    await tester.tap(find.text('Končano'));
    await tester.pumpAndSettle();
    expect(find.text('Končano'), findsNothing);
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
    // Tonaliteta v oblačku, ko je vklopljena.
    await Nastavitve.aplikacija.nastaviOblacekTonalitete(true);
    await tester.pumpWidget(
      MaterialApp(
        home: PesemZaslon(key: const ValueKey(2), pesem: baza.pesem('a')!, baza: baza, prijava: Prijava()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('F'), findsNWidgets(2));
    await Nastavitve.aplikacija.nastaviOblacekTonalitete(false);
    await tester.tap(find.byTooltip('Išči pesem'));
    await tester.pumpAndSettle();
    final iskalnik = find.byType(IskalnikPesmi);
    expect(find.descendant(of: iskalnik, matching: find.byIcon(Icons.pause)), findsOneWidget);
    expect(find.descendant(of: iskalnik, matching: find.text('0 PAVZA')), findsNothing);
    // Odigrana pesem ima samo naslov (brez podatkov pod njim).
    expect(find.descendant(of: iskalnik, matching: find.text('B')), findsNothing);
    expect(find.descendant(of: iskalnik, matching: find.text('Valček')), findsWidgets);

    await tester.tap(find.descendant(of: iskalnik, matching: find.widgetWithText(FilterChip, 'Polka')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: iskalnik, matching: find.text('AVSENIK')), findsOneWidget);
    expect(find.descendant(of: iskalnik, matching: find.text('BELO OBLEKO')), findsNothing);

    // Dotik mimo iskalnika ga zapre; ob ponovnem odprtju filtrov ni več.
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();
    expect(find.byType(IskalnikPesmi), findsNothing);
    await tester.tap(find.byTooltip('Išči pesem'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(IskalnikPesmi), matching: find.text('BELO OBLEKO')), findsOneWidget);
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
