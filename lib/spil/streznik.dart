import '../baza.dart';
import 'streznik_web.dart' if (dart.library.io) 'streznik_io.dart' as izvedba;

/// Strežnik vodje na lokalnem WiFi-ju: ponuja spletno različico in podatke iPadom ter
/// pošilja stanje špila vsem sledilcem prek WebSocketa.
abstract class StreznikVodje {
  /// Zažene strežnik in vrne naslov, ki ga odprejo sledilci.
  Future<String> zacni(Baza baza, void Function(int sledilcev) obSpremembi);
  void poslji(String sporocilo);
  Future<void> ustavi();
}

/// Strežnik za to platformo ali null, kjer ga ni mogoče zagnati (brskalnik).
StreznikVodje? ustvariStreznik() => izvedba.ustvariStreznik();

/// Naslovi vodij (npr. http://192.168.1.5:8765), ki se oglašajo na lokalnem omrežju.
/// V brskalniku iskanje ni mogoče (prazen tok).
Stream<String> isciVodjo() => izvedba.isciVodjo();
