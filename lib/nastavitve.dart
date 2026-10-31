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

  /// Daljši podatek, ki v vrstici dobi preostalo širino; kratki (npr. tonaliteta) vzamejo le svojo.
  bool get dolg => switch (this) {
    naslov || izvajalec || avtorji || opombe || naslednja => true,
    _ => false,
  };
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
  static const _zgoraj = 'zgornja_vrstica';
  static const _prelom = 'prelom_vrstic';
  static const _oblacek = 'oblacek_tonalitete';
  static const _zasedba = 'zasedba';
  static const _barvaZgoraj = 'barva_zgoraj';
  static const _barvaSpodaj = 'barva_spodaj';
  static const _poljaIskalnika = 'polja_iskalnika';
  static const _razvrstiIskalnik = 'razvrsti_iskalnik';
  static const _pisavaPesmi = 'pisava_pesmi_';
  static const _razvrstiMape = 'razvrsti_mape_';
  static const _padajoceMape = 'padajoce_mape_';
  static const _runda = 'runda_';

  /// Splošna velikost pisave besedila (pesem ima lahko svojo, glej [pisavaZa]).
  double pisava = 22;

  /// Velikost pisave, ki jo je član nastavil na posamezni pesmi (ščip ali gumba).
  final Map<String, double> pisavePesmi = {};

  double pisavaZa(String pesem) => pisavePesmi[pesem] ?? pisava;

  /// Besedilo se ob večji pisavi prelomi v novo vrstico (sicer je stran širša od zaslona).
  bool prelom = true;

  /// Barvi ozadja vrstice z naslovom zgoraj in spodnje vrstice pri pesmi (ARGB; null = barva teme).
  int? barvaZgoraj;
  int? barvaSpodaj;

  /// Izbrana zasedba (ID), če je član v več zasedbah; prikažejo se njene pesmi in setliste.
  String zasedba = '';

  /// Tonaliteta v oblačku v zgornjem desnem kotu pesmi (pod zgornjo vrstico).
  bool oblacekTonalitete = false;

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

  /// Privzeto razvrščanje seznama; vsaka mapa si zapomni svoje ([razvrscanjeMape]).
  PoljePesmi razvrsti = PoljePesmi.koda;
  bool padajoce = false;
  final Map<String, (PoljePesmi, bool)> _razvrscanjeMap = {};

  (PoljePesmi, bool) razvrscanjeMape(String mapa) => _razvrscanjeMap[mapa] ?? (razvrsti, padajoce);

  /// Podatki pod naslovom v iskalniku pesmi.
  List<PoljePesmi> poljaIskalnika = const [PoljePesmi.izvajalec, PoljePesmi.tonaliteta];

  /// Razvrščanje v iskalniku; null = kot v mapi.
  PoljePesmi? razvrstiIskalnik;

  /// Po koliko minutah odprte pesmi se ta označi kot odigrana (0 = nikoli).
  int minuteOdigrane = 2;

  /// Levi, srednji in desni del spodnje vrstice pri pesmi.
  List<InfoVrstice> spodaj = const [InfoVrstice.tonalitetaHarmonika, InfoVrstice.naslednja, InfoVrstice.ura];

  /// Vrstica pod orodno vrstico pri pesmi (trije deli kot spodaj).
  List<InfoVrstice> zgoraj = const [InfoVrstice.naslov, InfoVrstice.tonaliteta, InfoVrstice.nic];

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
    _razvrscanjeMap.clear();
    pisavePesmi.clear();
    for (final k in p.getKeys()) {
      if (k.startsWith(_razvrstiMape)) {
        final mapa = k.substring(_razvrstiMape.length);
        final polje = PoljePesmi.values.asNameMap()[p.getString(k)];
        if (polje != null) _razvrscanjeMap[mapa] = (polje, p.getBool('$_padajoceMape$mapa') ?? false);
      }
      if (k.startsWith(_pisavaPesmi)) {
        final v = p.getDouble(k);
        if (v != null) pisavePesmi[k.substring(_pisavaPesmi.length)] = v;
      }
    }
    prelom = p.getBool(_prelom) ?? prelom;
    oblacekTonalitete = p.getBool(_oblacek) ?? oblacekTonalitete;
    zasedba = p.getString(_zasedba) ?? zasedba;
    barvaZgoraj = p.getInt(_barvaZgoraj);
    barvaSpodaj = p.getInt(_barvaSpodaj);
    poljaIskalnika = seznam(_poljaIskalnika, PoljePesmi.values) ?? poljaIskalnika;
    razvrstiIskalnik = PoljePesmi.values.asNameMap()[p.getString(_razvrstiIskalnik)];
    final zg = seznam(_zgoraj, InfoVrstice.values);
    if (zg != null && zg.length == 3) zgoraj = zg;
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

  /// Pisava ene pesmi; null pomeni splošno.
  Future<void> nastaviPisavoPesmi(String pesem, double? v) {
    if (v == null) {
      pisavePesmi.remove(pesem);
      return _shrani((p) => p.remove('$_pisavaPesmi$pesem'));
    }
    final x = v.clamp(12, 64).toDouble();
    pisavePesmi[pesem] = x;
    return _shrani((p) => p.setDouble('$_pisavaPesmi$pesem', x));
  }

  /// Vse pesmi spet s splošno pisavo in privzeto povečavo PDF-ja.
  Future<void> ponastaviPovecavePesmi() async {
    pisavePesmi.clear();
    await _shrani((p) {
      for (final k in p.getKeys().toList()) {
        if (k.startsWith(_pisavaPesmi) || k.startsWith('pdf_zoom_')) p.remove(k);
      }
    });
  }

  Future<void> nastaviPrelom(bool v) {
    prelom = v;
    return _shrani((p) => p.setBool(_prelom, v));
  }

  Future<void> nastaviBarvoVrstice({required bool zgoraj, required int? barva}) {
    zgoraj ? barvaZgoraj = barva : barvaSpodaj = barva;
    final k = zgoraj ? _barvaZgoraj : _barvaSpodaj;
    return _shrani((p) => barva == null ? p.remove(k) : p.setInt(k, barva));
  }

  Future<void> nastaviZasedbo(String v) {
    zasedba = v;
    return _shrani((p) => p.setString(_zasedba, v));
  }

  Future<void> nastaviOblacekTonalitete(bool v) {
    oblacekTonalitete = v;
    return _shrani((p) => p.setBool(_oblacek, v));
  }

  Future<void> nastaviZgoraj(int del, InfoVrstice v) {
    zgoraj = [...zgoraj]..[del] = v;
    return _shrani((p) => p.setStringList(_zgoraj, [for (final x in zgoraj) x.name]));
  }

  Future<void> nastaviPoljaIskalnika(List<PoljePesmi> v) {
    poljaIskalnika = List.unmodifiable(v);
    return _shrani((p) => p.setStringList(_poljaIskalnika, [for (final x in v) x.name]));
  }

  Future<void> nastaviRazvrscanjeIskalnika(PoljePesmi? v) {
    razvrstiIskalnik = v;
    return _shrani((p) => v == null ? p.remove(_razvrstiIskalnik) : p.setString(_razvrstiIskalnik, v.name));
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

  /// Razvrščanje seznama v [mapa]; brez mape (npr. v testih) se nastavi privzeto.
  Future<void> nastaviRazvrscanje(PoljePesmi polje, bool padajoce, {String? mapa}) {
    if (mapa != null) {
      _razvrscanjeMap[mapa] = (polje, padajoce);
      return _shrani((p) {
        p.setString('$_razvrstiMape$mapa', polje.name);
        p.setBool('$_padajoceMape$mapa', padajoce);
      });
    }
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
