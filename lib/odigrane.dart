import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pesmi, ki so bile ta večer že odigrane (dovolj dolgo odprte), na tej napravi.
/// Oznaka velja [trajanje] od odprtja, da je naslednji špil spet čist.
class Odigrane extends ChangeNotifier {
  static Odigrane aplikacija = Odigrane();

  static const _kljuc = 'odigrane';
  static const trajanje = Duration(hours: 12);

  final Map<String, DateTime> _kdaj = {};

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
    _kdaj[pesem] = DateTime.now();
    _kdaj.removeWhere((k, _) => !je(k));
    await _shrani();
  }

  Future<void> ponastavi() async {
    _kdaj.clear();
    await _shrani();
  }

  Future<void> _shrani() async {
    notifyListeners();
    (await SharedPreferences.getInstance()).setString(
      _kljuc,
      jsonEncode({for (final e in _kdaj.entries) e.key: e.value.toIso8601String()}),
    );
  }
}
