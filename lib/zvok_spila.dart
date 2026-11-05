import 'dart:async';

import 'package:flutter/foundation.dart';

import 'nastavitve.dart';
import 'uvodi.dart';

/// Uvodi in playback na špilu: uho (vklop uvodov) je skupno vsem, kdorkoli ga preklopi; vsi vidijo,
/// kdaj kakšna naprava predvaja uvod ali playback; gumb ▶ na katerikoli napravi sproži playback na napravi,
/// ki ga predvaja. Brez špila vse ostane na tej napravi.
class ZvokSpila extends ChangeNotifier {
  static ZvokSpila aplikacija = ZvokSpila();

  /// Vodja: pošlje sporočilo vsem sledilcem.
  void Function(Map<String, dynamic>)? vsem;

  /// Sledilec: pošlje ukaz vodji.
  void Function(Map<String, dynamic>)? vodji;

  /// Predvaja ali ustavi playback pesmi na tej napravi (nastavi main).
  Future<void> Function(String pesem)? predvajajTu;

  /// Kaj predvajajo druge naprave (vodja: sledilci; sledilec: stanje od vodje, tudi vodjevo).
  String? _drugUvod;
  String? _drugPlayback;
  int _drugMs = 0;
  DateTime _drugCas = DateTime.now();

  bool _povezano = false;
  Timer? _porocaj;

  /// Pesem, katere uvod igra na tej ali drugi napravi.
  String? get uvod => Predvajanje.uvodi.igra ?? _drugUvod;

  /// Pesem, katere playback igra na tej ali drugi napravi.
  String? get playback => Predvajanje.playback.igra ?? _drugPlayback;

  /// Trenutni čas playbacka (lokalno ali ocena po zadnjem sporočilu druge naprave).
  Duration get pozicijaPlaybacka {
    if (Predvajanje.playback.igra != null) return Predvajanje.playback.pozicija.value;
    if (_drugPlayback == null) return Duration.zero;
    return Duration(milliseconds: _drugMs) + DateTime.now().difference(_drugCas);
  }

  /// Poslušanje lokalnih predvajalnikov (enkrat, iz main; v testih znova po zamenjavi predvajalnikov).
  void povezi() {
    if (_povezano) return;
    _povezano = true;
    Predvajanje.uvodi.addListener(_lokalno);
    Predvajanje.playback.addListener(_lokalno);
  }

  void odklopi() {
    if (!_povezano) return;
    _povezano = false;
    Predvajanje.uvodi.removeListener(_lokalno);
    Predvajanje.playback.removeListener(_lokalno);
    _porocaj?.cancel();
  }

  void _lokalno() {
    _porocaj?.cancel();
    // Med playbackom vsake 2 s čas, da druge naprave sledijo vrstici.
    if (Predvajanje.playback.igra != null) {
      _porocaj = Timer.periodic(const Duration(seconds: 2), (_) => _sporoci());
    }
    _sporoci();
    notifyListeners();
  }

  Map<String, dynamic> _lastno() => {
    'uvod': Predvajanje.uvodi.igra,
    'playback': Predvajanje.playback.igra,
    'ms': Predvajanje.playback.pozicija.value.inMilliseconds,
  };

  void _sporoci() {
    if (vodji case final f?) {
      f({'akcija': 'stanje', ..._lastno()});
    } else {
      objavi();
    }
  }

  /// Vodja: stanje vsem (tudi ob novem sledilcu).
  void objavi() {
    final f = vsem;
    if (f == null) return;
    final lastno = _lastno();
    final tuPlayback = lastno['playback'] != null;
    f({
      'vrsta': 'zvok',
      'uho': Nastavitve.aplikacija.uvodi,
      'uvod': lastno['uvod'] ?? _drugUvod,
      'playback': lastno['playback'] ?? _drugPlayback,
      'ms': tuPlayback
          ? lastno['ms']
          : _drugPlayback == null
          ? 0
          : _drugMs + DateTime.now().difference(_drugCas).inMilliseconds,
    });
  }

  /// Uho (uvodi vklopljeni) na tej napravi in na špilu.
  Future<void> nastaviUho(bool v) async {
    await _uho(v);
    vodji?.call({'akcija': 'uho', 'v': v});
    objavi();
  }

  Future<void> _uho(bool v) async {
    if (Nastavitve.aplikacija.uvodi != v) await Nastavitve.aplikacija.nastaviUvode(v);
    if (!v) await Predvajanje.uvodi.ustavi();
    notifyListeners();
  }

  /// Gumb ▶/■ ali nožno stikalo: na tej napravi, če predvaja playback, sicer na napravi špila, ki ga.
  Future<void> preklopiPlayback(String pesem) async {
    if (Nastavitve.aplikacija.predvajajPlayback) {
      await predvajajTu?.call(pesem);
    } else if (vodji case final f?) {
      f({'akcija': 'playback', 'pesem': pesem});
    } else {
      vsem?.call({'vrsta': 'zvokUkaz', 'akcija': 'playback', 'pesem': pesem});
    }
  }

  /// Ali je gumb ▶ smiseln na tej napravi (predvaja sama ali je na špilu).
  bool get lahkoPlayback => Nastavitve.aplikacija.predvajajPlayback || vodji != null || vsem != null;

  /// Vodja: ukaz sledilca (uho, playback, stanje predvajanja).
  Future<void> odSledilca(Map<String, dynamic> u) async {
    switch (u['akcija']) {
      case 'uho':
        await _uho(u['v'] == true);
      case 'playback':
        final pesem = u['pesem']?.toString() ?? '';
        if (pesem.isEmpty) return;
        if (Nastavitve.aplikacija.predvajajPlayback) {
          await predvajajTu?.call(pesem);
        } else {
          vsem?.call({'vrsta': 'zvokUkaz', 'akcija': 'playback', 'pesem': pesem});
        }
      case 'stanje':
        _drugUvod = u['uvod']?.toString();
        _drugPlayback = u['playback']?.toString();
        _drugMs = (u['ms'] as num?)?.toInt() ?? 0;
        _drugCas = DateTime.now();
        notifyListeners();
    }
    objavi();
  }

  /// Sledilec: sporočilo vodje.
  Future<void> odVodje(Map<String, dynamic> j) async {
    if (j['vrsta'] == 'zvokUkaz') {
      if (j['akcija'] == 'playback' && Nastavitve.aplikacija.predvajajPlayback) {
        await predvajajTu?.call(j['pesem']?.toString() ?? '');
      }
      return;
    }
    if (j['uho'] is bool && j['uho'] != Nastavitve.aplikacija.uvodi) await _uho(j['uho'] as bool);
    // Svoje predvajanje ta naprava pozna sama; od vodje vzame le tuje.
    final uvod = j['uvod']?.toString();
    final playback = j['playback']?.toString();
    _drugUvod = uvod == Predvajanje.uvodi.igra ? null : uvod;
    _drugPlayback = playback == Predvajanje.playback.igra ? null : playback;
    _drugMs = (j['ms'] as num?)?.toInt() ?? 0;
    _drugCas = DateTime.now();
    notifyListeners();
  }

  /// Konec špila: tuje stanje pozabi.
  void pozabi() {
    vsem = null;
    vodji = null;
    _drugUvod = null;
    _drugPlayback = null;
    notifyListeners();
  }
}
