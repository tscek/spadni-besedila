import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'config.dart';

/// Google prijava. ID žeton velja eno uro, zato se pred vsakim klicem osveži brez interakcije.
class Prijava extends ChangeNotifier {
  final _gsi = GoogleSignIn.instance;
  GoogleSignInAccount? racun;
  String? napaka;
  bool _pripravljena = false;

  bool get nastavljena => Config.googleServerClientId.isNotEmpty;

  Future<void> zacni() async {
    if (!nastavljena) return;
    await _gsi.initialize(serverClientId: Config.googleServerClientId);
    _pripravljena = true;
    try {
      racun = await _gsi.attemptLightweightAuthentication();
    } catch (_) {
      racun = null;
    }
    notifyListeners();
  }

  Future<void> prijavi() async {
    napaka = null;
    try {
      if (!_pripravljena) await zacni();
      racun = await _gsi.authenticate();
    } on GoogleSignInException catch (e) {
      napaka = e.code == GoogleSignInExceptionCode.canceled
          ? null
          : 'Prijava ni uspela: ${e.description ?? e.code.name}';
    } catch (e) {
      napaka = 'Prijava ni uspela: $e';
    }
    notifyListeners();
  }

  Future<void> odjavi() async {
    await _gsi.signOut();
    racun = null;
    _zeton = null;
    notifyListeners();
  }

  // ID žeton velja eno uro; isti uporabimo 45 minut, da vsak klic ne čaka na osvežitev.
  Future<String>? _zeton;
  DateTime _zetonVeljaDo = DateTime(0);

  /// Veljaven ID žeton za klic na strežnik. Sočasni klici si delijo isto osvežitev.
  Future<String> zeton() {
    if (_zeton == null || DateTime.now().isAfter(_zetonVeljaDo)) {
      _zetonVeljaDo = DateTime.now().add(const Duration(minutes: 45));
      _zeton = _osveziZeton()
        ..catchError((_) {
          _zeton = null;
          return '';
        });
    }
    return _zeton!;
  }

  Future<String> _osveziZeton() async {
    final osvezen = await _gsi.attemptLightweightAuthentication();
    if (osvezen != null) racun = osvezen;
    final t = racun?.authentication.idToken;
    if (t == null) throw StateError('Nisi prijavljen');
    return t;
  }
}
