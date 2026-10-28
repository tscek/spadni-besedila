import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/risbe.dart';

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

    final risbe = Risbe(() async => mapa);
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
}
