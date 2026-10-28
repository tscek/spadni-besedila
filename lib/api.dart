import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiNapaka implements Exception {
  ApiNapaka(this.sporocilo);
  final String sporocilo;

  @override
  String toString() => sporocilo;
}

/// Klici na Apps Script (besedila-api.gs). Vsak klic nosi Google ID žeton člana.
class Api {
  Api(this._zeton, {http.Client? client, String? url}) : _client = client ?? http.Client(), _url = url ?? Config.apiUrl;

  final Future<String> Function() _zeton;
  final http.Client _client;
  final String _url;

  Future<Map<String, dynamic>> podatki() => _get({'akcija': 'podatki'});

  Future<Uint8List> pdf(String driveId) async {
    final odg = await _get({'akcija': 'pdf', 'id': driveId});
    return base64Decode(odg['base64'] as String);
  }

  /// Zadnja različica Android aplikacije: {verzija, url}.
  Future<Map<String, dynamic>> verzija() => _get({'akcija': 'verzija'});

  /// Vse risbe prijavljenega člana: {pesem: {vsebina, spremenjeno}}.
  Future<Map<String, dynamic>> risbe() => _get({'akcija': 'risbe'});

  /// Shrani risbo pesmi na strežnik; prazna vsebina jo izbriše.
  Future<void> risba(String pesem, String vsebina) => _post({'akcija': 'risba', 'pesem': pesem, 'vsebina': vsebina});

  Future<void> dnevnik(List<Map<String, dynamic>> vrstice) => _post({'akcija': 'dnevnik', 'vrstice': vrstice});

  Future<Map<String, dynamic>> _get(Map<String, String> parametri) async {
    final uri = Uri.parse(_url).replace(queryParameters: {...parametri, 'zeton': await _zeton()});
    final odg = await _client.get(uri);
    return _odgovor(odg);
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> telo) async {
    final zahteva = http.Request('POST', Uri.parse(_url))
      ..followRedirects = false
      ..headers['Content-Type'] = 'text/plain;charset=utf-8'
      ..body = jsonEncode({...telo, 'zeton': await _zeton()});
    var odg = await http.Response.fromStream(await _client.send(zahteva));
    // Apps Script po POST preusmeri na stran z rezultatom, ki jo je treba prebrati z GET.
    final naprej = odg.headers['location'];
    if (odg.statusCode == 302 && naprej != null) {
      odg = await _client.get(Uri.parse(naprej));
    }
    return _odgovor(odg);
  }

  Map<String, dynamic> _odgovor(http.Response odg) {
    if (odg.statusCode != 200) {
      throw ApiNapaka('Strežnik je vrnil napako ${odg.statusCode}');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(odg.bodyBytes));
    } on FormatException {
      throw ApiNapaka(
        'Strežnik ni vrnil podatkov (preveri naslov skripte in uvedbo). Odgovor: ${povzetekHtml(odg.body)}',
      );
    }
    if (json is! Map<String, dynamic>) throw ApiNapaka('Nepričakovan odgovor strežnika');
    if (json['napaka'] != null) throw ApiNapaka(json['napaka'].toString());
    return json;
  }
}

/// Kratek berljiv povzetek HTML strani (naslov ali začetek besedila), za sporočilo o napaki.
String povzetekHtml(String html) {
  final naslov = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(html)?.group(1)?.trim();
  final besedilo = html
      .replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final kratko = besedilo.length > 160 ? '${besedilo.substring(0, 160)} …' : besedilo;
  return [if (naslov != null && naslov.isNotEmpty) naslov, kratko].join(' | ');
}
