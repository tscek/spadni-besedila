import '../baza.dart';
import 'streznik_web.dart' if (dart.library.io) 'streznik_io.dart' as izvedba;

/// Strežnik vodje na lokalnem WiFi-ju: ponuja spletno različico in podatke iPadom ter
/// pošilja stanje špila vsem sledilcem prek WebSocketa.
abstract class StreznikVodje {
  /// Zažene strežnik in vrne naslov, ki ga odprejo sledilci. [obSporocilu] dobi sporočila sledilcev.
  Future<String> zacni(
    Baza baza,
    void Function(int sledilcev) obSpremembi, {
    void Function(Map<String, dynamic> sporocilo)? obSporocilu,
  });

  /// Pošlje sporočilo vsem sledilcem; zadnje sporočilo vsake vrste dobi tudi sledilec, ki se poveže kasneje.
  void poslji(String sporocilo);

  /// Povezane naprave: član in vrsta naprave (sledilec se predstavi ob povezavi).
  List<String> get povezani;
  Future<void> ustavi();
}

/// Strežnik za to platformo ali null, kjer ga ni mogoče zagnati (brskalnik).
StreznikVodje? ustvariStreznik() => izvedba.ustvariStreznik();

/// Vodja, ki se oglaša na lokalnem omrežju: naslov (npr. http://192.168.1.5:8765) in ime člana, ki vodi.
typedef NajdenVodja = ({String naslov, String ime});

/// Vodje, ki se oglašajo na lokalnem omrežju. V brskalniku iskanje ni mogoče (prazen tok).
Stream<NajdenVodja> isciVodjo() => izvedba.isciVodjo();
