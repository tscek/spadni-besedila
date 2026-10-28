/// Nastavitve, ki se podajo ob gradnji (--dart-define), z privzetimi vrednostmi.
class Config {
  /// Naslov Apps Script spletne aplikacije (besedila-api.gs).
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://script.google.com/macros/s/AKfycbzgdFxntfPVcp6xnLXo9hIVSx6x9gbBmdcfZbAFH8H8LvAU6HvQsBrWMVO4SR2aIHm6jg/exec',
  );

  /// OAuth "Web application" client ID iz Google Cloud. Brez njega prijava ne deluje.
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
}
