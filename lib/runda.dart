import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ena runda ali pavza: kdaj se je začela in koliko je trajala.
class Odsek {
  const Odsek({required this.pavza, required this.zacetek, required this.trajanje});

  factory Odsek.izJson(Map<String, dynamic> j) => Odsek(
    pavza: j['p'] == true,
    zacetek: DateTime.parse(j['z'] as String),
    trajanje: Duration(seconds: (j['t'] as num).toInt()),
  );

  final bool pavza;
  final DateTime zacetek;
  final Duration trajanje;

  Map<String, dynamic> vJson() => {'p': pavza, 'z': zacetek.toIso8601String(), 't': trajanje.inSeconds};
}

/// Časovnik runde in pavze na tej napravi; pretekli odseki se hranijo, dokler jih ne ponastaviš.
class Runda extends ChangeNotifier {
  static Runda aplikacija = Runda();

  static const _kljuc = 'runda';

  /// Sledilec na špilu: spremembe gredo vodji, ta pa časovnik pošlje vsem (tudi nazaj sem).
  void Function(Map<String, dynamic> ukaz)? vodji;

  /// null: časovnik ne teče; true: pavza; false: igramo.
  bool? pavza;
  DateTime? zacetek;
  List<Odsek> zgodovina = [];

  Duration trenutno({DateTime? zdaj}) =>
      zacetek == null ? Duration.zero : (zdaj ?? DateTime.now()).difference(zacetek!);

  Future<void> nalozi() async {
    final p = await SharedPreferences.getInstance();
    try {
      final j = jsonDecode(p.getString(_kljuc) ?? '{}') as Map<String, dynamic>;
      pavza = j['pavza'] as bool?;
      zacetek = DateTime.tryParse(j['zacetek']?.toString() ?? '');
      if (zacetek == null) pavza = null;
      zgodovina = [
        for (final o in (j['zgodovina'] as List?) ?? const [])
          if (o is Map) Odsek.izJson(o.cast<String, dynamic>()),
      ];
    } catch (_) {
      pavza = null;
      zacetek = null;
      zgodovina = [];
    }
    notifyListeners();
  }

  /// Začne pavzo ([pavzo] true) ali igranje; prejšnji odsek gre v zgodovino.
  Future<void> zacni(bool pavzo, {DateTime? zdaj}) async {
    if (vodji case final f?) return f({'akcija': 'zacni', 'pavza': pavzo});
    await _zacni(pavzo, zdaj: zdaj);
  }

  Future<void> _zacni(bool pavzo, {DateTime? zdaj}) async {
    final t = zdaj ?? DateTime.now();
    if (pavza != null && zacetek != null) {
      zgodovina.insert(0, Odsek(pavza: pavza!, zacetek: zacetek!, trajanje: t.difference(zacetek!)));
    }
    pavza = pavzo;
    zacetek = t;
    await _shrani();
  }

  /// Ustavi časovnik (zadnji odsek gre v zgodovino).
  Future<void> ustavi({DateTime? zdaj}) async {
    if (vodji case final f?) return f({'akcija': 'ustavi'});
    await _ustavi(zdaj: zdaj);
  }

  Future<void> _ustavi({DateTime? zdaj}) async {
    final t = zdaj ?? DateTime.now();
    if (pavza != null && zacetek != null) {
      zgodovina.insert(0, Odsek(pavza: pavza!, zacetek: zacetek!, trajanje: t.difference(zacetek!)));
    }
    pavza = null;
    zacetek = null;
    await _shrani();
  }

  Future<void> ponastavi() async {
    vodji?.call({'akcija': 'ponastavi'});
    await _ponastavi();
  }

  Future<void> _ponastavi() async {
    pavza = null;
    zacetek = null;
    zgodovina = [];
    await _shrani();
  }

  /// Vodja: ukaz sledilca (začni, ustavi, ponastavi).
  Future<void> izvedi(Map<String, dynamic> u) => switch (u['akcija']) {
    'zacni' => _zacni(u['pavza'] == true),
    'ustavi' => _ustavi(),
    'ponastavi' => _ponastavi(),
    _ => Future.value(),
  };

  /// Stanje za sledilce: kaj teče in koliko časa že (ure naprav se lahko razlikujejo).
  Map<String, dynamic> vJson() => {'vrsta': 'runda', 'pavza': pavza, 'tece': trenutno().inSeconds};

  /// Sledilec: stanje časovnika od vodje.
  Future<void> prevzemi(Map<String, dynamic> j) async {
    final p = j['pavza'] as bool?;
    if (p == null) {
      if (pavza != null) await _ustavi();
      return;
    }
    final zacetekVodje = DateTime.now().subtract(Duration(seconds: (j['tece'] as num?)?.toInt() ?? 0));
    // Isti odsek (le ura se malo razlikuje): nič novega.
    if (p == pavza && zacetek != null && zacetek!.difference(zacetekVodje).inSeconds.abs() < 5) return;
    if (p == pavza && zacetek != null) {
      zacetek = zacetekVodje;
      return _shrani();
    }
    await _zacni(p, zdaj: zacetekVodje);
  }

  Future<void> _shrani() async {
    notifyListeners();
    (await SharedPreferences.getInstance()).setString(
      _kljuc,
      jsonEncode({
        'pavza': pavza,
        'zacetek': zacetek?.toIso8601String(),
        'zgodovina': [for (final o in zgodovina.take(100)) o.vJson()],
      }),
    );
  }
}

/// 5:07 ali 1:05:07.
String casBesedilo(Duration d) {
  String dv(int x) => x.toString().padLeft(2, '0');
  final s = d.inSeconds;
  return s >= 3600 ? '${s ~/ 3600}:${dv(s ~/ 60 % 60)}:${dv(s % 60)}' : '${s ~/ 60}:${dv(s % 60)}';
}
