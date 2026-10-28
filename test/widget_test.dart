import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/chordpro.dart';
import 'package:spadni_besedila/models.dart';

void main() {
  group('chordpro', () {
    test('akordi nad zlogi', () {
      expect(razcleniVrstico('[C]Belo obleko si [G]že nosila'), const [
        Kos('C', 'Belo obleko si '),
        Kos('G', 'že nosila'),
      ]);
    });

    test('besedilo pred prvim akordom in akord na koncu', () {
      expect(razcleniVrstico('Oj [F]dekle [C7]'), const [Kos('', 'Oj '), Kos('F', 'dekle '), Kos('C7', '')]);
    });

    test('komentarji, prazne vrstice, ostale direktive se ne prikažejo', () {
      final v = razcleni('{title: Gora}\n{c: Refren 2x}\n\nLa la');
      expect(v.map((x) => x.vrsta), [VrstaVrstice.komentar, VrstaVrstice.prazna, VrstaVrstice.besedilo]);
      expect(v.first.komentar, 'Refren 2x');
      expect(v.last.imaAkorde, isFalse);
    });
  });

  group('modeli', () {
    test('koda kot število iz preglednice', () {
      final p = Pesem.izVrstice({'ID': 'a1', 'Koda': 1002.0, 'Naslov': 'BELO OBLEKO SI ŽE NOSILA', 'Aktivna': true});
      expect(p.koda, '1002');
      expect(p.kodaStevilka, 1002);
      expect(p.aktivna, isTrue);
    });

    test('iskanje brez šumnikov', () {
      final p = Pesem(id: 'x', koda: '1004', naslov: 'ČE DVE LJUBICI IMAŠ', izvajalec: 'Modrijani');
      expect(p.ustreza('ce dve'), isTrue);
      expect(p.ustreza('10'), isTrue);
      expect(p.ustreza('modri'), isTrue);
      expect(p.ustreza('slak'), isFalse);
    });

    test('skupine razdeljene z vejico', () {
      final p = Pesem.izVrstice({'ID': 'a', 'Koda': '1', 'Naslov': 'X', 'Skupine': 'ea98d692, e2087f13'});
      expect(p.skupine, ['ea98d692', 'e2087f13']);
    });
  });

  group('api', () {
    test('napaka iz skripte se prikaže kot ApiNapaka', () async {
      final api = Api(
        () async => 'zeton',
        url: 'https://example.com/exec',
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(jsonEncode({'napaka': 'Račun x ni med člani'})), 200),
        ),
      );
      expect(
        api.podatki(),
        throwsA(isA<ApiNapaka>().having((e) => e.sporocilo, 'sporocilo', contains('ni med člani'))),
      );
    });

    test('HTML namesto JSON: napaka pove naslov strani', () async {
      final api = Api(
        () async => 'zeton',
        url: 'https://example.com/exec',
        client: MockClient(
          (_) async => http.Response(
            '<html><head><title>Sign in</title><style>x{}</style></head><body>Prijava</body></html>',
            200,
          ),
        ),
      );
      expect(
        api.podatki(),
        throwsA(
          isA<ApiNapaka>().having(
            (e) => e.sporocilo,
            'sporocilo',
            allOf(startsWith('Strežnik ni vrnil'), contains('Sign in |'), contains('Prijava')),
          ),
        ),
      );
    });

    test('POST sledi preusmeritvi Apps Scripta', () async {
      final klici = <String>[];
      final api = Api(
        () async => 'zeton',
        url: 'https://example.com/exec',
        client: MockClient((r) async {
          klici.add('${r.method} ${r.url.host}');
          if (r.method == 'POST') {
            return http.Response('', 302, headers: {'location': 'https://rezultat.example.com/x'});
          }
          return http.Response(jsonEncode({'zapisano': 1}), 200);
        }),
      );
      await api.dnevnik([
        {'pesem': 'a'},
      ]);
      expect(klici, ['POST example.com', 'GET rezultat.example.com']);
    });
  });

  test('baza: osvežitev shrani podatke in PDF-je lokalno', () async {
    final mapa = await Directory.systemTemp.createTemp('baza');
    addTearDown(() => mapa.delete(recursive: true));
    final pdfBytes = utf8.encode('%PDF-1.4 test');
    final api = Api(
      () async => 'zeton',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        if (r.url.queryParameters['akcija'] == 'pdf') {
          return http.Response(jsonEncode({'base64': base64Encode(pdfBytes)}), 200);
        }
        return http.Response(
          jsonEncode({
            'cas': '2026-10-28T13:00:00.000Z',
            'vloge': [
              {'Skupina': 'ea98d692', 'Vloga': 'Administrator', 'Sme voditi': true},
            ],
            'tabele': {
              'Pesmi': [
                {'ID': 'b', 'Koda': 2001, 'Naslov': 'B', 'Aktivna': true},
                {'ID': 'a', 'Koda': 1002, 'Naslov': 'A', 'Aktivna': true},
                {'ID': 'c', 'Koda': 1003, 'Naslov': 'C', 'Aktivna': false},
              ],
              'PDF': [
                {'ID': 'p1', 'Pesem': 'a', 'Vrsta': 'Besedilo', 'Drive ID': 'drive1', 'Vrstni red': 1},
              ],
              'Besedila': [
                {'ID': 't1', 'Pesem': 'b', 'Vrsta': 'Besedilo z akordi', 'Besedilo': '[C]La'},
              ],
            },
          }),
          200,
        );
      }),
    );

    final baza = Baza(mapa: mapa);
    await baza.osvezi(api);

    expect(baza.napaka, isNull);
    expect(baza.pesmi.map((p) => p.koda), ['1002', '2001']);
    expect(baza.besedilaPesmi['b']!.single.vsebina, '[C]La');
    expect(await (await baza.datotekaPdf('drive1')).readAsBytes(), pdfBytes);
    expect(baza.urednikSkupine, ['ea98d692']);

    final ponovno = Baza(mapa: mapa);
    await ponovno.nalozi();
    expect(ponovno.pesmi.length, 2);
  });
}
