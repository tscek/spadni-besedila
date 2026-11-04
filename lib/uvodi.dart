import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:media_kit/media_kit.dart' as mk;

import 'api.dart';
import 'baza.dart';
import 'config.dart';
import 'models.dart';
import 'nastavitve.dart';

/// Zvočni izhod (npr. USB zvočna kartica).
typedef IzhodZvoka = ({String id, String ime});

/// Predvajalnik zvoka z izbiro izhoda (v testih ga zamenja ponaredek).
abstract class PredvajalnikZvoka {
  /// Windows: media_kit (izbira izhoda); Android in splet: audioplayers (manjši APK, izhod izbere sistem).
  static PredvajalnikZvoka Function() tovarna = () =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows ? PredvajalnikMediaKit() : PredvajalnikAudioplayers();

  /// Naloži zvok; vrne trajanje (null, če ga ni bilo mogoče prebrati).
  Future<Duration?> odpri(Uint8List bajti, String vrsta);
  Future<void> predvajaj(Duration od);
  Future<void> ustavi();
  Future<void> glasnost(double g);
  Stream<Duration> get pozicija;
  Stream<void> get konec;
  Future<List<IzhodZvoka>> izhodi();
  Future<void> nastaviIzhod(String id);
  void zapri();
}

/// audioplayers: brez izbire izhoda (Android sam uporabi priključeno USB kartico).
class PredvajalnikAudioplayers implements PredvajalnikZvoka {
  ap.AudioPlayer? _p;
  ap.AudioPlayer get _pl => _p ??= ap.AudioPlayer()..setReleaseMode(ap.ReleaseMode.stop);

  @override
  Future<Duration?> odpri(Uint8List bajti, String vrsta) async {
    final p = _pl;
    await p.stop();
    await p.setSource(ap.BytesSource(bajti, mimeType: vrsta.isEmpty ? null : vrsta));
    for (var i = 0; i < 25; i++) {
      final d = await p.getDuration();
      if (d != null && d > Duration.zero) return d;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return null;
  }

  @override
  Future<void> predvajaj(Duration od) async {
    await _pl.seek(od);
    await _pl.resume();
  }

  @override
  Future<void> ustavi() async => _p?.pause();

  @override
  Future<void> glasnost(double g) async => _p?.setVolume(g);

  @override
  Stream<Duration> get pozicija => _pl.onPositionChanged;

  @override
  Stream<void> get konec => _pl.onPlayerComplete;

  @override
  Future<List<IzhodZvoka>> izhodi() async => const [];

  @override
  Future<void> nastaviIzhod(String id) async {}

  @override
  void zapri() => _p?.dispose();
}

/// media_kit (libmpv): predvajanje iz pomnilnika in izbira izhoda (samo Windows).
class PredvajalnikMediaKit implements PredvajalnikZvoka {
  static bool _pripravljen = false;

  mk.Player? _p;
  mk.Player get _pl {
    if (!_pripravljen) {
      mk.MediaKit.ensureInitialized();
      _pripravljen = true;
    }
    return _p ??= mk.Player();
  }

  @override
  Future<Duration?> odpri(Uint8List bajti, String vrsta) async {
    final p = _pl;
    await p.open(await mk.Media.memory(bajti, type: vrsta.isEmpty ? null : vrsta), play: false);
    if (p.state.duration > Duration.zero) return p.state.duration;
    try {
      return await p.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<void> predvajaj(Duration od) async {
    await _pl.seek(od);
    await _pl.play();
  }

  @override
  Future<void> ustavi() async => _p?.pause();

  @override
  Future<void> glasnost(double g) async => _p?.setVolume(g * 100);

  @override
  Stream<Duration> get pozicija => _pl.stream.position;

  @override
  Stream<void> get konec => _pl.stream.completed.where((c) => c);

  @override
  Future<List<IzhodZvoka>> izhodi() async {
    final p = _pl;
    var naprave = p.state.audioDevices;
    if (naprave.length <= 1) {
      try {
        naprave = await p.stream.audioDevices.firstWhere((l) => l.length > 1).timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // samo samodejni izhod
      }
    }
    return [
      for (final n in naprave)
        if (n.name != 'auto') (id: n.name, ime: n.description.isEmpty ? n.name : n.description),
    ];
  }

  @override
  Future<void> nastaviIzhod(String id) async {
    final p = _pl;
    final n = p.state.audioDevices.where((d) => d.name == id).firstOrNull;
    await p.setAudioDevice(n ?? mk.AudioDevice.auto());
  }

  @override
  void zapri() => _p?.dispose();
}

/// Zvočni uvodi pesmi: ob odprtju pesmi (uho vklopljeno in »Predvajaj uvode na tej napravi«) se predvaja
/// del posnetka od–do, s kratkim pojemanjem na koncu. Ustavi se ob zaprtju pesmi.
class Uvodi extends ChangeNotifier {
  static Uvodi aplikacija = Uvodi();

  /// Pojemanje glasnosti pred koncem (ko konec ni konec posnetka).
  static const zatemni = Duration(milliseconds: 800);

  PredvajalnikZvoka? _p;
  PredvajalnikZvoka get _pl => _p ??= PredvajalnikZvoka.tovarna();
  StreamSubscription<Duration>? _poz;
  StreamSubscription<void>? _kon;

  /// Pesem, katere uvod igra (ali se pripravlja).
  String? igra;
  int _zahteva = 0;

  /// Ob odprtju pesmi.
  Future<void> obOdprtju(Baza baza, Api? api, Pesem p) async {
    final n = Nastavitve.aplikacija;
    if (!n.uvodi || !n.predvajajUvode || Config.prekoVodje || p.uvod.isEmpty) {
      await ustavi();
      return;
    }
    await predvajaj(baza, api, p);
  }

  /// Predvaja uvod pesmi (tudi ročno, z nožnim stikalom).
  Future<void> predvajaj(Baza baza, Api? api, Pesem p) async {
    final zahteva = ++_zahteva;
    await _ustaviTiho();
    igra = p.id;
    notifyListeners();
    try {
      final bajti = await baza.zvokUvoda(api, p);
      if (bajti == null || zahteva != _zahteva) return;
      await predvajajBajte(bajti, p.uvodVrsta, od: p.uvodOd, doo: p.uvodDo, zahteva: zahteva);
    } catch (e) {
      debugPrint('Uvod: $e');
      if (zahteva == _zahteva) {
        igra = null;
        notifyListeners();
      }
    }
  }

  /// Predvaja zvok od [od] do [doo] sekund (tudi za poslušanje pri obrezovanju).
  Future<void> predvajajBajte(Uint8List bajti, String vrsta, {double od = 0, double? doo, int? zahteva}) async {
    zahteva ??= ++_zahteva;
    final pl = _pl;
    final izhod = Nastavitve.aplikacija.izhodZvoka;
    await pl.odpri(bajti, vrsta);
    if (zahteva != _zahteva) return;
    if (izhod.isNotEmpty) await pl.nastaviIzhod(izhod);
    await pl.glasnost(1);
    final konec = doo == null ? null : Duration(milliseconds: (doo * 1000).round());
    await _poz?.cancel();
    await _kon?.cancel();
    if (konec != null) {
      _poz = pl.pozicija.listen((pos) {
        final ostane = konec - pos;
        if (ostane <= Duration.zero) {
          ustavi();
        } else if (ostane < zatemni) {
          pl.glasnost(ostane.inMilliseconds / zatemni.inMilliseconds);
        }
      });
    }
    _kon = pl.konec.listen((_) => ustavi());
    await pl.predvajaj(Duration(milliseconds: (od * 1000).round()));
  }

  Future<void> _ustaviTiho() async {
    await _poz?.cancel();
    await _kon?.cancel();
    _poz = null;
    _kon = null;
    await _p?.ustavi();
  }

  Future<void> ustavi() async {
    _zahteva++;
    final bilo = igra != null;
    igra = null;
    await _ustaviTiho();
    if (bilo) notifyListeners();
  }

  /// Ob zaprtju pesmi ustavi le njen uvod (naslednja pesem ga že lahko predvaja).
  Future<void> obZaprtju(Pesem p) async {
    if (igra == p.id) await ustavi();
  }

  Future<List<IzhodZvoka>> izhodi() => _pl.izhodi();

  /// Trajanje zvoka (za obrezovanje).
  Future<Duration?> trajanje(Uint8List bajti, String vrsta) async {
    await ustavi();
    return _pl.odpri(bajti, vrsta);
  }
}
