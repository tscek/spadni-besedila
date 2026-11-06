import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'midi/xy.dart';
import 'models.dart';
import 'nastavitve.dart';
import 'uvodi.dart';

/// Kaj gumb FX naredi ob pritisku.
enum NacinFx {
  enkratno('Enkratno (klik predvaja do konca)'),
  preklop('Preklop (klik vklopi, klik izklopi)'),
  medPritiskom('Med pritiskom (igra, dokler držiš)');

  const NacinFx(this.opis);
  final String opis;

  static NacinFx iz(String? s) => values.where((v) => v.name == s).firstOrNull ?? enkratno;
}

/// Ponoven pritisk gumba »Enkratno«, medtem ko še igra.
enum PonovnoFx {
  odZacetka('Znova od začetka'),
  ustavi('Ustavi (fade out)'),
  cez('Še enkrat čez (oba hkrati)');

  const PonovnoFx(this.opis);
  final String opis;

  static PonovnoFx iz(String? s) => values.where((v) => v.name == s).firstOrNull ?? odZacetka;
}

/// Gumb na FX panelu: zvočni efekt iz knjižnice in/ali MIDI ukazi, po želji odpre XY pad.
@immutable
class GumbFx {
  const GumbFx({
    required this.id,
    this.ime = '',
    this.barva = 0xFF1E88E5,
    this.nacin = NacinFx.enkratno,
    this.ponovno = PonovnoFx.odZacetka,
    this.zanka = false,
    this.fadeIn = 0,
    this.fadeOut = 300,
    this.efekt = '',
    this.od = 0,
    this.doo,
    this.glasnost = 1,
    this.ukazi = '',
    this.xy = false,
    this.pesem = '',
    this.ustaviObMenjavi = false,
    this.stran = 0,
    this.mesto = 0,
  });

  factory GumbFx.izJson(Map<String, dynamic> j) => GumbFx(
    id: j['id']?.toString() ?? '',
    ime: j['ime']?.toString() ?? '',
    barva: (j['barva'] as num?)?.toInt() ?? 0xFF1E88E5,
    nacin: NacinFx.iz(j['nacin']?.toString()),
    ponovno: PonovnoFx.iz(j['ponovno']?.toString()),
    zanka: j['zanka'] == true,
    fadeIn: (j['fadeIn'] as num?)?.toInt() ?? 0,
    fadeOut: (j['fadeOut'] as num?)?.toInt() ?? 0,
    efekt: j['efekt']?.toString() ?? '',
    od: (j['od'] as num?)?.toDouble() ?? 0,
    doo: (j['do'] as num?)?.toDouble(),
    glasnost: ((j['glasnost'] as num?)?.toDouble() ?? 1).clamp(0, 1),
    ukazi: j['ukazi']?.toString() ?? '',
    xy: j['xy'] == true,
    pesem: j['pesem']?.toString() ?? '',
    ustaviObMenjavi: j['ustaviObMenjavi'] == true,
    stran: (j['stran'] as num?)?.toInt() ?? 0,
    mesto: (j['mesto'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String ime;

  /// Barva kot ARGB.
  final int barva;
  final NacinFx nacin;
  final PonovnoFx ponovno;

  /// Po koncu (ali pri »do«) začne znova od »od«.
  final bool zanka;

  /// Pojemanje na začetku in koncu v milisekundah.
  final int fadeIn;
  final int fadeOut;

  /// ID efekta v knjižnici (prazno = samo MIDI ali XY).
  final String efekt;

  /// Obrezovanje v sekundah (datoteka ostane cela).
  final double od;
  final double? doo;

  /// Glasnost gumba (0–1), pomnožena z glasnostjo vseh efektov.
  final double glasnost;

  /// MIDI ukazi ali makri (ločeni s ;), poslani ob pritisku.
  final String ukazi;

  /// Pritisk odpre XY pad na zgornji polovici zaslona.
  final bool xy;

  /// Samo pri tej pesmi (prazno = pri vseh).
  final String pesem;

  /// Ob zamenjavi pesmi se efekt ustavi (sicer igra naprej).
  final bool ustaviObMenjavi;

  /// Stran in mesto na mreži (0 je levo zgoraj).
  final int stran;
  final int mesto;

  bool get imaZvok => efekt.isNotEmpty;

  Map<String, dynamic> vJson() => {
    'id': id,
    'ime': ime,
    'barva': barva,
    'nacin': nacin.name,
    'ponovno': ponovno.name,
    if (zanka) 'zanka': true,
    'fadeIn': fadeIn,
    'fadeOut': fadeOut,
    if (efekt.isNotEmpty) 'efekt': efekt,
    if (od > 0) 'od': od,
    'do': ?doo,
    if (glasnost < 1) 'glasnost': glasnost,
    if (ukazi.isNotEmpty) 'ukazi': ukazi,
    if (xy) 'xy': true,
    if (pesem.isNotEmpty) 'pesem': pesem,
    if (ustaviObMenjavi) 'ustaviObMenjavi': true,
    'stran': stran,
    'mesto': mesto,
  };
}

/// Skupna postavitev FX panela in XY pada (ureja administrator, vidijo jo vsi).
@immutable
class PostavitevFx {
  const PostavitevFx({this.gumbi = const [], this.strani = 1, this.xy});

  factory PostavitevFx.izBesedila(String s) {
    if (s.trim().isEmpty) return const PostavitevFx();
    try {
      final j = (jsonDecode(s) as Map).cast<String, dynamic>();
      return PostavitevFx(
        gumbi: [
          for (final g in (j['gumbi'] as List?) ?? const [])
            if (g is Map) GumbFx.izJson(g.cast<String, dynamic>()),
        ],
        strani: ((j['strani'] as num?)?.toInt() ?? 1).clamp(1, najvecStrani),
        xy: j['xy'] is Map ? NastavitveXy.izJson((j['xy'] as Map).cast<String, dynamic>()) : null,
      );
    } catch (_) {
      return const PostavitevFx();
    }
  }

  /// Mreža na strani: 4 stolpci in 3 vrstice.
  static const stolpcev = 4;
  static const vrstic = 3;
  static const naStran = stolpcev * vrstic;
  static const najvecStrani = 8;

  final List<GumbFx> gumbi;
  final int strani;

  /// Skupni XY pad (null = še ni nastavljen skupno).
  final NastavitveXy? xy;

  GumbFx? gumb(String id) => gumbi.where((g) => g.id == id).firstOrNull;

  /// Gumb na mestu strani, ki velja za pesem (gumb te pesmi ima prednost pred splošnim).
  GumbFx? na(int stran, int mesto, String? pesem) {
    GumbFx? splosen;
    for (final g in gumbi) {
      if (g.stran != stran || g.mesto != mesto) continue;
      if (g.pesem.isEmpty) {
        splosen ??= g;
      } else if (g.pesem == pesem) {
        return g;
      }
    }
    return splosen;
  }

  /// Gumbi po vrstnem redu (za nožno stikalo FX 1, 2, …): trenutna stran, nato naslednje.
  List<GumbFx> poVrsti(int stran, String? pesem) => [for (var m = 0; m < naStran; m++) ?na(stran, m, pesem)];

  PostavitevFx kopija({List<GumbFx>? gumbi, int? strani, NastavitveXy? xy}) =>
      PostavitevFx(gumbi: gumbi ?? this.gumbi, strani: strani ?? this.strani, xy: xy ?? this.xy);

  /// Shrani gumb (nov ali spremenjen).
  PostavitevFx zGumbom(GumbFx g) => kopija(gumbi: [...gumbi.where((x) => x.id != g.id), g]);
  PostavitevFx brezGumba(String id) => kopija(gumbi: gumbi.where((x) => x.id != id).toList());

  String vBesedilo() => jsonEncode({
    'gumbi': [for (final g in gumbi) g.vJson()],
    'strani': strani,
    if (xy != null) 'xy': xy!.vJson(),
  });
}

/// Zvočni efekt v knjižnici (list Efekti, datoteka na Drivu v mapi Efekti).
@immutable
class Efekt {
  const Efekt({required this.id, required this.ime, this.datoteka = '', this.vrsta = ''});

  factory Efekt.izVrstice(Zapis r) => Efekt(
    id: besedilo(r['ID']),
    ime: besedilo(r['Ime']),
    datoteka: besedilo(r['Datoteka']),
    vrsta: besedilo(r['Vrsta']),
  );

  final String id;
  final String ime;
  final String datoteka;
  final String vrsta;
}

/// Kaj trenutno igra (za utripanje in črto do konca).
typedef StanjeFx = ({Duration pozicija, Duration trajanje, bool zanka});

/// Ena predvajana instanca efekta.
class _Igra {
  _Igra(this.gumb, this.p, {required this.zacasen});

  final GumbFx gumb;
  final PredvajalnikZvoka p;

  /// Dodaten predvajalnik za »še enkrat čez« (po koncu se zapre).
  final bool zacasen;
  Duration trajanje = Duration.zero;
  Duration pozicija = Duration.zero;
  Duration od = Duration.zero;
  Duration doo = Duration.zero;

  /// Trenutni faktor pojemanja (0–1).
  double faktor = 1;
  Timer? pojemanje;
  bool ustavljam = false;
  StreamSubscription<Duration>? poz;
  StreamSubscription<void>? kon;
}

/// Predvajanje efektov na tej napravi (navadno PC). Vsak gumb ima svoj predvajalnik, naložen vnaprej,
/// da se zvok začne takoj; več efektov igra hkrati.
class Efekti extends ChangeNotifier {
  static Efekti aplikacija = Efekti();

  /// Bajti efekta iz knjižnice (nastavi main: lokalno ali s spleta).
  Future<({Uint8List bajti, String vrsta})?> Function(String efekt)? bajti;

  /// Trenutna postavitev (nastavi main iz baze).
  PostavitevFx Function() postavitev = () => const PostavitevFx();

  /// Pošlje MIDI ukaze gumba (nastavi main).
  Future<void> Function(String ukazi)? midi;

  /// Korak pojemanja.
  static const korak = Duration(milliseconds: 25);

  final _predvajalniki = <String, PredvajalnikZvoka>{};
  final _nalozeno = <String, String>{};
  final _trajanja = <String, Duration>{};
  final _igra = <String, List<_Igra>>{};

  /// Glasnost vseh efektov (drsnik ob strani panela).
  double glasnost = 1;

  /// Gumbi, ki trenutno igrajo, s pozicijo (zadnja instanca).
  Map<String, StanjeFx> get stanje => {
    for (final MapEntry(key: id, value: l) in _igra.entries)
      if (l.isNotEmpty) id: (pozicija: l.last.pozicija, trajanje: l.last.doo - l.last.od, zanka: l.last.gumb.zanka),
  };

  bool igra(String id) => _igra[id]?.isNotEmpty ?? false;

  /// Igra in se ne ustavlja (pojemanje ob ustavljanju ne šteje).
  bool _aktiven(String id) => _igra[id]?.any((i) => !i.ustavljam) ?? false;

  PredvajalnikZvoka _predvajalnik(String gumb) => _predvajalniki[gumb] ??= PredvajalnikZvoka.tovarna();

  /// Naloži zvok gumba v njegov predvajalnik (če še ni), vrne trajanje.
  Future<Duration?> _nalozi(GumbFx g, PredvajalnikZvoka p, {bool znova = false}) async {
    if (!znova && _nalozeno[g.id] == g.efekt) return _trajanja[g.id];
    final b = await bajti?.call(g.efekt);
    if (b == null) return null;
    final d = await p.odpri(b.bajti, b.vrsta);
    if (d == null) return null;
    if (!znova) {
      _nalozeno[g.id] = g.efekt;
      _trajanja[g.id] = d;
    }
    return d;
  }

  /// Vnaprej naloži vse efekte postavitve (da se ob pritisku začnejo takoj).
  Future<void> pripravi() async {
    final p = postavitev();
    for (final g in p.gumbi) {
      if (!g.imaZvok || igra(g.id)) continue;
      try {
        await _nalozi(g, _predvajalnik(g.id));
      } catch (e) {
        debugPrint('FX ${g.ime}: $e');
      }
    }
    // Gumbi, ki jih ni več.
    for (final id in _predvajalniki.keys.where((id) => p.gumb(id) == null).toList()) {
      await _ustaviGumb(id, takoj: true);
      _predvajalniki.remove(id)?.zapri();
      _nalozeno.remove(id);
      _trajanja.remove(id);
    }
  }

  /// Pritisk (dol = true) ali spust gumba.
  Future<void> dogodek(String id, {required bool dol}) async {
    final g = postavitev().gumb(id);
    if (g == null) return;
    if (!dol) {
      if (g.nacin == NacinFx.medPritiskom) await _ustaviGumb(id);
      return;
    }
    if (g.ukazi.isNotEmpty) midi?.call(g.ukazi).ignore();
    if (!g.imaZvok) return;
    final igra = _aktiven(id);
    switch (g.nacin) {
      case NacinFx.preklop:
        igra ? await _ustaviGumb(id) : await _zacni(g);
      case NacinFx.medPritiskom:
        if (!igra) await _zacni(g);
      case NacinFx.enkratno:
        if (!igra) {
          await _zacni(g);
        } else {
          switch (g.ponovno) {
            case PonovnoFx.odZacetka:
              await _ustaviGumb(id, takoj: true);
              await _zacni(g);
            case PonovnoFx.ustavi:
              await _ustaviGumb(id);
            case PonovnoFx.cez:
              await _zacni(g, zacasen: true);
          }
        }
    }
  }

  /// Nožno stikalo ali klik brez spusta: pri »med pritiskom« preklopi.
  Future<void> klik(String id) async {
    final g = postavitev().gumb(id);
    if (g == null) return;
    if (g.nacin == NacinFx.medPritiskom && _aktiven(id)) return dogodek(id, dol: false);
    return dogodek(id, dol: true);
  }

  double _jakost(_Igra i) => (i.gumb.glasnost * glasnost * i.faktor).clamp(0.0, 1.0);

  Future<void> _zacni(GumbFx g, {bool zacasen = false}) async {
    // Stalni predvajalnik gumba: prejšnja instanca (npr. še pojema) se konča takoj.
    if (!zacasen) {
      for (final s in [...?_igra[g.id]]) {
        if (!s.zacasen) await _koncaj(s);
      }
    }
    final p = zacasen ? PredvajalnikZvoka.tovarna() : _predvajalnik(g.id);
    final i = _Igra(g, p, zacasen: zacasen);
    final seznam = _igra.putIfAbsent(g.id, () => []);
    seznam.add(i);
    notifyListeners();
    try {
      final d = await _nalozi(g, p, znova: zacasen);
      if (d == null) throw StateError('Efekta ni bilo mogoče naložiti');
      i.trajanje = d;
      i.od = Duration(milliseconds: (g.od * 1000).round()).clamp(Duration.zero, d);
      final doo = g.doo == null ? d : Duration(milliseconds: (g.doo! * 1000).round());
      i.doo = doo > i.od && doo <= d ? doo : d;
      i.pozicija = i.od;
      if (!seznam.contains(i) || i.ustavljam) return;
      await p.nastaviIzhod(Nastavitve.aplikacija.izhodEfektov);
      await p.transponiraj(0);
      i.faktor = g.fadeIn > 0 ? 0 : 1;
      await p.glasnost(_jakost(i));
      i.poz = p.pozicija.listen((pos) => _obPoziciji(i, pos));
      i.kon = p.konec.listen((_) => _obKoncu(i));
      await p.predvajaj(i.od);
      if (g.fadeIn > 0) _pojemaj(i, 1, g.fadeIn);
    } catch (e) {
      debugPrint('FX ${g.ime}: $e');
      await _koncaj(i);
    }
  }

  void _obPoziciji(_Igra i, Duration pos) {
    i.pozicija = pos;
    if (i.ustavljam) return;
    final ostane = i.doo - pos;
    if (ostane <= Duration.zero) {
      _obKoncu(i);
    } else if (!i.gumb.zanka && i.gumb.fadeOut > 0 && ostane.inMilliseconds <= i.gumb.fadeOut && i.doo < i.trajanje) {
      // Obrezan konec: pojemanje pred »do«.
      _ustavi(i, fade: ostane.inMilliseconds);
    }
  }

  Future<void> _obKoncu(_Igra i) async {
    if (i.ustavljam) return _koncaj(i);
    if (i.gumb.zanka) {
      i.pozicija = i.od;
      await i.p.predvajaj(i.od);
      notifyListeners();
      return;
    }
    await _koncaj(i);
  }

  /// Glasnost gladko do [cilj] v [ms] milisekundah, nato [potem].
  void _pojemaj(_Igra i, double cilj, int ms, [Future<void> Function()? potem]) {
    i.pojemanje?.cancel();
    final zacetek = i.faktor;
    final koraki = (ms / korak.inMilliseconds).ceil().clamp(1, 1000);
    var n = 0;
    i.pojemanje = Timer.periodic(korak, (t) {
      n++;
      i.faktor = zacetek + (cilj - zacetek) * (n / koraki);
      i.p.glasnost(_jakost(i));
      if (n >= koraki) {
        t.cancel();
        potem?.call();
      }
    });
  }

  Future<void> _ustavi(_Igra i, {int? fade, bool takoj = false}) async {
    if (i.ustavljam && !takoj) return;
    i.ustavljam = true;
    final ms = fade ?? i.gumb.fadeOut;
    if (takoj || ms <= 0) {
      await _koncaj(i);
    } else {
      _pojemaj(i, 0, ms, () => _koncaj(i));
      notifyListeners();
    }
  }

  Future<void> _koncaj(_Igra i) async {
    i.pojemanje?.cancel();
    await i.poz?.cancel();
    await i.kon?.cancel();
    final seznam = _igra[i.gumb.id];
    final bil = seznam?.remove(i) ?? false;
    if (!bil) return;
    if (seznam != null && seznam.isEmpty) _igra.remove(i.gumb.id);
    await i.p.ustavi();
    if (i.zacasen) i.p.zapri();
    notifyListeners();
  }

  Future<void> _ustaviGumb(String id, {bool takoj = false}) async {
    for (final i in [...?_igra[id]]) {
      await _ustavi(i, takoj: takoj);
    }
  }

  /// »Ustavi vse«: vse, kar igra, s pojemanjem (fade out gumba, vsaj 0,5 s).
  Future<void> ustaviVse() async {
    for (final l in _igra.values.toList()) {
      for (final i in [...l]) {
        _ustavi(i, fade: i.gumb.fadeOut < 500 ? 500 : i.gumb.fadeOut);
      }
    }
  }

  void nastaviGlasnost(double g) {
    glasnost = g.clamp(0.0, 1.0);
    for (final l in _igra.values) {
      for (final i in l) {
        i.p.glasnost(_jakost(i));
      }
    }
    notifyListeners();
  }

  /// Zamenjava pesmi: ustavi efekte z »Ob zamenjavi pesmi ustavi«.
  Future<void> obMenjaviPesmi() async {
    for (final l in _igra.values.toList()) {
      for (final i in [...l]) {
        if (i.gumb.ustaviObMenjavi) _ustavi(i);
      }
    }
  }

  /// Pozabi naložene zvoke (npr. po spremembi knjižnice).
  void pozabiNalozene() {
    _nalozeno.clear();
    _trajanja.clear();
  }
}

extension on Duration {
  Duration clamp(Duration a, Duration b) => this < a ? a : (this > b ? b : this);
}
