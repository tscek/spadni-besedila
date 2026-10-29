import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'config.dart';

/// Google prijava. ID žeton velja eno uro, zato se pred iztekom osveži brez interakcije.
///
/// Na Androidu prijava teče prek sistemskega okna, v brskalniku prek Googlovega gumba
/// (glej `gumb_prijave_web.dart`) in samodejne prijave One Tap; v obeh primerih
/// rezultat pride po toku [GoogleSignIn.authenticationEvents].
class Prijava extends ChangeNotifier {
  final _gsi = GoogleSignIn.instance;
  GoogleSignInAccount? racun;
  String? napaka;
  Future<void>? _priprava;

  String? _idZeton;
  Completer<void>? _cakamZeton;

  bool get nastavljena => Config.googleServerClientId.isNotEmpty;

  /// Ali sme aplikacija klicati strežnik. Na špilu (prek vodje) prijava ni potrebna.
  bool get prijavljen => racun != null || Config.prekoVodje;

  Future<void> zacni() => _priprava ??= _zacni();

  Future<void> _zacni() async {
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

  Future<void> odjavi() async {
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
      throw StateError('Prijava je potekla. Prijavi se znova.');
    }
    final nov = _idZeton;
    if (nov == null) throw StateError('Nisi prijavljen');
    return nov;
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
