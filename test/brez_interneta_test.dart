import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/shramba/shramba.dart';

void main() {
  test('urejanje brez interneta: shrani na napravo, pošlje pozneje, nato osveži', () async {
    var povezava = true;
    final poslano = <Map<String, dynamic>>[];
    final api = Api(
      () async => 'z',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        if (!povezava) throw http.ClientException('Ni povezave');
        if (r.method == 'GET') {
          return http.Response(
            jsonEncode({
              'vloge': [
                {'Skupina': 's1', 'Vloga': 'Urejevalec'},
              ],
              'tabele': {
                'Pesmi': [
                  {'ID': 'a', 'Koda': 1002, 'Naslov': 'Stara', 'Aktivna': true, 'Skupine': 's1'},
                ],
              },
            }),
            200,
          );
        }
        final telo = jsonDecode(r.body) as Map<String, dynamic>;
        poslano.add(telo);
        final v = (telo['pesem'] ?? telo['besedilo']) as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'vrstica': {...v, 'ID': v['ID'] ?? 'b1'},
            }),
          ),
          200,
        );
      }),
    );
    final shramba = ShrambaIdb(newIdbFactoryMemory());
    final baza = Baza(shramba: shramba);
    await baza.osvezi(api);

    povezava = false;
    final p = await baza.shraniPesem(api, {'ID': 'a', 'Naslov': 'Nova'});
    expect(p.naslov, 'NOVA'); // prikaz z velikimi tiskanimi
    expect(p.vrstica['Naslov'], 'Nova'); // v bazi kot vpisano
    await baza.shraniBesedilo(api, {'Pesem': 'a', 'Vrsta': 'Besedilo', 'Besedilo': 'la la', 'Opombe': ''});
    await baza.shraniBesedilo(api, {
      'ID': baza.besedilaPesmi['a']!.single.id,
      'Pesem': 'a',
      'Vrsta': 'Besedilo',
      'Besedilo': 'la la la',
      'Opombe': '',
    });
    expect(baza.neposlano, hasLength(2)); // novo besedilo se pošlje samo v zadnji različici
    expect(baza.besedilaPesmi['a']!.single.vsebina, 'la la la');
    await expectLater(baza.shraniPesem(api, {'Naslov': 'Čisto nova'}), throwsStateError);

    // Po ponovnem zagonu spremembe še vedno čakajo.
    final znova = Baza(shramba: shramba);
    await znova.nalozi();
    expect(znova.neposlano, hasLength(2));
    expect(znova.pesem('a')!.naslov, 'NOVA');

    povezava = true;
    expect(await znova.posljiNeposlano(api), isNull);
    expect(znova.neposlano, isEmpty);
    expect(poslano.map((t) => t['akcija']), ['pesem', 'besedilo']);
    expect((poslano.last['besedilo'] as Map).containsKey('ID'), isFalse);
    expect(znova.besedilaPesmi['a']!.single.id, 'b1'); // začasni ID zamenja pravi

    // Osvežitev pošlje, kar čaka, in šele nato prenese podatke.
    povezava = false;
    await znova.shraniPesem(api, {'ID': 'a', 'Naslov': 'Še novejša'});
    povezava = true;
    await znova.osvezi(api);
    expect(znova.neposlano, isEmpty);
    expect((poslano.last['pesem'] as Map)['Naslov'], 'Še novejša');
  });

  test('shranjevanje ne čaka strežnika: takoj na napravi, pošlje v ozadju, zavrnitev sporoči', () async {
    var odpri = Completer<void>();
    var zavrni = false;
    final poslano = <Map<String, dynamic>>[];
    final api = Api(
      () async => 'z',
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
                ],
              },
            }),
            200,
          );
        }
        await odpri.future; // strežnik je počasen
        final telo = jsonDecode(r.body) as Map<String, dynamic>;
        poslano.add(telo);
        if (zavrni) return http.Response(jsonEncode({'napaka': 'Ni dovoljeno'}), 200);
        final v = (telo['pesem'] ?? telo['besedilo']) as Map;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'vrstica': {...v, 'ID': v['ID'] ?? 'b1'},
            }),
          ),
          200,
        );
      }),
    );
    final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
    await baza.osvezi(api);
    final sporocila = <String>[];
    baza.obZavrnjenem = sporocila.add;

    // Shrani se takoj, čeprav strežnik še ni odgovoril.
    final p = await baza.shraniPesem(api, {'ID': 'a', 'Naslov': 'Nova'});
    expect(p.naslov, 'NOVA');
    await baza.shraniBesedilo(api, {'Pesem': 'a', 'Vrsta': 'Besedilo', 'Besedilo': 'la', 'Opombe': ''});
    final zacasni = baza.besedilaPesmi['a']!.single.id;
    expect(zacasni, startsWith('lokalno-'));
    expect(poslano, isEmpty);
    expect(baza.neposlano, hasLength(2));

    odpri.complete();
    await baza.pocakajPosiljanje();
    expect(baza.neposlano, isEmpty);
    expect(poslano.map((t) => t['akcija']), ['pesem', 'besedilo']);
    expect(baza.besedilaPesmi['a']!.single.id, 'b1');

    // Zaslon z začasnim ID-jem shrani znova: spremeni se pravo besedilo, ne nastane novo.
    await baza.shraniBesedilo(api, {'ID': zacasni, 'Pesem': 'a', 'Vrsta': 'Besedilo', 'Besedilo': 'la la'});
    await baza.pocakajPosiljanje();
    expect((poslano.last['besedilo'] as Map)['ID'], 'b1');
    expect(baza.besedilaPesmi['a']!.single.vsebina, 'la la');

    // Strežnik spremembo zavrne: sporočilo za člana.
    zavrni = true;
    odpri = Completer<void>()..complete();
    await baza.shraniPesem(api, {'ID': 'a', 'Naslov': 'Druga'});
    await baza.pocakajPosiljanje();
    await Future<void>.delayed(Duration.zero);
    expect(sporocila.single, contains('Ni dovoljeno'));
    expect(baza.neposlano, isEmpty);
    baza.dispose();
  });
}
