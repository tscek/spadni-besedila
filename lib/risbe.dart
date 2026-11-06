import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'efekti.dart';
import 'shramba/shramba.dart';

/// Osebne risbe in opombe člana nad PDF-ji. Koordinate so relativne na stran (0..1),
/// zato ostanejo na istem mestu ne glede na velikost zaslona ali povečavo.
enum Orodje { pisalo, marker }

class Poteza {
  Poteza({required this.orodje, required this.barva, required this.debelina, required this.tocke});

  factory Poteza.izJson(Map<String, dynamic> j) {
    final t = (j['t'] as List).cast<num>();
    return Poteza(
      orodje: Orodje.values.byName(j['o'] as String),
      barva: j['b'] as int,
      debelina: (j['d'] as num).toDouble(),
      tocke: [for (var i = 0; i + 1 < t.length; i += 2) Offset(t[i].toDouble(), t[i + 1].toDouble())],
    );
  }

  final Orodje orodje;
  final int barva;

  /// Debelina kot delež širine strani.
  final double debelina;
  final List<Offset> tocke;

  Map<String, dynamic> vJson() => {
    'o': orodje.name,
    'b': barva,
    'd': debelina,
    // Štiri decimalke zadostujejo (desetinka milimetra na A4) in ohranijo datoteko majhno.
    't': [
      for (final p in tocke) ...[_zaokrozi(p.dx), _zaokrozi(p.dy)],
    ],
  };

  /// Ali poteza poteka bližje kot [polmer] od točke [p] (vse v relativnih koordinatah).
  bool blizu(Offset p, double polmer) {
    for (var i = 0; i < tocke.length; i++) {
      if ((tocke[i] - p).distance <= polmer + debelina / 2) return true;
      if (i > 0 && _razdaljaDoDaljice(p, tocke[i - 1], tocke[i]) <= polmer + debelina / 2) return true;
    }
    return false;
  }
}

class Opomba {
  Opomba({required this.polozaj, required this.besedilo, required this.barva, this.predloga = '', this.velikost = 1});

  factory Opomba.izJson(Map<String, dynamic> j) => Opomba(
    polozaj: Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()),
    besedilo: j['s'] as String? ?? '',
    barva: j['b'] as int? ?? 0xFF000000,
    predloga: j['p'] as String? ?? '',
    velikost: (j['v'] as num?)?.toDouble() ?? 1,
  );

  Offset polozaj;
  String besedilo;
  int barva;

  /// ID shranjene opombe ([Predloge]); taka opomba je pri vseh besedilih enaka.
  String predloga;

  /// Povečava (1 = običajna velikost).
  double velikost;

  /// Kar se nariše: pri shranjeni opombi besedilo in barva iz shranjene.
  Opomba get prikaz => switch (Predloge.aplikacija.opomba(predloga)) {
    final p? => Opomba(polozaj: polozaj, besedilo: p.besedilo, barva: p.barva, predloga: predloga, velikost: velikost),
    null => this,
  };

  Map<String, dynamic> vJson() => {
    'x': _zaokrozi(polozaj.dx),
    'y': _zaokrozi(polozaj.dy),
    's': besedilo,
    'b': barva,
    if (predloga.isNotEmpty) 'p': predloga,
    if (velikost != 1) 'v': _zaokrozi(velikost),
  };
}

/// Označen del besedila (pravokotnik čez vrstico, kot z markerjem), v relativnih koordinatah.
/// Na besedilu pesmi je oznaka vezana na vrstico ([vrstica], [besedilo]) in del njene širine ([od]–[doo]),
/// zato ostane na pravem mestu ob povečavi, prelomu in dodanih vrsticah; [obmocje] je le mesto ob nastanku.
class Oznaka {
  Oznaka({required this.obmocje, required this.barva, this.vrstica, this.besedilo = '', this.od = 0, this.doo = 1});

  factory Oznaka.izJson(Map<String, dynamic> j) => Oznaka(
    obmocje: Rect.fromLTRB(
      (j['l'] as num).toDouble(),
      (j['t'] as num).toDouble(),
      (j['r'] as num).toDouble(),
      (j['b'] as num).toDouble(),
    ),
    barva: j['c'] as int,
    vrstica: (j['v'] as num?)?.toInt(),
    besedilo: j['s'] as String? ?? '',
    od: (j['od'] as num?)?.toDouble() ?? 0,
    doo: (j['do'] as num?)?.toDouble() ?? 1,
  );

  final Rect obmocje;
  final int barva;

  /// Indeks vrstice besedila (null: oznaka na mestu strani, npr. na PDF-ju).
  final int? vrstica;

  /// Besedilo vrstice ob označevanju (brez akordov), da se vrstica najde tudi, če se premakne.
  final String besedilo;

  /// Začetek in konec oznake kot delež širine vrstice.
  final double od;
  final double doo;

  Map<String, dynamic> vJson() => {
    'l': _zaokrozi(obmocje.left),
    't': _zaokrozi(obmocje.top),
    'r': _zaokrozi(obmocje.right),
    'b': _zaokrozi(obmocje.bottom),
    'c': barva,
    if (vrstica != null) ...{'v': vrstica, 's': besedilo, 'od': _zaokrozi(od), 'do': _zaokrozi(doo)},
  };
}

enum OblikaGumba {
  zaobljen('Zaobljen'),
  krog('Krog'),
  kvadrat('Kvadrat'),
  drsnik('Drsnik ↔'),
  drsnikPokoncen('Drsnik ↕');

  const OblikaGumba(this.ime);
  final String ime;

  /// Drsnik (fader) pošilja CC z vrednostjo po položaju namesto ukazov ob dotiku.
  bool get jeDrsnik => this == drsnik || this == drsnikPokoncen;
}

/// Gumb v opombah, ki ob dotiku pošlje MIDI ukaze ali makre (zapis kot pri pesmi, ločeni s ;).
class GumbNaStrani {
  GumbNaStrani({
    this.polozaj = Offset.zero,
    required this.napis,
    required this.midi,
    required this.barva,
    this.oblika = OblikaGumba.zaobljen,
    this.predloga = '',
    this.velikost = 1,
    this.nozno = 0,
    this.zvok,
  });

  factory GumbNaStrani.izJson(Map<String, dynamic> j) => GumbNaStrani(
    polozaj: Offset(((j['x'] as num?) ?? 0).toDouble(), ((j['y'] as num?) ?? 0).toDouble()),
    napis: j['s'] as String? ?? '',
    midi: j['m'] as String? ?? '',
    barva: j['b'] as int? ?? 0xFF1565C0,
    oblika: OblikaGumba.values.asNameMap()[j['o']] ?? OblikaGumba.zaobljen,
    predloga: j['p'] as String? ?? '',
    velikost: (j['v'] as num?)?.toDouble() ?? 1,
    nozno: ((j['n'] as num?)?.toInt() ?? 0).clamp(0, 8),
    zvok: j['z'] is Map ? GumbFx.izJson((j['z'] as Map).cast<String, dynamic>()) : null,
  );

  Offset polozaj;
  String napis;
  String midi;
  int barva;
  OblikaGumba oblika;

  /// ID shranjenega gumba ([Predloge]); tak gumb je pri vseh besedilih enak.
  String predloga;

  /// Povečava (1 = običajna velikost).
  double velikost;

  /// Gumb nožnega stikala (1–8), ki sproži ta gumb (0 = brez). Ima prednost pred gumbom v spodnji vrstici.
  int nozno;

  /// Zvočni efekt iz knjižnice (predvaja ga naprava z efekti, kot gumb FX); null = samo MIDI.
  GumbFx? zvok;

  GumbNaStrani kopija({Offset? polozaj, String? predloga, double? velikost, int? nozno}) => GumbNaStrani(
    polozaj: polozaj ?? this.polozaj,
    napis: napis,
    midi: midi,
    barva: barva,
    oblika: oblika,
    predloga: predloga ?? this.predloga,
    velikost: velikost ?? this.velikost,
    nozno: nozno ?? this.nozno,
    zvok: zvok,
  );

  /// Kar se nariše in pošlje: pri shranjenem gumbu napis, ukazi, barva in oblika iz shranjenega.
  GumbNaStrani get prikaz => switch (Predloge.aplikacija.gumb(predloga)) {
    final p? => GumbNaStrani(
      polozaj: polozaj,
      napis: p.napis,
      midi: p.midi,
      barva: p.barva,
      oblika: p.oblika,
      predloga: predloga,
      velikost: velikost,
      nozno: nozno,
      zvok: p.zvok,
    ),
    null => this,
  };

  Map<String, dynamic> vJson() => {
    'x': _zaokrozi(polozaj.dx),
    'y': _zaokrozi(polozaj.dy),
    's': napis,
    'm': midi,
    'b': barva,
    'o': oblika.name,
    if (predloga.isNotEmpty) 'p': predloga,
    if (velikost != 1) 'v': _zaokrozi(velikost),
    if (nozno > 0) 'n': nozno,
    if (zvok != null) 'z': zvok!.vJson(),
  };
}

/// Shranjeni gumbi in opombe člana (na tej napravi). Gumb ali opomba, postavljena iz shranjene,
/// kaže nanjo z [GumbNaStrani.predloga], zato sprememba shranjene velja pri vseh besedilih.
class Predloge extends ChangeNotifier {
  static Predloge aplikacija = Predloge();

  static const _kljucGumbov = 'gumbi_predloge';
  static const _kljucOpomb = 'opombe_predloge';

  /// Shranjeni gumbi; ID je v [GumbNaStrani.predloga].
  List<GumbNaStrani> gumbi = [];
  List<Opomba> opombe = [];

  GumbNaStrani? gumb(String id) => id.isEmpty ? null : gumbi.where((g) => g.predloga == id).firstOrNull;
  Opomba? opomba(String id) => id.isEmpty ? null : opombe.where((o) => o.predloga == id).firstOrNull;

  static int _stevec = 0;
  static String novId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_stevec++}';

  Future<void> nalozi() async {
    try {
      final p = await SharedPreferences.getInstance();
      List<Map<String, dynamic>> beri(String k) => [
        for (final j in jsonDecode(p.getString(k) ?? '[]') as List) (j as Map).cast<String, dynamic>(),
      ];
      // Starejši shranjeni gumbi še nimajo ID-ja.
      gumbi = [for (final j in beri(_kljucGumbov)) GumbNaStrani.izJson(j)..predloga = (j['p'] as String?) ?? novId()];
      opombe = [
        for (final j in beri(_kljucOpomb))
          Opomba.izJson({'x': 0, 'y': 0, ...j})..predloga = (j['p'] as String?) ?? novId(),
      ];
    } catch (_) {
      gumbi = [];
      opombe = [];
    }
    notifyListeners();
  }

  Future<void> _shrani() async {
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    Map<String, dynamic> brezMesta(Map<String, dynamic> j) => j
      ..remove('x')
      ..remove('y')
      ..remove('v');
    await p.setString(_kljucGumbov, jsonEncode([for (final g in gumbi) brezMesta(g.vJson())]));
    await p.setString(_kljucOpomb, jsonEncode([for (final o in opombe) brezMesta(o.vJson())]));
  }

  /// Shrani gumb (nov dobi ID); vrne ID.
  Future<String> shraniGumb(GumbNaStrani g) async {
    final id = g.predloga.isEmpty ? novId() : g.predloga;
    final nov = g.kopija(polozaj: Offset.zero, predloga: id, velikost: 1);
    final i = gumbi.indexWhere((x) => x.predloga == id);
    i >= 0 ? gumbi[i] = nov : gumbi.add(nov);
    await _shrani();
    return id;
  }

  Future<String> shraniOpombo(Opomba o) async {
    final id = o.predloga.isEmpty ? novId() : o.predloga;
    final nova = Opomba(polozaj: Offset.zero, besedilo: o.besedilo, barva: o.barva, predloga: id);
    final i = opombe.indexWhere((x) => x.predloga == id);
    i >= 0 ? opombe[i] = nova : opombe.add(nova);
    await _shrani();
    return id;
  }

  /// Odstrani shranjeno; že postavljeni ostanejo z zadnjim napisom (vsak zase).
  Future<void> izbrisiGumb(String id) async {
    gumbi.removeWhere((g) => g.predloga == id);
    await _shrani();
  }

  Future<void> izbrisiOpombo(String id) async {
    opombe.removeWhere((o) => o.predloga == id);
    await _shrani();
  }
}

/// Vse risbe enega člana na eni pesmi, po straneh (od 1 naprej).
class Risba {
  Risba({
    Map<int, List<Poteza>>? poteze,
    Map<int, List<Opomba>>? opombe,
    Map<int, List<Oznaka>>? oznake,
    Map<int, List<GumbNaStrani>>? gumbi,
    DateTime? spremenjeno,
  }) : poteze = poteze ?? {},
       opombe = opombe ?? {},
       oznake = oznake ?? {},
       gumbi = gumbi ?? {},
       spremenjeno = spremenjeno ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  factory Risba.izJson(Map<String, dynamic> j) {
    Map<int, List<T>> strani<T>(Object? v, T Function(Map<String, dynamic>) f) => {
      for (final e in ((v as Map?) ?? {}).entries)
        int.parse(e.key as String): [for (final x in e.value as List) f(x as Map<String, dynamic>)],
    };
    return Risba(
      poteze: strani(j['poteze'], Poteza.izJson),
      opombe: strani(j['opombe'], Opomba.izJson),
      oznake: strani(j['oznake'], Oznaka.izJson),
      gumbi: strani(j['gumbi'], GumbNaStrani.izJson),
      spremenjeno: DateTime.tryParse(j['spremenjeno']?.toString() ?? ''),
    );
  }

  factory Risba.izBesedila(String s) => Risba.izJson(jsonDecode(s) as Map<String, dynamic>);

  final Map<int, List<Poteza>> poteze;
  final Map<int, List<Opomba>> opombe;

  /// Označeno besedilo (markiranje), zaenkrat samo na strani besedila.
  final Map<int, List<Oznaka>> oznake;
  final Map<int, List<GumbNaStrani>> gumbi;
  DateTime spremenjeno;

  bool get prazna =>
      poteze.values.every((l) => l.isEmpty) &&
      opombe.values.every((l) => l.isEmpty) &&
      oznake.values.every((l) => l.isEmpty) &&
      gumbi.values.every((l) => l.isEmpty);

  List<Poteza> potezeStrani(int stran) => poteze.putIfAbsent(stran, () => []);
  List<Opomba> opombeStrani(int stran) => opombe.putIfAbsent(stran, () => []);
  List<Oznaka> oznakeStrani(int stran) => oznake.putIfAbsent(stran, () => []);
  List<GumbNaStrani> gumbiStrani(int stran) => gumbi.putIfAbsent(stran, () => []);

  /// Odstrani vse na straneh, za katere [pogoj] vrne true.
  void izbrisiStrani(bool Function(int stran) pogoj) {
    for (final m in <Map<int, List<Object>>>[poteze, opombe, oznake, gumbi]) {
      m.removeWhere((stran, _) => pogoj(stran));
    }
  }

  Map<String, dynamic> vJson() => {
    'verzija': 1,
    'spremenjeno': spremenjeno.toUtc().toIso8601String(),
    'poteze': {
      for (final e in poteze.entries)
        if (e.value.isNotEmpty) '${e.key}': [for (final p in e.value) p.vJson()],
    },
    'opombe': {
      for (final e in opombe.entries)
        if (e.value.isNotEmpty) '${e.key}': [for (final o in e.value) o.vJson()],
    },
    'oznake': {
      for (final e in oznake.entries)
        if (e.value.isNotEmpty) '${e.key}': [for (final o in e.value) o.vJson()],
    },
    'gumbi': {
      for (final e in gumbi.entries)
        if (e.value.isNotEmpty) '${e.key}': [for (final g in e.value) g.vJson()],
    },
  };

  String vBesedilo() => jsonEncode(vJson());

  Risba kopija() => Risba.izBesedila(vBesedilo());
}

/// Shramba risb: lokalno pod ključi `risbe/<pesem>.json`, kopija na Drivu prek skripte.
/// Spremembe, ki še niso na strežniku, so zapisane v `risbe/_neposlano.json`.
/// S [skupne] so to skupne risbe pesmi (npr. pobarvani refreni), ki jih vidijo vsi člani
/// (lokalno `risbe_skupne/…`, na Drivu mapa `_skupne`).
class Risbe {
  Risbe(this._shramba, {this.skupne = false});

  final Shramba _shramba;
  final bool skupne;
  Api? api;
  Set<String>? _neposlano;
  Timer? _odlozenoPosiljanje;

  String get _mapa => skupne ? 'risbe_skupne' : 'risbe';
  String _kljuc(String pesem) => '$_mapa/$pesem.json';
  String get _kljucNeposlanih => '$_mapa/_neposlano.json';

  Future<Set<String>> _neposlane() async {
    if (_neposlano != null) return _neposlano!;
    final s = await _shramba.beriBesedilo(_kljucNeposlanih);
    _neposlano = s != null ? (jsonDecode(s) as List).cast<String>().toSet() : <String>{};
    return _neposlano!;
  }

  Future<void> _zapisiNeposlane() async =>
      _shramba.pisiBesedilo(_kljucNeposlanih, jsonEncode((await _neposlane()).toList()));

  Future<Risba> nalozi(String pesem) async {
    final s = await _shramba.beriBesedilo(_kljuc(pesem));
    if (s == null) return Risba();
    try {
      return Risba.izBesedila(s);
    } on FormatException {
      return Risba();
    }
  }

  /// Shrani lokalno takoj, na strežnik pa nekaj sekund kasneje (več potez v enem pošiljanju).
  Future<void> shrani(String pesem, Risba risba) async {
    risba.spremenjeno = DateTime.now().toUtc();
    if (risba.prazna) {
      await _shramba.izbrisi(_kljuc(pesem));
    } else {
      await _shramba.pisiBesedilo(_kljuc(pesem), risba.vBesedilo());
    }
    (await _neposlane()).add(pesem);
    await _zapisiNeposlane();
    _odlozenoPosiljanje?.cancel();
    _odlozenoPosiljanje = Timer(const Duration(seconds: 3), () => posljiNeposlane().ignore());
  }

  /// Pošlje vse lokalne spremembe na strežnik. Neuspešne ostanejo za naslednjič.
  Future<void> posljiNeposlane() async {
    final a = api;
    if (a == null) return;
    final neposlano = await _neposlane();
    for (final pesem in neposlano.toList()) {
      final vsebina = await _shramba.beriBesedilo(_kljuc(pesem)) ?? '';
      try {
        await a.risba(pesem, vsebina, skupna: skupne);
        neposlano.remove(pesem);
      } catch (_) {
        break; // brez povezave: poskusimo ob naslednji osvežitvi
      }
    }
    await _zapisiNeposlane();
  }

  /// Vodja: skupne risbe [pesmi] v obliki, kot jo vrne skripta (za iPade na špilu).
  Future<Map<String, dynamic>> izvozi(Iterable<String> pesmi) async => {
    '_skupne': true,
    'risbe': {
      for (final p in pesmi)
        if (await _shramba.beriBesedilo(_kljuc(p)) case final v? when v.isNotEmpty) p: {'vsebina': v},
    },
  };

  /// Najprej pošlje svoje spremembe, nato prenese risbe s strežnika, ki so novejše od lokalnih
  /// (npr. narisane na drugi tablici istega člana).
  Future<void> sinhroniziraj(Api a) async {
    api = a;
    await posljiNeposlane();
    final neposlano = await _neposlane();
    final odgovor = await a.risbe(skupne: skupne);
    // Starejša skripta ne pozna skupnih risb in vrne osebne: teh ne prepišemo med skupne.
    if (skupne && odgovor['_skupne'] != true) return;
    final streznik = skupne ? ((odgovor['risbe'] as Map?) ?? const {}).cast<String, dynamic>() : odgovor;
    for (final e in streznik.entries) {
      if (neposlano.contains(e.key)) continue;
      final vsebina = (e.value as Map)['vsebina']?.toString() ?? '';
      if (vsebina.isEmpty) continue;
      final Risba nova;
      try {
        nova = Risba.izBesedila(vsebina);
      } on FormatException {
        continue;
      }
      final lokalna = await nalozi(e.key);
      if (nova.spremenjeno.isAfter(lokalna.spremenjeno)) {
        await _shramba.pisiBesedilo(_kljuc(e.key), vsebina);
      }
    }
  }
}

/// Vodja: risbe ostalih članov, da jih na špilu brez interneta streže iPadom.
/// Kar član nariše na špilu, vodja shrani in kasneje pošlje na Drive (akcija risbaZa).
/// Vse je v eni datoteki `risbe/_clani.json`: {član: {pesem: {vsebina, spremenjeno, neposlano?}}}.
class RisbeClanov {
  RisbeClanov(this._shramba);

  final Shramba _shramba;
  Api? api;
  Map<String, Map<String, dynamic>>? _vse;
  Timer? _odlozenoPosiljanje;

  static const _kljuc = 'risbe/_clani.json';

  Future<Map<String, Map<String, dynamic>>> _nalozi() async {
    if (_vse != null) return _vse!;
    final s = await _shramba.beriBesedilo(_kljuc);
    Map<String, dynamic> j = {};
    try {
      if (s != null) j = jsonDecode(s) as Map<String, dynamic>;
    } on FormatException {
      // pokvarjena datoteka: začnemo znova, podatki so še na Drivu
    }
    return _vse = {for (final e in j.entries) e.key: (e.value as Map).cast<String, dynamic>()};
  }

  Future<void> _zapisi() async => _shramba.pisiBesedilo(_kljuc, jsonEncode(await _nalozi()));

  /// Risbe enega člana v obliki, kot jo vrne skripta za akcijo risbe.
  Future<Map<String, dynamic>> zaClana(String clan) async => {
    for (final e in ((await _nalozi())[clan] ?? const {}).entries)
      e.key: {'vsebina': (e.value as Map)['vsebina'], 'spremenjeno': (e.value as Map)['spremenjeno']},
  };

  /// Risba, ki jo je član naredil na špilu (iPad prek vodje).
  Future<void> shrani(String clan, String pesem, String vsebina) async {
    final vse = await _nalozi();
    var spremenjeno = DateTime.now().toUtc().toIso8601String();
    try {
      if (vsebina.isNotEmpty) spremenjeno = Risba.izBesedila(vsebina).spremenjeno.toUtc().toIso8601String();
    } on FormatException {
      // pustimo trenutni čas
    }
    vse.putIfAbsent(clan, () => {})[pesem] = {'vsebina': vsebina, 'spremenjeno': spremenjeno, 'neposlano': true};
    await _zapisi();
    _odlozenoPosiljanje?.cancel();
    _odlozenoPosiljanje = Timer(const Duration(seconds: 5), () => posljiNeposlane().ignore());
  }

  /// Pošlje na Drive, kar so člani narisali na špilu. Brez interneta ostane za naslednjič.
  Future<void> posljiNeposlane() async {
    final a = api;
    if (a == null) return;
    final vse = await _nalozi();
    try {
      for (final clan in vse.entries) {
        for (final r in clan.value.entries) {
          final v = r.value as Map;
          if (v['neposlano'] != true) continue;
          await a.risbaZa(clan.key, r.key, v['vsebina']?.toString() ?? '');
          v.remove('neposlano');
        }
      }
    } finally {
      await _zapisi();
    }
  }

  /// Pošlje risbe s špila, nato prenese risbe vseh članov (novejše zamenjajo starejše).
  Future<void> sinhroniziraj(Api a) async {
    api = a;
    await posljiNeposlane();
    final streznik = await a.risbeClanov();
    final vse = await _nalozi();
    for (final clan in streznik.entries) {
      final lokalno = vse.putIfAbsent(clan.key, () => {});
      for (final r in (clan.value as Map).entries) {
        final nova = (r.value as Map).cast<String, dynamic>();
        final stara = lokalno[r.key] as Map?;
        if (stara != null && stara['neposlano'] == true) continue;
        lokalno[r.key as String] = {'vsebina': nova['vsebina'], 'spremenjeno': nova['spremenjeno']};
      }
    }
    await _zapisi();
  }
}

double _zaokrozi(double v) => (v * 10000).roundToDouble() / 10000;

double _razdaljaDoDaljice(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final dolzina2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (dolzina2 == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / dolzina2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}
