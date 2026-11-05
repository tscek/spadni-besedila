import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../api.dart';
import '../baza.dart';
import '../models.dart';
import '../snemanje.dart';
import '../uvodi.dart';
import 'ucenje_casov.dart';
import '../snemalnik_web.dart' if (dart.library.io) '../snemalnik_io.dart' as datoteka;

/// Posnet uvod: bajti in MIME vrsta.
typedef PosnetUvod = ({Uint8List bajti, String vrsta});

/// Snemalnik uvoda v dobri kakovosti z izbranim vhodom (v testih ga zamenja ponaredek).
abstract class SnemalnikUvoda {
  static SnemalnikUvoda Function() tovarna = _SnemalnikUvodaRecord.new;

  Future<bool> dovoljenje();
  Future<void> zacni();
  Future<PosnetUvod?> ustavi();
  Future<void> zapri();
}

class _SnemalnikUvodaRecord implements SnemalnikUvoda {
  final _r = AudioRecorder();
  String _vrsta = 'audio/mp4';

  @override
  Future<bool> dovoljenje() => _r.hasPermission();

  @override
  Future<void> zacni() async {
    var enc = AudioEncoder.aacLc;
    if (kIsWeb && !await _r.isEncoderSupported(AudioEncoder.aacLc)) {
      enc = await _r.isEncoderSupported(AudioEncoder.opus) ? AudioEncoder.opus : AudioEncoder.wav;
    }
    _vrsta = switch (enc) {
      AudioEncoder.opus => 'audio/webm',
      AudioEncoder.wav => 'audio/wav',
      _ => 'audio/mp4',
    };
    // Isti vhod kot za snemanje špila (Nastavitve → Zvočni vhod).
    InputDevice? naprava;
    if (!kIsWeb) {
      final vhod = await SnemanjeSpila.aplikacija.shranjenVhod();
      if (vhod != null) naprava = (await _r.listInputDevices()).where((n) => n.id == vhod).firstOrNull;
    }
    await _r.start(
      RecordConfig(encoder: enc, bitRate: 128000, sampleRate: 44100, numChannels: 2, device: naprava),
      path: await datoteka.potZaPosnetek(switch (enc) {
        AudioEncoder.opus => 'webm',
        AudioEncoder.wav => 'wav',
        _ => 'm4a',
      }),
    );
  }

  @override
  Future<PosnetUvod?> ustavi() async {
    final pot = await _r.stop();
    if (pot == null) return null;
    final bajti = await datoteka.preberiPosnetek(pot);
    return bajti.isEmpty ? null : (bajti: bajti, vrsta: _vrsta);
  }

  @override
  Future<void> zapri() => _r.dispose();
}

/// MIME vrsta zvočne datoteke po končnici.
String vrstaZvoka(String ime) => switch (ime.split('.').last.toLowerCase()) {
  'mp3' => 'audio/mpeg',
  'wav' => 'audio/wav',
  'ogg' || 'oga' => 'audio/ogg',
  'webm' => 'audio/webm',
  'flac' => 'audio/flac',
  'aac' => 'audio/aac',
  _ => 'audio/mp4',
};

/// Čas v sekundah kot m:ss,d.
String casUvoda(double s) {
  final d = (s * 10).round();
  final m = d ~/ 600;
  final sek = (d % 600) ~/ 10;
  return '$m:${sek.toString().padLeft(2, '0')},${d % 10}';
}

/// Uvod ali playback pesmi pri urejanju: posnemi ali naloži (eno ali drugo, nov zamenja starega, z vprašanjem),
/// pri uvodu obreži začetek in konec, pri playbacku transpozicija in odstranitev vokala. Shrani se takoj
/// (potrebuje internet).
class UrejanjeZvoka extends StatefulWidget {
  const UrejanjeZvoka({
    super.key,
    required this.baza,
    required this.api,
    required this.pesem,
    this.vrsta = VrstaZvoka.uvod,
  });

  final Baza baza;
  final Api api;
  final String pesem;
  final VrstaZvoka vrsta;

  /// Največja velikost datoteke.
  int get najvec => (vrsta == VrstaZvoka.playback ? 25 : 15) * 1024 * 1024;

  @override
  State<UrejanjeZvoka> createState() => _UrejanjeZvokaState();
}

class _UrejanjeZvokaState extends State<UrejanjeZvoka> {
  Uint8List? _bajti;
  String _vrsta = '';
  double? _trajanje;
  RangeValues _obseg = const RangeValues(0, 0);
  int? _transpozicija;

  /// Nov zvok (posnet ali naložen), ki še ni na strežniku.
  bool _nov = false;
  bool _posnet = false;
  bool _spremenjenObseg = false;
  bool _delam = false;
  String? _napaka;

  SnemalnikUvoda? _snemalnik;
  DateTime? _zacetek;
  Timer? _ura;

  VrstaZvoka get _v => widget.vrsta;
  bool get _uvod => _v == VrstaZvoka.uvod;
  String get _k => _v.kaj;
  Predvajanje get _predvajanje => Predvajanje.za(_v);
  Pesem? get _pesem => widget.baza.pesem(widget.pesem);

  @override
  void initState() {
    super.initState();
    _naloziObstojecega();
  }

  @override
  void dispose() {
    _ura?.cancel();
    _snemalnik?.zapri();
    _predvajanje.ustavi();
    super.dispose();
  }

  Future<void> _naloziObstojecega() async {
    final p = _pesem;
    if (p == null || p.zvok(_v).isEmpty) return;
    setState(() => _delam = true);
    try {
      final b = await widget.baza.zvok(widget.api, p, _v);
      if (b != null) await _pripravi(b, p.zvokVrsta(_v), od: _uvod ? p.uvodOd : 0, doo: _uvod ? p.uvodDo : null);
    } catch (e) {
      _napaka = 'Posnetka ni bilo mogoče prebrati: $e';
    } finally {
      if (mounted) setState(() => _delam = false);
    }
  }

  Future<void> _pripravi(Uint8List bajti, String vrsta, {double od = 0, double? doo}) async {
    final t = await _predvajanje.trajanje(bajti, vrsta);
    if (!mounted) return;
    final s = t == null ? null : t.inMilliseconds / 1000;
    setState(() {
      _bajti = bajti;
      _vrsta = vrsta;
      _trajanje = s;
      if (s != null) {
        final konec = (doo ?? s).clamp(0, s).toDouble();
        _obseg = RangeValues(od.clamp(0, konec).toDouble(), konec);
      }
    });
  }

  /// Pred zamenjavo obstoječega posnetka vpraša.
  Future<bool> _smemZamenjati() async {
    if ((_pesem?.zvok(_v).isEmpty ?? true) && _bajti == null) return true;
    final da = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Zamenjam obstoječi ${_uvod ? 'uvod' : 'playback'}?'),
        content: const Text('Ko novega shraniš, gre stari posnetek v koš na Drivu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ne')),
          FilledButton(
            key: ValueKey('$_k-zamenjaj'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zamenjaj'),
          ),
        ],
      ),
    );
    return da == true;
  }

  Future<void> _snemaj() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_snemalnik != null) {
      final s = _snemalnik!;
      _ura?.cancel();
      setState(() => _snemalnik = null);
      final posneto = await s.ustavi();
      await s.zapri();
      if (posneto == null) return;
      _nov = true;
      _posnet = true;
      _spremenjenObseg = false;
      await _pripravi(posneto.bajti, posneto.vrsta);
      return;
    }
    if (!await _smemZamenjati()) return;
    await _predvajanje.ustavi();
    final s = SnemalnikUvoda.tovarna();
    if (!await s.dovoljenje()) {
      messenger.showSnackBar(const SnackBar(content: Text('Aplikacija nima dovoljenja za mikrofon.')));
      await s.zapri();
      return;
    }
    await s.zacni();
    setState(() {
      _snemalnik = s;
      _zacetek = DateTime.now();
    });
    _ura = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _nalozi() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await _smemZamenjati()) return;
    final izbrane = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'webm', 'flac'],
    );
    if (izbrane.isEmpty || !mounted) return;
    final f = izbrane.first;
    final bajti = await f.readAsBytes();
    if (bajti.length > widget.najvec) {
      messenger.showSnackBar(
        SnackBar(content: Text('Datoteka je prevelika (največ ${widget.najvec ~/ (1024 * 1024)} MB).')),
      );
      return;
    }
    _nov = true;
    _posnet = false;
    _spremenjenObseg = false;
    await _pripravi(bajti, vrstaZvoka(f.name));
    if (_trajanje == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Te datoteke ni bilo mogoče prebrati kot zvok.')));
    }
  }

  double? get _doo {
    final t = _trajanje;
    if (!_uvod || t == null || _obseg.end >= t - 0.05) return null;
    return _obseg.end;
  }

  Future<void> _shrani() async {
    final messenger = ScaffoldMessenger.of(context);
    final p = _pesem;
    final bajti = _bajti;
    if (p == null) return;
    await _predvajanje.ustavi();
    setState(() => _delam = true);
    try {
      if (_nov && bajti != null) {
        await widget.baza.shraniZvok(
          widget.api,
          p.id,
          _v,
          bajti,
          vrsta: _vrsta,
          od: _uvod ? _obseg.start : 0,
          doo: _doo,
          posnet: _posnet,
        );
      }
      final t = _transpozicija;
      if ((!_nov && _spremenjenObseg) || (t != null && t != p.playbackTranspozicija)) {
        await widget.baza.shraniPesem(widget.api, {
          'ID': p.id,
          'Koda': p.koda,
          'Naslov': p.naslov,
          if (_uvod && !_nov) ...{
            'Uvod od': double.parse(_obseg.start.toStringAsFixed(1)),
            'Uvod do': _doo == null ? '' : double.parse(_doo!.toStringAsFixed(1)),
          },
          'Playback transpozicija': ?t,
        });
      }
      _nov = false;
      _spremenjenObseg = false;
      _transpozicija = null;
      messenger.showSnackBar(SnackBar(content: Text('${_v.ime} je shranjen.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${_v.ime}: shranjevanje ni uspelo: $e')));
    } finally {
      if (mounted) setState(() => _delam = false);
    }
  }

  Future<void> _izbrisi() async {
    final messenger = ScaffoldMessenger.of(context);
    final p = _pesem;
    if (p == null) return;
    final da = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Izbrišem ${_uvod ? 'uvod' : 'playback'}?'),
        content: Text(
          'Posnetek pesmi »${p.naslov}« bo izbrisan za vse. Datoteka gre v koš na Drivu'
          '${p.playbackIzvirnik.isNotEmpty && !_uvod ? ' (tudi izvirnik z vokalom)' : ''}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ne')),
          FilledButton(
            key: ValueKey('$_k-izbrisi-potrdi'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Izbriši'),
          ),
        ],
      ),
    );
    if (da != true) return;
    await _predvajanje.ustavi();
    setState(() => _delam = true);
    try {
      if (p.zvok(_v).isNotEmpty) await widget.baza.shraniZvok(widget.api, p.id, _v, null);
      setState(() {
        _bajti = null;
        _trajanje = null;
        _nov = false;
        _spremenjenObseg = false;
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Posnetka ni bilo mogoče izbrisati: $e')));
    } finally {
      if (mounted) setState(() => _delam = false);
    }
  }

  /// Odstrani vokal (GitHub) ali vrni izvirnik.
  Future<void> _vokal({required bool izvirnik}) async {
    final messenger = ScaffoldMessenger.of(context);
    final p = _pesem;
    if (p == null) return;
    await _predvajanje.ustavi();
    setState(() => _delam = true);
    try {
      await widget.baza.obdelajPlayback(widget.api, p.id, izvirnik: izvirnik);
      if (izvirnik) {
        _bajti = null;
        await _naloziObstojecega();
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Vokal se odstranjuje (nekaj minut). Ko bo končano, osveži seznam pesmi.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Ni uspelo: $e')));
    } finally {
      if (mounted) setState(() => _delam = false);
    }
  }

  void _poslusaj({bool konec = false}) {
    final b = _bajti;
    if (b == null) return;
    final od = konec ? (_obseg.end - 3).clamp(_obseg.start, _obseg.end).toDouble() : _obseg.start;
    _predvajanje.predvajajBajte(
      b,
      _vrsta,
      od: _uvod ? od : (konec ? od : 0),
      doo: _doo,
      transpozicija: _uvod ? 0 : (_transpozicija ?? _pesem?.playbackTranspozicija ?? 0),
    );
  }

  String _opis(Pesem? p, double? t, bool imaZvok) {
    if (_snemalnik != null) return 'Snemam … ${casUvoda(DateTime.now().difference(_zacetek!).inMilliseconds / 1000)}';
    if (t != null) {
      final nov = _nov ? ' · še ni shranjen' : '';
      if (_uvod) {
        return 'Dolžina ${casUvoda(t)}, predvaja se od ${casUvoda(_obseg.start)} do ${casUvoda(_obseg.end)}$nov';
      }
      final vir = switch (p?.playbackVir) {
        'brez vokala' when !_nov => ' · brez vokala',
        _ => '',
      };
      return 'Dolžina ${casUvoda(t)}$vir$nov';
    }
    if (imaZvok) return _napaka ?? 'Nalagam posnetek …';
    return _uvod
        ? 'Ni uvoda. Posnemi ga ali naloži datoteko; predvaja se ob odprtju pesmi (uho v orodni vrstici).'
        : 'Ni playbacka. Naloži datoteko ali ga posnemi; predvajaš ga z gumbom ▶ v orodni vrstici.';
  }

  bool get _imaBesedilo =>
      (widget.baza.besedilaPesmi[widget.pesem] ?? const []).firstOrNull?.vsebina.trim().isNotEmpty ?? false;

  /// Učenje časov vrstic za sledenje besedilu med playbackom.
  Future<void> _naucCase() async {
    await _predvajanje.ustavi();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UcenjeCasovZaslon(baza: widget.baza, api: widget.api, pesem: widget.pesem),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _pesem;
    final t = _trajanje;
    final snemam = _snemalnik != null;
    final imaZvok = (p?.zvok(_v).isNotEmpty ?? false) || _bajti != null;
    final naStrezniku = (p?.zvok(_v).isNotEmpty ?? false) && !_nov;
    final slog = Theme.of(context).textTheme;
    final stanje = _uvod ? '' : (p?.playbackStanje ?? '');
    final transpozicija = _transpozicija ?? p?.playbackTranspozicija ?? 0;
    final spremembe =
        _nov || _spremenjenObseg || (_transpozicija != null && _transpozicija != p?.playbackTranspozicija);
    return Card(
      key: ValueKey(_k),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_uvod ? Icons.hearing : Icons.speaker),
                const SizedBox(width: 8),
                Text(_v.ime, style: slog.titleMedium),
                const Spacer(),
                if (_delam) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 4),
            Text(_opis(p, t, imaZvok), style: slog.bodySmall),
            if (stanje.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                stanje == 'čaka' ? 'Vokal se odstranjuje (nekaj minut). Ko bo končano, osveži seznam pesmi.' : stanje,
                key: const ValueKey('playback-stanje'),
                style: slog.bodySmall?.copyWith(
                  color: stanje == 'čaka' ? Colors.blue : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: ValueKey('$_k-snemaj'),
                  onPressed: _delam ? null : _snemaj,
                  icon: Icon(snemam ? Icons.stop : Icons.mic, color: snemam ? Colors.red : null),
                  label: Text(snemam ? 'Ustavi snemanje' : 'Posnemi'),
                ),
                OutlinedButton.icon(
                  key: ValueKey('$_k-nalozi'),
                  onPressed: _delam || snemam ? null : _nalozi,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Naloži datoteko'),
                ),
                if (imaZvok)
                  TextButton.icon(
                    key: ValueKey('$_k-izbrisi'),
                    onPressed: _delam || snemam ? null : _izbrisi,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Izbriši'),
                  ),
              ],
            ),
            if (t != null && t > 0 && !snemam) ...[
              const SizedBox(height: 8),
              if (_uvod)
                RangeSlider(
                  key: const ValueKey('uvod-obseg'),
                  min: 0,
                  max: t,
                  values: _obseg,
                  labels: RangeLabels(casUvoda(_obseg.start), casUvoda(_obseg.end)),
                  divisions: (t * 10).round().clamp(1, 100000),
                  onChanged: (v) => setState(() {
                    _obseg = v;
                    _spremenjenObseg = true;
                  }),
                )
              else
                Row(
                  children: [
                    const Text('Transpozicija'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      key: const ValueKey('playback-transpozicija'),
                      value: transpozicija,
                      onChanged: (v) => setState(() => _transpozicija = v),
                      items: [
                        for (var i = -6; i <= 6; i++)
                          DropdownMenuItem(value: i, child: Text(i == 0 ? '0' : '${i > 0 ? '+' : '−'}${i.abs()} pol.')),
                      ],
                    ),
                    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) ...[
                      const SizedBox(width: 8),
                      Flexible(child: Text('(velja na računalniku)', style: slog.bodySmall)),
                    ],
                  ],
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: ValueKey('$_k-poslusaj'),
                    onPressed: _poslusaj,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Poslušaj'),
                  ),
                  if (_uvod)
                    OutlinedButton.icon(
                      onPressed: () => _poslusaj(konec: true),
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Konec (zadnje 3 s)'),
                    ),
                  IconButton(tooltip: 'Ustavi', onPressed: _predvajanje.ustavi, icon: const Icon(Icons.stop)),
                  if (!_uvod && naStrezniku && stanje != 'čaka' && p!.playbackVir == 'naložen')
                    OutlinedButton.icon(
                      key: const ValueKey('playback-vokal'),
                      onPressed: _delam || spremembe ? null : () => _vokal(izvirnik: false),
                      icon: const Icon(Icons.mic_off),
                      label: const Text('Odstrani vokal'),
                    ),
                  if (!_uvod && naStrezniku && p!.playbackIzvirnik.isNotEmpty)
                    OutlinedButton.icon(
                      key: const ValueKey('playback-izvirnik'),
                      onPressed: _delam || spremembe ? null : () => _vokal(izvirnik: true),
                      icon: const Icon(Icons.restore),
                      label: const Text('Vrni izvirnik z vokalom'),
                    ),
                  if (!_uvod && naStrezniku && _imaBesedilo)
                    OutlinedButton.icon(
                      key: const ValueKey('playback-casi'),
                      onPressed: _delam || spremembe ? null : _naucCase,
                      icon: const Icon(Icons.subtitles),
                      label: Text(
                        p!.casiPlaybacka.prazno
                            ? 'Nauči čase vrstic'
                            : 'Nauči čase vrstic (${p.casiPlaybacka.stevilo} vrstic)',
                      ),
                    ),
                  if (spremembe)
                    FilledButton.icon(
                      key: ValueKey('$_k-shrani'),
                      onPressed: _delam ? null : _shrani,
                      icon: const Icon(Icons.save),
                      label: Text(_uvod ? 'Shrani uvod' : 'Shrani playback'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
