import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/models.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/snemanje.dart';
import 'package:spadni_besedila/zasloni/snemanje_zaslon.dart';

const _kosi =
    '[{"i":0,"z":"2026-11-21T21:54:15Z","t":600,"d":"k0"},{"i":1,"z":"2026-11-21T22:04:15Z","t":487,"d":"k1"}]';

Map<String, dynamic> _vrstica(
  String id, {
  String stanje = 'posneto',
  String yt = '',
  String video = '',
  String? sprem,
}) => {
  'ID': id,
  'Naslov': 'Špil $id',
  'Začetek': '2026-11-21T21:54:00Z',
  'Stanje': stanje,
  'YouTube ID': yt,
  'Kosi': _kosi,
  'Video': video,
  'Spremenjeno': sprem ?? DateTime.now().toUtc().toIso8601String(),
};

void main() {
  test('stanje videa: čaka, zahtevan, v obdelavi, obtičal, napaka, na YouTubu', () {
    final zdaj = DateTime.utc(2026, 11, 22, 12);
    Snemanje s(Map<String, dynamic> r) => Snemanje.izVrstice(r);
    final caka = s(_vrstica('a', sprem: '2026-11-22T11:00:00Z'));
    expect(caka.opisVidea(zdaj), 'Posneto, čaka na video');
    expect(caka.lahkoNarediVideo(zdaj), isTrue);
    expect(caka.trajanje, const Duration(seconds: 1087));

    final zahtevan = s(_vrstica('b', video: 'zahtevan', sprem: '2026-11-22T11:30:00Z'));
    expect(zahtevan.lahkoNarediVideo(zdaj), isFalse);
    expect(zahtevan.opisVidea(zdaj), contains('zahtevan'));

    final obtical = s(_vrstica('c', video: 'obdelava', sprem: '2026-11-22T07:00:00Z'));
    expect(obtical.lahkoNarediVideo(zdaj), isTrue);
    expect(obtical.opisVidea(zdaj), contains('poskusi znova'));

    final napaka = s(_vrstica('d', video: 'napaka: kos ni dosegljiv'));
    expect(napaka.lahkoNarediVideo(zdaj), isTrue);
    expect(napaka.opisVidea(zdaj), 'Napaka pri videu (kos ni dosegljiv)');

    final narejen = s(_vrstica('e', stanje: 'video', yt: 'abc'));
    expect(narejen.lahkoNarediVideo(zdaj), isFalse);
    expect(narejen.opisVidea(zdaj), 'Na YouTubu');

    expect(s(_vrstica('f', stanje: 'snema')).lahkoNarediVideo(zdaj), isFalse);
  });

  testWidgets('vodja: seznam snemanj in gumb Naredi video zdaj', (t) async {
    SharedPreferences.setMockInitialValues({});
    final poslano = <Map<String, dynamic>>[];
    final api = Api(
      () async => 'z',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        if (r.method == 'GET') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'clan': {'ID': 'C', 'Ime': 'Janez'},
                'vloge': [
                  {'Član': 'C', 'Skupina': 's1', 'Vloga': 'Urejevalec', 'Sme voditi': true},
                ],
                'tabele': {
                  'Snemanja': [_vrstica('nov'), _vrstica('star', stanje: 'video', yt: 'yt1')],
                },
              }),
            ),
            200,
          );
        }
        final telo = jsonDecode(r.body) as Map<String, dynamic>;
        poslano.add(telo);
        return http.Response.bytes(
          utf8.encode(jsonEncode({'vrstica': _vrstica(telo['id'] as String, video: 'zahtevan')})),
          200,
        );
      }),
    );
    final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
    await t.runAsync(() => baza.osvezi(api));
    SnemanjeSpila.aplikacija = SnemanjeSpila()..api = () => api;
    expect(baza.smeZahtevatiVideo, isTrue);

    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PloscaSnemanja(baza: baza)),
      ),
    );
    expect(find.textContaining('čaka na video'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('vsa-snemanja')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('snemanje-nov')), findsOneWidget);
    expect(find.byKey(const ValueKey('snemanje-star')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('snemanje-star')), matching: find.text('Špil star')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('naredi-video-star')), findsNothing);

    await t.tap(find.byKey(const ValueKey('naredi-video-nov')).last);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pumpAndSettle();
    expect(poslano.single['akcija'], 'narediVideo');
    expect(poslano.single['id'], 'nov');
    expect(baza.snemanja.firstWhere((s) => s.id == 'nov').video, 'zahtevan');
    expect(find.byKey(const ValueKey('naredi-video-nov')), findsNothing);
    expect(find.textContaining('Video je zahtevan'), findsWidgets);
  });
}
