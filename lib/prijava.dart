import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
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

  // Seja aplikacije: skripta po prijavi izda svoj žeton za 30 dni (Googlov ID žeton velja le 1 uro in ga
  // brskalnik pogosto ne zna obnoviti). Seja se sama podaljša, ko ji ostane manj kot teden.
  static const _kljucSeje = 'seja';
  static const _kljucEmailaSeje = 'seja_email';
  String? _seja;
  String? _sejaEmail;
  Future<void>? _obnavljam;

  /// Za preizkuse: Api za dani žeton.
  @visibleForTesting
  static Api Function(Future<String> Function() zeton) tovarnaApi = Api.new;

  bool get _sejaVelja => _seja != null && veljaSeja(_seja!, Duration.zero);

  bool get nastavljena => _namizje ? PrijavaNamizje.nastavljena : Config.googleServerClientId.isNotEmpty;

  /// Ali sme aplikacija klicati strežnik. Na špilu (prek vodje) prijava ni potrebna.
  bool get prijavljen => racun != null || _namiznaEmail != null || _sejaVelja || Config.prekoVodje;

  /// E-naslov prijavljenega računa.
  String? get email => racun?.email ?? _namiznaEmail ?? (_sejaVelja ? _sejaEmail : null);

  Future<void> zacni() => _priprava ??= _zacni();

  Future<void> _zacni() async {
    try {
      final p = await SharedPreferences.getInstance();
      _seja = p.getString(_kljucSeje);
      _sejaEmail = p.getString(_kljucEmailaSeje);
      if (_seja != null) notifyListeners();
    } catch (_) {}
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
    // Nova prijava (morda z drugim računom) dobi novo sejo.
    await _shraniSejo(null, null);
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
    await _shraniSejo(null, null);
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
    try {
      await _gsi.signOut();
    } catch (_) {
      // Prijavljen le s sejo (Google še ni pripravljen).
    }
    racun = null;
    _idZeton = null;
    notifyListeners();
  }

  /// Žeton za klic na strežnik: seja aplikacije ali (prvič) Googlov ID žeton, ki se zamenja za sejo.
  Future<String> zeton() async {
    if (Config.prekoVodje) return '';
    final s = _seja;
    if (s != null && veljaSeja(s, Duration.zero)) {
      if (!veljaSeja(s, const Duration(days: 7))) _obnavljam ??= _obnoviSejo(s).whenComplete(() => _obnavljam = null);
      return s;
    }
    final g = await _googleZeton();
    try {
      final o = await tovarnaApi(() async => g).seja();
      final nova = o['seja']?.toString();
      if (nova != null && nova.startsWith('sb1.')) {
        await _shraniSejo(nova, o['email']?.toString() ?? email);
        return nova;
      }
    } catch (_) {
      // Stara skripta seje ne pozna: ostane Googlov žeton.
    }
    return g;
  }

  Future<void> _obnoviSejo(String s) async {
    try {
      final o = await tovarnaApi(() async => s).seja();
      final nova = o['seja']?.toString();
      if (nova != null && nova.startsWith('sb1.')) await _shraniSejo(nova, o['email']?.toString() ?? _sejaEmail);
    } catch (_) {}
  }

  Future<void> _shraniSejo(String? seja, String? email) async {
    _seja = seja;
    _sejaEmail = seja == null ? null : email;
    try {
      final p = await SharedPreferences.getInstance();
      if (seja == null) {
        await p.remove(_kljucSeje);
        await p.remove(_kljucEmailaSeje);
      } else {
        await p.setString(_kljucSeje, seja);
        if (email != null) await p.setString(_kljucEmailaSeje, email);
      }
    } catch (_) {}
  }

  /// Veljaven Googlov ID žeton. Sočasni klici si delijo isto osvežitev.
  Future<String> _googleZeton() async {
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

/// Ali seja aplikacije (`sb1.vsebina.podpis`) velja še vsaj [rezerva] (polje x v milisekundah).
bool veljaSeja(String seja, Duration rezerva) {
  try {
    final deli = seja.split('.');
    if (deli.length != 3 || deli[0] != 'sb1') return false;
    final v = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(deli[1])))) as Map<String, dynamic>;
    final poteka = DateTime.fromMillisecondsSinceEpoch((v['x'] as num).toInt());
    return DateTime.now().add(rezerva).isBefore(poteka);
  } catch (_) {
    return false;
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
