import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'prijava_namizje_web.dart' if (dart.library.io) 'prijava_namizje.dart';

/// Google prijava. ID žeton velja eno uro, zato se pred iztekom osveži brez interakcije.
///
/// Na Androidu prijava teče prek sistemskega okna, v brskalniku prek Googlovega gumba
/// (glej `gumb_prijave_web.dart`) in samodejne prijave One Tap; v obeh primerih
/// rezultat pride po toku [GoogleSignIn.authenticationEvents]. Na računalniku (Windows) Googlove knjižnice ni,
/// zato prijava teče prek brskalnika ([PrijavaNamizje]), osvežilni žeton pa ostane shranjen.
class Prijava extends ChangeNotifier {
  final _gsi = GoogleSignIn.instance;
  GoogleSignInAccount? racun;
  String? napaka;
  Future<void>? _priprava;

  String? _idZeton;
  Completer<void>? _cakamZeton;

  static bool get _namizje =>
      !kIsWeb && {TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS}.contains(defaultTargetPlatform);

  static const _kljucOsvezilnega = 'namizje_osvezilni';
  static const _kljucEmaila = 'namizje_email';
  String? _osvezilni;
  String? _namiznaEmail;

  bool get nastavljena => _namizje ? PrijavaNamizje.nastavljena : Config.googleServerClientId.isNotEmpty;

  /// Ali sme aplikacija klicati strežnik. Na špilu (prek vodje) prijava ni potrebna.
  bool get prijavljen => racun != null || _namiznaEmail != null || Config.prekoVodje;

  /// E-naslov prijavljenega računa.
  String? get email => racun?.email ?? _namiznaEmail;

  Future<void> zacni() => _priprava ??= _zacni();

  Future<void> _zacni() async {
    if (_namizje) {
      final p = await SharedPreferences.getInstance();
      _osvezilni = p.getString(_kljucOsvezilnega);
      _namiznaEmail = _osvezilni == null ? null : p.getString(_kljucEmaila);
      notifyListeners();
      return;
    }
    if (!nastavljena || Config.prekoVodje) return;
    // V brskalniku je isti "Web application" client ID clientId, na Androidu serverClientId.
    await _gsi.initialize(
      clientId: kIsWeb ? Config.googleServerClientId : null,
      serverClientId: kIsWeb ? null : Config.googleServerClientId,
    );
    _gsi.authenticationEvents.listen(
      _dogodek,
      onError: (Object e) {
        if (e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled) return;
        napaka = 'Prijava ni uspela: ${e is GoogleSignInException ? (e.description ?? e.code.name) : e}';
        notifyListeners();
      },
    );
    try {
      final r = await _gsi.attemptLightweightAuthentication();
      if (r != null) _prijavljen(r);
    } catch (_) {
      // brez interneta ali brez prejšnje prijave
    }
  }

  void _dogodek(GoogleSignInAuthenticationEvent e) {
    switch (e) {
      case GoogleSignInAuthenticationEventSignIn():
        _prijavljen(e.user);
      case GoogleSignInAuthenticationEventSignOut():
        racun = null;
        _idZeton = null;
        notifyListeners();
    }
  }

  void _prijavljen(GoogleSignInAccount r) {
    racun = r;
    napaka = null;
    _idZeton = r.authentication.idToken;
    _cakamZeton?.complete();
    _cakamZeton = null;
    notifyListeners();
  }

  /// Prijava s sistemskim oknom (Android). V brskalniku se uporabi Googlov gumb.
  Future<void> prijavi() async {
    napaka = null;
    if (_namizje) return _prijaviNamizje();
    try {
      await zacni();
      _prijavljen(await _gsi.authenticate());
    } on GoogleSignInException catch (e) {
      napaka = e.code == GoogleSignInExceptionCode.canceled
          ? null
          : 'Prijava ni uspela: ${e.description ?? e.code.name}';
      notifyListeners();
    } catch (e) {
      napaka = 'Prijava ni uspela: $e';
      notifyListeners();
    }
  }

  Future<void> _prijaviNamizje() async {
    try {
      final r = await PrijavaNamizje.prijavi();
      _idZeton = r.idZeton;
      _osvezilni = r.osvezilni ?? _osvezilni;
      _namiznaEmail = poljeZetona(r.idZeton, 'email') ?? '';
      final p = await SharedPreferences.getInstance();
      if (_osvezilni != null) await p.setString(_kljucOsvezilnega, _osvezilni!);
      await p.setString(_kljucEmaila, _namiznaEmail!);
    } catch (e) {
      napaka = '$e';
    }
    notifyListeners();
  }

  Future<void> odjavi() async {
    if (_namizje) {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kljucOsvezilnega);
      await p.remove(_kljucEmaila);
      _osvezilni = null;
      _namiznaEmail = null;
      _idZeton = null;
      notifyListeners();
      return;
    }
    await _gsi.signOut();
    racun = null;
    _idZeton = null;
    notifyListeners();
  }

  /// Veljaven ID žeton za klic na strežnik. Sočasni klici si delijo isto osvežitev.
  Future<String> zeton() async {
    if (Config.prekoVodje) return '';
    final z = _idZeton;
    if (z != null && veljaVsaj(z, const Duration(minutes: 5))) return z;
    if (_namizje) {
      final o = _osvezilni;
      if (o == null) throw StateError('Nisi prijavljen');
      return _idZeton = await PrijavaNamizje.osvezi(o);
    }
    final prvi = _cakamZeton == null;
    final cakam = _cakamZeton ??= Completer<void>();
    if (prvi) {
      GoogleSignInAccount? r;
      try {
        r = await _gsi.attemptLightweightAuthentication();
      } catch (_) {
        r = null;
      }
      if (r != null) {
        _prijavljen(r);
      } else if (!kIsWeb) {
        // Na Androidu je odgovor takojšen; brez računa nima smisla čakati.
        _cakamZeton = null;
        if (!cakam.isCompleted) cakam.completeError(StateError('Nisi prijavljen'));
        cakam.future.ignore();
        throw StateError('Nisi prijavljen');
      }
    }
    try {
      // V brskalniku nov žeton pride po toku dogodkov, ko One Tap prijavi uporabnika.
      await cakam.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      if (identical(_cakamZeton, cakam)) _cakamZeton = null;
      // Brez veljavnega žetona aplikacija ponudi ponovno prijavo (meni in pri urejanju).
      racun = null;
      _idZeton = null;
      notifyListeners();
      throw StateError('Prijava je potekla. Prijavi se znova.');
    }
    final nov = _idZeton;
    if (nov == null) throw StateError('Nisi prijavljen');
    return nov;
  }
}

/// Polje iz vsebine JWT žetona (npr. email).
String? poljeZetona(String jwt, String polje) {
  try {
    final deli = jwt.split('.');
    final vsebina = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(deli[1])))) as Map<String, dynamic>;
    return vsebina[polje]?.toString();
  } catch (_) {
    return null;
  }
}

/// Ali JWT žeton velja še vsaj [rezerva] (po polju exp).
bool veljaVsaj(String jwt, Duration rezerva) {
  try {
    final deli = jwt.split('.');
    final vsebina = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(deli[1])))) as Map<String, dynamic>;
    final poteka = DateTime.fromMillisecondsSinceEpoch((vsebina['exp'] as num).toInt() * 1000);
    return DateTime.now().add(rezerva).isBefore(poteka);
  } catch (_) {
    return false;
  }
}
