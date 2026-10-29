import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../baza.dart';
import '../config.dart';
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

enum VlogaSpila { nic, vodja, sledilec }

/// Sinhronizacija na špilu prek lokalnega WiFi-ja (brez interneta).
/// Vodja zažene strežnik ([StreznikVodje]) in pošilja [StanjeSpila]; sledilci ga prek WebSocketa
/// prejemajo in pokažejo isto pesem iz svoje lokalne kopije.
class Spil extends ChangeNotifier {
  Spil({StreznikVodje? Function()? streznik, Stream<String> Function()? iskalec})
    : _ustvariStreznik = streznik ?? ustvariStreznik,
      _isciVodjo = iskalec ?? isciVodjo;

  final StreznikVodje? Function() _ustvariStreznik;
  final Stream<String> Function() _isciVodjo;

  VlogaSpila vloga = VlogaSpila.nic;
  StanjeSpila? stanje;
  String? napaka;

  /// Vodja: naslov, ki ga odprejo iPadi (npr. http://192.168.1.5:8765).
  String? naslov;
  int sledilcev = 0;

  /// Sledilec: ali je povezava z vodjo trenutno vzpostavljena.
  bool povezan = false;

  StreznikVodje? _streznik;
  WebSocketChannel? _kanal;
  StreamSubscription<dynamic>? _poslusam;
  Timer? _ponovnaPovezava;
  Uri? _naslovVodje;
  StreamSubscription<String>? _iskanje;

  /// Kar ta naprava trenutno kaže; ko začne voditi, to takoj pošlje sledilcem.
  StanjeSpila? _prikazano;

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
      });
      _streznik = s;
      vloga = VlogaSpila.vodja;
      napaka = null;
      stanje = _prikazano ?? stanje;
      if (stanje != null) s.poslji(jsonEncode(stanje!.vJson()));
    } catch (e) {
      napaka = 'Strežnika ni bilo mogoče zagnati: $e';
    }
    notifyListeners();
  }

  /// Zaslon s pesmijo pove, kaj kaže; vodja to pošlje sledilcem.
  void prikazujem(StanjeSpila s) {
    _prikazano = s;
    if (vloga == VlogaSpila.vodja) objavi(s);
  }

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
      (naslov) {
        final ws = naslovWebSocket(naslov);
        if (ws != null && ws != _naslovVodje && vloga == VlogaSpila.sledilec) sledi(ws);
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
        napaka = null;
        notifyListeners();
      }, onError: (Object _) => _prekinjeno(kanal));
      _poslusam = kanal.stream.listen(
        (m) {
          final j = jsonDecode(m as String) as Map<String, dynamic>;
          if (j['vrsta'] == 'stanje') {
            stanje = StanjeSpila.izJson(j);
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
    if (povezan) {
      povezan = false;
      notifyListeners();
    }
    _poslusam?.cancel();
    _kanal = null;
    _ponovnaPovezava?.cancel();
    if (vloga == VlogaSpila.sledilec) _ponovnaPovezava = Timer(const Duration(seconds: 2), _povezi);
  }

  void _ustaviSledenje() {
    _ponovnaPovezava?.cancel();
    _poslusam?.cancel();
    _kanal?.sink.close();
    _kanal = null;
    povezan = false;
  }

  Future<void> ustavi() async {
    await _iskanje?.cancel();
    _iskanje = null;
    _ustaviSledenje();
    _naslovVodje = null;
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
