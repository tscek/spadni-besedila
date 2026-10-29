// Ročni preizkus vodje s pravo spletno različico (ni del običajnih testov):
//   flutter build web --release --no-web-resources-cdn
//   (cd build/web && zip -qr ../../assets/splet/splet.zip .)
//   flutter test tool/e2e/vodja_test.dart   # nato v brskalniku odpri http://127.0.0.1:8765
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/spil/spil.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('vodja streže spletno različico in menja pesmi', () async {
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
                  {'ID': 'a', 'Koda': 1002, 'Naslov': 'BELO OBLEKO SI ŽE NOSILA', 'Aktivna': true, 'Skupine': 's1'},
                  {'ID': 'b', 'Koda': 1003, 'Naslov': 'BOG TE ŽIVI', 'Aktivna': true, 'Skupine': 's1'},
                ],
                'Besedila': [
                  {'ID': 't1', 'Pesem': 'a', 'Besedilo': '[C]Belo obleko [G7]si že nosila'},
                  {'ID': 't2', 'Pesem': 'b', 'Besedilo': '{c: Refren}\n[F]Bog te [C]živi'},
                ],
                'Člani': [
                  {'ID': 'A', 'Ime': 'Nina Kovšca', 'Email': 'x@example.com', 'Aktiven': true},
                  {'ID': 'B', 'Ime': 'Matej Šček', 'Email': 'y@example.com', 'Aktiven': true},
                ],
                'Setliste': [
                  {'ID': 'x', 'Skupina': 's1', 'Ime': 'Poroka'},
                ],
                'Setlista pesmi': [
                  {'ID': '1', 'Setlista': 'x', 'Zaporedje': 1, 'Pesem': 'a', 'Opomba': 'brez uvoda'},
                  {'ID': '2', 'Setlista': 'x', 'Zaporedje': 2, 'Pesem': 'b'},
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
    final vodja = Spil();
    await vodja.zacniVoditi(baza);
    // ignore: avoid_print
    print('VODJA ${vodja.naslov} ${vodja.napaka ?? ''}');
    vodja.prikazujem(const StanjeSpila(pesem: 'a', setlista: 'x', indeks: 0));
    await Future<void>.delayed(const Duration(seconds: 40));
    vodja.prikazujem(const StanjeSpila(pesem: 'b'));
    await Future<void>.delayed(const Duration(seconds: 40));
    await vodja.ustavi();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
