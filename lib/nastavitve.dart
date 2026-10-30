import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Gumbi in prikazi v orodnih vrsticah pri pesmi.
enum Orodje {
  spil('Špil (vloga in povezava)', Mesto.zgoraj),
  bluetooth('Bluetooth (modra, ko je naprava povezana)', Mesto.zgoraj),
  midi('MIDI IN / OUT (pikici zasvetita ob ukazu)', Mesto.zgoraj),
  runda('Runda in pavza (čas)', Mesto.zgoraj),
  pisava('Gumba za manjšo in večjo pisavo (sicer s ščipom)', Mesto.skrito),
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

/// Kaj je v posameznem delu spodnje vrstice pri pesmi.
enum InfoVrstice {
  nic('Nič'),
  naslov('Naslov'),
  izvajalec('Izvajalec'),
  avtorji('Avtorja glasbe in besedila'),
  tonaliteta('Tonaliteta'),
  harmonika('Harmonika'),
  tonalitetaHarmonika('Tonaliteta in harmonika'),
  vrsta('Vrsta'),
  tempo('Tempo (BPM)'),
  trajanje('Trajanje'),
  ocena('Ocena'),
  status('Status'),
  opombe('Opombe pesmi'),
  naslednja('Naslednja pesem'),
  ura('Ura'),
  runda('Čas runde ali pavze');

  const InfoVrstice(this.ime);
  final String ime;
}

/// Gumb v oknu runde: pavza ali igranje, z napisom, barvo in MIDI ukazom ob kliku.
class GumbRunde {
  const GumbRunde({required this.napis, required this.barva, this.midi = ''});

  final String napis;
  final int barva;

  /// Ukazi ali makri kot pri pesmi (npr. »PC 1 5« ali ime makra), ločeni s ;.
  final String midi;

  GumbRunde kopija({String? napis, int? barva, String? midi}) =>
      GumbRunde(napis: napis ?? this.napis, barva: barva ?? this.barva, midi: midi ?? this.midi);
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
  static const _poljaSeznama = 'polja_seznama';
  static const _ikoneSeznama = 'ikone_seznama';
  static const _razvrsti = 'razvrsti';
  static const _padajoce = 'razvrsti_padajoce';
  static const _minuteOdigrane = 'minute_odigrane';
  static const _spodaj = 'spodnja_vrstica';
  static const _poljaVrste = 'polja_cakalne_vrste';
  static const _runda = 'runda_';

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

  /// Podatki v vrstici seznama pesmi (naslov je vedno).
  List<PoljePesmi> poljaSeznama = const [PoljePesmi.izvajalec, PoljePesmi.tonaliteta];

  /// Ikoni besedila in PDF-ja v vrstici seznama.
  bool ikoneSeznama = true;

  PoljePesmi razvrsti = PoljePesmi.koda;
  bool padajoce = false;

  /// Po koliko minutah odprte pesmi se ta označi kot odigrana (0 = nikoli).
  int minuteOdigrane = 2;

  /// Levi, srednji in desni del spodnje vrstice pri pesmi.
  List<InfoVrstice> spodaj = const [InfoVrstice.tonalitetaHarmonika, InfoVrstice.naslednja, InfoVrstice.ura];

  /// Podatki pesmi v napisu čakalne vrste.
  List<PoljePesmi> poljaVrste = const [PoljePesmi.naslov, PoljePesmi.tonaliteta, PoljePesmi.harmonika];

  GumbRunde pavza = const GumbRunde(napis: 'PAVZA', barva: 0xFFD32F2F);
  GumbRunde igranje = const GumbRunde(napis: 'ŠPILEJ!!', barva: 0xFF2E7D32);

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
    List<T>? seznam<T extends Enum>(String kljuc, List<T> vrednosti) {
      final s = p.getStringList(kljuc);
      if (s == null) return null;
      final imena = vrednosti.asNameMap();
      return [for (final x in s) ?imena[x]];
    }

    poljaSeznama = seznam(_poljaSeznama, PoljePesmi.values) ?? poljaSeznama;
    ikoneSeznama = p.getBool(_ikoneSeznama) ?? ikoneSeznama;
    razvrsti = PoljePesmi.values.asNameMap()[p.getString(_razvrsti)] ?? razvrsti;
    padajoce = p.getBool(_padajoce) ?? padajoce;
    minuteOdigrane = p.getInt(_minuteOdigrane) ?? minuteOdigrane;
    final sp = seznam(_spodaj, InfoVrstice.values);
    if (sp != null && sp.length == 3) spodaj = sp;
    poljaVrste = seznam(_poljaVrste, PoljePesmi.values) ?? poljaVrste;
    GumbRunde gumb(String k, GumbRunde g) => GumbRunde(
      napis: p.getString('$_runda${k}_napis') ?? g.napis,
      barva: p.getInt('$_runda${k}_barva') ?? g.barva,
      midi: p.getString('$_runda${k}_midi') ?? g.midi,
    );
    pavza = gumb('pavza', pavza);
    igranje = gumb('igranje', igranje);
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

  Future<void> nastaviPoljaSeznama(List<PoljePesmi> v) {
    poljaSeznama = List.unmodifiable(v);
    return _shrani((p) => p.setStringList(_poljaSeznama, [for (final x in v) x.name]));
  }

  Future<void> nastaviIkoneSeznama(bool v) {
    ikoneSeznama = v;
    return _shrani((p) => p.setBool(_ikoneSeznama, v));
  }

  Future<void> nastaviRazvrscanje(PoljePesmi polje, bool padajoce) {
    razvrsti = polje;
    this.padajoce = padajoce;
    return _shrani((p) {
      p.setString(_razvrsti, polje.name);
      p.setBool(_padajoce, padajoce);
    });
  }

  Future<void> nastaviMinuteOdigrane(int v) {
    minuteOdigrane = v.clamp(0, 30);
    return _shrani((p) => p.setInt(_minuteOdigrane, minuteOdigrane));
  }

  Future<void> nastaviSpodaj(int del, InfoVrstice v) {
    spodaj = [...spodaj]..[del] = v;
    return _shrani((p) => p.setStringList(_spodaj, [for (final x in spodaj) x.name]));
  }

  Future<void> nastaviPoljaVrste(List<PoljePesmi> v) {
    poljaVrste = List.unmodifiable(v);
    return _shrani((p) => p.setStringList(_poljaVrste, [for (final x in v) x.name]));
  }

  /// [pavzo] true nastavi gumb za pavzo, sicer gumb za igranje.
  Future<void> nastaviGumbRunde(bool pavzo, GumbRunde g) {
    final k = pavzo ? 'pavza' : 'igranje';
    if (pavzo) {
      pavza = g;
    } else {
      igranje = g;
    }
    return _shrani((p) {
      p.setString('$_runda${k}_napis', g.napis);
      p.setInt('$_runda${k}_barva', g.barva);
      p.setString('$_runda${k}_midi', g.midi);
    });
  }

  /// Povečava PDF-ja pesmi, ki jo je član nastavil (null: cela stran na zaslonu).
  Future<double?> povecavaPdf(String pesem) async =>
      (await SharedPreferences.getInstance()).getDouble('pdf_zoom_$pesem');

  Future<void> nastaviPovecavoPdf(String pesem, double? v) async {
    final p = await SharedPreferences.getInstance();
    v == null ? await p.remove('pdf_zoom_$pesem') : await p.setDouble('pdf_zoom_$pesem', v);
  }

  Future<void> nastaviZaslonPrizgan(bool v) {
    zaslonPrizgan = v;
    return _shrani((p) => p.setBool(_zaslon, v));
  }
}
