import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import '../baza.dart';
import '../config.dart';
import 'streznik.dart';

StreznikVodje? ustvariStreznik() => StreznikIo();

/// Strežnik vodje (Android, računalnik).
///
/// - `/` ... spletna različica iz `assets/splet/splet.zip` (za iPade v Safariju)
/// - `/api` ... isti klici kot skripta (podatki, pdf, ...), odgovori iz vodjeve lokalne kopije
/// - `/ws` ... WebSocket, po katerem gre stanje špila vsem sledilcem
class StreznikIo implements StreznikVodje {
  HttpServer? _streznik;
  final _odjemalci = <WebSocket>{};
  String? _zadnje;
  Map<String, Uint8List> _splet = {};
  void Function(int)? _obSpremembi;

  @override
  Future<String> zacni(Baza baza, void Function(int sledilcev) obSpremembi) async {
    _obSpremembi = obSpremembi;
    _splet = await _naloziSplet();
    final s = await HttpServer.bind(InternetAddress.anyIPv4, Config.vrataVodje, shared: true);
    _streznik = s;
    s.listen((zahteva) async {
      try {
        await _obdelaj(zahteva, baza);
      } catch (e) {
        try {
          zahteva.response.statusCode = HttpStatus.internalServerError;
          await zahteva.response.close();
        } catch (_) {}
      }
    });
    return 'http://${await lokalniNaslov() ?? 'localhost'}:${Config.vrataVodje}';
  }

  @override
  void poslji(String sporocilo) {
    _zadnje = sporocilo;
    for (final ws in _odjemalci.toList()) {
      try {
        ws.add(sporocilo);
      } catch (_) {
        _odjemalci.remove(ws);
      }
    }
  }

  @override
  Future<void> ustavi() async {
    for (final ws in _odjemalci.toList()) {
      await ws.close();
    }
    _odjemalci.clear();
    await _streznik?.close(force: true);
    _streznik = null;
  }

  Future<void> _obdelaj(HttpRequest z, Baza baza) async {
    final pot = z.uri.path;
    if (pot == '/ws' && WebSocketTransformer.isUpgradeRequest(z)) {
      final ws = await WebSocketTransformer.upgrade(z);
      ws.pingInterval = const Duration(seconds: 5);
      _odjemalci.add(ws);
      _obSpremembi?.call(_odjemalci.length);
      if (_zadnje != null) ws.add(_zadnje);
      ws.listen(
        null,
        onDone: () {
          _odjemalci.remove(ws);
          _obSpremembi?.call(_odjemalci.length);
        },
        onError: (Object _) {},
        cancelOnError: true,
      );
      return;
    }
    final r = z.response;
    if (pot == '/api') {
      r.headers.contentType = ContentType.json;
      if (z.method == 'POST') {
        // Risbe in dnevnik s špila zaenkrat ostanejo na napravi sledilca.
        await utf8.decoder.bind(z).join();
        r.write(jsonEncode({'shranjeno': true}));
      } else {
        r.write(await _api(z.uri.queryParameters, baza));
      }
      await r.close();
      return;
    }
    var ime = pot == '/' ? 'index.html' : pot.substring(1);
    var vsebina = _splet[ime];
    // Pot brez končnice (npr. osvežena podstran) vrne začetno stran.
    if (vsebina == null && !ime.contains('.')) vsebina = _splet[ime = 'index.html'];
    if (vsebina == null) {
      r.statusCode = HttpStatus.notFound;
      r.headers.contentType = ContentType.html;
      r.write(
        _splet.isEmpty ? '<h1>Spletna različica ni vključena v to gradnjo aplikacije.</h1>' : '<h1>Ni najdeno</h1>',
      );
      await r.close();
      return;
    }
    r.headers.set(HttpHeaders.contentTypeHeader, _vrstaVsebine(ime));
    r.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    r.add(vsebina);
    await r.close();
  }

  Future<String> _api(Map<String, String> p, Baza baza) async {
    switch (p['akcija']) {
      case 'podatki':
        return baza.podatkiZaSledilce();
      case 'pdf':
        final id = p['id'] ?? '';
        final b = await baza.pdf(id);
        if (b == null) return jsonEncode({'napaka': 'PDF-ja ni pri vodji'});
        return jsonEncode({'id': id, 'base64': base64Encode(b)});
      case 'verzija':
        return jsonEncode({'verzija': 0});
      case 'risbe':
        return jsonEncode({});
      default:
        return jsonEncode({'napaka': 'Neznana akcija'});
    }
  }

  static Future<Map<String, Uint8List>> _naloziSplet() async {
    try {
      final zip = await rootBundle.load('assets/splet/splet.zip');
      final arhiv = ZipDecoder().decodeBytes(zip.buffer.asUint8List(zip.offsetInBytes, zip.lengthInBytes));
      return {
        for (final f in arhiv)
          if (f.isFile) f.name: f.content,
      };
    } catch (_) {
      return {};
    }
  }

  static String _vrstaVsebine(String ime) {
    final koncnica = ime.contains('.') ? ime.substring(ime.lastIndexOf('.') + 1).toLowerCase() : '';
    return switch (koncnica) {
      'html' => 'text/html; charset=utf-8',
      'js' || 'mjs' => 'application/javascript',
      'json' => 'application/json',
      'wasm' => 'application/wasm',
      'png' => 'image/png',
      'ico' => 'image/x-icon',
      'css' => 'text/css',
      'ttf' => 'font/ttf',
      'otf' => 'font/otf',
      'woff2' => 'font/woff2',
      'svg' => 'image/svg+xml',
      _ => 'application/octet-stream',
    };
  }
}

/// IPv4 naslov naprave na lokalnem omrežju (WiFi ali dostopna točka), ki ga vidijo drugi.
Future<String?> lokalniNaslov() async {
  final vmesniki = await NetworkInterface.list(type: InternetAddressType.IPv4);
  // Najprej WiFi in dostopna točka telefona, šele nato ostali (npr. mobilni podatki).
  int prednost(NetworkInterface v) {
    final i = v.name.toLowerCase();
    if (i.startsWith('wlan') || i.startsWith('ap') || i.startsWith('swlan') || i.contains('wi-fi')) return 0;
    if (i.startsWith('eth') || i.startsWith('en')) return 1;
    if (i.startsWith('rmnet') || i.startsWith('ccmni')) return 3;
    return 2;
  }

  vmesniki.sort((a, b) => prednost(a).compareTo(prednost(b)));
  for (final v in vmesniki) {
    for (final a in v.addresses) {
      if (!a.isLoopback) return a.address;
    }
  }
  return null;
}
