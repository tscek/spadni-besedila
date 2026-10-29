import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/midi/midi.dart';
import 'package:spadni_besedila/midi/prenos.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/config.dart';
import 'package:spadni_besedila/risbe.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/spil/spil.dart';
import 'package:spadni_besedila/spil/streznik.dart';

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
              'Člani': [
                {'ID': 'A', 'Ime': 'Nina', 'Email': 'nina@example.com', 'Aktiven': true},
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

    // E-naslovi članov ne gredo na iPade.
    expect((podatki['tabele']['Člani'] as List).single, {'ID': 'A', 'Ime': 'Nina', 'Aktiven': true});

    // iPad pošlje risbo člana A; vodja jo shrani in vrne ob naslednjem branju.
    final z = await odjemalec.postUrl(Uri.parse('http://127.0.0.1:${Config.vrataVodje}/api'));
    z.write(
      jsonEncode({
        'akcija': 'risba',
        'pesem': 'a',
        'vsebina': '{"spremenjeno":"2026-10-29T10:00:00Z"}',
        'clan': 'A',
        'zeton': '',
      }),
    );
    final o = await z.close();
    expect(await utf8.decoder.bind(o).join(), contains('shranjeno'));
    final (_, risbe) = await get('/api?akcija=risbe&clan=A&zeton=');
    expect((jsonDecode(risbe) as Map)['a']['vsebina'], contains('2026-10-29'));
    final (_, tujeRisbe) = await get('/api?akcija=risbe&zeton=');
    expect(jsonDecode(tujeRisbe), isEmpty);

    // Brez zapakirane spletne različice (v testih) strežnik to pove.
    final (kodaStrani, stran) = await get('/');
    expect(kodaStrani, 404);
    expect(stran, contains('Spletna različica ni vključena'));

    await vodja.ustavi();
    await _pocakaj(() => !sledilec.povezan);
    expect(sledilec.prekinjeno, isTrue); // gumb utripa rdeče
    expect(sledilec.vloga, VlogaSpila.sledilec); // se poskuša znova povezati
  });

  test('iPad pošlje MIDI vodji, ta ga pošlje na svoje naprave', () async {
    final baza = await _baza();
    final vodja = Spil();
    addTearDown(vodja.ustavi);
    await vodja.zacniVoditi(baza);
    final prenos = _Prenos();
    final midi = Midi(prenos);
    Midi.aplikacija = midi;
    await midi.osveziNaprave();

    final ipad = Api(() async => '', url: 'http://127.0.0.1:${Config.vrataVodje}/api');
    final ukazi = [
      {'zapis': 'CC 9 12 127', 'ime': 'Delay ON', 'izhod': 'Privzeti'},
    ];
    // Vodja brez vklopljenega MIDI to pove.
    await expectLater(ipad.posljiMidi(ukazi), throwsA(isA<ApiNapaka>()));

    midi.vklopljen = true;
    expect(await ipad.posljiMidi(ukazi), 0);
    expect(prenos.poslano, ['x 184 12 127']);
    expect(midi.dnevnik.single.opis, startsWith('Delay ON: CC'));
  });

  test('sledilec sam najde vodjo in dobi tudi pesmi izven setliste', () async {
    final baza = await _baza();
    final vodja = Spil();
    final oglasi = StreamController<String>();
    final sledilec = Spil(iskalec: () => oglasi.stream);
    addTearDown(() async {
      await sledilec.ustavi();
      await vodja.ustavi();
    });

    sledilec.samodejnoSledi();
    expect(sledilec.vloga, VlogaSpila.sledilec);
    expect(sledilec.povezan, isFalse);

    vodja.prikazujem(const StanjeSpila(pesem: 'a'));
    await vodja.zacniVoditi(baza);
    oglasi.add('http://127.0.0.1:${Config.vrataVodje}');
    await _pocakaj(() => sledilec.povezan && sledilec.stanje?.pesem == 'a');
    expect(sledilec.naslovVodje, '127.0.0.1:${Config.vrataVodje}');

    // Pesem izven setliste: vodja jo samo odpre.
    vodja.prikazujem(const StanjeSpila(pesem: 'b'));
    await _pocakaj(() => sledilec.stanje?.pesem == 'b');

    await sledilec.ustavi();
    expect(oglasi.hasListener, isFalse);
  });

  test('vodja se oglaša na omrežju', () async {
    final baza = await _baza();
    final vodja = Spil();
    addTearDown(vodja.ustavi);
    final najdeni = <String>[];
    final p = isciVodjo().listen(najdeni.add);
    addTearDown(p.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await vodja.zacniVoditi(baza);
    for (var i = 0; i < 60 && najdeni.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // V nekaterih okoljih (CI brez omrežja) oddajanje ne pride do sprejemnika; tam test ne pove ničesar.
    if (najdeni.isEmpty) {
      markTestSkipped('oddajanje v tem okolju ne doseže sprejemnika');
      return;
    }
    expect(najdeni.first, endsWith(':${Config.vrataVodje}'));
  });

  test('vodja: risbe članov s špila gredo na strežnik, nato se prenesejo vse', () async {
    final poslano = <Map<String, dynamic>>[];
    final api = Api(
      () async => 'z',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        if (r.method == 'POST') {
          poslano.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(jsonEncode({'shranjeno': true}), 200);
        }
        expect(r.url.queryParameters['akcija'], 'risbeClanov');
        return http.Response(
          jsonEncode({
            'A': {
              'a': {'vsebina': 'stara', 'spremenjeno': '2026-01-01T00:00:00Z'},
              'b': {'vsebina': 'z Drive', 'spremenjeno': '2026-01-01T00:00:00Z'},
            },
          }),
          200,
        );
      }),
    );
    final r = RisbeClanov(ShrambaIdb(newIdbFactoryMemory()));
    await r.shrani('A', 'a', '');
    await r.sinhroniziraj(api);
    expect(poslano.single, containsPair('akcija', 'risbaZa'));
    expect(poslano.single, containsPair('clan', 'A'));
    final a = await r.zaClana('A');
    expect(a['a']['vsebina'], 'stara'); // poslano, zato zdaj velja različica s strežnika
    expect(a['b']['vsebina'], 'z Drive');
  });
}

class _Prenos implements MidiPrenos {
  final poslano = <String>[];

  @override
  Future<List<NapravaMidi>> naprave() async => const [NapravaMidi('x', 'WIDI', 'Bluetooth', true)];
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
