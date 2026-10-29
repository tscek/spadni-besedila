import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';

/// Google prijava na računalniku (Windows): odpre brskalnik, Google vrne kodo na lokalni naslov
/// (http://127.0.0.1:vrata), aplikacija jo zamenja za ID žeton in osvežilni žeton.
class PrijavaNamizje {
  static const _scope = 'openid email';

  static bool get nastavljena => Config.googleDesktopClientId.isNotEmpty;

  /// Vrne (ID žeton, osvežilni žeton).
  static Future<({String idZeton, String? osvezilni})> prijavi() async {
    final streznik = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final preusmeritev = 'http://127.0.0.1:${streznik.port}';
      final preverjalnik = _nakljucno(64);
      final izziv = base64Url.encode(sha256.convert(ascii.encode(preverjalnik)).bytes).replaceAll('=', '');
      final stanje = _nakljucno(16);
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': Config.googleDesktopClientId,
        'redirect_uri': preusmeritev,
        'response_type': 'code',
        'scope': _scope,
        'code_challenge': izziv,
        'code_challenge_method': 'S256',
        'state': stanje,
        'access_type': 'offline',
        'prompt': 'select_account consent',
      });
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('Brskalnika ni bilo mogoče odpreti');
      }
      final zahteva = await streznik.first.timeout(const Duration(minutes: 5));
      final q = zahteva.uri.queryParameters;
      zahteva.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<meta charset="utf-8"><h2>Prijava ${q['code'] != null ? 'uspela' : 'ni uspela'}.</h2>'
          '<p>To okno lahko zapreš in se vrneš v aplikacijo Špadni besedila.</p>',
        );
      await zahteva.response.close();
      if (q['state'] != stanje || q['code'] == null) throw StateError('Prijava ni uspela: ${q['error'] ?? 'ni kode'}');
      final odg = await _zeton({
        'grant_type': 'authorization_code',
        'code': q['code']!,
        'code_verifier': preverjalnik,
        'redirect_uri': preusmeritev,
      });
      return (idZeton: odg['id_token'] as String, osvezilni: odg['refresh_token'] as String?);
    } finally {
      await streznik.close(force: true);
    }
  }

  /// Nov ID žeton z osvežilnim žetonom (brez brskalnika).
  static Future<String> osvezi(String osvezilni) async {
    final odg = await _zeton({'grant_type': 'refresh_token', 'refresh_token': osvezilni});
    return odg['id_token'] as String;
  }

  static Future<Map<String, dynamic>> _zeton(Map<String, String> polja) async {
    final r = await http.post(
      Uri.https('oauth2.googleapis.com', '/token'),
      body: {...polja, 'client_id': Config.googleDesktopClientId, 'client_secret': Config.googleDesktopClientSecret},
    );
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200 || j['id_token'] == null) {
      throw StateError('Prijava ni uspela: ${j['error_description'] ?? j['error'] ?? r.statusCode}');
    }
    return j;
  }

  static String _nakljucno(int dolzina) {
    const znaki = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List.generate(dolzina, (_) => znaki[r.nextInt(znaki.length)]).join();
  }
}
