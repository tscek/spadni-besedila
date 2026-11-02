import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pesmi, ki so bile ta večer že odigrane (dovolj dolgo odprte).
/// Oznaka velja [trajanje] od odprtja, da je naslednji špil spet čist.
/// Na špilu so skupne: sledilec pošlje oznako vodji, ta pa seznam vsem.
class Odigrane extends ChangeNotifier {
  static Odigrane aplikacija = Odigrane();

  static const _kljuc = 'odigrane';
  static const trajanje = Duration(hours: 12);

  final Map<String, DateTime> _kdaj = {};

  /// Sledilec na špilu: oznake gredo vodji, ta pa seznam pošlje vsem (tudi nazaj sem).
  void Function(Map<String, dynamic> ukaz)? vodji;

  Future<void> nalozi() async {
    final p = await SharedPreferences.getInstance();
    try {
      final j = (jsonDecode(p.getString(_kljuc) ?? '{}') as Map).cast<String, dynamic>();
      _kdaj
        ..clear()
        ..addAll({for (final e in j.entries) e.key: ?DateTime.tryParse(e.value.toString())});
    } catch (_) {
      _kdaj.clear();
    }
    notifyListeners();
  }

  bool je(String pesem, {DateTime? zdaj}) {
    final d = _kdaj[pesem];
    return d != null && (zdaj ?? DateTime.now()).difference(d) < trajanje;
  }

  int get stevilo => _kdaj.keys.where(je).length;

  Future<void> oznaci(String pesem) async {
    vodji?.call({'akcija': 'oznaci', 'pesem': pesem});
    _kdaj[pesem] = DateTime.now();
    _kdaj.removeWhere((k, _) => !je(k));
    await _shrani();
  }

  Future<void> ponastavi() async {
    vodji?.call({'akcija': 'ponastavi'});
    _kdaj.clear();
    await _shrani();
  }

  Map<String, String> get _zapis => {for (final e in _kdaj.entries) e.key: e.value.toUtc().toIso8601String()};

  static Map<String, DateTime> _beri(Object? j) => {
    if (j is Map)
      for (final e in j.entries) e.key.toString(): ?DateTime.tryParse(e.value.toString())?.toLocal(),
  };

  /// Sledilec ob povezavi pošlje vodji svoje oznake, da se združijo.
  Map<String, dynamic> zaZdruzitev() => {'akcija': 'zdruzi', 'odigrane': _zapis};

  /// Vodja: ukaz sledilca.
  Future<void> izvedi(Map<String, dynamic> u) async {
    switch (u['akcija']) {
      case 'oznaci' when u['pesem'] != null:
        _kdaj[u['pesem'].toString()] = DateTime.now();
      case 'ponastavi':
        _kdaj.clear();
      case 'zdruzi':
        for (final e in _beri(u['odigrane']).entries) {
          final d = _kdaj[e.key];
          if (d == null || e.value.isAfter(d)) _kdaj[e.key] = e.value;
        }
      default:
        return;
    }
    _kdaj.removeWhere((k, _) => !je(k));
    await _shrani();
  }

  /// Za sledilce.
  Map<String, dynamic> vJson() => {'vrsta': 'odigrane', 'odigrane': _zapis};

  /// Sledilec: seznam od vodje.
  Future<void> prevzemi(Map<String, dynamic> j) async {
    final novo = _beri(j['odigrane']);
    if (mapEquals(novo, _kdaj)) return;
    _kdaj
      ..clear()
      ..addAll(novo);
    await _shrani();
  }

  Future<void> _shrani() async {
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString(
        _kljuc,
        jsonEncode({for (final e in _kdaj.entries) e.key: e.value.toIso8601String()}),
      );
    } catch (_) {
      // Shramba ni na voljo (npr. v preizkusih); oznake ostanejo v pomnilniku.
    }
  }
}
