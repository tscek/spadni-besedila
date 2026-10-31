import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../baza.dart';
import '../config.dart';
import '../runda.dart';
import 'streznik.dart';

/// Kar vodja trenutno kaže: pesem in (če igra po setlisti) mesto v setlisti.
@immutable
class StanjeSpila {
  const StanjeSpila({required this.pesem, this.setlista, this.indeks});

  factory StanjeSpila.izJson(Map<String, dynamic> j) => StanjeSpila(
    pesem: j['pesem'] as String,
    setlista: j['setlista'] as String?,
    indeks: (j['indeks'] as num?)?.toInt(),
  );

  final String pesem;
  final String? setlista;
  final int? indeks;

  Map<String, dynamic> vJson() => {
    'vrsta': 'stanje',
    'pesem': pesem,
    if (setlista != null) 'setlista': setlista,
    if (indeks != null) 'indeks': indeks,
  };

  @override
  bool operator ==(Object other) =>
      other is StanjeSpila && other.pesem == pesem && other.setlista == setlista && other.indeks == indeks;

  @override
  int get hashCode => Object.hash(pesem, setlista, indeks);
}

/// Pesem v seznamčku naslednjih: kdo jo je dodal in ali gre (v setlisti) na konec.
@immutable
class Naslednja {
  const Naslednja({required this.pesem, this.kdo = '', this.naKonec = false});

  factory Naslednja.izJson(Map<String, dynamic> j) =>
      Naslednja(pesem: j['pesem'] as String, kdo: j['kdo'] as String? ?? '', naKonec: j['naKonec'] == true);

  final String pesem;
  final String kdo;
  final bool naKonec;

  Map<String, dynamic> vJson() => {'pesem': pesem, if (kdo.isNotEmpty) 'kdo': kdo, if (naKonec) 'naKonec': true};
}

enum VlogaSpila { nic, vodja, sledilec }

/// Sinhronizacija na špilu prek lokalnega WiFi-ja (brez interneta).
/// Vodja zažene strežnik ([StreznikVodje]) in pošilja [StanjeSpila]; sledilci ga prek WebSocketa
/// prejemajo in pokažejo isto pesem iz svoje lokalne kopije.
class Spil extends ChangeNotifier {
  Spil({StreznikVodje? Function()? streznik, Stream<NajdenVodja> Function()? iskalec})
    : _ustvariStreznik = streznik ?? ustvariStreznik,
      _isciVodjo = iskalec ?? isciVodjo;

  final StreznikVodje? Function() _ustvariStreznik;
  final Stream<NajdenVodja> Function() _isciVodjo;

  VlogaSpila vloga = VlogaSpila.nic;
  StanjeSpila? stanje;

  /// Seznamček naslednjih pesmi; hrani ga vodja, sledilci dobijo kopijo (brez špila je samo na tej napravi).
  List<Naslednja> naslednje = const [];

  /// Vodja: pesem, ki jo je sledilec s pravico zamenjal vsem; aplikacija jo odpre tudi na vodji.
  final zahtevanaPesem = ValueNotifier<StanjeSpila?>(null);
  String? napaka;

  /// Vodja: naslov, ki ga odprejo iPadi (npr. http://192.168.1.5:8765).
  String? naslov;
  int sledilcev = 0;

  /// Sledilec: ali je povezava z vodjo trenutno vzpostavljena.
  bool povezan = false;

  /// Sledilec: povezava je bila vzpostavljena in je padla (opozorilo, dokler se ne obnovi).
  bool prekinjeno = false;

  StreznikVodje? _streznik;
  WebSocketChannel? _kanal;
  StreamSubscription<dynamic>? _poslusam;
  Timer? _ponovnaPovezava;
  Uri? _naslovVodje;
  StreamSubscription<NajdenVodja>? _iskanje;

  /// Sledilec: vodje, ki se oglašajo na omrežju (naslov WebSocket → ime), za izbiro, ko jih je več.
  final Map<Uri, String> najdeniVodje = {};

  /// Kar ta naprava trenutno kaže; ko začne voditi, to takoj pošlje sledilcem.
  StanjeSpila? _prikazano;

  /// Pesem, ki jo ta naprava trenutno kaže (ali jo je nazadnje).
  StanjeSpila? get prikazano => _prikazano;

  /// Sledilec: naslov WebSocket vodje, ki mu sledi.
  Uri? get vodja => _naslovVodje;

  /// Sledilec: naslov vodje, s katerim se povezuje (npr. 192.168.1.5:8765).
  String? get naslovVodje => _naslovVodje == null ? null : '${_naslovVodje!.host}:${_naslovVodje!.port}';

  /// Ali naprava lahko vodi (strežnika v brskalniku ni mogoče zagnati).
  bool get lahkoVodi => _ustvariStreznik() != null;

  Future<void> zacniVoditi(Baza baza) async {
    if (vloga == VlogaSpila.vodja) return;
    await ustavi();
    final s = _ustvariStreznik();
    if (s == null) {
      napaka = 'Ta naprava ne more voditi špila.';
      notifyListeners();
      return;
    }
    try {
      naslov = await s.zacni(baza, (n) {
        sledilcev = n;
        notifyListeners();
      }, obSporocilu: _odSledilca);
      _streznik = s;
      vloga = VlogaSpila.vodja;
      napaka = null;
      stanje = _prikazano ?? stanje;
      if (stanje != null) s.poslji(jsonEncode(stanje!.vJson()));
      _objaviNaslednje();
      // Časovnik runde in pavze je skupen: vodja ga pošilja ob vsaki spremembi.
      Runda.aplikacija.addListener(_objaviRundo);
      _objaviRundo();
    } catch (e) {
      napaka = 'Strežnika ni bilo mogoče zagnati: $e';
    }
    notifyListeners();
  }

  /// Zaslon s pesmijo pove, kaj kaže; vodja to pošlje sledilcem.
  /// Pesem, ki se odpre, gre s seznamčka naslednjih (pri vodji ali brez špila).
  void prikazujem(StanjeSpila s) {
    _prikazano = s;
    if (_zgodovina.lastOrNull != s.pesem) {
      _zgodovina.add(s.pesem);
      if (_zgodovina.length > 200) _zgodovina.removeAt(0);
    }
    if (vloga == VlogaSpila.vodja) objavi(s);
    if (vloga != VlogaSpila.sledilec && naslednje.any((n) => n.pesem == s.pesem)) {
      _nastaviNaslednje([...naslednje.where((n) => n.pesem != s.pesem)]);
    }
  }

  /// Pesmi, ki jih je ta naprava pokazala (za nazaj s podrsajem ali nožnim stikalom).
  final List<String> _zgodovina = [];

  /// Prejšnja pokazana pesem; trenutna gre nazaj na začetek čakalne vrste, da je spet naslednja.
  String? nazaj() {
    if (_zgodovina.length < 2) return null;
    final zdaj = _zgodovina.removeLast();
    dodajNaslednjo(Naslednja(pesem: zdaj), naPrvo: true);
    return _zgodovina.last;
  }

  /// Doda pesem v čakalno vrsto (lahko vsak): na konec ali z [naPrvo] na prvo mesto.
  /// Pesem, ki je že v vrsti, se premakne. Sledilec jo pošlje vodji, ta pa vrsto vsem.
  void dodajNaslednjo(Naslednja n, {bool naPrvo = false}) =>
      _spremeni({'ukaz': 'dodaj', ...n.vJson(), if (naPrvo) 'naPrvo': true});

  /// Odstrani [i]-to pesem s seznamčka.
  void odstraniNaslednjo(int i) => _spremeni({'ukaz': 'odstrani', 'i': i, 'pesem': naslednje[i].pesem});

  /// Nova čakalna vrsta s [pesmi] po vrsti (npr. iz playliste); zamenja dosedanjo pri vseh.
  void nastaviVrsto(List<String> pesmi) => _spremeni({'ukaz': 'nastavi', 'pesmi': pesmi});

  /// Izprazni čakalno vrsto (nova čakalna vrsta).
  void pocistiNaslednje() => _spremeni({'ukaz': 'pocisti'});

  /// Sledilec s pravico: vsem (tudi vodji) pokaže to pesem.
  void zamenjajVsem(StanjeSpila s) {
    if (vloga == VlogaSpila.sledilec) {
      _posljiVodji({'vrsta': 'ukaz', 'ukaz': 'prikazi', 'stanje': s.vJson()});
    } else {
      zahtevanaPesem.value = s;
    }
  }

  /// Prva pesem s seznamčka, ki je na vrsti; z [naKonec] false brez tistih za konec setliste.
  Naslednja? prvaNaslednja({bool naKonec = true}) => naslednje.where((n) => naKonec || !n.naKonec).firstOrNull;

  void _spremeni(Map<String, dynamic> ukaz) {
    if (vloga == VlogaSpila.sledilec) {
      _posljiVodji({'vrsta': 'ukaz', ...ukaz});
    } else {
      _izvedi(ukaz);
    }
  }

  void _posljiVodji(Map<String, dynamic> sporocilo) {
    try {
      _kanal?.sink.add(jsonEncode(sporocilo));
    } catch (_) {}
  }

  /// Vodja: sporočilo sledilca.
  void _odSledilca(Map<String, dynamic> j) {
    if (j['vrsta'] != 'ukaz') return;
    if (j['ukaz'] == 'prikazi' && j['stanje'] is Map) {
      zahtevanaPesem.value = StanjeSpila.izJson((j['stanje'] as Map).cast<String, dynamic>());
      return;
    }
    _izvedi(j);
  }

  void _izvedi(Map<String, dynamic> u) {
    final pesem = u['pesem']?.toString() ?? '';
    // Indeks velja, če se ujema pesem (seznamček se je medtem lahko spremenil).
    int indeks() {
      final i = (u['i'] as num?)?.toInt() ?? -1;
      return i >= 0 && i < naslednje.length && naslednje[i].pesem == pesem
          ? i
          : naslednje.indexWhere((n) => n.pesem == pesem);
    }

    switch (u['ukaz']) {
      case 'dodaj' when pesem.isNotEmpty:
        final ostale = naslednje.where((n) => n.pesem != pesem);
        final nova = Naslednja.izJson(u);
        _nastaviNaslednje(u['naPrvo'] == true ? [nova, ...ostale] : [...ostale, nova]);
      case 'odstrani':
        final i = indeks();
        if (i >= 0) _nastaviNaslednje([...naslednje]..removeAt(i));
      case 'pocisti':
        _nastaviNaslednje([]);
      case 'runda':
        Runda.aplikacija.izvedi(u);
      case 'nastavi' when u['pesmi'] is List:
        _nastaviNaslednje([
          for (final p in (u['pesmi'] as List).map((x) => x.toString()).toSet())
            if (p.isNotEmpty) Naslednja(pesem: p),
        ]);
    }
  }

  void _nastaviNaslednje(List<Naslednja> n) {
    naslednje = List.unmodifiable(n);
    _objaviNaslednje();
    notifyListeners();
  }

  void _objaviRundo() => _streznik?.poslji(jsonEncode(Runda.aplikacija.vJson()));

  void _objaviNaslednje() => _streznik?.poslji(
    jsonEncode({
      'vrsta': 'naslednje',
      'seznam': [for (final n in naslednje) n.vJson()],
    }),
  );

  /// Sledilec: poišče vodjo na WiFi-ju (vodja svoj naslov oddaja vsaki 2 s) in se z njim poveže.
  /// Če je podan [zadnji] naslov, se z njim poveže takoj, dokler se vodja ne oglasi.
  void samodejnoSledi({Uri? zadnji}) {
    if (vloga == VlogaSpila.vodja) return;
    if (zadnji != null) {
      sledi(zadnji);
    } else if (vloga != VlogaSpila.sledilec) {
      vloga = VlogaSpila.sledilec;
      notifyListeners();
    }
    _iskanje ??= _isciVodjo().listen(
      (v) {
        final ws = naslovWebSocket(v.naslov);
        if (ws == null) return;
        if (najdeniVodje[ws] != v.ime) {
          najdeniVodje[ws] = v.ime;
          notifyListeners();
        }
        // Samodejno samo, dokler ni povezave; z izbranim vodjo ostane povezan, tudi če se oglaša še kdo.
        if (ws != _naslovVodje && vloga == VlogaSpila.sledilec && !povezan) sledi(ws);
      },
      onError: (Object e) {
        napaka = 'Iskanje vodje ne deluje: $e';
        notifyListeners();
      },
    );
  }

  /// Vodja: pošlji sledilcem, kaj je zdaj na vrsti.
  void objavi(StanjeSpila s) {
    if (s == stanje) return;
    stanje = s;
    _streznik?.poslji(jsonEncode(s.vJson()));
    notifyListeners();
  }

  /// Sledilec: poveži se z vodjo na [ws] (npr. ws://192.168.1.5:8765/ws). Ob prekinitvi se poveže znova.
  void sledi(Uri ws) {
    if (vloga == VlogaSpila.vodja) return;
    _ustaviSledenje();
    vloga = VlogaSpila.sledilec;
    _naslovVodje = ws;
    napaka = null;
    _povezi();
    notifyListeners();
  }

  void _povezi() {
    final ws = _naslovVodje;
    if (ws == null || vloga != VlogaSpila.sledilec) return;
    try {
      final kanal = WebSocketChannel.connect(ws);
      _kanal = kanal;
      kanal.ready.then((_) {
        if (_kanal != kanal) return;
        povezan = true;
        prekinjeno = false;
        napaka = null;
        // Gumba runde in pavze gresta vodji, ta pa časovnik pošlje vsem.
        Runda.aplikacija.vodji = (u) => _posljiVodji({'vrsta': 'ukaz', 'ukaz': 'runda', ...u});
        notifyListeners();
      }, onError: (Object _) => _prekinjeno(kanal));
      _poslusam = kanal.stream.listen(
        (m) {
          final j = jsonDecode(m as String) as Map<String, dynamic>;
          if (j['vrsta'] == 'stanje') {
            stanje = StanjeSpila.izJson(j);
            notifyListeners();
          } else if (j['vrsta'] == 'runda') {
            Runda.aplikacija.prevzemi(j);
          } else if (j['vrsta'] == 'naslednje') {
            naslednje = List.unmodifiable([
              for (final n in (j['seznam'] as List?) ?? const [])
                if (n is Map) Naslednja.izJson(n.cast<String, dynamic>()),
            ]);
            notifyListeners();
          }
        },
        onError: (Object _) => _prekinjeno(kanal),
        onDone: () => _prekinjeno(kanal),
      );
    } catch (_) {
      _prekinjeno(null);
    }
  }

  void _prekinjeno(WebSocketChannel? kanal) {
    if (kanal != null && kanal != _kanal) return;
    Runda.aplikacija.vodji = null;
    if (povezan) {
      povezan = false;
      prekinjeno = true;
      notifyListeners();
    }
    _poslusam?.cancel();
    _kanal = null;
    _ponovnaPovezava?.cancel();
    if (vloga == VlogaSpila.sledilec) _ponovnaPovezava = Timer(const Duration(seconds: 2), _povezi);
  }

  void _ustaviSledenje() {
    Runda.aplikacija.vodji = null;
    _ponovnaPovezava?.cancel();
    _poslusam?.cancel();
    _kanal?.sink.close();
    _kanal = null;
    povezan = false;
    prekinjeno = false;
  }

  Future<void> ustavi() async {
    await _iskanje?.cancel();
    _iskanje = null;
    najdeniVodje.clear();
    // Kopija vodjevega seznamčka ne velja več.
    if (vloga == VlogaSpila.sledilec) naslednje = const [];
    _ustaviSledenje();
    _naslovVodje = null;
    Runda.aplikacija.removeListener(_objaviRundo);
    await _streznik?.ustavi();
    _streznik = null;
    vloga = VlogaSpila.nic;
    naslov = null;
    sledilcev = 0;
    notifyListeners();
  }
}

/// Iz vnosa, kot je "192.168.1.5", "192.168.1.5:8765" ali "http://192.168.1.5:8765", naredi naslov WebSocketa.
Uri? naslovWebSocket(String vnos) {
  var s = vnos.trim();
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp(r'^(https?|wss?)://'), '');
  s = s.split('/').first;
  if (!s.contains(':')) s = '$s:${Config.vrataVodje}';
  return Uri.tryParse('ws://$s/ws');
}
