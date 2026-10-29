import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'prenos.dart';
import 'ukazi.dart';

/// Izhod, ki ga ta naprava ne pošilja nikamor.
const nePosiljaj = '-';

/// Privzeti izhod brez izbrane naprave gre na vse povezane naprave.
const vsePovezane = '';

class Poslano {
  Poslano(this.cas, this.opis, this.izhod, this.naprave);
  final DateTime cas;
  final String opis;
  final String izhod;

  /// Imena naprav, na katere je ukaz šel (prazno: nikamor).
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

  bool vklopljen = false;

  /// Logični izhod → ime naprave ([vsePovezane] ali [nePosiljaj]).
  Map<String, String> izhodi = {};

  /// Imena naprav, na katere se aplikacija ob zagonu sama poveže.
  Set<String> shranjeneNaprave = {};

  List<NapravaMidi> naprave = [];
  bool iscem = false;
  String? napaka;
  final List<Poslano> dnevnik = [];

  Pesem? _odprta;
  KnjiznicaMidi? _knjiznicaOdprte;
  bool _nalozeno = false;
  StreamSubscription<void>? _spremembe;

  Future<void> nalozi() async {
    if (_nalozeno) return;
    _nalozeno = true;
    final p = await SharedPreferences.getInstance();
    vklopljen = p.getBool(_kljucVklopa) ?? false;
    try {
      izhodi = (jsonDecode(p.getString(_kljucIzhodov) ?? '{}') as Map).cast<String, String>();
    } catch (_) {
      izhodi = {};
    }
    shranjeneNaprave = (p.getStringList(_kljucNaprav) ?? const []).toSet();
    notifyListeners();
    if (vklopljen) unawaited(_zazeni());
  }

  Future<void> vklopi(bool da) async {
    vklopljen = da;
    (await SharedPreferences.getInstance()).setBool(_kljucVklopa, da);
    notifyListeners();
    if (da) await _zazeni();
  }

  Future<void> nastaviIzhod(String izhod, String naprava) async {
    izhodi[izhod] = naprava;
    (await SharedPreferences.getInstance()).setString(_kljucIzhodov, jsonEncode(izhodi));
    notifyListeners();
  }

  Future<void> _zazeni() async {
    _spremembe ??= _prenos.spremembe.listen((_) => osveziNaprave());
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
  Future<void> poslji(List<PoslaniUkaz> ukazi, {KnjiznicaMidi? knjiznica}) async {
    if (!vklopljen || ukazi.isEmpty) return;
    for (final u in ukazi) {
      final cilji = napraveZa(u.izhod);
      for (final n in cilji) {
        _prenos.poslji(Uint8List.fromList(u.ukaz.bajti), n.id);
        if (u.ukaz.bajtiKonca case final konec?) {
          Timer(const Duration(milliseconds: 100), () => _prenos.poslji(Uint8List.fromList(konec), n.id));
        }
      }
      final ime = u.ukaz.ime.isEmpty ? '' : '${u.ukaz.ime}: ';
      dnevnik.insert(
        0,
        Poslano(DateTime.now(), '$ime${u.ukaz.opis(knjiznica?.imeKanala(u.ukaz.kanal) ?? '')}', u.izhod, [
          for (final n in cilji) n.ime,
        ]),
      );
      // Majhen presledek, da naprave Bluetooth ne izgubijo ukazov.
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (dnevnik.length > 50) dnevnik.removeRange(50, dnevnik.length);
    notifyListeners();
  }

  /// Ob odprtju pesmi: najprej ukazi ob zaprtju prejšnje (če še ni zaprta), nato ukazi nove pesmi.
  Future<void> odprta(Pesem p, KnjiznicaMidi k) async {
    if (_odprta?.id == p.id) return;
    final prejsnja = _odprta;
    final prejsnjaKnjiznica = _knjiznicaOdprte;
    _odprta = p;
    _knjiznicaOdprte = k;
    if (prejsnja != null) await poslji(prejsnjaKnjiznica!.obZaprtju(prejsnja), knjiznica: prejsnjaKnjiznica);
    await poslji(k.obOdprtju(p), knjiznica: k);
  }

  /// Ob zaprtju pesmi; če je medtem že odprta druga, so ukazi ob zaprtju že poslani.
  Future<void> zaprta(Pesem p) async {
    if (_odprta?.id != p.id) return;
    final k = _knjiznicaOdprte!;
    _odprta = null;
    _knjiznicaOdprte = null;
    await poslji(k.obZaprtju(p), knjiznica: k);
  }

  @override
  void dispose() {
    _spremembe?.cancel();
    super.dispose();
  }
}
