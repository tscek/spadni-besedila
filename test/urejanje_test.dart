import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/chordpro.dart';
import 'package:spadni_besedila/models.dart';
import 'package:spadni_besedila/prijava.dart';
import 'package:spadni_besedila/risbe.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/zasloni/pesem_zaslon.dart';
import 'package:spadni_besedila/zasloni/urejanje_pesmi.dart';

void main() {
  test('akordi nad besedilom se pretvorijo v oglate oklepaje', () {
    const vhod = 'C           G7\nBelo obleko si že nosila\n\nF   C\n\nRefren:\nAm    Fis/E\nla la';
    expect(akordiNadBesedilom(vhod), '[C]Belo obleko [G7]si že nosila\n\n[F] [C]\n\nRefren:\n[Am]la la [Fis/E]');
    expect(jeVrsticaAkordov('Es  B  As  H7  Cis'), isTrue);
    expect(jeVrsticaAkordov('A ti veš'), isFalse);
  });

  test('urejanje: shrani pesem in besedilo v lokalno kopijo, brisanje odstrani besedilo', () async {
    // Ista shramba kot v brskalniku (IndexedDB), le v pomnilniku.
    final shramba = ShrambaIdb(newIdbFactoryMemory());
    final poslano = <Map<String, dynamic>>[];
    final api = Api(
      () async => 'zeton',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        if (r.method == 'GET') {
          return http.Response(
            jsonEncode({
              'vloge': [
                {'Skupina': 's1', 'Vloga': 'Urejevalec'},
              ],
              'tabele': {
                'Pesmi': [
                  {'ID': 'a', 'Koda': 1002, 'Naslov': 'Stara', 'Aktivna': true, 'Skupine': 's1'},
                  {'ID': 'x', 'Koda': 3000, 'Naslov': 'Tuja', 'Aktivna': true, 'Skupine': 's2'},
                ],
              },
            }),
            200,
          );
        }
        final telo = jsonDecode(r.body) as Map<String, dynamic>;
        poslano.add(telo);
        if (telo['akcija'] == 'pesem') {
          final p = telo['pesem'] as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'vrstica': {...p, 'ID': p['ID'] ?? 'nova', 'Aktivna': true},
              }),
            ),
            200,
          );
        }
        final b = telo['besedilo'] as Map<String, dynamic>;
        if ((b['Besedilo'] as String).isEmpty) return http.Response(jsonEncode({'izbrisano': b['ID']}), 200);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'vrstica': {...b, 'ID': b['ID'] ?? 't1'},
            }),
          ),
          200,
        );
      }),
    );

    final baza = Baza(shramba: shramba);
    await baza.osvezi(api);
    expect(baza.smeUrejatiPesem(baza.pesmi.first), isTrue);
    expect(baza.smeUrejatiPesem(baza.pesmi.last), isFalse);

    await baza.shraniPesem(api, {'ID': 'a', 'Koda': '1002', 'Naslov': 'Popravljena'});
    final nova = await baza.shraniPesem(api, {'Koda': '1500', 'Naslov': 'Čisto nova'});
    expect(nova.id, 'nova');
    expect(baza.pesmi.map((p) => p.naslov), ['Popravljena', 'Čisto nova', 'Tuja']);

    await baza.shraniBesedilo(api, {'Pesem': 'nova', 'Vrsta': 'Besedilo z akordi', 'Besedilo': '[C]La'});
    expect(baza.besedilaPesmi['nova']!.single.vsebina, '[C]La');

    // Spremembe ostanejo tudi po ponovnem zagonu brez interneta.
    final ponovno = Baza(shramba: shramba);
    await ponovno.nalozi();
    expect(ponovno.pesmi.first.naslov, 'Popravljena');
    expect(ponovno.besedilaPesmi['nova'], isNotNull);

    await baza.shraniBesedilo(api, {'ID': 't1', 'Pesem': 'nova', 'Besedilo': ''});
    expect(baza.besedilaPesmi['nova'], isNull);
    expect(poslano.map((t) => t['akcija']), ['pesem', 'pesem', 'besedilo', 'besedilo']);
  });

  testWidgets('en zaslon za urejanje: podatki, besedilo s predogledom, shrani oboje', (tester) async {
    final poslano = <Map<String, dynamic>>[];
    final api = Api(
      () async => 'z',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        final telo = jsonDecode(r.body) as Map<String, dynamic>;
        poslano.add(telo);
        final vrstica = (telo['pesem'] ?? telo['besedilo']) as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'vrstica': {...vrstica, 'ID': vrstica['ID'] ?? 'nova', 'Aktivna': true},
            }),
          ),
          200,
        );
      }),
    );
    final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
    final pesem = Pesem.izVrstice({
      'ID': 'a',
      'Koda': 1002,
      'Naslov': 'BELO OBLEKO',
      'Zvrst': 'Pop',
      'Aktivna': true,
      'Skupine': 's1',
    });

    Pesem? rezultat;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => rezultat = await Navigator.of(context).push<Pesem>(
              MaterialPageRoute(
                builder: (_) => UrejanjePesmiZaslon(baza: baza, api: api, pesem: pesem),
              ),
            ),
            child: const Text('odpri'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('odpri'));
    await tester.pumpAndSettle();
    expect(find.text('BELO OBLEKO'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextField, 'Avtor glasbe'), 'Slavko Avsenik');

    await tester.tap(find.text('Besedilo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Besedilo pesmi'), 'C     G\nBelo obleko');
    await tester.tap(find.byIcon(Icons.auto_fix_high));
    await tester.pump();
    await tester.tap(find.text('Predogled'));
    await tester.pumpAndSettle();
    expect(find.text('G '), findsOneWidget);

    await tester.tap(find.text('Shrani'));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && rezultat == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(poslano.map((t) => t['akcija']), ['pesem', 'besedilo']);
    expect((poslano.first['pesem'] as Map)['Avtor glasbe'], 'Slavko Avsenik');
    expect((poslano.last['besedilo'] as Map)['Besedilo'], '[C]Belo o[G]bleko');
    expect(rezultat?.id, 'a');
  });

  testWidgets('risanje po besedilu: poteza se shrani kot stran 0 risbe pesmi', (tester) async {
    final baza = Baza(shramba: _Pomnilnik());
    await tester.runAsync(() async {
      await baza.osvezi(
        Api(
          () async => 'z',
          url: 'https://example.com/exec',
          client: MockClient(
            (r) async => http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'tabele': {
                    'Pesmi': [
                      {'ID': 'a', 'Koda': 1002, 'Naslov': 'BELO OBLEKO', 'Aktivna': true},
                    ],
                    'Besedila': [
                      {'ID': 't', 'Pesem': 'a', 'Besedilo': '[C]Belo obleko [G7]si že nosila'},
                    ],
                  },
                }),
              ),
              200,
            ),
          ),
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PesemZaslon(pesem: baza.pesmi.single, baza: baza, prijava: Prijava()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belo obleko '), findsOneWidget);

    // Pridržanje na besedilu vklopi risanje.
    await tester.longPress(find.text('Belo obleko '));
    await tester.pumpAndSettle();
    expect(find.text('Končano'), findsOneWidget);
    await tester.dragFrom(const Offset(100, 200), const Offset(200, 50));
    await tester.pumpAndSettle();
    // Shranjevanje teče v lažnem času testa: počakamo, da se konča, nato preberemo shranjeno.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    Risba? risba;
    baza.risbe.nalozi('a').then((r) => risba = r);
    await tester.pump();
    expect(risba!.poteze[0], hasLength(1));
    expect(risba!.poteze.keys, [0]);
    // Koordinate so relativne na širino strani: neodvisne od velikosti zaslona.
    expect(risba!.poteze[0]!.single.tocke.first.dx, inInclusiveRange(0, 1));
  });
}

/// Preprosta shramba v pomnilniku, ki deluje tudi v lažnem času testov z gradniki.
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
