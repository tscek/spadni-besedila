import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/zasloni/mape.dart';

http.Response _odg(Object telo) => http.Response.bytes(utf8.encode(jsonEncode(telo)), 200);

void main() {
  late List<Map<String, dynamic>> poslano;

  Api api() => Api(
    () async => 'z',
    url: 'https://example.com/exec',
    client: MockClient((r) async {
      if (r.method == 'GET' && r.url.queryParameters['akcija'] == 'podatki') {
        return _odg({
          'clan': {'ID': 'c1'},
          'tabele': {
            'Pesmi': [
              {'ID': 'a', 'Koda': 1, 'Naslov': 'BELO OBLEKO', 'Aktivna': true, 'Mapa': 'nz', 'Skupine': 's'},
            ],
            'Besedila': [
              {'ID': 'b1', 'Pesem': 'a', 'Vrsta': 'Besedilo', 'Besedilo': 'La la'},
            ],
            'Mape': [
              {
                'ID': 'nz',
                'Ime': 'Narodno-zabavne',
                'Vrstni red': 1,
                'Barva': '#C62828',
                'Ikona': 'srce',
                'Opis': 'Glavna',
              },
              {'ID': 'vaje', 'Ime': 'Vaje', 'Vrstni red': 2},
            ],
            'Vloge': [
              {'Član': 'c1', 'Skupina': 's', 'Vloga': 'Urejevalec'},
            ],
          },
        });
      }
      if (r.method == 'GET') return _odg({});
      final telo = jsonDecode(r.body) as Map<String, dynamic>;
      poslano.add(telo);
      if (telo['akcija'] == 'kopirajPesem') {
        return _odg({
          'pesem': {'ID': 'k', 'Koda': 2, 'Naslov': 'BELO OBLEKO', 'Aktivna': true, 'Mapa': telo['mapa']},
          'besedila': [
            {'ID': 'b2', 'Pesem': 'k', 'Vrsta': 'Besedilo', 'Besedilo': 'La la'},
          ],
          'pdf': [],
        });
      }
      if (telo['akcija'] == 'midi') {
        final v = telo['vrstica'] as Map<String, dynamic>;
        return _odg({
          'vrstica': {...v, 'ID': v['ID'] ?? 'nova'},
        });
      }
      return _odg({});
    }),
  );

  setUp(() => poslano = []);

  test('mapa ima opis, barvo in ikono; kopija pesmi je samostojna pesem v drugi mapi', () async {
    final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
    await baza.osvezi(api());
    final m = baza.mapa('nz')!;
    expect((m.opis, m.argb, ikonaMape(m)), ('Glavna', 0xFFC62828, Icons.favorite_outline));
    expect(steviloVMapi(baza, 'nz'), 1);

    final k = await baza.kopirajPesem(api(), 'a', 'vaje');
    expect(poslano.single, {'akcija': 'kopirajPesem', 'pesem': 'a', 'mapa': 'vaje', 'zeton': 'z'});
    expect(k.mapa, 'vaje');
    expect(baza.pesmiMape('vaje').map((p) => p.id), ['k']);
    expect(baza.pesmiMape('nz').map((p) => p.id), ['a']);
    expect(baza.besedilaPesmi['k']!.single.vsebina, 'La la');
  });

  testWidgets('nova mapa z opisom, barvo in ikono', (tester) async {
    final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
    await tester.runAsync(() => baza.osvezi(api()));
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    urediMapo(ctx, baza, api());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byKey(const ValueKey('ime-mape')), 'Poroke');
    await tester.enterText(find.byKey(const ValueKey('opis-mape')), 'Za svatbe');
    await tester.tap(find.byKey(const ValueKey('ikona-poroka')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shrani-mapo')));
    for (var i = 0; i < 20 && poslano.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final v = poslano.single['vrstica'] as Map;
    expect(poslano.single['tabela'], 'Mape');
    expect(v['Ime'], 'Poroke');
    expect(v['Opis'], 'Za svatbe');
    expect(v['Ikona'], 'poroka');
    expect(v['Vrstni red'], 3);
    expect(v.containsKey('ID'), isFalse);
  });
}
