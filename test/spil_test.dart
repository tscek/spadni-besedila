import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/config.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/spil/spil.dart';
import 'package:spadni_besedila/zasloni/spil_zaslon.dart';

Future<Baza> _baza() async {
  final api = Api(
    () async => 'z',
    url: 'https://example.com/exec',
    client: MockClient(
      (r) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'vloge': [
              {'Skupina': 's1', 'Vloga': 'Administrator', 'Sme voditi': true},
            ],
            'tabele': {
              'Pesmi': [
                {'ID': 'a', 'Koda': 1002, 'Naslov': 'BELO OBLEKO', 'Aktivna': true},
              ],
            },
          }),
        ),
        200,
      ),
    ),
  );
  final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
  await baza.osvezi(api);
  return baza;
}

Future<void> _pocakaj(bool Function() pogoj) async {
  for (var i = 0; i < 100 && !pogoj(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(pogoj(), isTrue);
}

void main() {
  test('naslov vodje iz različnih vnosov', () {
    expect(naslovWebSocket('192.168.1.5').toString(), 'ws://192.168.1.5:${Config.vrataVodje}/ws');
    expect(naslovWebSocket(' http://192.168.1.5:9000/ ').toString(), 'ws://192.168.1.5:9000/ws');
    expect(naslovWebSocket(''), isNull);
  });

  test('vodja pošlje pesem, sledilec jo prejme; iPadi dobijo podatke brez vlog', () async {
    final baza = await _baza();
    expect(baza.smeVoditi, isTrue);
    final vodja = Spil();
    final sledilec = Spil();
    addTearDown(() async {
      await sledilec.ustavi();
      await vodja.ustavi();
    });

    vodja.objavi(const StanjeSpila(pesem: 'a', setlista: 'x', indeks: 0));
    await vodja.zacniVoditi(baza);
    expect(vodja.napaka, isNull);
    expect(vodja.naslov, endsWith(':${Config.vrataVodje}'));

    // Sledilec, ki se poveže kasneje, takoj dobi zadnje stanje.
    sledilec.sledi(Uri.parse('ws://127.0.0.1:${Config.vrataVodje}/ws'));
    await _pocakaj(() => sledilec.stanje?.pesem == 'a');
    await _pocakaj(() => vodja.sledilcev == 1);

    vodja.objavi(const StanjeSpila(pesem: 'b', setlista: 'x', indeks: 1));
    await _pocakaj(() => sledilec.stanje?.indeks == 1);

    final odjemalec = HttpClient();
    addTearDown(odjemalec.close);
    Future<(int, String)> get(String pot) async {
      final z = await odjemalec.getUrl(Uri.parse('http://127.0.0.1:${Config.vrataVodje}$pot'));
      final o = await z.close();
      return (o.statusCode, await utf8.decoder.bind(o).join());
    }

    final (koda, telo) = await get('/api?akcija=podatki&zeton=');
    expect(koda, 200);
    final podatki = jsonDecode(telo) as Map<String, dynamic>;
    expect(podatki['vloge'], isEmpty);
    expect((podatki['tabele']['Pesmi'] as List).single['Naslov'], 'BELO OBLEKO');

    // Brez zapakirane spletne različice (v testih) strežnik to pove.
    final (kodaStrani, stran) = await get('/');
    expect(kodaStrani, 404);
    expect(stran, contains('Spletna različica ni vključena'));

    await vodja.ustavi();
    await _pocakaj(() => !sledilec.povezan);
    expect(sledilec.vloga, VlogaSpila.sledilec); // se poskuša znova povezati
  });
}
