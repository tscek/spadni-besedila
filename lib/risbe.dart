import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'api.dart';
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
  Opomba({required this.polozaj, required this.besedilo, required this.barva});

  factory Opomba.izJson(Map<String, dynamic> j) => Opomba(
    polozaj: Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble()),
    besedilo: j['s'] as String,
    barva: j['b'] as int,
  );

  Offset polozaj;
  String besedilo;
  int barva;

  Map<String, dynamic> vJson() => {'x': _zaokrozi(polozaj.dx), 'y': _zaokrozi(polozaj.dy), 's': besedilo, 'b': barva};
}

/// Vse risbe enega člana na eni pesmi, po straneh (od 1 naprej).
class Risba {
  Risba({Map<int, List<Poteza>>? poteze, Map<int, List<Opomba>>? opombe, DateTime? spremenjeno})
    : poteze = poteze ?? {},
      opombe = opombe ?? {},
      spremenjeno = spremenjeno ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  factory Risba.izJson(Map<String, dynamic> j) {
    Map<int, List<T>> strani<T>(Object? v, T Function(Map<String, dynamic>) f) => {
      for (final e in ((v as Map?) ?? {}).entries)
        int.parse(e.key as String): [for (final x in e.value as List) f(x as Map<String, dynamic>)],
    };
    return Risba(
      poteze: strani(j['poteze'], Poteza.izJson),
      opombe: strani(j['opombe'], Opomba.izJson),
      spremenjeno: DateTime.tryParse(j['spremenjeno']?.toString() ?? ''),
    );
  }

  factory Risba.izBesedila(String s) => Risba.izJson(jsonDecode(s) as Map<String, dynamic>);

  final Map<int, List<Poteza>> poteze;
  final Map<int, List<Opomba>> opombe;
  DateTime spremenjeno;

  bool get prazna => poteze.values.every((l) => l.isEmpty) && opombe.values.every((l) => l.isEmpty);

  List<Poteza> potezeStrani(int stran) => poteze.putIfAbsent(stran, () => []);
  List<Opomba> opombeStrani(int stran) => opombe.putIfAbsent(stran, () => []);

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
  };

  String vBesedilo() => jsonEncode(vJson());

  Risba kopija() => Risba.izBesedila(vBesedilo());
}

/// Shramba risb: lokalno pod ključi `risbe/<pesem>.json`, kopija na Drivu prek skripte.
/// Spremembe, ki še niso na strežniku, so zapisane v `risbe/_neposlano.json`.
class Risbe {
  Risbe(this._shramba);

  final Shramba _shramba;
  Api? api;
  Set<String>? _neposlano;
  Timer? _odlozenoPosiljanje;

  static String _kljuc(String pesem) => 'risbe/$pesem.json';
  static const _kljucNeposlanih = 'risbe/_neposlano.json';

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
        await a.risba(pesem, vsebina);
        neposlano.remove(pesem);
      } catch (_) {
        break; // brez povezave: poskusimo ob naslednji osvežitvi
      }
    }
    await _zapisiNeposlane();
  }

  /// Najprej pošlje svoje spremembe, nato prenese risbe s strežnika, ki so novejše od lokalnih
  /// (npr. narisane na drugi tablici istega člana).
  Future<void> sinhroniziraj(Api a) async {
    api = a;
    await posljiNeposlane();
    final neposlano = await _neposlane();
    final streznik = await a.risbe();
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
