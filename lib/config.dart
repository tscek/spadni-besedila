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

  /// Vrata strežnika, ki ga na špilu zažene vodja.
  static const vrataVodje = 8765;

  /// Ali je spletna različica odprta s strežnika vodje na lokalnem WiFi-ju (iPad na špilu).
  /// Takrat podatke daje vodja, Google prijava pa ni potrebna.
  static bool get prekoVodje => kIsWeb && Uri.base.port == vrataVodje;

  static String get apiUrl => prekoVodje ? '${Uri.base.origin}/api' : _skripta;
}
