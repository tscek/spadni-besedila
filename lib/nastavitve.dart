import 'dart:convert';

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
  ura('Ura', Mesto.skrito),
  uvodi('Uvodi ob odprtju pesmi: MIDI in zvok (vklop in izklop)', Mesto.zgoraj),
  xyPad('FX: zvočni efekti in XY pad', Mesto.zgoraj),
  playback('Playback ▶/■ (če ga ima pesem)', Mesto.zgoraj),
  youtube('YouTube (če ima pesem povezavo)', Mesto.zgoraj);

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

/// Usmeritev zaslona na tej napravi (zaklep deluje na Androidu).
enum Usmeritev {
  samodejno('Samodejno'),
  pokoncno('Pokončno'),
  lezece('Ležeče');

  const Usmeritev(this.ime);
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

/// Oblaček na besedilu pesmi: podatek, velikost, barva in kot (zlagajo se navzdol).
@immutable
class Oblacek {
  const Oblacek({required this.vsebina, this.velikost = 1, this.barva, this.levo = false});

  factory Oblacek.izJson(Map<String, dynamic> j) => Oblacek(
    vsebina: InfoVrstice.values.asNameMap()[j['v']] ?? InfoVrstice.tonaliteta,
    velikost: ((j['s'] as num?)?.toInt() ?? 1).clamp(0, 2),
    barva: (j['b'] as num?)?.toInt(),
    levo: j['l'] == true,
  );

  final InfoVrstice vsebina;

  /// 0 majhen, 1 srednji, 2 velik.
  final int velikost;

  /// Ozadje (ARGB); null = barva teme.
  final int? barva;

  /// Levi (sicer desni) zgornji kot.
  final bool levo;

  static const velikosti = ['Majhen', 'Srednji', 'Velik'];

  Map<String, dynamic> vJson() => {'v': vsebina.name, 's': velikost, 'b': ?barva, if (levo) 'l': true};

  Oblacek kopija({InfoVrstice? vsebina, int? velikost, int? Function()? barva, bool? levo}) => Oblacek(
    vsebina: vsebina ?? this.vsebina,
    velikost: velikost ?? this.velikost,
    barva: barva == null ? this.barva : barva(),
    levo: levo ?? this.levo,
  );

  @override
  bool operator ==(Object other) =>
      other is Oblacek &&
      other.vsebina == vsebina &&
      other.velikost == velikost &&
      other.barva == barva &&
      other.levo == levo;

  @override
  int get hashCode => Object.hash(vsebina, velikost, barva, levo);
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
  static const _skrijIgrane = 'skrij_igrane';
  static const _svetla = 'svetla_tema';
  static const _sledenje = 'samodejno_sledenje';
  static const _zaslon = 'zaslon_prizgan';
  static const _usmeritev = 'usmeritev';
  static const _uvodi = 'uvodi';
  static const _hraniUvode = 'hrani_uvode';
  static const _predvajajUvode = 'predvajaj_uvode';
  static const _izhodZvoka = 'izhod_zvoka';
  static const _hraniPlayback = 'hrani_playback';
  static const _predvajajPlayback = 'predvajaj_playback';
  static const _izhodPlaybacka = 'izhod_playbacka';
  static const _hraniEfekte = 'hrani_efekte';
  static const _predvajajEfekte = 'predvajaj_efekte';
  static const _fxMidiTu = 'fx_midi_tu';
  static const _izhodEfektov = 'izhod_efektov';
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
  static const _oblacki = 'oblacki';
  static const _zasedba = 'zasedba';
  static const _barvaZgoraj = 'barva_zgoraj';
  static const _barvaSpodaj = 'barva_spodaj';
  static const _pogledPrevzet = 'pogled_prevzet';
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

  /// Nastavitve pogleda administratorja, ki jih je član že prevzel ali zavrnil (da ga ne sprašuje znova).
  String pogledPrevzet = '';

  Future<void> oznaciPogled(String vsebina) {
    pogledPrevzet = vsebina;
    return _shrani((p) => p.setString(_pogledPrevzet, vsebina));
  }

  /// Izbrana zasedba (ID), če je član v več zasedbah; prikažejo se njene pesmi in setliste.
  String zasedba = '';

  /// Stara nastavitev (samo tonaliteta v oblačku); ob nalaganju postane prvi oblaček.
  bool oblacekTonalitete = false;

  /// Oblački na besedilu pesmi (levo in desno zgoraj, zloženi navzdol).
  List<Oblacek> oblacki = const [];

  /// Pri pesmi z besedilom in PDF-jem najprej pokaži PDF.
  bool pdfNajprej = false;

  /// Akordi nad besedilom (pevci jih lahko skrijejo).
  bool akordi = true;

  /// Iskalnik ob listanju ne kaže že igranih pesmi; z vpisano besedo jih najde.
  bool skrijIgrane = true;
  bool svetlaTema = false;

  /// Sledilec: pesem, ki jo izbere vodja, se odpre sama.
  bool samodejnoSledenje = true;

  /// Zaslon se med uporabo aplikacije ne ugasne.
  bool zaslonPrizgan = true;

  /// Zaklep usmeritve zaslona.
  Usmeritev usmeritev = Usmeritev.samodejno;

  /// Uvodi MIDI se pošiljajo ob odprtju pesmi (gumb Uvodi v orodni vrstici).
  bool uvodi = true;

  /// Zvočni uvodi pesmi se ob osvežitvi prenesejo na napravo (sicer se predvajajo s spleta).
  bool hraniUvode = false;

  /// Ta naprava predvaja zvočne uvode (privzeto le računalnik, da ne igrajo vsi iPadi hkrati).
  bool predvajajUvode = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Zvočni izhod za uvode (ime naprave; prazno = privzeti izhod sistema).
  String izhodZvoka = '';

  /// Playback pesmi: prenos na napravo, predvajanje na tej napravi in izhod (npr. ozvočenje).
  bool hraniPlayback = false;
  bool predvajajPlayback = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  String izhodPlaybacka = '';

  /// Zvočni efekti (FX panel): prenos na napravo, predvajanje na tej napravi (privzeto PC) in izhod.
  bool hraniEfekte = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool predvajajEfekte = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  String izhodEfektov = '';

  /// Na špilu gre ves MIDI s FX (gumbi FX, XY pad in njegovi gumbi) z vseh naprav na to napravo (privzeto PC).
  bool fxMidiTu = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> nastaviFxMidiTu(bool da) => _nastavi(() => fxMidiTu = da, (p) => p.setBool(_fxMidiTu, da));

  Future<void> nastaviHraniEfekte(bool da) => _nastavi(() => hraniEfekte = da, (p) => p.setBool(_hraniEfekte, da));
  Future<void> nastaviPredvajajEfekte(bool da) =>
      _nastavi(() => predvajajEfekte = da, (p) => p.setBool(_predvajajEfekte, da));
  Future<void> nastaviIzhodEfektov(String id) =>
      _nastavi(() => izhodEfektov = id, (p) => p.setString(_izhodEfektov, id));

  bool hrani(VrstaZvoka v) => v == VrstaZvoka.playback ? hraniPlayback : hraniUvode;
  bool predvajaj(VrstaZvoka v) => v == VrstaZvoka.playback ? predvajajPlayback : predvajajUvode;
  String izhod(VrstaZvoka v) => v == VrstaZvoka.playback ? izhodPlaybacka : izhodZvoka;

  Future<void> nastaviHrani(VrstaZvoka v, bool da) => v == VrstaZvoka.playback
      ? _nastavi(() => hraniPlayback = da, (p) => p.setBool(_hraniPlayback, da))
      : nastaviHraniUvode(da);
  Future<void> nastaviPredvajaj(VrstaZvoka v, bool da) => v == VrstaZvoka.playback
      ? _nastavi(() => predvajajPlayback = da, (p) => p.setBool(_predvajajPlayback, da))
      : nastaviPredvajajUvode(da);
  Future<void> nastaviIzhod(VrstaZvoka v, String id) => v == VrstaZvoka.playback
      ? _nastavi(() => izhodPlaybacka = id, (p) => p.setString(_izhodPlaybacka, id))
      : nastaviIzhodZvoka(id);

  Future<void> _nastavi(void Function() v, void Function(SharedPreferences) zapis) {
    v();
    return _shrani(zapis);
  }

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
    // Privzete vrednosti za ključe, ki jih ni (npr. po prevzemu nastavitev administratorja).
    final d = Nastavitve();
    for (final o in Orodje.values) {
      orodja[o] = Mesto.values.asNameMap()[p.getString('orodje_${o.name}')] ?? o.privzeto;
    }
    pisava = p.getDouble(_pisava) ?? d.pisava;
    pdfNajprej = p.getBool(_pdfNajprej) ?? d.pdfNajprej;
    akordi = p.getBool(_akordi) ?? d.akordi;
    skrijIgrane = p.getBool(_skrijIgrane) ?? d.skrijIgrane;
    svetlaTema = p.getBool(_svetla) ?? d.svetlaTema;
    samodejnoSledenje = p.getBool(_sledenje) ?? d.samodejnoSledenje;
    zaslonPrizgan = p.getBool(_zaslon) ?? d.zaslonPrizgan;
    usmeritev = Usmeritev.values.asNameMap()[p.getString(_usmeritev)] ?? d.usmeritev;
    uvodi = p.getBool(_uvodi) ?? d.uvodi;
    hraniUvode = p.getBool(_hraniUvode) ?? d.hraniUvode;
    predvajajUvode = p.getBool(_predvajajUvode) ?? d.predvajajUvode;
    izhodZvoka = p.getString(_izhodZvoka) ?? d.izhodZvoka;
    hraniPlayback = p.getBool(_hraniPlayback) ?? d.hraniPlayback;
    predvajajPlayback = p.getBool(_predvajajPlayback) ?? d.predvajajPlayback;
    izhodPlaybacka = p.getString(_izhodPlaybacka) ?? d.izhodPlaybacka;
    hraniEfekte = p.getBool(_hraniEfekte) ?? d.hraniEfekte;
    predvajajEfekte = p.getBool(_predvajajEfekte) ?? d.predvajajEfekte;
    fxMidiTu = p.getBool(_fxMidiTu) ?? d.fxMidiTu;
    izhodEfektov = p.getString(_izhodEfektov) ?? d.izhodEfektov;
    List<T>? seznam<T extends Enum>(String kljuc, List<T> vrednosti) {
      final s = p.getStringList(kljuc);
      if (s == null) return null;
      final imena = vrednosti.asNameMap();
      return [for (final x in s) ?imena[x]];
    }

    poljaSeznama = seznam(_poljaSeznama, PoljePesmi.values) ?? d.poljaSeznama;
    ikoneSeznama = p.getBool(_ikoneSeznama) ?? d.ikoneSeznama;
    razvrsti = PoljePesmi.values.asNameMap()[p.getString(_razvrsti)] ?? d.razvrsti;
    padajoce = p.getBool(_padajoce) ?? d.padajoce;
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
    prelom = p.getBool(_prelom) ?? d.prelom;
    oblacekTonalitete = p.getBool(_oblacek) ?? d.oblacekTonalitete;
    final ob = p.getString(_oblacki);
    oblacki = ob == null
        ? (oblacekTonalitete ? const [Oblacek(vsebina: InfoVrstice.tonaliteta)] : const [])
        : [
            for (final o in (jsonDecode(ob) as List? ?? const []))
              if (o is Map) Oblacek.izJson(o.cast<String, dynamic>()),
          ];
    zasedba = p.getString(_zasedba) ?? d.zasedba;
    pogledPrevzet = p.getString(_pogledPrevzet) ?? '';
    barvaZgoraj = p.getInt(_barvaZgoraj);
    barvaSpodaj = p.getInt(_barvaSpodaj);
    poljaIskalnika = seznam(_poljaIskalnika, PoljePesmi.values) ?? d.poljaIskalnika;
    razvrstiIskalnik = PoljePesmi.values.asNameMap()[p.getString(_razvrstiIskalnik)];
    final zg = seznam(_zgoraj, InfoVrstice.values);
    zgoraj = zg != null && zg.length == 3 ? zg : d.zgoraj;
    minuteOdigrane = p.getInt(_minuteOdigrane) ?? d.minuteOdigrane;
    final sp = seznam(_spodaj, InfoVrstice.values);
    spodaj = sp != null && sp.length == 3 ? sp : d.spodaj;
    poljaVrste = seznam(_poljaVrste, PoljePesmi.values) ?? d.poljaVrste;
    GumbRunde gumb(String k, GumbRunde g) => GumbRunde(
      napis: p.getString('$_runda${k}_napis') ?? g.napis,
      barva: p.getInt('$_runda${k}_barva') ?? g.barva,
      midi: p.getString('$_runda${k}_midi') ?? g.midi,
    );
    pavza = gumb('pavza', d.pavza);
    igranje = gumb('igranje', d.igranje);
    notifyListeners();
  }

  /// Nastavitve pogleda, ki jih administrator lahko pošlje vsem (brez povečav pesmi, zasedbe ipd.).
  static bool _kljucPogleda(String k) =>
      const {
        _pisava, _pdfNajprej, _akordi, _svetla, _poljaSeznama, _ikoneSeznama, _razvrsti, _padajoce, //
        _minuteOdigrane, _spodaj, _poljaVrste, _zgoraj, _prelom, _oblacek, _oblacki, _barvaZgoraj, _barvaSpodaj,
        _poljaIskalnika, _razvrstiIskalnik,
      }.contains(k) ||
      k.startsWith('orodje_') ||
      k.startsWith(_runda) ||
      k.startsWith(_razvrstiMape) ||
      k.startsWith(_padajoceMape);

  /// Nastavitve pogleda te naprave kot JSON (ključi, ki niso shranjeni, imajo privzeto vrednost).
  Future<String> izvoziPogled() async {
    final p = await SharedPreferences.getInstance();
    return jsonEncode({
      for (final k in p.getKeys())
        if (_kljucPogleda(k)) k: p.get(k),
    });
  }

  /// Prevzame nastavitve pogleda (npr. od administratorja); ostale osebne nastavitve ostanejo.
  Future<void> uvoziPogled(String json) async {
    final j = jsonDecode(json) as Map<String, dynamic>;
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().where(_kljucPogleda).toList()) {
      await p.remove(k);
    }
    for (final MapEntry(:key, :value) in j.entries) {
      if (!_kljucPogleda(key)) continue;
      switch (value) {
        // Splet v JSON-u zapiše 22.0 kot 22.
        case final num v when key == _pisava:
          await p.setDouble(key, v.toDouble());
        case final bool v:
          await p.setBool(key, v);
        case final int v:
          await p.setInt(key, v);
        case final double v:
          await p.setDouble(key, v);
        case final String v:
          await p.setString(key, v);
        case final List<dynamic> v:
          await p.setStringList(key, [for (final x in v) '$x']);
      }
    }
    await nalozi();
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

  Future<void> nastaviOblacke(List<Oblacek> v) {
    oblacki = List.unmodifiable(v);
    return _shrani((p) => p.setString(_oblacki, jsonEncode([for (final o in oblacki) o.vJson()])));
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

  Future<void> nastaviSkrijIgrane(bool v) {
    skrijIgrane = v;
    return _shrani((p) => p.setBool(_skrijIgrane, v));
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

  Future<void> nastaviUsmeritev(Usmeritev v) {
    usmeritev = v;
    return _shrani((p) => p.setString(_usmeritev, v.name));
  }

  Future<void> nastaviUvode(bool v) {
    uvodi = v;
    return _shrani((p) => p.setBool(_uvodi, v));
  }

  Future<void> nastaviHraniUvode(bool v) {
    hraniUvode = v;
    return _shrani((p) => p.setBool(_hraniUvode, v));
  }

  Future<void> nastaviPredvajajUvode(bool v) {
    predvajajUvode = v;
    return _shrani((p) => p.setBool(_predvajajUvode, v));
  }

  Future<void> nastaviIzhodZvoka(String v) {
    izhodZvoka = v;
    return _shrani((p) => p.setString(_izhodZvoka, v));
  }

  Future<void> nastaviZaslonPrizgan(bool v) {
    zaslonPrizgan = v;
    return _shrani((p) => p.setBool(_zaslon, v));
  }
}
