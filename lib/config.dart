import 'package:flutter/foundation.dart';

/// Nastavitve, ki se podajo ob gradnji (--dart-define), z privzetimi vrednostmi.
class Config {
  /// Naslov Apps Script spletne aplikacije (besedila-api.gs).
  static const _skripta = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://script.google.com/macros/s/AKfycbzgdFxntfPVcp6xnLXo9hIVSx6x9gbBmdcfZbAFH8H8LvAU6HvQsBrWMVO4SR2aIHm6jg/exec',
  );

  /// OAuth "Web application" client ID iz Google Cloud. Brez njega prijava ne deluje.
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// OAuth "Desktop app" client ID in skrivnost za prijavo na računalniku (Windows).
  /// Skrivnost pri namiznih aplikacijah po Googlovih pravilih ni zaupna (je v vsaki namestitvi).
  static const googleDesktopClientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const googleDesktopClientSecret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');

  /// Vrata strežnika, ki ga na špilu zažene vodja.
  static const vrataVodje = 8765;

  /// Rezervna vrata, če so prva zasedena (Windows nekatera vrata rezervira zase, napaka 10013).
  static const vsaVrataVodje = [vrataVodje, 8775, 18765, 28765, 38765, 5765];

  /// Vrata UDP, na katerih vodja oddaja svoj naslov, da ga sledilci najdejo sami.
  static const vrataIskanja = 8766;

  /// Ali je spletna različica odprta s strežnika vodje na lokalnem WiFi-ju (iPad na špilu).
  /// Takrat podatke daje vodja, Google prijava pa ni potrebna.
  static bool get prekoVodje => kIsWeb && vsaVrataVodje.contains(Uri.base.port);

  /// Neprijavljen sledilec (iPad prek vodje): sme le gledati, dodajati klicaje in predlagati pesmi
  /// (na konec čakalne vrste). Risanje, čakalna vrsta, časovnik, MIDI in snemanje so zaklenjeni.
  static bool get samoKlicaji => prekoVodje;

  /// Spletna različica; s `?pesem=ID` se odpre neposredno pesem.
  static const spletniNaslov = 'https://spadni-besedila.web.app/';

  static String povezavaDoPesmi(String id) => '$spletniNaslov?pesem=$id';

  /// ID pesmi iz povezave, s katero je bila odprta spletna različica (null, če ga ni).
  static String? get pesemIzPovezave {
    if (!kIsWeb) return null;
    final id = Uri.base.queryParameters['pesem'];
    return id == null || id.isEmpty ? null : id;
  }

  static String get apiUrl => prekoVodje ? '${Uri.base.origin}/api' : _skripta;
}
