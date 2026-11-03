import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'prenos.dart';
import 'takt.dart';
import 'xy.dart';
import 'ukazi.dart';

/// Izhod, ki ga ta naprava ne pošilja nikamor.
const nePosiljaj = '-';

/// Privzeti izhod brez izbrane naprave gre na vse povezane naprave.
const vsePovezane = '';

class Poslano {
  Poslano(this.cas, this.opis, this.izhod, this.naprave, [this.kanal = 0]);
  final DateTime cas;

  /// MIDI kanal ukaza (za barvno piko).
  final int kanal;
  final String opis;
  final String izhod;

  /// Imena naprav, na katere je ukaz šel (prazno: nikamor).
  final List<String> naprave;
}

/// Vnos v MIDI monitorju: prejet (IN) ali poslan (OUT) ukaz.
class ZapisMonitorja {
  ZapisMonitorja(this.cas, this.vhod, this.opis, [this.naprave = const []]);
  final DateTime cas;
  final bool vhod;
  final String opis;
  final List<String> naprave;
}

/// MIDI na tej napravi: povezane naprave, preslikava izhodov na naprave in pošiljanje.
/// Nastavitve so na vsaki napravi svoje (shared_preferences).
class Midi extends ChangeNotifier {
  Midi(this._prenos);

  static Midi? _aplikacija;
  static Midi get aplikacija => _aplikacija ??= Midi(MidiPrenosNaprave());

  /// Za teste.
  static set aplikacija(Midi m) => _aplikacija = m;

  final MidiPrenos _prenos;

  static const _kljucVklopa = 'midi_vklop';
  static const _kljucIzhodov = 'midi_izhodi';
  static const _kljucNaprav = 'midi_naprave';
  static const _kljucVhoda = 'midi_vhod';
  static const _kljucOdprtja = 'midi_ob_odprtju';
  static const _kljucTakta = 'midi_takt';
  static const _kljucXy = 'midi_xy';

  bool vklopljen = false;

  /// Ukazi ob odprtju in zaprtju pesmi (pesmi in splošna makra) s te naprave; privzeto izklopljeno,
  /// da jih ne pošilja vsaka naprava, ampak le tista, ki upravlja MIDI.
  bool obOdprtju = false;

  /// MIDI clock ali ukaz na dobo v tempu pesmi (pošilja ga naprava, ki pošilja ukaze ob odprtju).
  NastavitveTakta takt = const NastavitveTakta();
  Timer? _taktUra;

  /// XY pad v orodni vrstici (en, skupen za vse pesmi).
  NastavitveXy xy = const NastavitveXy();

  /// iPad na špilu: ukazi gredo vodji, ki jih pošlje na svoje naprave (vrne število ukazov brez naprave).
  Future<int> Function(List<PoslaniUkaz>)? prekoVodje;

  /// Na iPadu prek vodje pošilja vodja: vklopi pošiljanje in ne pošilja ukazov ob odprtju pesmi (to naredi vodja).
  void posiljajPrekoVodje(Future<int> Function(List<PoslaniUkaz>) vodja) {
    prekoVodje = vodja;
    vklopljen = true;
    notifyListeners();
  }

  /// Logični izhod → ime naprave ([vsePovezane] ali [nePosiljaj]).
  Map<String, String> izhodi = {};

  /// Imena naprav, na katere se aplikacija ob zagonu sama poveže.
  Set<String> shranjeneNaprave = {};

  List<NapravaMidi> naprave = [];
  bool iscem = false;
  String? napaka;
  final List<Poslano> dnevnik = [];

  /// Zgodovina prejetih in poslanih ukazov za MIDI monitor (najnovejši prvi).
  final List<ZapisMonitorja> monitor = [];
  static const dolzinaMonitorja = 300;

  void _vMonitor(ZapisMonitorja z) {
    monitor.insert(0, z);
    if (monitor.length > dolzinaMonitorja) monitor.removeRange(dolzinaMonitorja, monitor.length);
  }

  void pocistiMonitor() {
    monitor.clear();
    notifyListeners();
  }

  /// Dejanje → sprožilec (npr. "CC 1 64"), na vsaki napravi svoje.
  Map<DejanjeMidi, String> vhod = {};

  /// Dejanje, ki čaka na pritisk stikala (učenje).
  DejanjeMidi? ucim;

  /// Števca prejetih in poslanih ukazov za lučki MIDI IN / OUT.
  final aktivnostVhoda = ValueNotifier(0);
  final aktivnostIzhoda = ValueNotifier(0);

  /// Nazadnje prejeti ukaz, za prikaz v nastavitvah.
  String? zadnjePrejeto;

  final List<bool Function(DejanjeMidi)> _prejemniki = [];
  StreamSubscription<(String, Uint8List)>? _vhodNarocnina;

  Pesem? _odprta;
  KnjiznicaMidi? _knjiznicaOdprte;
  bool _nalozeno = false;
  StreamSubscription<void>? _spremembe;

  Future<void> nalozi() async {
    if (_nalozeno) return;
    _nalozeno = true;
    final p = await SharedPreferences.getInstance();
    vklopljen = p.getBool(_kljucVklopa) ?? false;
    obOdprtju = p.getBool(_kljucOdprtja) ?? false;
    try {
      takt = NastavitveTakta.izJson((jsonDecode(p.getString(_kljucTakta) ?? '{}') as Map).cast<String, dynamic>());
    } catch (_) {
      takt = const NastavitveTakta();
    }
    try {
      xy = NastavitveXy.izJson((jsonDecode(p.getString(_kljucXy) ?? '{}') as Map).cast<String, dynamic>());
    } catch (_) {
      xy = const NastavitveXy();
    }
    try {
      izhodi = (jsonDecode(p.getString(_kljucIzhodov) ?? '{}') as Map).cast<String, String>();
    } catch (_) {
      izhodi = {};
    }
    shranjeneNaprave = (p.getStringList(_kljucNaprav) ?? const []).toSet();
    try {
      final v = (jsonDecode(p.getString(_kljucVhoda) ?? '{}') as Map).cast<String, String>();
      vhod = {for (final d in DejanjeMidi.values) d: ?v[d.name]};
    } catch (_) {
      vhod = {};
    }
    notifyListeners();
    if (vklopljen) unawaited(_zazeni());
  }

  Future<void> vklopi(bool da) async {
    vklopljen = da;
    (await SharedPreferences.getInstance()).setBool(_kljucVklopa, da);
    notifyListeners();
    if (da) await _zazeni();
  }

  Future<void> nastaviObOdprtju(bool da) async {
    obOdprtju = da;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_kljucOdprtja, da);
  }

  Future<void> nastaviTakt(NastavitveTakta t) async {
    takt = t;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString(_kljucTakta, jsonEncode(t.vJson()));
    } catch (_) {}
  }

  Future<void> nastaviXy(NastavitveXy n) async {
    xy = n;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString(_kljucXy, jsonEncode(n.vJson()));
    } catch (_) {}
  }

  bool get taktTece => _taktUra != null;

  /// Začne pošiljati takt v tempu pesmi (če je vklopljen in ima pesem tempo).
  void zacniTakt(Pesem p, KnjiznicaMidi k, {@visibleForTesting DateTime Function()? ura}) {
    ustaviTakt();
    final t = takt;
    final bpm = tempoPesmi(p);
    if (t.nacin == NacinTakta.izklop || bpm == null || !vklopljen || prekoVodje != null) return;
    final ukazi = t.nacin == NacinTakta.ukaz ? k.razsiri(t.ukaz) : const <PoslaniUkaz>[];
    if (t.nacin == NacinTakta.ukaz && ukazi.isEmpty) return;
    final razmik = t.razmik(bpm);
    final vseh = t.sporocil();
    final zdaj = ura ?? DateTime.now;
    final zacetek = zdaj();
    var poslanih = 0;
    void korak() {
      final pretekel = zdaj().difference(zacetek).inMicroseconds;
      final na = (pretekel / razmik).floor();
      // Zamujena sporočila (npr. zaspala aplikacija) preskoči, da ne pridejo v kupu.
      if (na > poslanih + 1) poslanih = na;
      while (poslanih <= na) {
        if (t.nacin == NacinTakta.clock) {
          posljiSurovo(const [0xF8], t.izhod.isEmpty ? privzetiIzhod : t.izhod);
        } else {
          for (final u in ukazi) {
            posljiSurovo(u.ukaz.bajti, u.izhod, konec: u.ukaz.bajtiKonca);
          }
          aktivnostIzhoda.value++;
        }
        poslanih++;
        if (vseh != null && poslanih >= vseh) {
          ustaviTakt();
          return;
        }
      }
    }

    korak();
    if (vseh != null && poslanih >= vseh) return;
    _taktUra = Timer.periodic(Duration(milliseconds: t.nacin == NacinTakta.clock ? 2 : 5), (_) => korak());
  }

  void ustaviTakt() {
    _taktUra?.cancel();
    _taktUra = null;
  }

  /// Pošlje bajte na naprave izhoda brez zapisa v dnevnik (takt).
  void posljiSurovo(List<int> bajti, String izhod, {List<int>? konec}) {
    for (final n in napraveZa(izhod)) {
      _prenos.poslji(Uint8List.fromList(bajti), n.id);
      if (konec != null) Timer(const Duration(milliseconds: 50), () => _prenos.poslji(Uint8List.fromList(konec), n.id));
    }
  }

  Future<void> nastaviIzhod(String izhod, String naprava) async {
    izhodi[izhod] = naprava;
    (await SharedPreferences.getInstance()).setString(_kljucIzhodov, jsonEncode(izhodi));
    notifyListeners();
  }

  Future<void> _zazeni() async {
    _spremembe ??= _prenos.spremembe.listen((_) => osveziNaprave());
    _vhodNarocnina ??= _prenos.prejeto.listen((p) => prejeto(p.$2));
    await isci();
  }

  Future<void> osveziNaprave() async {
    try {
      naprave = await _prenos.naprave();
    } catch (e) {
      napaka = 'Naprav ni mogoče prebrati: $e';
    }
    notifyListeners();
    // Shranjene naprave poveži same, ko se pojavijo.
    for (final n in naprave) {
      if (!n.povezana && shranjeneNaprave.contains(n.ime)) unawaited(_povezi(n));
    }
  }

  final Set<String> _povezujem = {};

  Future<void> _povezi(NapravaMidi n) async {
    if (!_povezujem.add(n.id)) return;
    try {
      await _prenos.povezi(n.id);
    } catch (e) {
      napaka = 'Povezava z ${n.ime} ni uspela: $e';
    } finally {
      _povezujem.remove(n.id);
      await osveziNaprave();
    }
  }

  /// Išče naprave Bluetooth (USB so vidne tudi brez iskanja).
  Future<void> isci({Duration trajanje = const Duration(seconds: 15)}) async {
    if (iscem) return;
    iscem = true;
    napaka = null;
    notifyListeners();
    try {
      await _prenos.zacniIskanje();
      await osveziNaprave();
      await Future<void>.delayed(trajanje);
    } catch (e) {
      napaka = 'Iskanje ni uspelo: $e';
    } finally {
      _prenos.ustaviIskanje();
      iscem = false;
      await osveziNaprave();
    }
  }

  Future<void> povezi(NapravaMidi n, bool da) async {
    if (da) {
      shranjeneNaprave.add(n.ime);
    } else {
      shranjeneNaprave.remove(n.ime);
    }
    (await SharedPreferences.getInstance()).setStringList(_kljucNaprav, shranjeneNaprave.toList());
    if (da) {
      await _povezi(n);
    } else {
      _prenos.prekini(n.id);
      await osveziNaprave();
    }
  }

  Future<void> nastaviVhod(DejanjeMidi d, String? sprozilec) async {
    if (sprozilec == null) {
      vhod.remove(d);
    } else {
      // En sprožilec sproži samo eno dejanje.
      vhod.removeWhere((_, s) => s == sprozilec);
      vhod[d] = sprozilec;
    }
    (await SharedPreferences.getInstance()).setString(
      _kljucVhoda,
      jsonEncode({for (final e in vhod.entries) e.key.name: e.value}),
    );
    notifyListeners();
  }

  /// Začne ali prekliče učenje: naslednji prejeti ukaz postane sprožilec dejanja.
  void uci(DejanjeMidi? d) {
    ucim = d;
    notifyListeners();
  }

  /// Prejet ukaz z MIDI naprave.
  void prejeto(List<int> bajti) {
    if (!vklopljen) return;
    aktivnostVhoda.value++;
    final s = sprozilecIz(bajti);
    _vMonitor(
      ZapisMonitorja(
        DateTime.now(),
        true,
        s ?? bajti.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' '),
      ),
    );
    if (s == null) {
      notifyListeners();
      return;
    }
    zadnjePrejeto = s;
    final u = ucim;
    if (u != null) {
      ucim = null;
      nastaviVhod(u, s);
      return;
    }
    notifyListeners();
    for (final e in vhod.entries) {
      if (e.value == s) sprozi(e.key);
    }
  }

  /// Zasloni, ki se odzovejo na dejanja; zadnji dodani ima prednost (je na vrhu).
  void dodajPrejemnika(bool Function(DejanjeMidi) p) => _prejemniki.add(p);
  void odstraniPrejemnika(bool Function(DejanjeMidi) p) => _prejemniki.remove(p);

  /// Pošlje dejanje zaslonom od vrha navzdol, dokler ga kateri ne izvede.
  bool sprozi(DejanjeMidi d) {
    for (final p in _prejemniki.reversed.toList()) {
      if (p(d)) return true;
    }
    return false;
  }

  /// Povezane naprave, na katere gre logični izhod.
  List<NapravaMidi> napraveZa(String izhod) {
    final povezane = naprave.where((n) => n.povezana).toList();
    var cilj = izhodi[izhod] ?? vsePovezane;
    if (cilj == vsePovezane && izhod != privzetiIzhod) cilj = izhodi[privzetiIzhod] ?? vsePovezane;
    if (cilj == nePosiljaj) return const [];
    if (cilj == vsePovezane) return povezane;
    return povezane.where((n) => n.ime == cilj).toList();
  }

  /// Pošlje ukaze po vrsti; note off za note pride malo kasneje.
  Future<int> poslji(List<PoslaniUkaz> ukazi, {KnjiznicaMidi? knjiznica}) async {
    if (!vklopljen || ukazi.isEmpty) return ukazi.length;
    if (prekoVodje case final vodja?) return _posljiVodji(vodja, ukazi, knjiznica);
    var brezNaprave = 0;
    for (final u in ukazi) {
      final cilji = napraveZa(u.izhod);
      if (cilji.isEmpty) brezNaprave++;
      for (final n in cilji) {
        _prenos.poslji(Uint8List.fromList(u.ukaz.bajti), n.id);
        if (u.ukaz.bajtiKonca case final konec?) {
          Timer(const Duration(milliseconds: 100), () => _prenos.poslji(Uint8List.fromList(konec), n.id));
        }
      }
      _zapisi(u, knjiznica, [for (final n in cilji) n.ime]);
      // Majhen presledek, da naprave Bluetooth ne izgubijo ukazov.
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    notifyListeners();
    return brezNaprave;
  }

  Future<int> _posljiVodji(
    Future<int> Function(List<PoslaniUkaz>) vodja,
    List<PoslaniUkaz> ukazi,
    KnjiznicaMidi? knjiznica,
  ) async {
    var brezNaprave = ukazi.length;
    try {
      brezNaprave = await vodja(ukazi);
      napaka = null;
    } catch (e) {
      napaka = 'Vodja ni dosegljiv: $e';
    }
    for (final u in ukazi) {
      _zapisi(u, knjiznica, napaka == null ? const ['vodja'] : const []);
    }
    notifyListeners();
    return brezNaprave;
  }

  void _zapisi(PoslaniUkaz u, KnjiznicaMidi? knjiznica, List<String> naprave) {
    if (naprave.isNotEmpty) aktivnostIzhoda.value++;
    final ime = u.ukaz.ime.isEmpty ? '' : '${u.ukaz.ime}: ';
    dnevnik.insert(
      0,
      Poslano(
        DateTime.now(),
        '$ime${u.ukaz.opis(knjiznica?.imeKanala(u.ukaz.kanal) ?? '')}',
        u.izhod,
        naprave,
        u.ukaz.kanal,
      ),
    );
    if (dnevnik.length > 50) dnevnik.removeRange(50, dnevnik.length);
    _vMonitor(ZapisMonitorja(DateTime.now(), false, dnevnik.first.opis, naprave));
  }

  /// Ukazi z iPada (prek vodje), ki jih vodja pošlje na svoje naprave. Vrne število ukazov brez naprave.
  Future<int> izIpada(List<dynamic> ukazi, KnjiznicaMidi knjiznica) => poslji([
    for (final u in ukazi)
      if (u is Map)
        if (razcleniUkaz(u['zapis']?.toString() ?? '') case final ukaz?)
          PoslaniUkaz(ukaz.kopija(ime: u['ime']?.toString() ?? ''), u['izhod']?.toString() ?? privzetiIzhod),
  ], knjiznica: knjiznica);

  /// Ob odprtju pesmi: najprej ukazi ob zaprtju prejšnje (če še ni zaprta), nato ukazi nove pesmi.
  /// [uvod]: ali gre zraven tudi MIDI za uvod (gumb Uvodi v orodni vrstici).
  Future<void> odprta(Pesem p, KnjiznicaMidi k, {bool uvod = true}) async {
    if (_odprta?.id == p.id || prekoVodje != null) return;
    final prejsnja = _odprta;
    final prejsnjaKnjiznica = _knjiznicaOdprte;
    _odprta = p;
    _knjiznicaOdprte = k;
    if (!obOdprtju) return;
    ustaviTakt();
    if (prejsnja != null) await poslji(prejsnjaKnjiznica!.obZaprtju(prejsnja), knjiznica: prejsnjaKnjiznica);
    await poslji(k.obOdprtju(p, uvod: uvod), knjiznica: k);
    if (_odprta?.id == p.id) zacniTakt(p, k);
  }

  /// Ob zaprtju pesmi; če je medtem že odprta druga, so ukazi ob zaprtju že poslani.
  Future<void> zaprta(Pesem p) async {
    if (_odprta?.id != p.id) return;
    final k = _knjiznicaOdprte!;
    _odprta = null;
    _knjiznicaOdprte = null;
    ustaviTakt();
    if (obOdprtju) await poslji(k.obZaprtju(p), knjiznica: k);
  }

  @override
  void dispose() {
    ustaviTakt();
    _spremembe?.cancel();
    _vhodNarocnina?.cancel();
    super.dispose();
  }
}

/// Ovije zaslon, ki se odziva na dejanja MIDI (nožno stikalo), dokler je njegov zaslon na vrhu.
class NaMidi extends StatefulWidget {
  const NaMidi({super.key, required this.dejanje, required this.child});

  /// Vrne true, če je dejanje izvedel; sicer ga dobi zaslon pod njim.
  final bool Function(DejanjeMidi) dejanje;
  final Widget child;

  @override
  State<NaMidi> createState() => _NaMidiState();
}

class _NaMidiState extends State<NaMidi> {
  bool _prejmi(DejanjeMidi d) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    return widget.dejanje(d);
  }

  @override
  void initState() {
    super.initState();
    Midi.aplikacija.dodajPrejemnika(_prejmi);
  }

  @override
  void dispose() {
    Midi.aplikacija.odstraniPrejemnika(_prejmi);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
