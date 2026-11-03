import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/prijava.dart';

String _seja(Duration cez) {
  final v = base64Url
      .encode(utf8.encode(jsonEncode({'e': 'a@b.si', 'x': DateTime.now().add(cez).millisecondsSinceEpoch})))
      .replaceAll('=', '');
  return 'sb1.$v.podpis';
}

void main() {
  tearDown(() => Prijava.tovarnaApi = Api.new);

  test('veljavnost seje', () {
    expect(veljaSeja(_seja(const Duration(days: 30)), const Duration(days: 7)), isTrue);
    expect(veljaSeja(_seja(const Duration(days: 3)), const Duration(days: 7)), isFalse);
    expect(veljaSeja(_seja(const Duration(minutes: -1)), Duration.zero), isFalse);
    expect(veljaSeja('eyJ.abc.def', Duration.zero), isFalse);
  });

  test('shranjena seja: prijavljen brez Googla, skoraj potekla se podaljša', () async {
    final stara = _seja(const Duration(days: 2));
    final nova = _seja(const Duration(days: 30));
    SharedPreferences.setMockInitialValues({'seja': stara, 'seja_email': 'a@b.si'});
    final zahteve = <Uri>[];
    Prijava.tovarnaApi = (z) => Api(
      z,
      url: 'https://example.com/exec',
      client: MockClient((r) async {
        zahteve.add(r.url);
        return http.Response(jsonEncode({'seja': nova, 'email': 'a@b.si'}), 200);
      }),
    );
    final p = Prijava();
    await p.zacni();
    expect(p.prijavljen, isTrue);
    expect(p.email, 'a@b.si');
    expect(await p.zeton(), stara); // takoj, podaljšanje teče v ozadju
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(zahteve.single.queryParameters['zeton'], stara);
    expect(await p.zeton(), nova);
    expect((await SharedPreferences.getInstance()).getString('seja'), nova);

    await p.odjavi();
    expect(p.email, isNull);
  });
}
