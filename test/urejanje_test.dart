import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/chordpro.dart';
import 'package:spadni_besedila/models.dart';
import 'package:spadni_besedila/zasloni/urejanje_besedila.dart';
import 'package:spadni_besedila/zasloni/urejanje_pesmi.dart';

void main() {
  test('akordi nad besedilom se pretvorijo v oglate oklepaje', () {
    const vhod = 'C           G7\nBelo obleko si že nosila\n\nF   C\n\nRefren:\nAm    Fis/E\nla la';
    expect(akordiNadBesedilom(vhod), '[C]Belo obleko [G7]si že nosila\n\n[F] [C]\n\nRefren:\n[Am]la la [Fis/E]');
    expect(jeVrsticaAkordov('Es  B  As  H7  Cis'), isTrue);
    expect(jeVrsticaAkordov('A ti veš'), isFalse);
  });

  test('urejanje: shrani pesem in besedilo v lokalno kopijo, brisanje odstrani besedilo', () async {
    final mapa = await Directory.systemTemp.createTemp('urejanje');
    addTearDown(() => mapa.delete(recursive: true));
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

    final baza = Baza(mapa: mapa);
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
    final ponovno = Baza(mapa: mapa);
    await ponovno.nalozi();
    expect(ponovno.pesmi.first.naslov, 'Popravljena');
    expect(ponovno.besedilaPesmi['nova'], isNotNull);

    await baza.shraniBesedilo(api, {'ID': 't1', 'Pesem': 'nova', 'Besedilo': ''});
    expect(baza.besedilaPesmi['nova'], isNull);
    expect(poslano.map((t) => t['akcija']), ['pesem', 'pesem', 'besedilo', 'besedilo']);
  });

  testWidgets('zaslona za urejanje se izrišeta, predogled pokaže akorde', (tester) async {
    final api = Api(() async => 'z', url: 'https://example.com/exec');
    final baza = Baza();
    final pesem = Pesem(
      id: 'a',
      koda: '1002',
      naslov: 'BELO OBLEKO',
      vrstica: {'Naslov': 'BELO OBLEKO', 'Zvrst': 'Pop'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UrejanjePesmiZaslon(baza: baza, api: api, pesem: pesem),
      ),
    );
    expect(find.text('BELO OBLEKO'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pesem je v repertoarju'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Pesem je v repertoarju'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: UrejanjeBesedilaZaslon(baza: baza, api: api, pesem: pesem),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'C     G\nBelo obleko');
    await tester.tap(find.byIcon(Icons.auto_fix_high));
    await tester.pump();
    await tester.tap(find.text('Predogled'));
    await tester.pumpAndSettle();
    expect(find.text('G '), findsOneWidget);
  });
}
