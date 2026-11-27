import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../baza.dart';
import '../config.dart';
import '../nastavitve.dart';
import '../odigrane.dart';
import '../runda.dart';
import '../snemanje.dart';
import '../zvok_spila.dart';
import 'preizkus.dart';
import 'streznik.dart';

/// Kar vodja trenutno kaže: pesem in (če igra po setlisti) mesto v setlisti.
@immutable
class StanjeSpila {
  const StanjeSpila({required this.pesem, this.setlista, this.indeks, this.odprl = ''});

  factory StanjeSpila.izJson(Map<String, dynamic> j) => StanjeSpila(
    pesem: j['pesem'] as String,
    setlista: j['setlista'] as String?,
    indeks: (j['indeks'] as num?)?.toInt(),
    odprl: j['odprl']?.toString() ?? '',
  );

  final String pesem;
  final String? setlista;
  final int? indeks;

  /// Kdo je pesem odprl za vse (sledilec s pravico obračanja); prazno = vodja. Ne šteje pri primerjavi.
  final String odprl;

  StanjeSpila zOdprl(String kdo) => StanjeSpila(pesem: pesem, setlista: setlista, indeks: indeks, odprl: kdo);

  Map<String, dynamic> vJson() => {
    'vrsta': 'stanje',
    'pesem': pesem,
    if (setlista != null) 'setlista': setlista,
    if (indeks != null) 'indeks': indeks,
    if (odprl.isNotEmpty) 'odprl': odprl,
  };

  @override
  bool operator ==(Object other) =>
      other is StanjeSpila && other.pesem == pesem && other.setlista == setlista && other.indeks == indeks;

  @override
  int get hashCode => Object.hash(pesem, setlista, indeks);
}

/// Skupno pomikanje: kje v pesmi je naprava, ki pomika vsem. Pri besedilu je [polozaj] vrstica na vrhu
/// zaslona (indeks in delež vrstice), pri PDF-ju delež višine dokumenta; tako velja na vsakem zaslonu.
typedef PomikPesmi = ({String pesem, bool pdf, double polozaj});

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

  /// Lokalna kopija baze (klicaji gredo sproti med vodjo in sledilci).
  Baza? baza;
  Baza? _bazaVodje;
  String? _zadnjiKlicaji;
  StanjeSpila? stanje;

  /// Seznamček naslednjih pesmi; hrani ga vodja, sledilci dobijo kopijo (brez špila je samo na tej napravi).
  List<Naslednja> naslednje = const [];

  /// Vodja: pesem, ki jo je sledilec s pravico zamenjal vsem; aplikacija jo odpre tudi na vodji.
  final zahtevanaPesem = ValueNotifier<StanjeSpila?>(null);
  String? napaka;

  /// Vodja: naslov, ki ga odprejo iPadi (npr. http://192.168.1.5:8765).
  String? naslov;
  int sledilcev = 0;

  /// Vodja: povezane naprave (član, vrsta naprave).
  List<String> povezani = const [];

  /// Vodja: naprave, ki so bile na tem špilu povezane in so izpadle (rdeča pika).
  final Set<String> odpadli = {};
  Set<String> _prejPovezani = {};

  /// Ta naprava pomika besedilo vsem na špilu (stikalo v meniju Špil, samo na tej napravi).
  bool pomikamVsem = false;

  /// Zadnji pomik naprave, ki pomika vsem (zaslon pesmi mu sledi, če je odprta ista pesem).
  final pomik = ValueNotifier<PomikPesmi?>(null);

  /// Pomika lahko vodja ali povezan sledilec, ki sme obračati pesmi za vse.
  bool get lahkoPomikaVsem =>
      vloga == VlogaSpila.vodja || (vloga == VlogaSpila.sledilec && povezan && (baza?.obracaZaVse ?? false));

  void nastaviPomikamVsem(bool da) {
    pomikamVsem = da;
    notifyListeners();
  }

  /// Zaslon pesmi sporoči, kje je; gre vsem, če ta naprava pomika vsem.
  void posljiPomik(PomikPesmi p) {
    if (!pomikamVsem || !lahkoPomikaVsem) return;
    final j = {'pesem': p.pesem, 'pdf': p.pdf, 'polozaj': p.polozaj};
    if (vloga == VlogaSpila.sledilec) {
      _posljiVodji({'vrsta': 'ukaz', 'ukaz': 'pomik', ...j});
    } else {
      _streznik?.poslji(jsonEncode({'vrsta': 'pomik', ...j}));
    }
  }

  static PomikPesmi? _pomikIz(Map<String, dynamic> j) {
    final pesem = j['pesem']?.toString() ?? '';
    final polozaj = (j['polozaj'] as num?)?.toDouble();
    if (pesem.isEmpty || polozaj == null) return null;
    return (pesem: pesem, pdf: j['pdf'] == true, polozaj: polozaj);
  }

  /// Sledilec: ali je povezava z vodjo trenutno vzpostavljena.
  bool povezan = false;

  /// Sledilec: povezava je bila vzpostavljena in je padla (opozorilo, dokler se ne obnovi).
  bool prekinjeno = false;

  StreznikVodje? _streznik;
  WebSocketChannel? _kanal;
  StreamSubscription<dynamic>? _poslusam;
  Timer? _ponovnaPovezava;
  Uri? _naslovVodje;

  /// Sledilec: kdaj je od vodje nazadnje prišlo karkoli (utrip vsaki 2 s ali drugo sporočilo).
  DateTime _zadnjiSignal = DateTime.now();

  /// Vodja pošilja utrip (starejša različica ga ne): šele potem tišina pomeni padlo povezavo.
  bool _vodjaUtripa = false;
  Timer? _nadzorUtripa;

  /// Brez signala toliko časa sledilec povezavo zapre in se takoj poveže znova.
  static const tisinaUtripa = Duration(seconds: 6);
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
        // Nov sledilec (npr. osvežen iPad) dobi trenutni čas runde, ne tistega ob zadnji spremembi.
        if (n > sledilcev && _streznik != null) {
          _objaviRundo();
          _objaviSnemanje();
          _objaviOdigrane();
          ZvokSpila.aplikacija.objavi();
        }
        sledilcev = n;
        povezani = List.unmodifiable(s.povezani);
        // Naprave, ki so bile že povezane, ostanejo na seznamu (rdeče), dokler se ne vrnejo.
        for (final k in odpadli.toList()) {
          if (povezani.contains(k)) odpadli.remove(k);
        }
        for (final k in _prejPovezani) {
          if (!povezani.contains(k) && k != 'Neznana naprava') odpadli.add(k);
        }
        _prejPovezani = {...povezani};
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
      // Snemanje špila: vsi vidijo, da in na kateri napravi se snema.
      SnemanjeSpila.aplikacija
        ..addListener(_objaviSnemanje)
        ..snemalcu = (u) => _streznik?.poslji(jsonEncode({'vrsta': 'snemanjeUkaz', ...u}));
      _objaviSnemanje();
      // Odigrane pesmi so skupne vsem na špilu.
      Odigrane.aplikacija.addListener(_objaviOdigrane);
      _objaviOdigrane();
      // Uho in playback: skupna vsem na špilu.
      ZvokSpila.aplikacija.vsem = (m) => _streznik?.poslji(jsonEncode(m));
      ZvokSpila.aplikacija.objavi();
      // Klicaji: vsak nov ali izbrisan gre takoj vsem.
      _bazaVodje = baza;
      _zadnjiKlicaji = null;
      baza.addListener(_objaviKlicaje);
      _objaviKlicaje();
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

  /// Ali je kam nazaj (vsaj ena prej pokazana pesem).
  bool get imaNazaj => _zgodovina.length >= 2;

  /// Prejšnja pokazana pesem. Čakalne vrste ne spremeni (vrsta je skupna vsem in jo spreminja
  /// samo dodajanje, odstranjevanje in čiščenje).
  String? nazaj() {
    if (_zgodovina.length < 2) return null;
    _zgodovina.removeLast();
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
    if (Config.samoKlicaji && !(baza?.obracanje.neprijavljeni ?? false)) return;
    if (vloga == VlogaSpila.sledilec) {
      final ime = baza?.imeClana ?? '';
      final kdo = ime.isNotEmpty ? ime : (Config.samoKlicaji ? 'iPad' : 'sledilec');
      _posljiVodji({'vrsta': 'ukaz', 'ukaz': 'prikazi', 'stanje': s.zOdprl(kdo).vJson()});
    } else {
      zahtevanaPesem.value = s;
    }
  }

  /// Kdo je zadnji odprl pesem za vse (za kratek napis »Odprl: …«); samo, če to ni bila ta naprava.
  final odprl = ValueNotifier<({String kdo, String pesem})?>(null);

  void _javiOdprl(StanjeSpila s) {
    if (s.odprl.isEmpty || s.odprl == (baza?.imeClana ?? '')) return;
    odprl.value = (kdo: s.odprl, pesem: s.pesem);
  }

  /// Prva pesem s seznamčka, ki je na vrsti; z [naKonec] false brez tistih za konec setliste.
  Naslednja? prvaNaslednja({bool naKonec = true}) => naslednje.where((n) => naKonec || !n.naKonec).firstOrNull;

  void _spremeni(Map<String, dynamic> ukaz) {
    // Neprijavljen sledilec sme pesem le predlagati (na konec čakalne vrste).
    if (Config.samoKlicaji) {
      if (ukaz['ukaz'] != 'dodaj') return;
      ukaz = {...ukaz}..remove('naPrvo');
    }
    if (vloga == VlogaSpila.sledilec) {
      _posljiVodji({'vrsta': 'ukaz', ...ukaz});
    } else {
      _izvedi(ukaz);
    }
  }

  /// Sledilec vodji pove, kdo je (za seznam povezanih naprav pri vodji).
  Future<void> _predstaviSe() async {
    final (ime, naprava) = await _kdoSem();
    _posljiVodji({'vrsta': 'kdo', 'ime': ime, 'naprava': naprava});
  }

  /// Ime člana (na iPadu izbrani član) in vrsta naprave.
  Future<(String, String)> _kdoSem() async {
    var ime = baza?.imeClana ?? '';
    if (ime.isEmpty) {
      try {
        final id = (await SharedPreferences.getInstance()).getString('jaz_clan');
        if (id != null) ime = baza?.imeClanaZ(id) ?? '';
      } catch (_) {}
    }
    final naprava = kIsWeb
        ? 'brskalnik'
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => 'Android',
            TargetPlatform.iOS => 'iOS',
            TargetPlatform.windows => 'Windows',
            TargetPlatform.macOS => 'Mac',
            _ => defaultTargetPlatform.name,
          };
    return (ime, naprava);
  }

  /// Vodja: poročila naprav ob preizkusu pred špilom (po imenu naprave).
  final porocila = <String, PorociloNaprave>{};

  /// Vodja: vse povezane naprave naj pošljejo poročilo (tudi tiste, ki se povežejo kasneje).
  void zahtevajPorocila() {
    porocila.clear();
    _streznik?.poslji(jsonEncode({'vrsta': 'preizkus', 'cas': DateTime.now().toIso8601String()}));
    notifyListeners();
  }

  Future<void> _posljiPorocilo() async {
    final b = baza;
    if (b == null) return;
    final (ime, naprava) = await _kdoSem();
    final kdo = [if (ime.isNotEmpty) ime, naprava].join(', ');
    final r = await porociloTeNaprave(b, kdo: kdo);
    _posljiVodji({'vrsta': 'ukaz', 'ukaz': 'porocilo', 'porocilo': r.vJson()});
  }

  void _posljiVodji(Map<String, dynamic> sporocilo) {
    try {
      _kanal?.sink.add(jsonEncode(sporocilo));
    } catch (_) {}
  }

  /// Vodja: sporočilo sledilca.
  void _odSledilca(Map<String, dynamic> j) {
    if (j['vrsta'] != 'ukaz') return;
    if (j['ukaz'] == 'pomik') {
      final p = _pomikIz(j);
      if (p == null) return;
      _streznik?.poslji(jsonEncode({'vrsta': 'pomik', 'pesem': p.pesem, 'pdf': p.pdf, 'polozaj': p.polozaj}));
      if (!pomikamVsem) pomik.value = p;
      return;
    }
    if (j['ukaz'] == 'porocilo' && j['porocilo'] is Map) {
      final r = PorociloNaprave.izJson((j['porocilo'] as Map).cast<String, dynamic>());
      porocila[r.kdo] = r;
      notifyListeners();
      return;
    }
    if (j['ukaz'] == 'prikazi' && j['stanje'] is Map) {
      final s = StanjeSpila.izJson((j['stanje'] as Map).cast<String, dynamic>());
      zahtevanaPesem.value = s;
      _javiOdprl(s);
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
      case 'odigrane':
        Odigrane.aplikacija.izvedi(u);
      // Snemanje vodi samo administrator (iPad prek vodje ukaza ne more poslati, glej streznik_io).
      case 'snemanje' when u['admin'] == true:
        SnemanjeSpila.aplikacija.izvedi(u);
      // Snema sledilec: njegovo stanje gre prek vodje vsem.
      case 'snemanjeStanje':
        SnemanjeSpila.aplikacija.prevzemi(u);
      case 'klicaj' when u['klicaj'] is Map && _bazaVodje != null:
        final k = (u['klicaj'] as Map).cast<String, dynamic>();
        final b = _bazaVodje!;
        if (u['izbrisi'] == true) {
          b.izbrisiKlicaj(b.risbeClanov.api, k['ID']?.toString() ?? '');
        } else {
          b.shraniKlicaj(b.risbeClanov.api, k);
        }
      case 'zvok':
        ZvokSpila.aplikacija.odSledilca(u);
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

  void _objaviSnemanje() => _streznik?.poslji(jsonEncode(SnemanjeSpila.aplikacija.vJson()));

  void _objaviOdigrane() => _streznik?.poslji(jsonEncode(Odigrane.aplikacija.vJson()));

  /// Sledilec, ki snema: stanje pošlje vodji, ta ga pošlje vsem.
  void _snemamKotSledilec() {
    final s = SnemanjeSpila.aplikacija;
    if (!s.snemaTu && !_poslalSnemanje) return;
    _poslalSnemanje = s.snemaTu;
    _posljiVodji({...s.vJson(), 'vrsta': 'ukaz', 'ukaz': 'snemanjeStanje'});
  }

  bool _poslalSnemanje = false;

  void _objaviKlicaje() {
    final b = _bazaVodje;
    if (b == null || _streznik == null) return;
    final s = jsonEncode({'vrsta': 'klicaji', 'klicaji': b.vrsticeKlicajev});
    if (s == _zadnjiKlicaji) return;
    _zadnjiKlicaji = s;
    _streznik?.poslji(s);
  }

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
    _poslusajVodje();
  }

  /// Posluša vodje, ki se oglašajo na omrežju (sledilec se poveže; rezervni vodja preda vodenje nazaj).
  void _poslusajVodje() {
    _iskanje ??= _isciVodjo().listen(
      (v) {
        final ws = naslovWebSocket(v.naslov);
        if (ws == null) return;
        if (najdeniVodje[ws] != v.ime) {
          najdeniVodje[ws] = v.ime;
          notifyListeners();
        }
        if (ws == _naslovVodje) _zadnjiOglasVodje = DateTime.now();
        // Rezervni vodja: prvi vodja je spet tu in nihče ne sledi rezervi, zato mu ta naprava spet sledi.
        if (vloga == VlogaSpila.vodja && ws == prevzetoOd && sledilcev == 0) {
          _predajNazaj(ws);
          return;
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

  /// Rezervni vodja: koliko časa brez vodje, preden ta naprava prevzame vodenje.
  static Duration cakanjeRezerve = const Duration(seconds: 10);
  Timer? _rezerva;
  bool _bilPovezan = false;
  DateTime? _zadnjiOglasVodje;

  /// Naslov vodje, od katerega je ta naprava (rezerva) prevzela vodenje.
  Uri? prevzetoOd;

  /// Kratka obvestila za napis na zaslonu (npr. prevzem vodenja).
  final obvestilo = ValueNotifier<String?>(null);

  bool get _jeRezerva =>
      Nastavitve.aplikacija.rezervniVodja && (baza?.smeVoditi ?? false) && !Config.prekoVodje && lahkoVodi;

  Future<void> _prevzemi() async {
    _rezerva = null;
    final b = baza;
    if (b == null || povezan || vloga != VlogaSpila.sledilec || !_jeRezerva) return;
    // Vodja se še oglaša na omrežju: padla je le ta povezava, zato vodenja ne prevzame.
    if (_zadnjiOglasVodje case final t? when DateTime.now().difference(t) < const Duration(seconds: 6)) {
      _rezerva = Timer(cakanjeRezerve, () => _prevzemi().ignore());
      return;
    }
    final stari = _naslovVodje;
    final vrsta = naslednje;
    await zacniVoditi(b);
    if (vloga != VlogaSpila.vodja) return;
    prevzetoOd = stari;
    if (vrsta.isNotEmpty) _nastaviNaslednje(vrsta);
    _poslusajVodje();
    obvestilo.value = 'Vodja je izpadel: to napravo sem naredil za vodjo (rezervni vodja).';
    notifyListeners();
  }

  Future<void> _predajNazaj(Uri ws) async {
    prevzetoOd = null;
    final vrsta = naslednje;
    await ustavi();
    samodejnoSledi(zadnji: ws);
    if (naslednje.isEmpty && vrsta.isNotEmpty) naslednje = vrsta;
    obvestilo.value = 'Prvi vodja je spet tu: ta naprava mu spet sledi.';
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
        _bilPovezan = true;
        _rezerva?.cancel();
        _rezerva = null;
        _zadnjiSignal = DateTime.now();
        _vodjaUtripa = false;
        _nadzorUtripa?.cancel();
        _nadzorUtripa = Timer.periodic(const Duration(seconds: 2), (_) {
          if (_kanal != kanal || !_vodjaUtripa) return;
          if (DateTime.now().difference(_zadnjiSignal) > tisinaUtripa) {
            kanal.sink.close().ignore();
            _prekinjeno(kanal);
          }
        });
        povezan = true;
        prekinjeno = false;
        napaka = null;
        // Gumba runde in pavze gresta vodji, ta pa časovnik pošlje vsem.
        Runda.aplikacija.vodji = (u) => _posljiVodji({'vrsta': 'ukaz', 'ukaz': 'runda', ...u});
        // Odigrane: najprej svoje oznake vodji, nato vsaka nova; seznam pride od vodje.
        Odigrane.aplikacija.vodji = (u) => _posljiVodji({'vrsta': 'ukaz', 'ukaz': 'odigrane', ...u});
        _posljiVodji({'vrsta': 'ukaz', 'ukaz': 'odigrane', ...Odigrane.aplikacija.zaZdruzitev()});
        SnemanjeSpila.aplikacija.vodji = (u) =>
            _posljiVodji({'vrsta': 'ukaz', 'ukaz': 'snemanje', 'admin': baza?.jeAdministrator ?? false, ...u});
        ZvokSpila.aplikacija.vodji = (u) => _posljiVodji({'vrsta': 'ukaz', 'ukaz': 'zvok', ...u});
        _predstaviSe();
        // Klicaj iz aplikacije gre tudi vodji (iPad ga vodji pošlje sam prek /api).
        if (!Config.prekoVodje) {
          baza?.obKlicaju = (v, izbrisi) =>
              _posljiVodji({'vrsta': 'ukaz', 'ukaz': 'klicaj', 'klicaj': v, if (izbrisi) 'izbrisi': true});
        }
        notifyListeners();
      }, onError: (Object _) => _prekinjeno(kanal));
      _poslusam = kanal.stream.listen(
        (m) {
          _zadnjiSignal = DateTime.now();
          final j = jsonDecode(m as String) as Map<String, dynamic>;
          if (j['vrsta'] == 'utrip') {
            _vodjaUtripa = true;
          } else if (j['vrsta'] == 'preizkus') {
            _posljiPorocilo().ignore();
          } else if (j['vrsta'] == 'stanje') {
            final s = StanjeSpila.izJson(j);
            // Pesmi, ki jih odprejo drugi sledilci, ta naprava po želji preskoči (sledi samo vodji).
            if (s.odprl.isNotEmpty && s.odprl != (baza?.imeClana ?? '') && !Nastavitve.aplikacija.sprejemamObracanje) {
              return;
            }
            if (s != stanje) _javiOdprl(s);
            stanje = s;
            notifyListeners();
          } else if (j['vrsta'] == 'pomik') {
            if (!pomikamVsem) pomik.value = _pomikIz(j);
          } else if (j['vrsta'] == 'runda') {
            Runda.aplikacija.prevzemi(j);
          } else if (j['vrsta'] == 'odigrane') {
            Odigrane.aplikacija.prevzemi(j);
          } else if (j['vrsta'] == 'snemanje') {
            SnemanjeSpila.aplikacija.prevzemi(j);
          } else if (j['vrsta'] == 'snemanjeUkaz') {
            SnemanjeSpila.aplikacija.izvediTu(j);
          } else if (j['vrsta'] == 'zvok' || j['vrsta'] == 'zvokUkaz') {
            ZvokSpila.aplikacija.odVodje(j);
          } else if (j['vrsta'] == 'klicaji' && j['klicaji'] is List) {
            baza?.prevzemiKlicaje(
              (j['klicaji'] as List).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList(),
            );
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
    Odigrane.aplikacija.vodji = null;
    SnemanjeSpila.aplikacija
      ..vodji = null
      ..removeListener(_snemamKotSledilec)
      ..pozabiVodjo();
    baza?.obKlicaju = null;
    ZvokSpila.aplikacija.pozabi();
    if (povezan) {
      povezan = false;
      prekinjeno = true;
      notifyListeners();
    }
    _nadzorUtripa?.cancel();
    _poslusam?.cancel();
    _kanal = null;
    _ponovnaPovezava?.cancel();
    if (vloga == VlogaSpila.sledilec) _ponovnaPovezava = Timer(const Duration(seconds: 1), _povezi);
    if (vloga == VlogaSpila.sledilec && _bilPovezan && _jeRezerva) {
      _rezerva ??= Timer(cakanjeRezerve, () => _prevzemi().ignore());
    }
  }

  void _ustaviSledenje() {
    Runda.aplikacija.vodji = null;
    Odigrane.aplikacija.vodji = null;
    SnemanjeSpila.aplikacija
      ..vodji = null
      ..removeListener(_snemamKotSledilec)
      ..pozabiVodjo();
    baza?.obKlicaju = null;
    ZvokSpila.aplikacija.pozabi();
    _ponovnaPovezava?.cancel();
    _nadzorUtripa?.cancel();
    _rezerva?.cancel();
    _rezerva = null;
    _bilPovezan = false;
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
    Odigrane.aplikacija.removeListener(_objaviOdigrane);
    SnemanjeSpila.aplikacija
      ..removeListener(_objaviSnemanje)
      ..snemalcu = null;
    _bazaVodje?.removeListener(_objaviKlicaje);
    _bazaVodje = null;
    ZvokSpila.aplikacija.pozabi();
    await _streznik?.ustavi();
    _streznik = null;
    vloga = VlogaSpila.nic;
    naslov = null;
    sledilcev = 0;
    povezani = const [];
    odpadli.clear();
    _prejPovezani = {};
    porocila.clear();
    pomikamVsem = false;
    pomik.value = null;
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
