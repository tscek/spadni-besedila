import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../baza.dart';
import '../config.dart';
import '../models.dart';
import '../runda.dart' show casBesedilo;
import '../zvocnik.dart';
import '../snemalnik_web.dart' if (dart.library.io) '../snemalnik_io.dart' as datoteka;

/// Posnet zvok: bajti, MIME vrsta in dolžina.
typedef Posneto = ({Uint8List bajti, String vrsta, int sekund});

/// Snemalnik zvoka (v testih ga zamenja ponaredek).
abstract class Snemalnik {
  static Snemalnik Function() tovarna = SnemalnikRecord.new;

  Future<bool> dovoljenje();
  Future<void> zacni();

  /// Konča snemanje in vrne posnetek (null, če ni nič posneto).
  Future<Posneto?> ustavi();
  Future<void> prekini();
  Future<void> zapri();
}

/// Majhne datoteke: AAC (m4a) mono z nizko bitno hitrostjo, v brskalniku brez AAC pa Opus (webm).
/// MP3 snemalniki na napravah ne znajo, AAC pa je pri enaki velikosti boljši od MP3.
class SnemalnikRecord implements Snemalnik {
  final _r = AudioRecorder();
  final _ura = Stopwatch();
  String _vrsta = 'audio/mp4';

  @override
  Future<bool> dovoljenje() => _r.hasPermission();

  @override
  Future<void> zacni() async {
    final windows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    var enc = AudioEncoder.aacLc;
    if (kIsWeb && !await _r.isEncoderSupported(AudioEncoder.aacLc)) {
      enc = await _r.isEncoderSupported(AudioEncoder.opus) ? AudioEncoder.opus : AudioEncoder.wav;
    }
    _vrsta = switch (enc) {
      AudioEncoder.opus => 'audio/webm',
      AudioEncoder.wav => 'audio/wav',
      _ => 'audio/mp4',
    };
    final koncnica = switch (enc) {
      AudioEncoder.opus => 'webm',
      AudioEncoder.wav => 'wav',
      _ => 'm4a',
    };
    await _r.start(
      RecordConfig(
        encoder: enc,
        numChannels: 1,
        // Windows (Media Foundation) AAC zna le 44,1/48 kHz in vsaj 96 kbit/s.
        sampleRate: windows ? 44100 : 22050,
        bitRate: windows ? 96000 : 32000,
      ),
      path: await datoteka.potZaPosnetek(koncnica),
    );
    _ura
      ..reset()
      ..start();
  }

  @override
  Future<Posneto?> ustavi() async {
    _ura.stop();
    final pot = await _r.stop();
    if (pot == null) return null;
    final bajti = await datoteka.preberiPosnetek(pot);
    if (bajti.isEmpty) return null;
    return (bajti: bajti, vrsta: _vrsta, sekund: _ura.elapsed.inSeconds);
  }

  @override
  Future<void> prekini() async {
    _ura.stop();
    await _r.cancel();
  }

  @override
  Future<void> zapri() => _r.dispose();
}

/// Okno s posnetki pesmi: snemanje (osebno ali skupno) in poslušanje.
Future<void> oknoPosnetkov(
  BuildContext context, {
  required Baza baza,
  required Api? api,
  required String pesem,
  bool skupno = false,
}) {
  if (Config.prekoVodje) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Posnetki prek vodje niso na voljo. Odpri spletno različico ali aplikacijo.')),
    );
    return Future.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => OknoPosnetkov(baza: baza, api: api, pesem: pesem, skupno: skupno),
  );
}

class OknoPosnetkov extends StatefulWidget {
  const OknoPosnetkov({super.key, required this.baza, required this.api, required this.pesem, this.skupno = false});

  final Baza baza;
  final Api? api;
  final String pesem;
  final bool skupno;

  @override
  State<OknoPosnetkov> createState() => _OknoPosnetkovState();
}

class _OknoPosnetkovState extends State<OknoPosnetkov> {
  late bool _skupno = widget.skupno;
  Snemalnik? _snemalnik;
  bool _snemam = false;
  bool _shranjujem = false;
  DateTime? _zacetek;
  Timer? _ura;

  final _zvocnik = Zvocnik.tovarna();
  bool _naroceno = false;

  /// Posnetki, katerih zvok se pripravlja, in tisti, ki niso dostopni (brez prijave ali interneta).
  final _pripravljam = <String>{};
  final _niDostopa = <String>{};
  String? _predvajam;
  Duration _pozicija = Duration.zero;
  Duration _trajanje = Duration.zero;
  bool _pavza = false;
  _Zanka _zanka = _Zanka.brez;
  Duration? _a;
  Duration? _b;
  double _hitrost = 1;
  final _narocnine = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _pripraviVse();
  }

  @override
  void dispose() {
    _ura?.cancel();
    final s = _snemalnik;
    if (s != null) {
      if (_snemam) s.prekini();
      s.zapri();
    }
    for (final n in _narocnine) {
      n.cancel();
    }
    _zvocnik.zapri();
    super.dispose();
  }

  void _sporoci(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _snemaj() async {
    await _ustaviPredvajanje();
    final s = _snemalnik ??= Snemalnik.tovarna();
    try {
      if (!await s.dovoljenje()) {
        _sporoci('Aplikacija nima dovoljenja za mikrofon.');
        return;
      }
      await s.zacni();
    } catch (e) {
      _sporoci('Snemanja ni bilo mogoče začeti: $e');
      return;
    }
    setState(() {
      _snemam = true;
      _zacetek = DateTime.now();
    });
    _ura = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  Future<void> _ustavi({bool shrani = true}) async {
    _ura?.cancel();
    final s = _snemalnik!;
    setState(() {
      _snemam = false;
      _shranjujem = shrani;
    });
    try {
      if (!shrani) return await s.prekini();
      final p = await s.ustavi();
      if (p == null) return _sporoci('Nič ni bilo posneto.');
      final t = DateTime.now();
      final ime = await _vprasajIme(
        'Posnetek ${t.day}. ${t.month}. ${t.hour}:${t.minute.toString().padLeft(2, '0')}',
        zavrzi: true,
      );
      if (ime == null) return;
      await widget.baza.dodajPosnetek(
        widget.api,
        widget.pesem,
        p.bajti,
        skupno: _skupno,
        ime: ime,
        vrsta: p.vrsta,
        trajanje: p.sekund,
      );
    } catch (e) {
      _sporoci('Posnetka ni bilo mogoče shraniti: $e');
    } finally {
      if (mounted) setState(() => _shranjujem = false);
    }
  }

  /// Naslov posnetka (privzeti je predlagan); null = zavrzi ali prekliči.
  Future<String?> _vprasajIme(String privzeto, {bool zavrzi = false}) async {
    final c = TextEditingController(text: privzeto)
      ..selection = TextSelection(baseOffset: 0, extentOffset: privzeto.length);
    final ime = await showDialog<String>(
      context: context,
      barrierDismissible: !zavrzi,
      builder: (context) => AlertDialog(
        title: const Text('Naslov posnetka'),
        content: TextField(
          key: const ValueKey('naslov-posnetka'),
          controller: c,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(zavrzi ? 'Zavrzi' : 'Prekliči')),
          FilledButton(
            key: const ValueKey('shrani-posnetek'),
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Shrani'),
          ),
        ],
      ),
    );
    c.dispose();
    if (ime == null) return null;
    return ime.trim().isEmpty ? privzeto : ime.trim();
  }

  Future<void> _preimenuj(PosnetekPesmi p) async {
    final ime = await _vprasajIme(p.ime.isEmpty ? 'Posnetek' : p.ime);
    if (ime == null || ime == p.ime) return;
    await widget.baza.preimenujPosnetek(widget.api, p.id, ime);
  }

  Future<void> _ustaviPredvajanje() async {
    if (_predvajam != null) await _zvocnik.ustavi();
    if (mounted) setState(() => _predvajam = null);
  }

  Future<void> _premakni(Duration d) async {
    if (_predvajam == null) return;
    var t = d < Duration.zero ? Duration.zero : d;
    if (_trajanje > Duration.zero && t > _trajanje) t = _trajanje;
    await _zvocnik.premakni(t);
    if (mounted) setState(() => _pozicija = t);
  }

  Future<void> _pavzaNadaljuj() async {
    if (_predvajam == null) return;
    if (_pavza) {
      await _zvocnik.nadaljuj();
    } else {
      await _zvocnik.pavza();
    }
    if (mounted) setState(() => _pavza = !_pavza);
  }

  Future<void> _nastaviZanko(_Zanka z) async {
    if (_predvajam != null) await _zvocnik.zanka(z != _Zanka.brez);
    setState(() => _zanka = z);
  }

  void _obPoziciji(Duration d) {
    if (!mounted) return;
    setState(() => _pozicija = d);
    // Ponavljanje odseka A–B (za vadbo težavnega dela).
    if (_zanka == _Zanka.odsek && _a != null && _b != null && d >= _b!) _zvocnik.premakni(_a!);
  }

  /// Vnaprej pripravi zvok vseh posnetkov pesmi (so majhni), da predvajanje steče takoj ob dotiku.
  Future<void> _pripraviVse() async {
    final posnetki = widget.baza.posnetki[widget.pesem] ?? const <PosnetekPesmi>[];
    for (final p in posnetki) {
      if (!mounted) return;
      if (_zvocnik.pripravljen(p.id) || _pripravljam.contains(p.id) || _niDostopa.contains(p.id)) continue;
      setState(() => _pripravljam.add(p.id));
      try {
        final bajti = await widget.baza.zvokPosnetka(widget.api, p);
        if (bajti == null) {
          _niDostopa.add(p.id);
        } else {
          _zvocnik.pripravi(p.id, bajti, p.vrsta);
        }
      } catch (_) {
        _niDostopa.add(p.id);
      } finally {
        if (mounted) setState(() => _pripravljam.remove(p.id));
      }
    }
  }

  void _predvajaj(PosnetekPesmi p) {
    if (_predvajam == p.id) {
      _ustaviPredvajanje();
      return;
    }
    if (!_zvocnik.pripravljen(p.id)) {
      if (_niDostopa.remove(p.id)) _pripraviVse();
      if (!_pripravljam.contains(p.id) && !_zvocnik.pripravljen(p.id)) {
        _sporoci('Posnetek je dostopen šele s prijavo in internetom.');
      }
      return;
    }
    _naroci();
    // Predvajanje se začne takoj, brez čakanja pred tem (zahteva Safarija na iPadu).
    final zacetek = _zvocnik.predvajaj(p.id, zanka: _zanka == _Zanka.ves, hitrost: _hitrost);
    setState(() {
      _predvajam = p.id;
      _pozicija = Duration.zero;
      _trajanje = Duration(seconds: p.trajanje);
      _pavza = false;
      _a = null;
      _b = null;
      if (_zanka == _Zanka.odsek) _zanka = _Zanka.brez;
    });
    zacetek.catchError((Object e) {
      if (!mounted) return;
      setState(() => _predvajam = null);
      _sporoci('Predvajanje ni uspelo: $e');
    });
  }

  void _naroci() {
    if (_naroceno) return;
    _naroceno = true;
    _narocnine
      ..add(_zvocnik.pozicija.listen(_obPoziciji))
      ..add(_zvocnik.trajanje.listen((d) => mounted && d > Duration.zero ? setState(() => _trajanje = d) : null))
      ..add(_zvocnik.konec.listen((_) => mounted && _zanka == _Zanka.brez ? setState(() => _predvajam = null) : null));
  }

  Future<void> _izbrisi(PosnetekPesmi p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izbriši posnetek?'),
        content: Text(p.ime),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Prekliči')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Izbriši')),
        ],
      ),
    );
    if (ok != true) return;
    if (_predvajam == p.id) await _ustaviPredvajanje();
    await widget.baza.izbrisiPosnetek(widget.api, p.id);
  }

  @override
  Widget build(BuildContext context) {
    final barve = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.baza,
      builder: (context, _) {
        final posnetki = widget.baza.posnetki[widget.pesem] ?? const <PosnetekPesmi>[];
        if (posnetki.any(
          (p) => !_zvocnik.pripravljen(p.id) && !_pripravljam.contains(p.id) && !_niDostopa.contains(p.id),
        )) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _pripraviVse());
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Posnetki', style: Theme.of(context).textTheme.titleLarge)),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: false, icon: Icon(Icons.person_outline), label: Text('Osebno')),
                        ButtonSegment(value: true, icon: Icon(Icons.groups_outlined), label: Text('Skupno')),
                      ],
                      selected: {_skupno},
                      onSelectionChanged: _snemam ? null : (v) => setState(() => _skupno = v.first),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_snemam)
                  Row(
                    children: [
                      const Icon(Icons.fiber_manual_record, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(
                        casBesedilo(DateTime.now().difference(_zacetek!)),
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      const Spacer(),
                      TextButton(onPressed: () => _ustavi(shrani: false), child: const Text('Zavrzi')),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const ValueKey('ustavi-snemanje'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: _ustavi,
                        icon: const Icon(Icons.stop),
                        label: const Text('Ustavi in shrani'),
                      ),
                    ],
                  )
                else
                  FilledButton.icon(
                    key: const ValueKey('snemaj'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(52)),
                    onPressed: _shranjujem ? null : _snemaj,
                    icon: _shranjujem
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.mic),
                    label: Text(_skupno ? 'Snemaj skupni posnetek' : 'Snemaj osebni posnetek'),
                  ),
                const SizedBox(height: 8),
                if (posnetki.where((p) => p.id == _predvajam).firstOrNull case final p?) _predvajalnikPanel(context, p),
                if (posnetki.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Pesem še nima posnetkov.', textAlign: TextAlign.center),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in posnetki)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: IconButton(
                              tooltip: _predvajam == p.id ? 'Ustavi' : 'Predvajaj',
                              icon: _pripravljam.contains(p.id)
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Icon(_predvajam == p.id ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                              iconSize: 32,
                              color: barve.primary,
                              onPressed: () => _predvajaj(p),
                            ),
                            title: Row(
                              children: [
                                Icon(p.skupno ? Icons.groups_outlined : Icons.person_outline, size: 16),
                                const SizedBox(width: 4),
                                Expanded(child: Text(p.ime.isEmpty ? 'Posnetek' : p.ime)),
                              ],
                            ),
                            subtitle: Text(
                              [
                                if (_predvajam == p.id)
                                  '${casBesedilo(_pozicija)} / ${casBesedilo(Duration(seconds: p.trajanje))}'
                                else
                                  casBesedilo(Duration(seconds: p.trajanje)),
                                if (p.velikostKb > 0) '${p.velikostKb} KB',
                                if (p.clan.isNotEmpty) 'Posnel: ${widget.baza.imeClanaZ(p.clan)}',
                                if (p.driveId.isEmpty) 'čaka na pošiljanje',
                              ].join(' · '),
                            ),
                            trailing: widget.baza.smeIzbrisatiPosnetek(p)
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Popravi naslov',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _preimenuj(p),
                                      ),
                                      IconButton(
                                        tooltip: 'Izbriši',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _izbrisi(p),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
                _igranja(context),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Kdaj je bila pesem igrana na špilih, s povezavo na YouTube na pravem mestu (ko je video narejen).
  Widget _igranja(BuildContext context) {
    final igranja = widget.baza.igranja[widget.pesem] ?? const <Igranje>[];
    if (igranja.isEmpty) return const SizedBox.shrink();
    final tema = Theme.of(context);
    String dv(int x) => x.toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Text('Igrana na špilih (${igranja.length})', style: tema.textTheme.titleMedium),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final ig in igranja)
                () {
                  final c = ig.cas.toLocal();
                  final sn = widget.baza.snemanjeOb(ig.cas);
                  final povezava = sn?.povezava(ig.cas);
                  return ListTile(
                    key: ValueKey('igranje-${ig.cas.toIso8601String()}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.event_note, color: tema.colorScheme.primary),
                    title: Text('${c.day}. ${c.month}. ${c.year} ob ${c.hour}:${dv(c.minute)}'),
                    subtitle: sn == null
                        ? null
                        : Text(povezava == null ? '${sn.naslov} · video še ni narejen' : sn.naslov),
                    trailing: povezava == null
                        ? null
                        : IconButton(
                            tooltip: 'Odpri na YouTubu',
                            icon: const Icon(Icons.smart_display_outlined, color: Colors.red),
                            onPressed: () => launchUrl(Uri.parse(povezava), mode: LaunchMode.externalApplication),
                          ),
                  );
                }(),
            ],
          ),
        ),
      ],
    );
  }

  /// Predvajalnik: drsnik, nazaj/naprej za 10 s, ponavljanje (vse ali odsek A–B) in hitrost.
  Widget _predvajalnikPanel(BuildContext context, PosnetekPesmi p) {
    final barve = Theme.of(context).colorScheme;
    final skupaj = _trajanje > Duration.zero ? _trajanje : const Duration(seconds: 1);
    final poz = _pozicija > skupaj ? skupaj : _pozicija;
    String oznakaAB(Duration? d, String crka) => d == null ? crka : '$crka ${casBesedilo(d)}';
    return Card(
      key: const ValueKey('predvajalnik'),
      color: barve.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.ime.isEmpty ? 'Posnetek' : p.ime, style: Theme.of(context).textTheme.titleSmall),
            Row(
              children: [
                Text(casBesedilo(poz)),
                Expanded(
                  child: Slider(
                    value: poz.inMilliseconds.toDouble(),
                    max: skupaj.inMilliseconds.toDouble(),
                    onChanged: (v) => _premakni(Duration(milliseconds: v.round())),
                  ),
                ),
                Text(casBesedilo(_trajanje)),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Nazaj 10 s',
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => _premakni(_pozicija - const Duration(seconds: 10)),
                ),
                IconButton.filled(
                  tooltip: _pavza ? 'Nadaljuj' : 'Pavza',
                  icon: Icon(_pavza ? Icons.play_arrow : Icons.pause),
                  onPressed: _pavzaNadaljuj,
                ),
                IconButton(
                  tooltip: 'Naprej 10 s',
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => _premakni(_pozicija + const Duration(seconds: 10)),
                ),
                IconButton(
                  tooltip: switch (_zanka) {
                    _Zanka.brez => 'Ponavljaj ves posnetek',
                    _Zanka.ves => _a != null && _b != null ? 'Ponavljaj odsek A–B' : 'Brez ponavljanja',
                    _Zanka.odsek => 'Brez ponavljanja',
                  },
                  isSelected: _zanka != _Zanka.brez,
                  icon: Icon(_zanka == _Zanka.odsek ? Icons.repeat_one : Icons.repeat),
                  onPressed: () => _nastaviZanko(switch (_zanka) {
                    _Zanka.brez => _Zanka.ves,
                    _Zanka.ves => _a != null && _b != null ? _Zanka.odsek : _Zanka.brez,
                    _Zanka.odsek => _Zanka.brez,
                  }),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _a = _pozicija;
                    if (_b != null && _b! <= _a!) _b = null;
                  }),
                  child: Text(oznakaAB(_a, 'A')),
                ),
                TextButton(
                  onPressed: () {
                    if (_a == null || _pozicija <= _a!) return;
                    setState(() => _b = _pozicija);
                    _nastaviZanko(_Zanka.odsek);
                  },
                  child: Text(oznakaAB(_b, 'B')),
                ),
                PopupMenuButton<double>(
                  tooltip: 'Hitrost',
                  initialValue: _hitrost,
                  onSelected: (h) {
                    setState(() => _hitrost = h);
                    if (_predvajam != null) _zvocnik.hitrost(h);
                  },
                  itemBuilder: (_) => [
                    for (final h in const [0.5, 0.75, 1.0, 1.25]) PopupMenuItem(value: h, child: Text('$h×')),
                  ],
                  child: Padding(padding: const EdgeInsets.all(8), child: Text('$_hitrost×')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ponavljanje v predvajalniku posnetkov.
enum _Zanka { brez, ves, odsek }
