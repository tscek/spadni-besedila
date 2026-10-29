import 'dart:typed_data';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/midi/midi.dart';
import 'package:spadni_besedila/midi/prenos.dart';
import 'package:spadni_besedila/midi/ukazi.dart';
import 'package:spadni_besedila/models.dart';
import 'package:spadni_besedila/prijava.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/zasloni/iskalnik_pesmi.dart';
import 'package:spadni_besedila/zasloni/midi_zaslon.dart';
import 'package:spadni_besedila/zasloni/pesem_zaslon.dart';
import 'package:spadni_besedila/zasloni/setliste_zaslon.dart';
import 'package:spadni_besedila/zasloni/urejanje_pesmi.dart';

class _Prenos implements MidiPrenos {
  final poslano = <String>[];
  List<NapravaMidi> seznam = const [
    NapravaMidi('a', 'WIDI', 'Bluetooth', true),
    NapravaMidi('b', 'USB MIDI', 'USB', true),
  ];

  @override
  Future<List<NapravaMidi>> naprave() async => seznam;
  @override
  Future<void> zacniIskanje() async {}
  @override
  void ustaviIskanje() {}
  @override
  Future<void> povezi(String id) async {}
  @override
  void prekini(String id) {}
  @override
  void poslji(Uint8List bajti, String id) => poslano.add('$id ${bajti.join(' ')}');
  @override
  Stream<void> get spremembe => const Stream.empty();
  @override
  Stream<(String, Uint8List)> get prejeto => const Stream.empty();
}

KnjiznicaMidi _knjiznica() => KnjiznicaMidi.izTabel(_tabele);

void main() {
  test('bajti ukazov', () {
    expect(razcleniUkaz('CC 9 12 127')!.bajti, [0xB8, 12, 127]);
    expect(razcleniUkaz('PC 7 1')!.bajti, [0xC6, 1]);
    expect(razcleniUkaz('Nota 10 20 1')!.bajti, [0x99, 20, 1]);
    expect(razcleniUkaz('Nota 10 20 1')!.bajtiKonca, [0x89, 20, 0]);
    expect(razcleniUkaz('3|7|15|0|23')!.zapis, 'CC 15 0 23');
    expect(razcleniUkaz('3|5|7|2|0')!.zapis, 'PC 7 2');
    expect(razcleniUkaz('Delay ON'), isNull);
  });

  test('razširitev makrov z izhodi', () {
    final k = _knjiznica();
    final r = k.razsiri('Vse');
    expect(
      [for (final u in r) '${u.ukaz.zapis} > ${u.izhod}'],
      [
        'CC 9 12 127 > Miza', // ukaz brez izhoda dobi izhod makra
        'PC 5 3 > Luči', // ukaz s svojim izhodom gre tja
        'CC 15 0 4 > Miza',
        'Nota 10 20 1 > Privzeti',
      ],
    );
    expect(k.imeKanala(9), 'MixingStation');
    expect(k.izhodi, containsAll([privzetiIzhod, 'Luči', 'Miza']));
    expect(k.razsiri('delay on').single.ukaz.ime, 'Delay ON');
    expect(k.razsiri('Ne obstaja'), isEmpty);
  });

  test('ob odprtju in zaprtju', () {
    final k = _knjiznica();
    final p = Pesem.izVrstice({
      'ID': 'p1',
      'Koda': 1,
      'Naslov': 'A',
      'MIDI ob odprtju': '3|7|15|0|7',
      'Makro ob odprtju': 'Delay ON',
      'Makro ob zaprtju': 'Luči pavza',
    });
    expect(k.obOdprtju(p).map((u) => u.ukaz.zapis), ['CC 15 0 7', 'CC 9 12 127']);
    expect(k.obZaprtju(p).map((u) => u.ukaz.zapis), ['PC 5 3']);
  });

  test('pošiljanje na naprave po izhodih in zaprtje prejšnje pesmi', () async {
    SharedPreferences.setMockInitialValues({'midi_vklop': true});
    final prenos = _Prenos();
    final midi = Midi(prenos);
    await midi.nalozi();
    await midi.osveziNaprave();
    await midi.nastaviIzhod('Luči', 'USB MIDI');
    await midi.nastaviIzhod('Miza', nePosiljaj);
    final k = _knjiznica();

    final a = Pesem.izVrstice({'ID': 'a', 'Koda': 1, 'Naslov': 'A', 'Makro ob odprtju': 'Delay ON'});
    final b = Pesem.izVrstice({'ID': 'b', 'Koda': 2, 'Naslov': 'B', 'Makro ob zaprtju': 'Luči pavza'});

    await midi.odprta(b, k);
    expect(prenos.poslano, isEmpty);
    // Nova pesem se odpre, preden se stara zapre (setlista): najprej zaprtje B, nato odprtje A.
    await midi.odprta(a, k);
    await midi.zaprta(b);
    expect(prenos.poslano, [
      'b 196 3', // PC 5 3: Luči → USB MIDI
      'a 184 12 127', // CC 9 12 127: Privzeti → vse povezane
      'b 184 12 127',
    ]);

    prenos.poslano.clear();
    await midi.poslji(k.razsiri('Pavza'), knjiznica: k);
    // Miza je izklopljena, Luči gre na USB.
    expect(prenos.poslano, ['b 196 3']);
    expect(midi.dnevnik.first.naprave, isEmpty);
  });

  testWidgets('knjižnica MIDI in zavihek MIDI pri pesmi', (tester) async {
    final poslano = <Map<String, dynamic>>[];
    final api = Api(
      () async => 'z',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        if (r.method == 'GET') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'vloge': [
                  {'Skupina': 's1', 'Vloga': 'Urejevalec'},
                ],
                'tabele': {
                  'Pesmi': [
                    {
                      'ID': 'p',
                      'Koda': 1,
                      'Naslov': 'A',
                      'Aktivna': true,
                      'Skupine': 's1',
                      'Makro ob zaprtju': 'Pavza',
                    },
                  ],
                  'MIDI ukazi': _tabele['MIDI ukazi'],
                  'Makri': _tabele['Makri'],
                  'MIDI kanali': _tabele['MIDI kanali'],
                },
              }),
            ),
            200,
          );
        }
        final telo = jsonDecode(r.body) as Map<String, dynamic>;
        poslano.add(telo);
        final v = telo['vrstica'] as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'vrstica': telo['tabela'] == 'MIDI kanali' ? {'Kanal': int.parse(v['ID']), 'Ime': v['Ime']} : v,
            }),
          ),
          200,
        );
      }),
    );
    final baza = Baza(shramba: _Pomnilnik());
    await tester.runAsync(() => baza.osvezi(api));
    expect(baza.midi.ukazi, hasLength(3));

    await tester.runAsync(() => baza.shraniMidi(api, 'MIDI kanali', {'ID': '3', 'Ime': 'Harmonika'}));
    expect(poslano.single['akcija'], 'midi');
    expect(baza.midi.imeKanala(3), 'Harmonika');
    expect(baza.midi.imeKanala(9), 'MixingStation');

    await tester.pumpWidget(
      MaterialApp(
        home: MidiKnjiznicaZaslon(baza: baza, prijava: Prijava()),
      ),
    );
    expect(find.text('Delay ON'), findsOneWidget);
    expect(find.text('CC · kanal 9 (MixingStation) · kontroler 12 = 127'), findsOneWidget);
    await tester.tap(find.text('Makri'));
    await tester.pumpAndSettle();
    expect(find.text('Pavza'), findsOneWidget);
    await tester.tap(find.text('Kanali'));
    await tester.pumpAndSettle();
    expect(find.text('Harmonika'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: UrejanjePesmiZaslon(baza: baza, api: api, pesem: baza.pesmi.single, zavihek: 4),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Makro ob zaprtju'), findsOneWidget);
    // Predogled: makro Pavza se razširi v ukaze z izhodi.
    expect(find.text('Delay ON: CC · kanal 9 (MixingStation) · kontroler 12 = 127 → Miza'), findsOneWidget);
    expect(find.text('Luči pavza: PC · kanal 5 (Luči) · program 3 → Luči'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'MIDI ob odprtju'), 'Ne obstaja');
    await tester.pump();
    expect(find.text('Neznano: Ne obstaja'), findsOneWidget);
  });
  testWidgets('nožno stikalo: učenje, naslednja pesem, gumbi pesmi, iskalnik in setlista', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prenos = _Prenos();
    final midi = Midi(prenos);
    Midi.aplikacija = midi;
    await tester.runAsync(() async {
      await midi.nalozi();
      midi.vklopljen = true;
      await midi.osveziNaprave();
    });

    // Učenje: prvi pritisk stikala postane sprožilec; spust (vrednost 0) se ne šteje.
    midi.uci(DejanjeMidi.naslednja);
    midi.prejeto([0xB0, 64, 0]);
    expect(midi.ucim, DejanjeMidi.naslednja);
    midi.prejeto([0xB0, 64, 127]);
    expect(midi.vhod[DejanjeMidi.naslednja], 'CC 1 64');
    expect(midi.ucim, isNull);
    await tester.runAsync(() async {
      await midi.nastaviVhod(DejanjeMidi.gumb2, 'Nota 10 20');
      await midi.nastaviVhod(DejanjeMidi.iskalnik, 'CC 1 67');
      await midi.nastaviVhod(DejanjeMidi.dol, 'CC 1 66');
      await midi.nastaviVhod(DejanjeMidi.potrdi, 'CC 1 65');
    });

    final api = Api(
      () async => 'z',
      url: 'https://example.com/exec',
      client: MockClient(
        (r) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'tabele': {
                'Pesmi': [
                  {'ID': 'a', 'Koda': 1, 'Naslov': 'PRVA', 'Aktivna': true},
                  {'ID': 'b', 'Koda': 2, 'Naslov': 'DRUGA', 'Aktivna': true},
                  {'ID': 'c', 'Koda': 3, 'Naslov': 'TRETJA', 'Aktivna': true},
                ],
                'Besedila': [
                  {'ID': 't', 'Pesem': 'a', 'Besedilo': 'la la'},
                ],
                'Setliste': [
                  {'ID': 's', 'Skupina': 's1', 'Ime': 'Poroka'},
                ],
                'Setlista pesmi': [
                  {'ID': '1', 'Setlista': 's', 'Zaporedje': 1, 'Pesem': 'c'},
                  {'ID': '2', 'Setlista': 's', 'Zaporedje': 2, 'Pesem': 'a'},
                ],
                'MIDI ukazi': _tabele['MIDI ukazi'],
                'Makri': _tabele['Makri'],
                'MIDI gumbi': [
                  {'ID': 'g1', 'Pesem': '', 'Ime': 'Pavza', 'Makro': 'Luči pavza', 'Zaporedje': 1},
                  {'ID': 'g2', 'Pesem': 'b', 'Ime': 'Solo', 'Makro': 'CC 9 12 127', 'Barva': 'rdeča'},
                ],
              },
            }),
          ),
          200,
        ),
      ),
    );
    final baza = Baza(shramba: _Pomnilnik());
    await tester.runAsync(() => baza.osvezi(api));
    final pesmi = baza.pesmi;

    await tester.pumpWidget(
      MaterialApp(
        home: PesemZaslon(pesem: pesmi.first, baza: baza, prijava: Prijava(), seznam: pesmi),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1  PRVA'), findsOneWidget);
    expect(find.text('1  Pavza'), findsOneWidget); // splošni gumb

    midi.prejeto([0xB0, 64, 127]); // naslednja
    await tester.pumpAndSettle();
    expect(find.text('2  DRUGA'), findsOneWidget);
    expect(find.text('2  Solo'), findsOneWidget); // gumb te pesmi je drugi

    prenos.poslano.clear();
    await tester.runAsync(() async {
      midi.prejeto([0x99, 20, 100]); // gumb 2
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(prenos.poslano, ['a 184 12 127', 'b 184 12 127']);

    // Iskalnik: odpre se pri trenutni pesmi, dol in potrdi odpreta naslednjo.
    midi.prejeto([0xB0, 67, 127]);
    await tester.pumpAndSettle();
    expect(find.byType(IskalnikPesmi), findsOneWidget);
    midi.prejeto([0xB0, 66, 127]);
    await tester.pump();
    midi.prejeto([0xB0, 65, 127]);
    await tester.pumpAndSettle();
    expect(find.text('3  TRETJA'), findsOneWidget);
    expect(find.byType(IskalnikPesmi), findsNothing);

    // Setlista: naslednja gre po setlisti, ne po seznamu.
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('setlista'),
        home: IgranjeZaslon(setlista: baza.setliste.single, baza: baza, prijava: Prijava()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3  TRETJA'), findsOneWidget);
    midi.prejeto([0xB0, 64, 127]);
    await tester.pumpAndSettle();
    expect(find.text('1  PRVA'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
  });
}

final _tabele = {
  'MIDI ukazi': [
    {'ID': '1', 'Ime': 'Delay ON', 'Vrsta': 'CC', 'Kanal': 9, 'Številka': 12, 'Vrednost': 127, 'Izhod': ''},
    {'ID': '2', 'Ime': 'Luči pavza', 'Vrsta': 'PC', 'Kanal': 5, 'Številka': 3, 'Vrednost': '', 'Izhod': 'Luči'},
    {'ID': '3', 'Ime': 'FC page 1', 'Vrsta': 'Nota', 'Kanal': 10, 'Številka': 20, 'Vrednost': 1, 'Izhod': ''},
  ],
  'Makri': [
    {'ID': 'm1', 'Ime': 'Pavza', 'Ukazi': 'Delay ON; Luči pavza; 3|7|15|0|4', 'Izhod': 'Miza'},
    {'ID': 'm2', 'Ime': 'Vse', 'Ukazi': '3|10|Pavza; FC page 1; Vse', 'Izhod': ''},
  ],
  'MIDI kanali': [
    {'Kanal': 5, 'Ime': 'Luči'},
    {'Kanal': 9, 'Ime': 'MixingStation'},
  ],
};

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
