import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gumbi in prikazi v orodnih vrsticah pri pesmi.
enum Orodje {
  spil('Špil (vloga in povezava)', Mesto.zgoraj),
  bluetooth('Bluetooth (modra, ko je naprava povezana)', Mesto.zgoraj),
  midi('MIDI IN / OUT (zasveti ob ukazu)', Mesto.zgoraj),
  iskanje('Iskanje pesmi', Mesto.spodaj),
  pisava('Manjša in večja pisava', Mesto.zgoraj),
  pdf('Besedilo / PDF', Mesto.zgoraj),
  uredi('Uredi pesem', Mesto.zgoraj),
  ura('Ura', Mesto.skrito);

  const Orodje(this.opis, this.privzeto);
  final String opis;
  final Mesto privzeto;
}

enum Mesto {
  zgoraj('Zgoraj'),
  spodaj('Spodaj'),
  skrito('Skrito');

  const Mesto(this.ime);
  final String ime;
}

/// Osebne nastavitve na tej napravi (vsak član ima svojo tablico oziroma iPad).
class Nastavitve extends ChangeNotifier {
  static Nastavitve aplikacija = Nastavitve();

  static const _pisava = 'velikost_pisave';
  static const _pdfNajprej = 'pdf_najprej';
  static const _akordi = 'akordi';
  static const _svetla = 'svetla_tema';
  static const _sledenje = 'samodejno_sledenje';
  static const _zaslon = 'zaslon_prizgan';

  /// Velikost pisave besedila.
  double pisava = 22;

  /// Pri pesmi z besedilom in PDF-jem najprej pokaži PDF.
  bool pdfNajprej = false;

  /// Akordi nad besedilom (pevci jih lahko skrijejo).
  bool akordi = true;
  bool svetlaTema = false;

  /// Sledilec: pesem, ki jo izbere vodja, se odpre sama.
  bool samodejnoSledenje = true;

  /// Zaslon se med uporabo aplikacije ne ugasne.
  bool zaslonPrizgan = true;

  /// Kje je posamezno orodje pri pesmi.
  final Map<Orodje, Mesto> orodja = {for (final o in Orodje.values) o: o.privzeto};

  Mesto mesto(Orodje o) => orodja[o] ?? o.privzeto;

  /// Orodja na [m] v vrstnem redu.
  List<Orodje> orodjaNa(Mesto m) => [
    for (final o in Orodje.values)
      if (mesto(o) == m) o,
  ];

  Future<void> nalozi() async {
    final p = await SharedPreferences.getInstance();
    for (final o in Orodje.values) {
      orodja[o] = Mesto.values.asNameMap()[p.getString('orodje_${o.name}')] ?? o.privzeto;
    }
    pisava = p.getDouble(_pisava) ?? pisava;
    pdfNajprej = p.getBool(_pdfNajprej) ?? pdfNajprej;
    akordi = p.getBool(_akordi) ?? akordi;
    svetlaTema = p.getBool(_svetla) ?? svetlaTema;
    samodejnoSledenje = p.getBool(_sledenje) ?? samodejnoSledenje;
    zaslonPrizgan = p.getBool(_zaslon) ?? zaslonPrizgan;
    notifyListeners();
  }

  Future<void> _shrani(void Function(SharedPreferences p) zapisi) async {
    notifyListeners();
    zapisi(await SharedPreferences.getInstance());
  }

  Future<void> nastaviPisavo(double v) {
    pisava = v.clamp(12, 64);
    return _shrani((p) => p.setDouble(_pisava, pisava));
  }

  Future<void> nastaviPdfNajprej(bool v) {
    pdfNajprej = v;
    return _shrani((p) => p.setBool(_pdfNajprej, v));
  }

  Future<void> nastaviAkorde(bool v) {
    akordi = v;
    return _shrani((p) => p.setBool(_akordi, v));
  }

  Future<void> nastaviSvetloTemo(bool v) {
    svetlaTema = v;
    return _shrani((p) => p.setBool(_svetla, v));
  }

  Future<void> nastaviSamodejnoSledenje(bool v) {
    samodejnoSledenje = v;
    return _shrani((p) => p.setBool(_sledenje, v));
  }

  Future<void> nastaviOrodje(Orodje o, Mesto m) {
    orodja[o] = m;
    return _shrani((p) => p.setString('orodje_${o.name}', m.name));
  }

  Future<void> nastaviZaslonPrizgan(bool v) {
    zaslonPrizgan = v;
    return _shrani((p) => p.setBool(_zaslon, v));
  }
}
