import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/risbe.dart';
import 'package:spadni_besedila/shramba/shramba_datoteke.dart';

Risba _primer() => Risba()
  ..potezeStrani(1).add(
    Poteza(
      orodje: Orodje.marker,
      barva: 0xFFFFEB3B,
      debelina: 0.025,
      tocke: [const Offset(0.1, 0.2), const Offset(0.5, 0.2)],
    ),
  )
  ..opombeStrani(2).add(Opomba(polozaj: const Offset(0.3, 0.4), besedilo: 'Refren 2x', barva: 0xFFD32F2F));

void main() {
  test('shranjen gumb velja povsod: sprememba shranjenega spremeni postavljene, velikost ostane', () async {
    SharedPreferences.setMockInitialValues({});
    Predloge.aplikacija = Predloge();
    final p = Predloge.aplikacija;
    final id = await p.shraniGumb(GumbNaStrani(napis: 'Solo', midi: 'PC 1 5', barva: 0xFF1976D2));
    final postavljen = GumbNaStrani(napis: 'Solo', midi: 'PC 1 5', barva: 0xFF1976D2, predloga: id, velikost: 1.5);
    final risba = Risba()..gumbiStrani(0).add(postavljen);
    final iz = Risba.izBesedila(risba.vBesedilo()).gumbiStrani(0).single;
    expect(iz.predloga, id);
    expect(iz.velikost, 1.5);

    await p.shraniGumb(GumbNaStrani(napis: 'Konec', midi: 'PC 1 9', barva: 0xFFD32F2F, predloga: id));
    expect(iz.prikaz.napis, 'Konec');
    expect(iz.prikaz.velikost, 1.5);

    // Po ponovnem zagonu so shranjeni gumbi in opombe še tu.
    final idOpombe = await p.shraniOpombo(Opomba(polozaj: Offset.zero, besedilo: 'Refren 2x', barva: 0xFF000000));
    final ponovno = Predloge();
    await ponovno.nalozi();
    expect(ponovno.gumb(id)?.napis, 'Konec');
    expect(ponovno.opomba(idOpombe)?.besedilo, 'Refren 2x');
  });

  test('risba se ohrani skozi JSON', () {
    final r = Risba.izBesedila(_primer().vBesedilo());
    expect(r.poteze[1]!.single.orodje, Orodje.marker);
    expect(r.poteze[1]!.single.tocke, [const Offset(0.1, 0.2), const Offset(0.5, 0.2)]);
    expect(r.opombe[2]!.single.besedilo, 'Refren 2x');
    expect(r.prazna, isFalse);
    expect(Risba().prazna, isTrue);
  });

  test('radirka zadene potezo ob daljici, ne pa daleč od nje', () {
    final p = _primer().poteze[1]!.single;
    expect(p.blizu(const Offset(0.3, 0.21), 0.02), isTrue);
    expect(p.blizu(const Offset(0.3, 0.5), 0.02), isFalse);
  });

  test('shrani lokalno, pošlje na strežnik in prenese novejšo risbo z druge tablice', () async {
    final mapa = await Directory.systemTemp.createTemp('risbe');
    addTearDown(() => mapa.delete(recursive: true));

    final poslano = <String, String>{};
    final novejsa = (_primer()..spremenjeno = DateTime.utc(2030)).vBesedilo();
    final api = Api(
      () async => 'zeton',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        if (r.method == 'POST') {
          final telo = jsonDecode(r.body) as Map<String, dynamic>;
          poslano[telo['pesem'] as String] = telo['vsebina'] as String;
          return http.Response(jsonEncode({'shranjeno': true}), 200);
        }
        return http.Response(
          jsonEncode({
            'druga': {'vsebina': novejsa, 'spremenjeno': '2030-01-01T00:00:00Z'},
          }),
          200,
        );
      }),
    );

    final risbe = Risbe(ShrambaDatoteke(() async => mapa));
    await risbe.shrani('moja', _primer());
    expect((await risbe.nalozi('moja')).opombe[2]!.single.besedilo, 'Refren 2x');

    await risbe.sinhroniziraj(api);
    expect(poslano.keys, ['moja']);
    expect((await risbe.nalozi('druga')).poteze[1], isNotEmpty);

    // Ponovna uskladitev ne pošilja več istega.
    poslano.clear();
    await risbe.sinhroniziraj(api);
    expect(poslano, isEmpty);
  });

  test('skupne risbe: ločene od osebnih, stara skripta jih ne prepiše z osebnimi', () async {
    final mapa = await Directory.systemTemp.createTemp('skupne');
    addTearDown(() => mapa.delete(recursive: true));
    final poslano = <Map<String, dynamic>>[];
    var novaSkripta = false;
    final risba = _primer()..spremenjeno = DateTime.utc(2030);
    final api = Api(
      () async => 'zeton',
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        if (r.method == 'POST') {
          poslano.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(jsonEncode({'shranjeno': true}), 200);
        }
        final osebne = {
          'osebna': {'vsebina': risba.vBesedilo()},
        };
        if (!novaSkripta || r.url.queryParameters['skupne'] != '1') return http.Response(jsonEncode(osebne), 200);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              '_skupne': true,
              'risbe': {
                'refren': {'vsebina': risba.vBesedilo()},
              },
            }),
          ),
          200,
        );
      }),
    );
    final shramba = ShrambaDatoteke(() async => mapa);
    final skupne = Risbe(shramba, skupne: true);
    await skupne.sinhroniziraj(api);
    expect((await skupne.nalozi('osebna')).prazna, isTrue); // stara skripta vrne osebne: ne prevzame

    novaSkripta = true;
    await skupne.sinhroniziraj(api);
    expect((await skupne.nalozi('refren')).prazna, isFalse);
    expect((await Risbe(shramba).nalozi('refren')).prazna, isTrue); // osebne so ločene

    await skupne.shrani('refren', _primer());
    await skupne.posljiNeposlane();
    expect(poslano.single['skupna'], isTrue);
    expect((await skupne.izvozi(['refren', 'ni']))['risbe'], contains('refren'));
  });
}
