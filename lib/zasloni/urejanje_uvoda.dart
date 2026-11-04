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

/// Zvočni uvod pesmi pri urejanju: posnemi ali naloži (eno ali drugo, nov zamenja starega),
/// obreži začetek in konec ter poslušaj. Shrani se takoj (potrebuje internet).
class UrejanjeUvoda extends StatefulWidget {
  const UrejanjeUvoda({super.key, required this.baza, required this.api, required this.pesem});

  final Baza baza;
  final Api api;
  final String pesem;

  /// Največja velikost datoteke uvoda.
  static const najvec = 15 * 1024 * 1024;

  @override
  State<UrejanjeUvoda> createState() => _UrejanjeUvodaState();
}

class _UrejanjeUvodaState extends State<UrejanjeUvoda> {
  Uint8List? _bajti;
  String _vrsta = '';
  double? _trajanje;
  RangeValues _obseg = const RangeValues(0, 0);

  /// Nov zvok (posnet ali naložen), ki še ni na strežniku.
  bool _nov = false;
  bool _spremenjenObseg = false;
  bool _delam = false;
  String? _napaka;

  SnemalnikUvoda? _snemalnik;
  DateTime? _zacetek;
  Timer? _ura;

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
    Uvodi.aplikacija.ustavi();
    super.dispose();
  }

  Future<void> _naloziObstojecega() async {
    final p = _pesem;
    if (p == null || p.uvod.isEmpty) return;
    setState(() => _delam = true);
    try {
      final b = await widget.baza.zvokUvoda(widget.api, p);
      if (b != null) await _pripravi(b, p.uvodVrsta, od: p.uvodOd, doo: p.uvodDo);
    } catch (e) {
      _napaka = 'Uvoda ni bilo mogoče prebrati: $e';
    } finally {
      if (mounted) setState(() => _delam = false);
    }
  }

  Future<void> _pripravi(Uint8List bajti, String vrsta, {double od = 0, double? doo}) async {
    final t = await Uvodi.aplikacija.trajanje(bajti, vrsta);
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
      _spremenjenObseg = false;
      await _pripravi(posneto.bajti, posneto.vrsta);
      return;
    }
    await Uvodi.aplikacija.ustavi();
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
    final izbrane = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'webm', 'flac'],
    );
    if (izbrane.isEmpty || !mounted) return;
    final f = izbrane.first;
    final bajti = await f.readAsBytes();
    if (bajti.length > UrejanjeUvoda.najvec) {
      messenger.showSnackBar(const SnackBar(content: Text('Datoteka je prevelika (največ 15 MB).')));
      return;
    }
    _nov = true;
    _spremenjenObseg = false;
    await _pripravi(bajti, vrstaZvoka(f.name));
    if (_trajanje == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Te datoteke ni bilo mogoče prebrati kot zvok.')));
    }
  }

  double? get _doo {
    final t = _trajanje;
    if (t == null || _obseg.end >= t - 0.05) return null;
    return _obseg.end;
  }

  Future<void> _shrani() async {
    final messenger = ScaffoldMessenger.of(context);
    final p = _pesem;
    final bajti = _bajti;
    if (p == null || bajti == null) return;
    await Uvodi.aplikacija.ustavi();
    setState(() => _delam = true);
    try {
      if (_nov) {
        await widget.baza.shraniUvod(widget.api, p.id, bajti, vrsta: _vrsta, od: _obseg.start, doo: _doo);
      } else {
        await widget.baza.shraniPesem(widget.api, {
          'ID': p.id,
          'Koda': p.koda,
          'Naslov': p.naslov,
          'Uvod od': double.parse(_obseg.start.toStringAsFixed(1)),
          'Uvod do': _doo == null ? '' : double.parse(_doo!.toStringAsFixed(1)),
        });
      }
      _nov = false;
      _spremenjenObseg = false;
      messenger.showSnackBar(const SnackBar(content: Text('Uvod je shranjen.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Uvoda ni bilo mogoče shraniti: $e')));
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
        title: const Text('Izbrišem uvod?'),
        content: const Text('Datoteka gre v koš na Drivu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ne')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Izbriši')),
        ],
      ),
    );
    if (da != true) return;
    await Uvodi.aplikacija.ustavi();
    setState(() => _delam = true);
    try {
      if (p.uvod.isNotEmpty) await widget.baza.shraniUvod(widget.api, p.id, null);
      setState(() {
        _bajti = null;
        _trajanje = null;
        _nov = false;
        _spremenjenObseg = false;
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Uvoda ni bilo mogoče izbrisati: $e')));
    } finally {
      if (mounted) setState(() => _delam = false);
    }
  }

  void _poslusaj({bool konec = false}) {
    final b = _bajti;
    if (b == null) return;
    final od = konec ? (_obseg.end - 3).clamp(_obseg.start, _obseg.end).toDouble() : _obseg.start;
    Uvodi.aplikacija.predvajajBajte(b, _vrsta, od: od, doo: _doo);
  }

  @override
  Widget build(BuildContext context) {
    final p = _pesem;
    final t = _trajanje;
    final snemam = _snemalnik != null;
    final imaUvod = (p?.uvod.isNotEmpty ?? false) || _bajti != null;
    final slog = Theme.of(context).textTheme;
    return Card(
      key: const ValueKey('uvod'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hearing),
                const SizedBox(width: 8),
                Text('Uvod', style: slog.titleMedium),
                const Spacer(),
                if (_delam) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              snemam
                  ? 'Snemam … ${casUvoda(DateTime.now().difference(_zacetek!).inMilliseconds / 1000)}'
                  : t != null
                  ? 'Dolžina ${casUvoda(t)}, predvaja se od ${casUvoda(_obseg.start)} do ${casUvoda(_obseg.end)}'
                        '${_nov ? ' · še ni shranjen' : ''}'
                  : imaUvod
                  ? (_napaka ?? 'Nalagam uvod …')
                  : 'Ni uvoda. Posnemi ga ali naloži datoteko; predvaja se ob odprtju pesmi (uho v orodni vrstici).',
              style: slog.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('uvod-snemaj'),
                  onPressed: _delam ? null : _snemaj,
                  icon: Icon(snemam ? Icons.stop : Icons.mic, color: snemam ? Colors.red : null),
                  label: Text(snemam ? 'Ustavi snemanje' : 'Posnemi'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('uvod-nalozi'),
                  onPressed: _delam || snemam ? null : _nalozi,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Naloži datoteko'),
                ),
                if (imaUvod)
                  TextButton.icon(
                    key: const ValueKey('uvod-izbrisi'),
                    onPressed: _delam || snemam ? null : _izbrisi,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Izbriši'),
                  ),
              ],
            ),
            if (t != null && t > 0 && !snemam) ...[
              const SizedBox(height: 8),
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
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('uvod-poslusaj'),
                    onPressed: _poslusaj,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Poslušaj'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _poslusaj(konec: true),
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Konec (zadnje 3 s)'),
                  ),
                  IconButton(tooltip: 'Ustavi', onPressed: Uvodi.aplikacija.ustavi, icon: const Icon(Icons.stop)),
                  if (_nov || _spremenjenObseg)
                    FilledButton.icon(
                      key: const ValueKey('uvod-shrani'),
                      onPressed: _delam ? null : _shrani,
                      icon: const Icon(Icons.save),
                      label: const Text('Shrani uvod'),
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
