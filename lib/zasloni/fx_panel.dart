import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../efekti.dart';
import '../uvodi.dart';
import '../zvok_spila.dart';
import 'midi_zaslon.dart' show PoljeMidi;
import 'urejanje_uvoda.dart' show casUvoda;
import 'xy_pad.dart';

/// Ali sta FX panel (spodnja polovica) in XY pad (zgornja polovica) odprta; ostaneta odprta tudi ob menjavi pesmi.
abstract final class FxPrikaz {
  static final odprt = ValueNotifier(false);
  static final xy = ValueNotifier(false);

  /// Izbrana stran panela (za nožno stikalo FX 1–8 velja ta stran).
  static final stran = ValueNotifier(0);

  /// Urejanje postavitve (samo administrator).
  static final urejam = ValueNotifier(false);
}

/// Gumb FX v orodni vrstici: odpre ali zapre panel; moder, ko kakšen efekt igra.
class FxGumb extends StatelessWidget {
  const FxGumb({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([FxPrikaz.odprt, ZvokSpila.aplikacija, Efekti.aplikacija]),
    builder: (context, _) {
      final barve = Theme.of(context).colorScheme;
      final odprt = FxPrikaz.odprt.value;
      final igra = Efekti.aplikacija.stanje.isNotEmpty || ZvokSpila.aplikacija.igraKakFx;
      return IconButton(
        key: const ValueKey('fx'),
        tooltip: 'FX (efekti in XY pad)',
        isSelected: odprt,
        onPressed: () => FxPrikaz.odprt.value = !odprt,
        icon: Text(
          'FX',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 0.5,
            color: igra ? Colors.blue : (odprt ? barve.primary : null),
          ),
        ),
      );
    },
  );
}

/// Ovoj zaslona: XY pad na zgornji in FX panel na spodnji polovici (besedilo ostane vidno vmes).
class FxOkvir extends StatelessWidget {
  const FxOkvir({super.key, required this.baza, required this.api, this.pesem, required this.child});

  final Baza baza;
  final Api? Function() api;

  /// Odprta pesem (za gumbe, ki veljajo samo pri njej).
  final String? pesem;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([FxPrikaz.odprt, FxPrikaz.xy]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, meje) {
        final polovica = meje.maxHeight / 2;
        return Stack(
          children: [
            Positioned.fill(child: child),
            if (FxPrikaz.xy.value)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: polovica,
                child: _XyPolovica(baza: baza),
              ),
            if (FxPrikaz.odprt.value)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: polovica,
                child: FxPanel(baza: baza, api: api, pesem: pesem),
              ),
          ],
        );
      },
    ),
  );
}

class _XyPolovica extends StatelessWidget {
  const _XyPolovica({required this.baza});

  final Baza baza;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('xy-polovica'),
    elevation: 8,
    color: Theme.of(context).colorScheme.surface,
    child: Stack(
      children: [
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(width: 320, child: XyPad(knjiznica: baza.midi)),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            tooltip: 'Zapri XY pad',
            icon: const Icon(Icons.close),
            onPressed: () => FxPrikaz.xy.value = false,
          ),
        ),
      ],
    ),
  );
}

/// Panel z gumbi efektov, drsnikom glasnosti in gumbom »Ustavi vse«.
class FxPanel extends StatefulWidget {
  const FxPanel({super.key, required this.baza, required this.api, this.pesem});

  final Baza baza;
  final Api? Function() api;
  final String? pesem;

  @override
  State<FxPanel> createState() => _FxPanelState();
}

class _FxPanelState extends State<FxPanel> {
  Timer? _osvezi;

  @override
  void initState() {
    super.initState();
    ZvokSpila.aplikacija.addListener(_obStanju);
    Efekti.aplikacija.addListener(_obStanju);
    widget.baza.addListener(_obStanju);
    _obStanju();
  }

  @override
  void dispose() {
    _osvezi?.cancel();
    ZvokSpila.aplikacija.removeListener(_obStanju);
    Efekti.aplikacija.removeListener(_obStanju);
    widget.baza.removeListener(_obStanju);
    super.dispose();
  }

  /// Med igranjem se črte do konca osvežujejo.
  void _obStanju() {
    if (!mounted) return;
    final igra = widget.baza.fx.gumbi.any((g) => ZvokSpila.aplikacija.stanjeFx(g.id) != null);
    if (igra) {
      _osvezi ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _osvezi?.cancel();
      _osvezi = null;
    }
    setState(() {});
  }

  Future<void> _shrani(PostavitevFx p) async {
    final messenger = ScaffoldMessenger.of(context);
    final api = widget.api();
    if (api == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Za urejanje FX se prijavi (potreben je internet).')));
      return;
    }
    try {
      await widget.baza.shraniFx(api, p);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
    }
  }

  Future<void> _uredi(GumbFx? g, int stran, int mesto) async {
    final rezultat = await showDialog<_Urejeno>(
      context: context,
      builder: (_) => UrejanjeGumbaFx(
        baza: widget.baza,
        api: widget.api,
        gumb: g ?? GumbFx(id: _novId(), stran: stran, mesto: mesto),
        nov: g == null,
        pesem: widget.pesem,
      ),
    );
    if (rezultat == null) return;
    final fx = widget.baza.fx;
    await _shrani(rezultat.izbrisi ? fx.brezGumba(rezultat.gumb.id) : fx.zGumbom(rezultat.gumb));
  }

  static String _novId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  @override
  Widget build(BuildContext context) {
    final fx = widget.baza.fx;
    final tema = Theme.of(context);
    final admin = widget.baza.jeAdministrator;
    final urejam = admin && FxPrikaz.urejam.value;
    final stran = FxPrikaz.stran.value.clamp(0, fx.strani - 1);
    return Material(
      key: const ValueKey('fx-panel'),
      elevation: 12,
      color: tema.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Strani, XY pad, urejanje, zapri.
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (fx.strani > 1 || urejam)
                            for (var i = 0; i < fx.strani; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: ChoiceChip(
                                  key: ValueKey('fx-stran-$i'),
                                  label: Text('${i + 1}'),
                                  selected: i == stran,
                                  onSelected: (_) => setState(() => FxPrikaz.stran.value = i),
                                ),
                              ),
                          if (urejam && fx.strani < PostavitevFx.najvecStrani)
                            IconButton(
                              tooltip: 'Dodaj stran',
                              icon: const Icon(Icons.add),
                              onPressed: () => _shrani(fx.kopija(strani: fx.strani + 1)),
                            ),
                          if (urejam && fx.strani > 1 && !fx.gumbi.any((g) => g.stran == fx.strani - 1))
                            IconButton(
                              tooltip: 'Odstrani zadnjo (prazno) stran',
                              icon: const Icon(Icons.remove),
                              onPressed: () {
                                FxPrikaz.stran.value = 0;
                                _shrani(fx.kopija(strani: fx.strani - 1));
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (fx.xy?.nastavljen ?? false)
                    ValueListenableBuilder(
                      valueListenable: FxPrikaz.xy,
                      builder: (context, xy, _) => IconButton(
                        key: const ValueKey('fx-xy'),
                        tooltip: 'XY pad',
                        isSelected: xy,
                        icon: const Icon(Icons.control_camera),
                        onPressed: () => FxPrikaz.xy.value = !xy,
                      ),
                    ),
                  if (admin)
                    IconButton(
                      key: const ValueKey('fx-uredi'),
                      tooltip: urejam ? 'Končaj urejanje' : 'Uredi gumbe (administrator)',
                      isSelected: urejam,
                      icon: Icon(urejam ? Icons.check : Icons.edit),
                      onPressed: () => setState(() => FxPrikaz.urejam.value = !urejam),
                    ),
                  IconButton(
                    tooltip: 'Zapri FX',
                    icon: const Icon(Icons.close),
                    onPressed: () => FxPrikaz.odprt.value = false,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 4, 4),
                      child: LayoutBuilder(
                        builder: (context, meje) {
                          const razmik = 6.0;
                          final sirina = (meje.maxWidth - razmik * (PostavitevFx.stolpcev - 1)) / PostavitevFx.stolpcev;
                          final visina = (meje.maxHeight - razmik * (PostavitevFx.vrstic - 1)) / PostavitevFx.vrstic;
                          return Wrap(
                            spacing: razmik,
                            runSpacing: razmik,
                            children: [
                              for (var m = 0; m < PostavitevFx.naStran; m++)
                                SizedBox(
                                  width: sirina,
                                  height: math.max(visina, 24),
                                  child: switch (fx.na(stran, m, widget.pesem)) {
                                    final g? => TipkaFx(
                                      key: ValueKey('fx-gumb-${g.id}'),
                                      gumb: g,
                                      urejam: urejam,
                                      onUredi: () => _uredi(g, stran, m),
                                    ),
                                    null when urejam => OutlinedButton(
                                      key: ValueKey('fx-prazno-$stran-$m'),
                                      onPressed: () => _uredi(null, stran, m),
                                      child: const Icon(Icons.add),
                                    ),
                                    null => const SizedBox.shrink(),
                                  },
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  // Glasnost vseh efektov.
                  SizedBox(
                    width: 44,
                    child: Column(
                      children: [
                        const Icon(Icons.volume_up, size: 18),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              key: const ValueKey('fx-glasnost'),
                              value: ZvokSpila.aplikacija.glasnostFx.clamp(0, 1),
                              onChanged: ZvokSpila.aplikacija.fxGlasnost,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (fx.gumbi.isEmpty && !urejam)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  admin
                      ? 'Še ni gumbov. Pritisni svinčnik zgoraj in dodaj gumbe (efekte dodaš v Nastavitve → Efekti).'
                      : 'Še ni gumbov. Doda jih administrator.',
                  style: tema.textTheme.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('fx-ustavi-vse'),
                  style: FilledButton.styleFrom(backgroundColor: tema.colorScheme.error),
                  onPressed: ZvokSpila.aplikacija.fxUstaviVse,
                  icon: const Icon(Icons.stop),
                  label: const Text('Ustavi vse'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gumb efekta: barva in ime; med igranjem utripa in kaže črto do konca.
class TipkaFx extends StatefulWidget {
  const TipkaFx({super.key, required this.gumb, this.urejam = false, this.onUredi});

  final GumbFx gumb;
  final bool urejam;
  final VoidCallback? onUredi;

  @override
  State<TipkaFx> createState() => _TipkaFxState();
}

class _TipkaFxState extends State<TipkaFx> with SingleTickerProviderStateMixin {
  late final _utrip = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  bool _drzim = false;

  @override
  void dispose() {
    _utrip.dispose();
    super.dispose();
  }

  void _dol() {
    final g = widget.gumb;
    setState(() => _drzim = true);
    ZvokSpila.aplikacija.fx(g.id, dol: true);
    if (g.xy) FxPrikaz.xy.value = !FxPrikaz.xy.value;
  }

  void _gor() {
    if (!_drzim) return;
    setState(() => _drzim = false);
    if (widget.gumb.nacin == NacinFx.medPritiskom) ZvokSpila.aplikacija.fx(widget.gumb.id, dol: false);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gumb;
    final stanje = ZvokSpila.aplikacija.stanjeFx(g.id);
    final igra = stanje != null;
    if (igra && !_utrip.isAnimating) {
      _utrip.repeat(reverse: true);
    } else if (!igra && _utrip.isAnimating) {
      _utrip
        ..stop()
        ..value = 0;
    }
    final barva = Color(g.barva);
    final temna = ThemeData.estimateBrightnessForColor(barva) == Brightness.dark;
    final napredek = stanje == null || stanje.trajanje <= Duration.zero
        ? null
        : (stanje.pozicija.inMilliseconds / stanje.trajanje.inMilliseconds).clamp(0.0, 1.0);
    final vsebina = AnimatedBuilder(
      animation: _utrip,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(barva, Colors.white, igra ? 0.35 * _utrip.value : 0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: igra || _drzim ? Colors.white : Colors.transparent, width: igra ? 3 : 2),
          boxShadow: igra ? [BoxShadow(color: barva.withValues(alpha: 0.7), blurRadius: 10 + 6 * _utrip.value)] : null,
        ),
        child: child,
      ),
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.urejam) Icon(Icons.edit, size: 14, color: temna ? Colors.white70 : Colors.black54),
                  if (g.xy) Icon(Icons.control_camera, size: 14, color: temna ? Colors.white70 : Colors.black54),
                  if (g.pesem.isNotEmpty)
                    Icon(Icons.music_note, size: 14, color: temna ? Colors.white70 : Colors.black54),
                  Flexible(
                    child: Text(
                      g.ime.isEmpty ? '—' : g.ime,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold, color: temna ? Colors.white : Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (napredek != null)
            Positioned(
              left: 6,
              right: 6,
              bottom: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  key: ValueKey('fx-crta-${g.id}'),
                  value: napredek,
                  minHeight: 4,
                  color: temna ? Colors.white : Colors.black87,
                  backgroundColor: (temna ? Colors.white : Colors.black).withValues(alpha: 0.2),
                ),
              ),
            ),
        ],
      ),
    );
    if (widget.urejam) {
      return GestureDetector(onTap: widget.onUredi, child: vsebina);
    }
    // Listener: pritisk in spust takoj (brez zamika zaradi dvojnega dotika), za »med pritiskom«.
    return Listener(
      onPointerDown: (_) => _dol(),
      onPointerUp: (_) => _gor(),
      onPointerCancel: (_) => _gor(),
      child: vsebina,
    );
  }
}

/// Rezultat urejanja gumba.
typedef _Urejeno = ({GumbFx gumb, bool izbrisi});

/// Barve za gumbe.
const barveFx = [
  0xFF1E88E5,
  0xFF43A047,
  0xFFE53935,
  0xFFFB8C00,
  0xFF8E24AA,
  0xFF00ACC1,
  0xFFFDD835,
  0xFF6D4C41,
  0xFF546E7A,
  0xFFD81B60,
];

/// Urejanje gumba FX (administrator).
class UrejanjeGumbaFx extends StatefulWidget {
  const UrejanjeGumbaFx({
    super.key,
    required this.baza,
    required this.api,
    required this.gumb,
    this.nov = false,
    this.pesem,
  });

  final Baza baza;
  final Api? Function() api;
  final GumbFx gumb;
  final bool nov;
  final String? pesem;

  @override
  State<UrejanjeGumbaFx> createState() => _UrejanjeGumbaFxState();
}

class _UrejanjeGumbaFxState extends State<UrejanjeGumbaFx> {
  late GumbFx _g = widget.gumb;
  late final _ime = TextEditingController(text: widget.gumb.ime);
  late final _ukazi = TextEditingController(text: widget.gumb.ukazi);
  PredvajalnikZvoka? _poslusanje;
  StreamSubscription<Duration>? _poz;
  double? _trajanje;
  bool _nalagam = false;
  String? _napaka;

  @override
  void initState() {
    super.initState();
    if (_g.imaZvok) _naloziTrajanje();
  }

  @override
  void dispose() {
    _poz?.cancel();
    _poslusanje?.ustavi();
    _poslusanje?.zapri();
    _ime.dispose();
    _ukazi.dispose();
    super.dispose();
  }

  void _spremeni(GumbFx Function(Map<String, dynamic> j) f) => setState(() => _g = f(_g.vJson()));

  GumbFx _z(Map<String, dynamic> j) => GumbFx.izJson(j);

  Future<void> _naloziTrajanje() async {
    setState(() {
      _nalagam = true;
      _napaka = null;
      _trajanje = null;
    });
    try {
      final b = await widget.baza.bajtiEfekta(widget.api(), _g.efekt);
      if (b == null) throw StateError('ni na voljo brez interneta');
      final p = _poslusanje ??= PredvajalnikZvoka.tovarna();
      final d = await p.odpri(b.bajti, b.vrsta);
      if (!mounted) return;
      setState(() => _trajanje = d == null ? null : d.inMilliseconds / 1000);
    } catch (e) {
      if (mounted) setState(() => _napaka = 'Efekta ni bilo mogoče prebrati: $e');
    } finally {
      if (mounted) setState(() => _nalagam = false);
    }
  }

  Future<void> _poslusaj() async {
    final p = _poslusanje;
    final t = _trajanje;
    if (p == null || t == null) return;
    final konec = Duration(milliseconds: ((_g.doo ?? t) * 1000).round());
    await _poz?.cancel();
    _poz = p.pozicija.listen((pos) {
      if (pos >= konec) p.ustavi();
    });
    await p.glasnost(_g.glasnost);
    await p.predvajaj(Duration(milliseconds: (_g.od * 1000).round()));
  }

  @override
  Widget build(BuildContext context) {
    final efekti = widget.baza.efekti;
    final t = _trajanje;
    final od = _g.od;
    final doo = _g.doo ?? t ?? 0;
    return AlertDialog(
      title: Text(widget.nov ? 'Nov gumb FX' : 'Gumb FX'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('fx-ime'),
                controller: _ime,
                autofocus: widget.nov,
                decoration: const InputDecoration(labelText: 'Ime gumba'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final b in barveFx)
                    InkWell(
                      onTap: () => _spremeni((j) => _z({...j, 'barva': b})),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Color(b),
                        child: b == _g.barva ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('fx-efekt'),
                initialValue: efekti.any((e) => e.id == _g.efekt) ? _g.efekt : '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Zvočni efekt'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Brez zvoka (samo MIDI ali XY)')),
                  for (final e in efekti) DropdownMenuItem(value: e.id, child: Text(e.ime)),
                ],
                onChanged: (v) {
                  _spremeni((j) => _z({...j, 'efekt': v ?? '', 'od': 0, 'do': null}));
                  if ((v ?? '').isNotEmpty) _naloziTrajanje();
                },
              ),
              if (efekti.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Knjižnica je prazna. Efekte dodaš v Nastavitve → Efekti.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (_g.imaZvok) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<NacinFx>(
                  key: const ValueKey('fx-nacin'),
                  initialValue: _g.nacin,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Pritisk'),
                  items: [for (final n in NacinFx.values) DropdownMenuItem(value: n, child: Text(n.opis))],
                  onChanged: (v) => _spremeni((j) => _z({...j, 'nacin': (v ?? NacinFx.enkratno).name})),
                ),
                if (_g.nacin == NacinFx.enkratno)
                  DropdownButtonFormField<PonovnoFx>(
                    key: const ValueKey('fx-ponovno'),
                    initialValue: _g.ponovno,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Ponoven pritisk med igranjem'),
                    items: [for (final n in PonovnoFx.values) DropdownMenuItem(value: n, child: Text(n.opis))],
                    onChanged: (v) => _spremeni((j) => _z({...j, 'ponovno': (v ?? PonovnoFx.odZacetka).name})),
                  ),
                SwitchListTile(
                  key: const ValueKey('fx-zanka'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('V zanki (ponavlja, dokler ga ne ustaviš)'),
                  value: _g.zanka,
                  onChanged: (v) => _spremeni((j) => _z({...j, 'zanka': v})),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _Fade(
                        oznaka: 'Fade in',
                        ms: _g.fadeIn,
                        onChanged: (v) => _spremeni((j) => _z({...j, 'fadeIn': v})),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Fade(
                        oznaka: 'Fade out',
                        ms: _g.fadeOut,
                        onChanged: (v) => _spremeni((j) => _z({...j, 'fadeOut': v})),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Glasnost'),
                    Expanded(
                      child: Slider(
                        value: _g.glasnost,
                        divisions: 20,
                        label: '${(_g.glasnost * 100).round()} %',
                        onChanged: (v) => _spremeni((j) => _z({...j, 'glasnost': v})),
                      ),
                    ),
                  ],
                ),
                if (_nalagam) const LinearProgressIndicator(),
                if (_napaka case final n?) Text(n, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                if (t != null && t > 0) ...[
                  Text('Obrezovanje: ${casUvoda(od)} – ${casUvoda(doo)} (od ${casUvoda(t)})'),
                  RangeSlider(
                    key: const ValueKey('fx-obseg'),
                    values: RangeValues(od.clamp(0, t), doo.clamp(0, t)),
                    max: t,
                    onChanged: (v) =>
                        _spremeni((j) => _z({...j, 'od': v.start, 'do': v.end >= t - 0.05 ? null : v.end})),
                  ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _poslusaj,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Poslušaj'),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Ustavi',
                        onPressed: () => _poslusanje?.ustavi(),
                        icon: const Icon(Icons.stop),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 12),
              PoljeMidi(
                oznaka: 'MIDI ukazi ali makri ob pritisku',
                vnos: _ukazi,
                knjiznica: widget.baza.midi,
                pomoc: 'Pošlje jih naprava z efekti (PC), če ima vklopljen MIDI.',
              ),
              SwitchListTile(
                key: const ValueKey('fx-odpre-xy'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Odpre XY pad (zgornja polovica)'),
                value: _g.xy,
                onChanged: (v) => _spremeni((j) => _z({...j, 'xy': v})),
              ),
              if (widget.pesem != null)
                SwitchListTile(
                  key: const ValueKey('fx-samo-pesem'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Samo pri tej pesmi'),
                  subtitle: const Text('Pri tej pesmi zamenja splošni gumb na istem mestu.'),
                  value: _g.pesem.isNotEmpty,
                  onChanged: (v) => _spremeni((j) => _z({...j, 'pesem': v ? widget.pesem : ''})),
                ),
              if (_g.imaZvok)
                SwitchListTile(
                  key: const ValueKey('fx-ob-menjavi'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ob zamenjavi pesmi ustavi'),
                  subtitle: const Text('Sicer igra naprej, dokler ga ne ustaviš.'),
                  value: _g.ustaviObMenjavi,
                  onChanged: (v) => _spremeni((j) => _z({...j, 'ustaviObMenjavi': v})),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (!widget.nov)
          TextButton(
            key: const ValueKey('fx-izbrisi'),
            onPressed: () => Navigator.pop<_Urejeno>(context, (gumb: _g, izbrisi: true)),
            child: Text('Izbriši', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
        FilledButton(
          key: const ValueKey('fx-shrani'),
          onPressed: () {
            final g = _z({..._g.vJson(), 'ime': _ime.text.trim(), 'ukazi': _ukazi.text.trim()});
            Navigator.pop<_Urejeno>(context, (gumb: g, izbrisi: false));
          },
          child: const Text('Shrani'),
        ),
      ],
    );
  }
}

class _Fade extends StatelessWidget {
  const _Fade({required this.oznaka, required this.ms, required this.onChanged});

  final String oznaka;
  final int ms;
  final ValueChanged<int> onChanged;

  static const _moznosti = [0, 100, 250, 500, 1000, 2000, 3000, 5000];

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    initialValue: _moznosti.contains(ms) ? ms : 0,
    decoration: InputDecoration(labelText: oznaka),
    items: [
      for (final m in _moznosti)
        DropdownMenuItem(value: m, child: Text(m == 0 ? 'brez' : '${(m / 1000).toString().replaceAll('.', ',')} s')),
    ],
    onChanged: (v) => onChanged(v ?? 0),
  );
}
