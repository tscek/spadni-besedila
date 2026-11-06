import 'dart:async';

import 'package:flutter/foundation.dart';

import 'efekti.dart';
import 'midi/midi.dart';
import 'midi/ukazi.dart';
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

  /// Efekti, ki igrajo na drugi napravi: gumb → [pozicija ms, trajanje ms, zanka 0/1], in njihova glasnost.
  Map<String, List<int>> _drugFx = {};
  DateTime _drugFxCas = DateTime.now();
  double? _drugGlasnost;

  /// MIDI knjižnica (za ukaze gumbov, ki jih pošlje ta naprava; nastavi main).
  KnjiznicaMidi Function()? knjiznica;

  bool _povezano = false;
  Timer? _porocaj;

  /// Ta naprava predvaja efekte (PC) ali pa ni na špilu (efekti igrajo tu).
  bool get _efektiTu => Nastavitve.aplikacija.predvajajEfekte || (vodji == null && vsem == null);

  /// Stanje efekta gumba na tej ali drugi napravi (null = ne igra).
  StanjeFx? stanjeFx(String gumb) {
    if (_efektiTu) return Efekti.aplikacija.stanje[gumb];
    final d = _drugFx[gumb];
    if (d == null || d.length < 2) return null;
    var poz = d[0] + DateTime.now().difference(_drugFxCas).inMilliseconds;
    final zanka = d.length > 2 && d[2] == 1;
    if (zanka && d[1] > 0) poz %= d[1];
    return (pozicija: Duration(milliseconds: poz.clamp(0, d[1])), trajanje: Duration(milliseconds: d[1]), zanka: zanka);
  }

  /// Ali kakšen efekt igra na drugi napravi.
  bool get igraKakFx => _efektiTu ? Efekti.aplikacija.stanje.isNotEmpty : _drugFx.isNotEmpty;

  /// Glasnost efektov (na napravi, ki jih predvaja).
  double get glasnostFx => _efektiTu ? Efekti.aplikacija.glasnost : (_drugGlasnost ?? 1);

  /// Pritisk ali spust gumba FX (s katerekoli naprave; igra naprava z efekti).
  void fx(String gumb, {required bool dol}) => _ukazFx({'akcija': 'fx', 'gumb': gumb, 'dol': dol});

  /// Klik brez spusta (nožno stikalo).
  void fxKlik(String gumb) => _ukazFx({'akcija': 'fxKlik', 'gumb': gumb});

  void fxUstaviVse() => _ukazFx({'akcija': 'fxUstavi'});

  void fxGlasnost(double g) {
    _drugGlasnost = g;
    _ukazFx({'akcija': 'fxGlasnost', 'g': g});
    notifyListeners();
  }

  /// MIDI (XY pad): s te naprave, če ima vklopljen MIDI, sicer prek špila na napravo z efekti.
  Future<void> posljiMidi(List<PoslaniUkaz> ukazi, {KnjiznicaMidi? knjiznica, bool surovo = false}) async {
    final midi = Midi.aplikacija;
    if (midi.vklopljen || (vodji == null && vsem == null)) {
      if (surovo) {
        for (final u in ukazi) {
          midi.posljiSurovo(u.ukaz.bajti, u.izhod);
        }
        midi.aktivnostIzhoda.value++;
      } else {
        await midi.poslji(ukazi, knjiznica: knjiznica);
      }
      return;
    }
    _ukazFx({
      'akcija': 'midi',
      'ukazi': [
        for (final u in ukazi) {'z': u.ukaz.zapis, 'i': u.izhod},
      ],
    });
  }

  /// MIDI ukazi ali makri po imenu (gumbi nad XY padom).
  Future<void> posljiMidiZapis(String zapis, KnjiznicaMidi k) async {
    if (Midi.aplikacija.vklopljen || (vodji == null && vsem == null)) {
      await Midi.aplikacija.poslji(k.razsiri(zapis), knjiznica: k);
      return;
    }
    _ukazFx({'akcija': 'midi', 'zapis': zapis});
  }

  void _ukazFx(Map<String, dynamic> u) {
    if (_efektiTu) {
      _izvediFx(u);
    } else if (vodji case final f?) {
      f(u);
    } else {
      vsem?.call({'vrsta': 'zvokUkaz', ...u});
    }
  }

  static const _akcijeFx = {'fx', 'fxKlik', 'fxUstavi', 'fxGlasnost', 'midi'};

  /// Ukaz za efekte izvede ta naprava (ima efekte).
  Future<void> _izvediFx(Map<String, dynamic> u) async {
    final e = Efekti.aplikacija;
    final gumb = u['gumb']?.toString() ?? '';
    switch (u['akcija']) {
      case 'fx':
        await e.dogodek(gumb, dol: u['dol'] == true);
      case 'fxKlik':
        await e.klik(gumb);
      case 'fxUstavi':
        await e.ustaviVse();
      case 'fxGlasnost':
        e.nastaviGlasnost((u['g'] as num?)?.toDouble() ?? 1);
      case 'midi':
        final midi = Midi.aplikacija;
        if (!midi.vklopljen) return;
        final k = knjiznica?.call();
        if (u['zapis'] case final String z when k != null) {
          await midi.poslji(k.razsiri(z), knjiznica: k);
        } else if (u['ukazi'] case final List l) {
          final ukazi = [
            for (final x in l.whereType<Map>())
              if (razcleniUkaz(x['z']?.toString() ?? '') case final m?) PoslaniUkaz(m, x['i']?.toString() ?? ''),
          ];
          for (final p in ukazi) {
            midi.posljiSurovo(p.ukaz.bajti, p.izhod);
          }
          if (ukazi.isNotEmpty) midi.aktivnostIzhoda.value++;
        }
    }
  }

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
    Efekti.aplikacija.addListener(_lokalno);
  }

  void odklopi() {
    if (!_povezano) return;
    _povezano = false;
    Predvajanje.uvodi.removeListener(_lokalno);
    Predvajanje.playback.removeListener(_lokalno);
    Efekti.aplikacija.removeListener(_lokalno);
    _porocaj?.cancel();
  }

  void _lokalno() {
    _porocaj?.cancel();
    // Med playbackom vsake 2 s čas, da druge naprave sledijo vrstici.
    if (Predvajanje.playback.igra != null || Efekti.aplikacija.stanje.isNotEmpty) {
      _porocaj = Timer.periodic(const Duration(seconds: 2), (_) => _sporoci());
    }
    _sporoci();
    notifyListeners();
  }

  Map<String, dynamic> _lastno() => {
    'uvod': Predvajanje.uvodi.igra,
    'playback': Predvajanje.playback.igra,
    'ms': Predvajanje.playback.pozicija.value.inMilliseconds,
    if (Nastavitve.aplikacija.predvajajEfekte) ...{'fx': _lastniFx(), 'fxG': Efekti.aplikacija.glasnost},
  };

  static Map<String, List<int>> _lastniFx() => {
    for (final MapEntry(key: id, value: s) in Efekti.aplikacija.stanje.entries)
      id: [s.pozicija.inMilliseconds, s.trajanje.inMilliseconds, if (s.zanka) 1 else 0],
  };

  Map<String, List<int>> _drugFxZdaj() {
    final pretece = DateTime.now().difference(_drugFxCas).inMilliseconds;
    return {
      for (final MapEntry(key: id, value: d) in _drugFx.entries)
        if (d.length >= 2) id: [d[0] + pretece, d[1], if (d.length > 2) d[2] else 0],
    };
  }

  void _sprejmiFx(Object? fx, Object? g) {
    if (fx is! Map) return;
    _drugFx = {
      for (final MapEntry(:key, :value) in fx.entries)
        if (value is List) key.toString(): [for (final v in value) (v as num).toInt()],
    };
    _drugFxCas = DateTime.now();
    if (g is num) _drugGlasnost = g.toDouble();
  }

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
      'fx': lastno['fx'] ?? _drugFxZdaj(),
      'fxG': lastno['fxG'] ?? _drugGlasnost,
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
    if (_akcijeFx.contains(u['akcija'])) {
      if (Nastavitve.aplikacija.predvajajEfekte) {
        await _izvediFx(u);
      } else {
        vsem?.call({'vrsta': 'zvokUkaz', ...u});
      }
      return;
    }
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
        if (u.containsKey('fx')) _sprejmiFx(u['fx'], u['fxG']);
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
      if (_akcijeFx.contains(j['akcija']) && Nastavitve.aplikacija.predvajajEfekte) await _izvediFx(j);
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
    if (!Nastavitve.aplikacija.predvajajEfekte) _sprejmiFx(j['fx'], j['fxG']);
    notifyListeners();
  }

  /// Konec špila: tuje stanje pozabi.
  void pozabi() {
    vsem = null;
    vodji = null;
    _drugUvod = null;
    _drugPlayback = null;
    _drugFx = {};
    notifyListeners();
  }
}
