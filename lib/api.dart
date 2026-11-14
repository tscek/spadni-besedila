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

  /// Seja aplikacije (žeton za 30 dni) za Googlov ID žeton ali za še veljavno sejo: {seja, poteka, email}.
  Future<Map<String, dynamic>> seja() => _get({'akcija': 'seja'});

  Future<Uint8List> pdf(String driveId) async {
    final odg = await _get({'akcija': 'pdf', 'id': driveId});
    return base64Decode(odg['base64'] as String);
  }

  /// Zadnja različica aplikacije za Android ali [platforma] 'windows': {verzija, url, platforma}.
  /// Administrator pošlje svoje nastavitve pogleda vsem (JSON).
  Future<Map<String, dynamic>> posljiPogled(String vsebina) => _post({'akcija': 'pogled', 'vsebina': vsebina});

  /// Nastavitve špila (samo administrator). Vrne {spil}.
  Future<Map<String, dynamic>> shraniSpil(String vsebina) => _post({'akcija': 'spil', 'vsebina': vsebina});

  /// Osebna nastavitev prijavljenega člana (npr. hitri filtri). Vrne {kljuc, vrednost}.
  Future<Map<String, dynamic>> mojaNastavitev(String kljuc, String vrednost) =>
      _post({'akcija': 'mojaNastavitev', 'kljuc': kljuc, 'vrednost': vrednost});

  /// Skupna postavitev FX panela in XY pada (samo administrator). Vrne {fx}.
  Future<Map<String, dynamic>> shraniFx(String vsebina) => _post({'akcija': 'fx', 'vsebina': vsebina});

  /// Efekt v knjižnici: nov (z bajti), preimenovan ali izbrisan. Vrne {vrstica} ali {izbrisano}.
  Future<Map<String, dynamic>> shraniEfekt({
    String? id,
    String ime = '',
    Uint8List? bajti,
    String vrsta = '',
    bool izbrisi = false,
  }) => _post({
    'akcija': 'efekt',
    'id': ?id,
    'ime': ime,
    if (bajti != null) ...{'vrsta': vrsta, 'base64': base64Encode(bajti)},
    if (izbrisi) 'izbrisi': true,
  });

  Future<({Uint8List bajti, String vrsta})> efekt(String id) async {
    final j = await _get({'akcija': 'efekt', 'id': id});
    return (bajti: base64Decode(j['base64'] as String), vrsta: (j['vrsta'] ?? '').toString());
  }

  Future<Map<String, dynamic>> verzija({String? platforma}) => _get({'akcija': 'verzija', 'platforma': ?platforma});

  /// Vse risbe prijavljenega člana: {pesem: {vsebina, spremenjeno}}.
  /// Z [skupne] skupne risbe pesmi: {_skupne: true, risbe: {pesem: {vsebina, spremenjeno}}}.
  Future<Map<String, dynamic>> risbe({bool skupne = false}) => _get({'akcija': 'risbe', if (skupne) 'skupne': '1'});

  /// Shrani risbo pesmi na strežnik; prazna vsebina jo izbriše.
  Future<void> risba(String pesem, String vsebina, {bool skupna = false}) =>
      _post({'akcija': 'risba', 'pesem': pesem, 'vsebina': vsebina, if (skupna) 'skupna': true});

  /// Vodja: risbe članov njegovih skupin {član: {pesem: {vsebina, spremenjeno}}}.
  /// Z [od] nova skripta vrne samo spremenjene: {_od: true, cas, risbe: {...}}.
  Future<Map<String, dynamic>> risbeClanov({String? od}) => _get({'akcija': 'risbeClanov', 'od': ?od});

  /// Vodja: shrani risbo, ki jo je član naredil na špilu (na iPadu prek vodje).
  Future<void> risbaZa(String clan, String pesem, String vsebina) =>
      _post({'akcija': 'risbaZa', 'clan': clan, 'pesem': pesem, 'vsebina': vsebina});

  /// Shrani pesem (brez ID = nova). Vrne zapisano vrstico lista Pesmi.
  Future<Map<String, dynamic>> shraniPesem(Map<String, dynamic> pesem) => _post({'akcija': 'pesem', 'pesem': pesem});

  /// Hitro urejanje: več pesmi (ID in spremenjena polja) naenkrat; vrne {vrstice}.
  Future<Map<String, dynamic>> shraniPesmi(List<Map<String, dynamic>> pesmi) =>
      _post({'akcija': 'pesmi', 'pesmi': pesmi});

  /// Samostojna kopija pesmi v drugi mapi; vrne {pesem, besedila, pdf}.
  Future<Map<String, dynamic>> kopirajPesem(String pesem, String mapa) =>
      _post({'akcija': 'kopirajPesem', 'pesem': pesem, 'mapa': mapa});

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
  /// Ukaz nad mapo (samo administrator): premakni, kopiraj (v [zasedba]), izprazni, izbrisi.
  Future<Map<String, dynamic>> mapaUkaz(String ukaz, String mapa, {String? zasedba, bool trajno = false}) =>
      _post({'akcija': 'mapaUkaz', 'ukaz': ukaz, 'mapa': mapa, 'zasedba': ?zasedba, if (trajno) 'trajno': true});

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

  /// Zvočni posnetek pesmi (vrstica lista Posnetki in zvok). Vrne {vrstica}.
  Future<Map<String, dynamic>> dodajPosnetek(Map<String, dynamic> posnetek, Uint8List bajti) =>
      _post({'akcija': 'posnetek', 'posnetek': posnetek, 'base64': base64Encode(bajti)});

  /// Zvok posnetka (svojega ali skupnega).
  Future<Uint8List> posnetek(String id) async =>
      base64Decode((await _get({'akcija': 'posnetek', 'id': id}))['base64'] as String);

  /// Shrani zvočni uvod ali playback pesmi ([kaj] 'uvod' ali 'playback'; na Drive, stari gre v koš);
  /// brez [bajti] ga izbriše. Vrne {vrstica}.
  Future<Map<String, dynamic>> shraniZvok(
    String kaj,
    String pesem,
    Uint8List? bajti, {
    String vrsta = '',
    double od = 0,
    double? doo,
    bool posnet = false,
  }) => _post({
    'akcija': 'uvod',
    'kaj': kaj,
    'pesem': pesem,
    if (bajti != null) ...{'vrsta': vrsta, 'base64': base64Encode(bajti), 'od': od, 'do': ?doo, 'posnet': posnet},
  });

  /// Zvok uvoda ali playbacka pesmi.
  Future<Uint8List> zvok(String kaj, String pesem) async =>
      base64Decode((await _get({'akcija': 'uvod', 'kaj': kaj, 'pesem': pesem}))['base64'] as String);

  /// GitHub odstrani vokal iz playbacka (nekaj minut). Vrne {vrstica} s stanjem »čaka«.
  Future<Map<String, dynamic>> odstraniVokal(String pesem) => _post({'akcija': 'odstraniVokal', 'pesem': pesem});

  /// Playback z vokalom nazaj. Vrne {vrstica}.
  Future<Map<String, dynamic>> vrniIzvirnik(String pesem) => _post({'akcija': 'vrniIzvirnik', 'pesem': pesem});

  /// Nastopi iz Nastopov okrog datuma (±1 dan): {nastopi: [{ID, Datum, Kraj, Dogodek, Zasedba, ZasedbaIme, Od}]}.
  Future<Map<String, dynamic>> nastopi(DateTime datum) => _get({
    'akcija': 'nastopi',
    'datum': '${datum.year}-${datum.month.toString().padLeft(2, '0')}-${datum.day.toString().padLeft(2, '0')}',
  });

  /// Nova ali spremenjena vrstica snemanja špila.
  Future<Map<String, dynamic>> snemanje(Map<String, dynamic> vrstica) =>
      _post({'akcija': 'snemanje', 'snemanje': vrstica});

  /// Kos posnetka špila (ponovno poslan kos se ne podvoji).
  Future<Map<String, dynamic>> snemanjeKos({
    required String id,
    required int i,
    required String zacetek,
    required int trajanje,
    required Uint8List bajti,
  }) => _post({
    'akcija': 'snemanjeKos',
    'id': id,
    'i': i,
    'zacetek': zacetek,
    'trajanje': trajanje,
    'vrsta': 'audio/mp4',
    'koncnica': 'm4a',
    'base64': base64Encode(bajti),
  });

  /// Sličice članov (stolpec Slika v Nastopih): {ID: {slika, base64}}.
  Future<Map<String, dynamic>> slikeClanov() => _get({'akcija': 'slikeClanov'});

  /// Stran z besedilo.si prek skripte (spletna različica je zaradi CORS ne more brati sama): {status, telo}.
  Future<Map<String, dynamic>> besedilosi(String url) => _get({'akcija': 'besedilosi', 'url': url});

  /// Nov naslov posnetka (svojega; administrator vseh).
  Future<Map<String, dynamic>> preimenujPosnetek(String id, String ime) =>
      _post({'akcija': 'posnetekIme', 'id': id, 'ime': ime});

  /// Izbriše posnetek (svojega; administrator tudi tuje skupne).
  Future<Map<String, dynamic>> izbrisiPosnetek(String id) => _post({'akcija': 'posnetekIzbrisi', 'id': id});

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
