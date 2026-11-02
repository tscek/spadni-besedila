import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'baza.dart';
import 'runda.dart';
import 'snemalnik_web.dart' if (dart.library.io) 'snemalnik_io.dart' as datoteka;

/// Zvočni vhod za snemanje (npr. USB mešalka).
typedef VhodZvoka = ({String id, String ime});

/// Snemalnik, ki snema v datoteko (v testih ga zamenja ponaredek).
abstract class SnemalnikKosov {
  static SnemalnikKosov Function() tovarna = SnemalnikKosovRecord.new;

  Future<bool> dovoljenje();
  Future<List<VhodZvoka>> vhodi();
  Future<void> zacni(String pot, {String? vhod});

  /// Konča snemanje; datoteka na poti iz [zacni] je zaprta.
  Future<void> ustavi();
  Future<void> zapri();
}

/// AAC 128 kbit/s stereo prek paketa record (Android, Windows).
class SnemalnikKosovRecord implements SnemalnikKosov {
  final _r = AudioRecorder();
  List<InputDevice> _naprave = [];

  @override
  Future<bool> dovoljenje() => _r.hasPermission();

  @override
  Future<List<VhodZvoka>> vhodi() async {
    _naprave = await _r.listInputDevices();
    return [for (final n in _naprave) (id: n.id, ime: n.label)];
  }

  @override
  Future<void> zacni(String pot, {String? vhod}) async {
    if (vhod != null && _naprave.isEmpty) await vhodi();
    final naprava = _naprave.where((n) => n.id == vhod).firstOrNull;
    await _r.start(
      RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100, numChannels: 2, device: naprava),
      path: pot,
    );
  }

  @override
  Future<void> ustavi() async => _r.stop();

  @override
  Future<void> zapri() => _r.dispose();
}

/// Snemanje špila: snema vodja (ali naprava brez špila), administrator ga lahko vodi tudi z druge naprave.
/// Posnetek se deli na kose po [dolzinaKosa]; vsak gre na Drive, nato se na napravi pobriše.
/// PAVZA (runda) snemanje začasno ustavi, ŠPILEJ!! ga nadaljuje.
class SnemanjeSpila extends ChangeNotifier {
  SnemanjeSpila({this.dolzinaKosa = const Duration(minutes: 10)});

  static SnemanjeSpila aplikacija = SnemanjeSpila();

  /// Datoteke kosov (v testih jih zamenja pomnilnik).
  static Future<String> Function(String snemanje, int i) potKosa = datoteka.potKosa;
  static Future<Uint8List?> Function(String pot) beriKos = datoteka.beriDatoteko;
  static Future<void> Function(String pot) izbrisiKos = datoteka.izbrisiDatoteko;

  static const _kljucVrste = 'snemanje_vrsta.json';
  static const _kljucVhoda = 'snemanje_vhod';

  final Duration dolzinaKosa;

  /// Baza (shramba čakalne vrste) in povezava za pošiljanje na Drive (null: ni prijave, kosi počakajo).
  Baza? baza;
  Api? Function()? api;

  /// Ime te naprave, kot ga vidijo drugi (npr. »Tomaž (windows)«).
  String imeNaprave = '';

  /// Sledilec: ukazi gredo vodji (ta snema), stanje pride od vodje.
  void Function(Map<String, dynamic> ukaz)? vodji;

  bool aktivno = false;
  bool pavza = false;
  String id = '';
  String naslov = '';
  String nastop = '';
  String zasedba = '';
  String naprava = '';
  DateTime? zacetek;
  String? napaka;

  /// Posneto v končanih kosih; trenutni kos teče od [_zacetekKosa].
  Duration _posneto = Duration.zero;
  DateTime? _zacetekKosa;

  /// Kosi in vrstice, ki še niso na Drivu (samo naprava, ki snema).
  List<Map<String, dynamic>> vrsta = [];

  SnemalnikKosov? _snemalnik;
  String? _potKosa;
  int _i = 0;
  Timer? _menjava;
  Timer? _ponovno;
  bool _posiljam = false;
  bool _snemaTu = false;

  /// Sledilec: kdaj je prišlo stanje vodje (da čas teče tudi vmes).
  DateTime? _prejeto;
  Duration _posnetoVodje = Duration.zero;

  /// Ali snema ta naprava (sicer kaže stanje vodje).
  bool get snemaTu => _snemaTu;

  /// Dolžina posnetka do zdaj (brez pavz).
  Duration posneto({DateTime? zdaj}) {
    final t = zdaj ?? DateTime.now();
    if (!_snemaTu) {
      return _posnetoVodje + (aktivno && !pavza && _prejeto != null ? t.difference(_prejeto!) : Duration.zero);
    }
    return _posneto + (_zacetekKosa == null ? Duration.zero : t.difference(_zacetekKosa!));
  }

  /// Kosi, ki čakajo na Drive.
  int get cakajo => vrsta.where((v) => v['vrsta'] == 'kos').length;

  Future<void> nalozi() async {
    final d = await baza?.shramba.beriBesedilo(_kljucVrste);
    if (d != null) {
      try {
        vrsta = (jsonDecode(d) as List).cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    if (vrsta.isNotEmpty) unawaited(poslji());
  }

  Future<String?> shranjenVhod() async => (await SharedPreferences.getInstance()).getString(_kljucVhoda);

  Future<void> nastaviVhod(String? vhod) async {
    final p = await SharedPreferences.getInstance();
    if (vhod == null) {
      await p.remove(_kljucVhoda);
    } else {
      await p.setString(_kljucVhoda, vhod);
    }
  }

  Future<List<VhodZvoka>> vhodi() async {
    final s = _snemalnik ??= SnemalnikKosov.tovarna();
    try {
      return await s.vhodi();
    } catch (_) {
      return const [];
    }
  }

  /// Začne snemanje (ali ukaz pošlje vodji).
  Future<void> zacni({required String naslov, String nastop = '', String zasedba = ''}) async {
    if (vodji case final f?) {
      return f({'dejanje': 'zacni', 'naslov': naslov, 'nastop': nastop, 'zasedba': zasedba});
    }
    await _zacni(naslov: naslov, nastop: nastop, zasedba: zasedba);
  }

  /// Konča snemanje (ali ukaz pošlje vodji).
  Future<void> zakljuci() async {
    if (vodji case final f?) return f({'dejanje': 'zakljuci'});
    await _zakljuci();
  }

  /// Vodja: ukaz administratorja z druge naprave.
  Future<void> izvedi(Map<String, dynamic> u) => switch (u['dejanje']) {
    'zacni' => _zacni(
      naslov: u['naslov']?.toString() ?? '',
      nastop: u['nastop']?.toString() ?? '',
      zasedba: u['zasedba']?.toString() ?? '',
    ),
    'zakljuci' => _zakljuci(),
    _ => Future.value(),
  };

  Future<void> _zacni({required String naslov, required String nastop, required String zasedba}) async {
    if (aktivno && _snemaTu) return;
    final s = _snemalnik ??= SnemalnikKosov.tovarna();
    try {
      if (!await s.dovoljenje()) {
        napaka = 'Aplikacija nima dovoljenja za mikrofon.';
        notifyListeners();
        return;
      }
    } catch (e) {
      napaka = 'Snemanja ni bilo mogoče začeti: $e';
      notifyListeners();
      return;
    }
    final t = DateTime.now();
    id = Baza.novId();
    this.naslov = naslov.trim().isEmpty ? privzetNaslov(t) : naslov.trim();
    this.nastop = nastop;
    this.zasedba = zasedba;
    final clan = baza?.imeClana ?? '';
    naprava = clan.isEmpty ? imeNaprave : '$clan ($imeNaprave)';
    zacetek = t;
    _i = 0;
    _posneto = Duration.zero;
    _zacetekKosa = null;
    napaka = null;
    aktivno = true;
    _snemaTu = true;
    pavza = Runda.aplikacija.pavza == true;
    await _vVrsto({'vrsta': 'vrstica', 'podatki': _vrstica('snema')});
    Runda.aplikacija.addListener(_obRundi);
    if (!pavza) await _zacniKos();
    _menjava = Timer.periodic(dolzinaKosa, (_) => _zamenjajKos());
    notifyListeners();
    unawaited(poslji());
  }

  Map<String, dynamic> _vrstica(String stanje) => {
    'ID': id,
    'Naslov': naslov,
    'Nastop': nastop,
    'Zasedba': zasedba,
    'Začetek': zacetek?.toUtc().toIso8601String(),
    'Naprava': naprava,
    'Stanje': stanje,
  };

  /// Naslov brez nastopa: datum in ura.
  static String privzetNaslov(DateTime t) =>
      'Špil ${t.day}. ${t.month}. ${t.year} ${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _zakljuci() async {
    if (!aktivno || !_snemaTu) return;
    Runda.aplikacija.removeListener(_obRundi);
    _menjava?.cancel();
    await _ustaviKos();
    await _vVrsto({
      'vrsta': 'vrstica',
      'podatki': {
        ..._vrstica('posneto'),
        'Konec': DateTime.now().toUtc().toIso8601String(),
        'Trajanje (s)': _posneto.inSeconds,
      },
    });
    aktivno = false;
    pavza = false;
    _snemaTu = false;
    notifyListeners();
    unawaited(poslji());
  }

  /// PAVZA ustavi trenutni kos, ŠPILEJ!! začne novega.
  Future<void> _obRundi() async {
    if (!aktivno || !_snemaTu) return;
    final p = Runda.aplikacija.pavza == true;
    if (p == pavza) return;
    pavza = p;
    if (p) {
      await _ustaviKos();
    } else {
      await _zacniKos();
    }
    notifyListeners();
  }

  Future<void> _zamenjajKos() async {
    if (!aktivno || pavza || _zacetekKosa == null) return;
    await _ustaviKos();
    await _zacniKos();
  }

  Future<void> _zacniKos() async {
    final s = _snemalnik ??= SnemalnikKosov.tovarna();
    try {
      final pot = await potKosa(id, _i);
      await s.zacni(pot, vhod: await shranjenVhod());
      _potKosa = pot;
      _zacetekKosa = DateTime.now();
    } catch (e) {
      napaka = 'Snemanje ne deluje: $e';
      notifyListeners();
    }
  }

  Future<void> _ustaviKos() async {
    final pot = _potKosa;
    final od = _zacetekKosa;
    if (pot == null || od == null) return;
    _potKosa = null;
    _zacetekKosa = null;
    try {
      await _snemalnik?.ustavi();
    } catch (e) {
      napaka = 'Kos posnetka ni shranjen: $e';
    }
    final trajanje = DateTime.now().difference(od);
    _posneto += trajanje;
    await _vVrsto({
      'vrsta': 'kos',
      'id': id,
      'i': _i++,
      'pot': pot,
      'zacetek': od.toUtc().toIso8601String(),
      'trajanje': trajanje.inSeconds,
    });
    unawaited(poslji());
  }

  Future<void> _vVrsto(Map<String, dynamic> v) async {
    vrsta.add(v);
    await _shraniVrsto();
  }

  Future<void> _shraniVrsto() async => baza?.shramba.pisiBesedilo(_kljucVrste, jsonEncode(vrsta));

  /// Pošlje čakajoče vrstice in kose na Drive (po vrsti); kos se na napravi pobriše, ko je na Drivu.
  Future<void> poslji() async {
    final a = api?.call();
    if (_posiljam || a == null || vrsta.isEmpty) return;
    _posiljam = true;
    _ponovno?.cancel();
    try {
      while (vrsta.isNotEmpty) {
        final v = vrsta.first;
        if (v['vrsta'] == 'kos') {
          final bajti = await beriKos(v['pot'] as String);
          if (bajti != null && bajti.isNotEmpty) {
            await a.snemanjeKos(
              id: v['id'] as String,
              i: (v['i'] as num).toInt(),
              zacetek: v['zacetek'] as String,
              trajanje: (v['trajanje'] as num).toInt(),
              bajti: bajti,
            );
          }
          await izbrisiKos(v['pot'] as String);
        } else {
          await a.snemanje((v['podatki'] as Map).cast<String, dynamic>());
        }
        vrsta.removeAt(0);
        await _shraniVrsto();
        if (napaka?.startsWith('Pošiljanje') ?? false) napaka = null;
        notifyListeners();
      }
    } catch (e) {
      napaka = 'Pošiljanje na Drive čaka (${e.toString().split('\n').first})';
      _ponovno = Timer(const Duration(minutes: 1), poslji);
      notifyListeners();
    } finally {
      _posiljam = false;
    }
  }

  /// Stanje za sledilce.
  Map<String, dynamic> vJson() => {
    'vrsta': 'snemanje',
    'aktivno': aktivno,
    'pavza': pavza,
    'naslov': naslov,
    'naprava': naprava,
    'posneto': posneto().inSeconds,
  };

  /// Sledilec: stanje od vodje.
  void prevzemi(Map<String, dynamic> j) {
    if (_snemaTu) return;
    aktivno = j['aktivno'] == true;
    pavza = j['pavza'] == true;
    naslov = j['naslov']?.toString() ?? '';
    naprava = j['naprava']?.toString() ?? '';
    _posnetoVodje = Duration(seconds: (j['posneto'] as num?)?.toInt() ?? 0);
    _prejeto = DateTime.now();
    notifyListeners();
  }

  /// Sledilec ni več povezan: stanja vodje ne poznamo.
  void pozabiVodjo() {
    if (_snemaTu || !aktivno) return;
    aktivno = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _menjava?.cancel();
    _ponovno?.cancel();
    _snemalnik?.zapri();
    super.dispose();
  }
}
