import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'api.dart';

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

/// Shramba risb: lokalne datoteke `risbe/<pesem>.json`, kopija na Drivu prek skripte.
/// Spremembe, ki še niso na strežniku, so zapisane v `risbe/_neposlano.json`.
class Risbe {
  Risbe(this._koren);

  final Future<Directory> Function() _koren;
  Api? api;
  Set<String>? _neposlano;
  Timer? _odlozenoPosiljanje;

  Future<Directory> _mapa() async => Directory('${(await _koren()).path}/risbe');
  Future<File> _datoteka(String pesem) async => File('${(await _mapa()).path}/$pesem.json');
  Future<File> _datotekaNeposlanih() async => File('${(await _mapa()).path}/_neposlano.json');

  Future<Set<String>> _neposlane() async {
    if (_neposlano != null) return _neposlano!;
    final f = await _datotekaNeposlanih();
    _neposlano = await f.exists() ? (jsonDecode(await f.readAsString()) as List).cast<String>().toSet() : <String>{};
    return _neposlano!;
  }

  Future<void> _zapisiNeposlane() async {
    final f = await _datotekaNeposlanih();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode((await _neposlane()).toList()));
  }

  Future<Risba> nalozi(String pesem) async {
    final f = await _datoteka(pesem);
    if (!await f.exists()) return Risba();
    try {
      return Risba.izBesedila(await f.readAsString());
    } on FormatException {
      return Risba();
    }
  }

  /// Shrani lokalno takoj, na strežnik pa nekaj sekund kasneje (več potez v enem pošiljanju).
  Future<void> shrani(String pesem, Risba risba) async {
    risba.spremenjeno = DateTime.now().toUtc();
    final f = await _datoteka(pesem);
    await f.parent.create(recursive: true);
    if (risba.prazna) {
      if (await f.exists()) await f.delete();
    } else {
      await f.writeAsString(risba.vBesedilo());
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
      final f = await _datoteka(pesem);
      final vsebina = await f.exists() ? await f.readAsString() : '';
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
        final f = await _datoteka(e.key);
        await f.parent.create(recursive: true);
        await f.writeAsString(vsebina);
      }
    }
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
