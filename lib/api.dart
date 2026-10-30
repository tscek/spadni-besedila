import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

class ApiNapaka implements Exception {
  ApiNapaka(this.sporocilo);
  final String sporocilo;

  @override
  String toString() => sporocilo;
}

/// Strežnik ni dosegljiv (ni interneta).
class NiPovezave extends ApiNapaka {
  NiPovezave() : super('Ni povezave s strežnikom. Preveri internet in poskusi znova.');
}

/// Klici na Apps Script (besedila-api.gs). Vsak klic nosi Google ID žeton člana.
class Api {
  Api(this._zeton, {http.Client? client, String? url, this.clan})
    : _client = client ?? http.Client(),
      _url = url ?? Config.apiUrl;

  final Future<String> Function() _zeton;

  /// iPad na špilu (brez prijave): član, ki ga je izbral, da vodja ve, čigave so risbe.
  final String? clan;
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

  /// Vodja: risbe vseh članov njegovih skupin {član: {pesem: {vsebina, spremenjeno}}}.
  Future<Map<String, dynamic>> risbeClanov() => _get({'akcija': 'risbeClanov'});

  /// Vodja: shrani risbo, ki jo je član naredil na špilu (na iPadu prek vodje).
  Future<void> risbaZa(String clan, String pesem, String vsebina) =>
      _post({'akcija': 'risbaZa', 'clan': clan, 'pesem': pesem, 'vsebina': vsebina});

  /// Shrani pesem (brez ID = nova). Vrne zapisano vrstico lista Pesmi.
  Future<Map<String, dynamic>> shraniPesem(Map<String, dynamic> pesem) => _post({'akcija': 'pesem', 'pesem': pesem});

  /// Shrani besedilo pesmi (brez ID = novo, prazno besedilo = izbriši).
  /// Vrne {vrstica} ali {izbrisano: ID}.
  Future<Map<String, dynamic>> shraniBesedilo(Map<String, dynamic> besedilo) =>
      _post({'akcija': 'besedilo', 'besedilo': besedilo});

  /// Shrani setlisto in njene pesmi v podanem vrstnem redu. Vrne {setlista, pesmi}.
  Future<Map<String, dynamic>> shraniSetlisto(Map<String, dynamic> setlista, List<Map<String, dynamic>> pesmi) =>
      _post({'akcija': 'setlista', 'setlista': setlista, 'pesmi': pesmi});

  Future<Map<String, dynamic>> izbrisiSetlisto(String id) => _post({
    'akcija': 'setlista',
    'setlista': {'ID': id},
    'izbrisi': true,
  });

  /// Shrani ali izbriše vrstico na listu MIDI ukazi, Makri, MIDI gumbi ali MIDI kanali.
  Future<Map<String, dynamic>> shraniMidi(String tabela, Map<String, dynamic> vrstica, {bool izbrisi = false}) =>
      _post({'akcija': 'midi', 'tabela': tabela, 'vrstica': vrstica, 'izbrisi': izbrisi});

  /// Klicaj »za vajo« na pesmi (sme vsak član). Vrne {vrstica}.
  Future<Map<String, dynamic>> zaVajo(String pesem, bool vrednost) =>
      _post({'akcija': 'zaVajo', 'pesem': pesem, 'vrednost': vrednost});

  /// Klicaj na mestu v pesmi (sme vsak član); z [izbrisi] ga odstrani.
  Future<Map<String, dynamic>> klicaj(Map<String, dynamic> klicaj, {bool izbrisi = false}) =>
      _post({'akcija': 'klicaj', 'klicaj': klicaj, 'izbrisi': izbrisi});

  /// Doda PDF pesmi (na Drive v mapo PDF). Vrne {vrstica} lista PDF.
  Future<Map<String, dynamic>> dodajPdf(String pesem, String ime, String vrsta, Uint8List bajti) =>
      _post({'akcija': 'pdfDodaj', 'pesem': pesem, 'ime': ime, 'vrsta': vrsta, 'base64': base64Encode(bajti)});

  /// Odstrani PDF pesmi (datoteka gre v koš na Drivu).
  Future<Map<String, dynamic>> izbrisiPdf(String id) => _post({'akcija': 'pdfIzbrisi', 'id': id});

  /// iPad na špilu: vodja pošlje ukaze na svoje MIDI naprave. Vrne število ukazov, ki niso imeli naprave.
  Future<int> posljiMidi(List<Map<String, dynamic>> ukazi) async {
    final odg = await _post({'akcija': 'posljiMidi', 'ukazi': ukazi});
    if (odg['vklopljen'] == false) throw ApiNapaka('Vodja nima vklopljenega MIDI');
    return (odg['brezNaprave'] as num?)?.toInt() ?? 0;
  }

  Future<void> dnevnik(List<Map<String, dynamic>> vrstice) => _post({'akcija': 'dnevnik', 'vrstice': vrstice});

  /// Kolikokrat ponovimo klic, ko povezava pade (npr. "Connection reset by peer" na slabem WiFi-ju).
  static const poskusi = 3;

  Future<Map<String, dynamic>> _get(Map<String, String> parametri) async {
    final uri = Uri.parse(_url).replace(queryParameters: {...parametri, 'zeton': await _zeton(), 'clan': ?clan});
    final odg = await _sPonovitvijo(() => _client.get(uri));
    return _odgovor(odg);
  }

  Future<http.Response> _sPonovitvijo(Future<http.Response> Function() klic, {int poskusov = poskusi}) async {
    for (var i = 1; ; i++) {
      try {
        return await klic();
      } on http.ClientException {
        // Sporočilo napake vsebuje celoten naslov z žetonom, zato ga ne prikažemo.
        if (i >= poskusov) throw NiPovezave();
        await Future<void>.delayed(Duration(milliseconds: 500 * i));
      }
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> telo) async {
    final zahteva = http.Request('POST', Uri.parse(_url))
      // Brskalnik preusmeritev skripte izvede sam (z GET); brez tega bi vsak POST v spletni različici padel.
      ..followRedirects = kIsWeb
      ..headers['Content-Type'] = 'text/plain;charset=utf-8'
      ..body = jsonEncode({...telo, 'zeton': await _zeton(), 'clan': ?clan});
    // POST ne ponavljamo: če je skripta zahtevo že izvedla, bi se zapis podvojil.
    var odg = await _sPonovitvijo(() async => http.Response.fromStream(await _client.send(zahteva)), poskusov: 1);
    // Apps Script po POST preusmeri na stran z rezultatom, ki jo je treba prebrati z GET.
    final naprej = odg.headers['location'];
    if (odg.statusCode == 302 && naprej != null) {
      odg = await _sPonovitvijo(() => _client.get(Uri.parse(naprej)));
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
