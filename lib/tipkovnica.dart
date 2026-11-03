import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'midi/midi.dart';
import 'midi/ukazi.dart' show DejanjeMidi;

/// Premik pogleda gor (-1) ali dol (1); posluša ga besedilo ali PDF, ki je na vrhu.
class Listanje {
  static final _tok = StreamController<int>.broadcast();
  static Stream<int> get tok => _tok.stream;
  static void premakni(int smer) => _tok.add(smer);
}

/// Bližnjice tipkovnice (tudi nožna stikala BT, ki pošiljajo tipke) za ista dejanja kot nožno stikalo MIDI.
/// Nastavitve so na vsaki napravi posebej.
class Tipkovnica extends ChangeNotifier {
  static Tipkovnica aplikacija = Tipkovnica();

  static const _kljuc = 'tipkovnica';

  static final privzete = <int, DejanjeMidi>{
    LogicalKeyboardKey.keyI.keyId: DejanjeMidi.iskalnik,
    LogicalKeyboardKey.arrowUp.keyId: DejanjeMidi.gor,
    LogicalKeyboardKey.arrowDown.keyId: DejanjeMidi.dol,
    LogicalKeyboardKey.arrowLeft.keyId: DejanjeMidi.prejsnja,
    LogicalKeyboardKey.arrowRight.keyId: DejanjeMidi.naslednja,
    LogicalKeyboardKey.enter.keyId: DejanjeMidi.potrdi,
    LogicalKeyboardKey.numpadEnter.keyId: DejanjeMidi.potrdi,
  };

  /// Tipka (keyId) → dejanje; ena tipka ima eno dejanje, dejanje ima lahko več tipk.
  Map<int, DejanjeMidi> bliznjice = Map.of(privzete);

  /// Dejanje, za katero se čaka na tipko (učenje).
  DejanjeMidi? ucim;

  /// Za preizkuse: namesto Midi.aplikacija.sprozi.
  @visibleForTesting
  bool Function(DejanjeMidi)? sprozi;

  bool _poslusam = false;

  Future<void> nalozi() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_kljuc);
      if (s != null) {
        final j = (jsonDecode(s) as Map).cast<String, dynamic>();
        final nove = <int, DejanjeMidi>{};
        for (final e in j.entries) {
          final k = int.tryParse(e.key);
          final d = DejanjeMidi.values.where((d) => d.name == e.value).firstOrNull;
          if (k != null && d != null) nove[k] = d;
        }
        bliznjice = nove;
      }
    } catch (_) {}
    if (!_poslusam) {
      _poslusam = true;
      HardwareKeyboard.instance.addHandler(obTipki);
    }
    notifyListeners();
  }

  Future<void> _shrani() async {
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString(
        _kljuc,
        jsonEncode({for (final e in bliznjice.entries) '${e.key}': e.value.name}),
      );
    } catch (_) {}
  }

  List<LogicalKeyboardKey> tipkeZa(DejanjeMidi d) => [
    for (final e in bliznjice.entries)
      if (e.value == d) LogicalKeyboardKey.findKeyByKeyId(e.key) ?? LogicalKeyboardKey(e.key),
  ];

  void uci(DejanjeMidi? d) {
    ucim = d;
    notifyListeners();
  }

  Future<void> odstrani(int tipka) async {
    bliznjice.remove(tipka);
    await _shrani();
  }

  Future<void> ponastavi() async {
    bliznjice = Map.of(privzete);
    ucim = null;
    await _shrani();
  }

  /// Ali ima fokus vnosno polje (takrat črke in levo/desno ostanejo polju).
  static bool get _vPolju {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && (ctx.widget is EditableText || ctx.findAncestorStateOfType<EditableTextState>() != null);
  }

  static bool _znotrajPolja(LogicalKeyboardKey k, String? znak) =>
      (znak != null && znak.isNotEmpty && znak.codeUnitAt(0) >= 32) ||
      k == LogicalKeyboardKey.arrowLeft ||
      k == LogicalKeyboardKey.arrowRight ||
      k == LogicalKeyboardKey.backspace ||
      k == LogicalKeyboardKey.space;

  /// Vrne true, če je tipko porabila aplikacija.
  bool obTipki(KeyEvent e) {
    if (e is KeyUpEvent) return false;
    final k = e.logicalKey;
    final u = ucim;
    if (u != null && e is KeyDownEvent) {
      if (k == LogicalKeyboardKey.escape) {
        uci(null);
        return true;
      }
      bliznjice[k.keyId] = u;
      ucim = null;
      unawaited(_shrani());
      return true;
    }
    final d = bliznjice[k.keyId];
    if (d == null) return false;
    // Ponavljanje ob držanju samo za premikanje.
    if (e is KeyRepeatEvent && d != DejanjeMidi.gor && d != DejanjeMidi.dol) return false;
    if (_vPolju && _znotrajPolja(k, e.character)) return false;
    return (sprozi ?? Midi.aplikacija.sprozi)(d);
  }
}
