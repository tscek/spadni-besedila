import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spadni_besedila/besedilo_si.dart';

const _vsebina =
    '<p>Prva vrstica<br />\nDruga vrstica &#8211; da<br />\nTretja</p>\n'
    '<p><strong>Refren ena<br />\nRefren dva &#8217;s</strong></p>\n';

final _rest = jsonEncode([
  {
    'id': 35829,
    'slug': 'malo-se-pocakaj',
    'link': 'https://besedilo.si/ema/malo-se-pocakaj',
    'title': {'rendered': 'Malo še počakaj'},
    'content': {'rendered': _vsebina},
    '_embedded': {
      'wp:term': [
        [
          {'id': 1292, 'name': 'Ema', 'taxonomy': 'category'},
        ],
        [],
      ],
    },
  },
  {
    'id': 1,
    'slug': 'malo-malo',
    'link': 'https://besedilo.si/sank-rock/malo-malo',
    'title': {'rendered': 'Malo, malo'},
    'content': {'rendered': '<p>x</p>'},
  },
]);

const _stran = '''
<html><head><script>var x = "Izvajalec: ne";</script></head><body>
<h1>Malo še počakaj</h1>
<p><strong>Izvajalec:</strong> <a href="https://besedilo.si/avtorji/ema">Ema</a><br/>
Avtor besedila: Matej Kocjančič<br/>Avtor glasbe: Marjan Turk</p>
<div class="besedilo"><p>Prva vrstica</p></div>
</body></html>''';

void main() {
  test('besedilo iz HTML objave', () {
    expect(besediloIzHtml(_vsebina), 'Prva vrstica\nDruga vrstica – da\nTretja\n\nRefren ena\nRefren dva ’s');
  });

  test('zadetki iz REST: izvajalec iz kategorije ali povezave, ujemanje naslova na vrhu', () {
    final z = razvrsti(razcleniRest(_rest), 'MALO, MALO');
    expect(z.map((p) => p.naslov), ['Malo, malo', 'Malo še počakaj']);
    expect(z.first.izvajalec, 'Sank Rock');
    expect(z.last.izvajalec, 'Ema');
    expect(z.last.slug, 'malo-se-pocakaj');
  });

  test('avtorji s strani pesmi, tudi v isti vrstici in z različicami oznak', () {
    expect(avtorjiIzStrani(_stran), {
      'Izvajalec': 'Ema',
      'Avtor besedila': 'Matej Kocjančič',
      'Avtor glasbe': 'Marjan Turk',
    });
    expect(
      avtorjiIzStrani(
        '<p>Izvajalec: Plava Trava Zelena Avtor slovenskega besedila: Ivan Novak Avtor pesmi: Tom J.</p>',
      ),
      {'Izvajalec': 'Plava Trava Zelena', 'Avtor besedila': 'Ivan Novak', 'Avtor glasbe': 'Tom J.'},
    );
  });

  test('zadetki iz strani iskanja', () {
    const html = '''
      <a href="https://besedilo.si/avtorji/ema">Ema</a>
      <h2><a href="https://besedilo.si/ema/malo-se-pocakaj/">Malo še počakaj</a></h2>
      <a href="https://besedilo.si/page/2?s=malo">2</a>
      <a href="https://besedilo.si/gadi/malo-malo-se">Malo, malo &#353;e</a>
      <a href="https://besedilo.si/ema/malo-se-pocakaj">Malo še počakaj</a>''';
    final z = razcleniIskanje(html);
    expect(z.map((p) => (p.naslov, p.izvajalec)), [('Malo še počakaj', 'Ema'), ('Malo, malo še', 'Gadi')]);
  });

  test('iskanje in podrobnosti prek http', () async {
    final klici = <String>[];
    final vir = BesediloSi(
      splet: false,
      client: MockClient((r) async {
        klici.add(r.url.toString());
        if (r.url.path.startsWith('/wp-json/')) {
          return http.Response.bytes(utf8.encode(_rest), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response.bytes(utf8.encode(_stran), 200);
      }),
    );
    final z = await vir.isci('Malo še počakaj');
    expect(z.first.naslov, 'Malo še počakaj');
    expect(Uri.parse(klici.first).queryParameters['search'], 'Malo še počakaj');
    final p = await vir.podrobnosti(z.first);
    expect((p.izvajalec, p.avtorBesedila, p.avtorGlasbe), ('Ema', 'Matej Kocjančič', 'Marjan Turk'));
    expect(p.besedilo, startsWith('Prva vrstica'));
  });
}
