import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api.dart';

/// Pesem z besedilo.si: naslov, izvajalec, povezava in (ko je prebrano) besedilo ter avtorji.
class PesemBs {
  PesemBs({required this.naslov, required this.povezava, this.izvajalec = '', this.besedilo});

  final String naslov;
  final String povezava;
  String izvajalec;

  /// Besedilo kot navaden tekst (kitice ločene s prazno vrstico); null, dokler ni prebrano.
  String? besedilo;
  String avtorBesedila = '';
  String avtorGlasbe = '';

  /// Zadnji del povezave (slug objave), npr. »malo-se-pocakaj«.
  String get slug => Uri.parse(povezava).pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
}

/// Iskanje in uvoz z besedilo.si (WordPress): iskanje in besedilo prek WordPress REST, avtorji s strani pesmi.
/// Brskalnik strani pesmi ne sme brati (CORS), zato jo v spletni različici prebere skripta.
class BesediloSi {
  BesediloSi({http.Client? client, this.api, bool? splet})
    : _client = client ?? http.Client(),
      _splet = splet ?? kIsWeb;

  final http.Client _client;
  final Api? api;
  final bool _splet;

  static const _osnova = 'https://besedilo.si';

  Future<String> _beri(Uri uri, {bool cors = false}) async {
    // REST pošilja glave CORS, navadne strani ne; te v brskalniku bere skripta.
    if (!_splet || cors) {
      try {
        final odg = await _client.get(uri).timeout(const Duration(seconds: 20));
        if (odg.statusCode == 200) return utf8.decode(odg.bodyBytes);
        throw Exception('besedilo.si: ${odg.statusCode}');
      } catch (_) {
        if (!_splet || api == null) rethrow;
      }
    }
    final a = api;
    if (a == null) throw Exception('besedilo.si ni dosegljiv');
    final odg = await a.besedilosi(uri.toString());
    if (odg['napaka'] != null) throw Exception(odg['napaka']);
    return odg['telo']?.toString() ?? '';
  }

  /// Zadetki za iskanje (najprej po naslovu prek REST, sicer iskalnik strani).
  Future<List<PesemBs>> isci(String niz) async {
    final q = niz.trim();
    if (q.isEmpty) return const [];
    final rest = Uri.parse('$_osnova/wp-json/wp/v2/posts')
        .replace(queryParameters: {'search': q, 'per_page': '20', '_embed': 'wp:term'});
    try {
      final zadetki = razcleniRest(await _beri(rest, cors: true));
      if (zadetki.isNotEmpty) return razvrsti(zadetki, q);
    } catch (_) {}
    final html = await _beri(Uri.parse('$_osnova/').replace(queryParameters: {'s': q}));
    return razvrsti(razcleniIskanje(html), q);
  }

  /// Prebere besedilo (če ga še ni) in avtorje s strani pesmi.
  Future<PesemBs> podrobnosti(PesemBs p) async {
    if (p.besedilo == null) {
      final rest = Uri.parse('$_osnova/wp-json/wp/v2/posts').replace(queryParameters: {'slug': p.slug});
      final z = razcleniRest(await _beri(rest, cors: true));
      if (z.isNotEmpty) {
        p.besedilo = z.first.besedilo;
        if (p.izvajalec.isEmpty) p.izvajalec = z.first.izvajalec;
      }
    }
    try {
      final a = avtorjiIzStrani(await _beri(Uri.parse(p.povezava)));
      if (a['Izvajalec'] case final i? when p.izvajalec.isEmpty) p.izvajalec = i;
      p.avtorBesedila = a['Avtor besedila'] ?? '';
      p.avtorGlasbe = a['Avtor glasbe'] ?? '';
    } catch (_) {
      // Brez avtorjev (npr. skripta še nima akcije) ostane vsaj besedilo.
    }
    return p;
  }
}

/// Zadetki iz WordPress REST (seznam objav).
List<PesemBs> razcleniRest(String telo) {
  final j = jsonDecode(telo);
  if (j is! List) return const [];
  return [
    for (final o in j.whereType<Map<String, dynamic>>())
      if (o['link'] case final String link)
        PesemBs(
          naslov: odHtml((o['title'] as Map?)?['rendered']?.toString() ?? ''),
          povezava: link,
          izvajalec: _izvajalecIzEmbed(o) ?? _izvajalecIzPovezave(link),
          besedilo: besediloIzHtml((o['content'] as Map?)?['rendered']?.toString() ?? ''),
        ),
  ];
}

String? _izvajalecIzEmbed(Map<String, dynamic> o) {
  final termi = (o['_embedded'] as Map?)?['wp:term'];
  if (termi is! List) return null;
  for (final skupina in termi) {
    if (skupina is! List) continue;
    for (final t in skupina) {
      if (t is Map && t['taxonomy'] == 'category' && (t['name']?.toString() ?? '').isNotEmpty) {
        return odHtml(t['name'].toString());
      }
    }
  }
  return null;
}

/// Izvajalec iz povezave, ko ga ni drugje: »/ema/malo-se-pocakaj« → »Ema«.
String _izvajalecIzPovezave(String link) {
  final deli = Uri.parse(link).pathSegments.where((s) => s.isNotEmpty).toList();
  if (deli.length < 2) return '';
  return deli.first.split('-').map((b) => b.isEmpty ? b : b[0].toUpperCase() + b.substring(1)).join(' ');
}

/// Zadetki iz strani iskanja (?s=): povezave oblike https://besedilo.si/izvajalec/pesem.
List<PesemBs> razcleniIskanje(String html) {
  final out = <PesemBs>[];
  final videne = <String>{};
  final re = RegExp(
    r'''<a[^>]+href=["'](https?://(?:www\.)?besedilo\.si/([^/"'?#]+)/([^/"'?#]+)/?)["'][^>]*>(.*?)</a>''',
    dotAll: true,
  );
  const neso = {'avtorji', 'page', 'category', 'tag', 'wp-content', 'wp-admin', 'wp-json', 'author', 'feed'};
  for (final m in re.allMatches(html)) {
    final link = m.group(1)!;
    if (neso.contains(m.group(2)) || !videne.add(link.replaceAll(RegExp(r'/$'), ''))) continue;
    final naslov = odHtml(m.group(4)!.replaceAll(RegExp(r'<[^>]*>'), '')).trim();
    if (naslov.isEmpty) continue;
    out.add(PesemBs(naslov: naslov, povezava: link, izvajalec: _izvajalecIzPovezave(link)));
  }
  return out;
}

/// Zadetki, katerih naslov se ujema z iskanim, gredo na vrh.
List<PesemBs> razvrsti(List<PesemBs> s, String q) {
  final iskano = poenostaviBs(q);
  int ocena(PesemBs p) {
    final n = poenostaviBs(p.naslov);
    if (n == iskano) return 0;
    if (n.startsWith(iskano)) return 1;
    if (n.contains(iskano)) return 2;
    return 3;
  }

  final kopija = [...s];
  mergeSort(kopija, compare: (a, b) => ocena(a).compareTo(ocena(b)));
  return kopija;
}

/// Male črke brez šumnikov in ločil, za primerjavo naslovov.
String poenostaviBs(String s) => s
    .toLowerCase()
    .replaceAll('č', 'c')
    .replaceAll('š', 's')
    .replaceAll('ž', 'z')
    .replaceAll('ć', 'c')
    .replaceAll('đ', 'd')
    .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Besedilo objave (HTML z <p> in <br />) kot navaden tekst; kitice ločene s prazno vrstico.
String besediloIzHtml(String html) {
  var t = html
      .replaceAll(RegExp(r'<br\s*/?>\s*', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>\s*', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  t = odHtml(t);
  final vrstice = t.split('\n').map((v) => v.trim()).join('\n');
  return vrstice.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Izvajalec in avtorja s strani pesmi (oznake »Izvajalec:«, »Avtor besedila:«, »Avtor glasbe:« in različice).
Map<String, String> avtorjiIzStrani(String html) {
  final telo = html
      .replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', dotAll: true, caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<br\s*/?>|</(p|div|li|h\d|tr|span|strong|b)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), ' ');
  final t = odHtml(telo);
  final oznake = RegExp(
    r'(Izvajalec|Izvajalci|Avtor(?:ji)?\s+(?:slovenskega\s+)?besedila|Avtor(?:ji)?\s+glasbe|Avtor(?:ji)?\s+pesmi|'
    r'Priredba(?:\s+skladbe)?|Aranžma)\s*:',
  );
  final ujemanja = oznake.allMatches(t).toList();
  final out = <String, String>{};
  for (var i = 0; i < ujemanja.length; i++) {
    final m = ujemanja[i];
    final konec = i + 1 < ujemanja.length ? ujemanja[i + 1].start : t.length;
    var vrednost = t.substring(m.end, konec);
    final nl = vrednost.indexOf('\n');
    if (nl >= 0 && vrednost.substring(0, nl).trim().isNotEmpty) vrednost = vrednost.substring(0, nl);
    vrednost = vrednost.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (vrednost.isEmpty || vrednost.length > 120) continue;
    final o = m.group(1)!.toLowerCase();
    final kljuc = o.startsWith('izvajal')
        ? 'Izvajalec'
        : o.contains('besedila')
        ? 'Avtor besedila'
        : (o.contains('glasbe') || o.contains('pesmi'))
        ? 'Avtor glasbe'
        : null;
    if (kljuc != null) out.putIfAbsent(kljuc, () => vrednost);
  }
  return out;
}

const _imenovane = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'hellip': '…',
  'ndash': '–',
  'mdash': '—',
  'laquo': '«',
  'raquo': '»',
  'bdquo': '„',
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
};

/// Razreši znake HTML (&#8217;, &amp; …).
String odHtml(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
  final k = m.group(1)!;
  if (k.startsWith('#x')) return String.fromCharCode(int.parse(k.substring(2), radix: 16));
  if (k.startsWith('#')) return String.fromCharCode(int.parse(k.substring(1)));
  return _imenovane[k] ?? m.group(0)!;
});
