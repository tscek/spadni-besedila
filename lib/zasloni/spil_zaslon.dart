import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../baza.dart';
import '../config.dart';
import '../models.dart';
import '../nastavitve.dart';
import '../prijava.dart';
import '../spil/spil.dart';
import 'nadzorna_plosca.dart';
import 'naslednje.dart';
import 'pesem_zaslon.dart';
import 'urejanje_pesmi.dart';

/// Kaj naprava naredi ob zagonu aplikacije.
enum PrivzetaVloga { sama, vodja, sledilec }

const _kljucVloge = 'vloga_naprave';
const _kljucVodje = 'zadnji_vodja';

Future<PrivzetaVloga> privzetaVloga() async {
  final v = (await SharedPreferences.getInstance()).getString(_kljucVloge);
  return PrivzetaVloga.values.where((x) => x.name == v).firstOrNull ?? PrivzetaVloga.sama;
}

/// Ob zagonu: vodja začne voditi, sledilec poišče vodjo in se poveže.
Future<void> zacniPrivzetoVlogo(Spil spil, Baza baza) async {
  if (kIsWeb) return;
  final prefs = await SharedPreferences.getInstance();
  switch (await privzetaVloga()) {
    case PrivzetaVloga.vodja when baza.smeVoditi && spil.lahkoVodi:
      await spil.zacniVoditi(baza);
    case PrivzetaVloga.sledilec:
      spil.samodejnoSledi(zadnji: naslovWebSocket(prefs.getString(_kljucVodje) ?? ''));
    default:
  }
}

const _kljucClana = 'jaz_clan';

/// iPad prek vodje: kateri član je na tej napravi (shranjeno v brskalniku za naslov vodje).
Future<String?> clanNaSpilu() async => (await SharedPreferences.getInstance()).getString(_kljucClana);

/// Klici na vodjo v imenu člana (brez Google prijave).
Api apiNaSpilu(String? clan) => Api(() async => '', clan: clan);

/// iPad prek vodje: vpraša, kdo je, in od vodje prenese njegove risbe.
Future<void> izberiClana(BuildContext context, Baza baza) async {
  final clani = baza.clani;
  if (clani.isEmpty) return;
  final id = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Kdo igra na tem iPadu?'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Tako vidiš svoje opombe in risbe.'),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in clani)
                    GumbClana(ime: c.ime, slika: baza.slikeClanov[c.id], onPressed: () => Navigator.pop(context, c.id)),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (id == null) return;
  await (await SharedPreferences.getInstance()).setString(_kljucClana, id);
  final api = apiNaSpilu(id);
  baza.risbe.api = api;
  try {
    await baza.risbe.sinhroniziraj(api);
  } catch (_) {
    // vodja ni dosegljiv: risbe se prenesejo ob naslednjem odprtju
  }
}

/// Ob prvem odprtju prek vodje (ko so člani znani) vpraša, kdo je na iPadu.
class ZahtevajClana extends StatefulWidget {
  const ZahtevajClana({super.key, required this.baza, required this.child});

  final Baza baza;
  final Widget child;

  @override
  State<ZahtevajClana> createState() => _ZahtevajClanaState();
}

class _ZahtevajClanaState extends State<ZahtevajClana> {
  bool _vprasano = false;

  @override
  void initState() {
    super.initState();
    widget.baza.addListener(_preveri);
    WidgetsBinding.instance.addPostFrameCallback((_) => _preveri());
  }

  @override
  void dispose() {
    widget.baza.removeListener(_preveri);
    super.dispose();
  }

  Future<void> _preveri() async {
    if (_vprasano || widget.baza.clani.isEmpty) return;
    _vprasano = true;
    if (await clanNaSpilu() != null || !mounted) return;
    await izberiClana(context, widget.baza);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Gumb v zgornji vrstici vseh zaslonov: pokaže stanje špila in odpre nastavitve povezave.
class SpilGumb extends StatelessWidget {
  const SpilGumb({super.key, required this.spil, required this.baza, required this.prijava});

  final Spil spil;
  final Baza baza;
  final Prijava prijava;

  @override
  Widget build(BuildContext context) {
    // Spletna različica z interneta (https) se z vodjo na WiFi-ju ne sme povezati: ponudi prehod na naslov vodje.
    if (kIsWeb && !Config.prekoVodje) {
      return IconButton(tooltip: 'Špil', onPressed: () => _odpriVodjo(context), icon: const Icon(Icons.cast));
    }
    return ListenableBuilder(
      listenable: spil,
      builder: (context, _) {
        // Samo ikona: vodja zelen s številom sledilcev, povezan sledilec zelen, brez povezave rdeč,
        // padla povezava utripa rdeče, dokler se ne obnovi.
        const zelena = Color(0xFF43A047);
        final rdeca = Theme.of(context).colorScheme.error;
        final (ikona, barva, opis) = switch (spil.vloga) {
          VlogaSpila.vodja => (Icons.cast_connected, zelena, 'Vodim, sledi ${spil.sledilcev}'),
          VlogaSpila.sledilec when spil.povezan => (Icons.cast_connected, zelena, 'Povezan z vodjo'),
          VlogaSpila.sledilec when spil.prekinjeno => (Icons.cast, rdeca, 'Povezava z vodjo je padla'),
          VlogaSpila.sledilec => (Icons.cast, rdeca, 'Iščem vodjo'),
          VlogaSpila.nic => (Icons.cast, Theme.of(context).colorScheme.onSurfaceVariant, 'Špil'),
        };
        Widget ikonaGumba = Icon(ikona, color: barva);
        if (spil.vloga == VlogaSpila.vodja) {
          ikonaGumba = Badge(label: Text('${spil.sledilcev}'), backgroundColor: zelena, child: ikonaGumba);
        }
        if (spil.vloga == VlogaSpila.sledilec && spil.prekinjeno) ikonaGumba = _Utripa(child: ikonaGumba);
        return IconButton(tooltip: opis, onPressed: () => _meni(context), icon: ikonaGumba);
      },
    );
  }

  Future<void> _odpriVodjo(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final c = TextEditingController(text: prefs.getString(_kljucVodje) ?? '');
    final vnos = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sledi vodji'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ta stran se z vodjo ne more povezati. Odpri naslov, ki ga vodja vidi pod '
              'Špil → Pokaži kodo za iPade (ali skeniraj kodo). Biti moraš na istem WiFi-ju.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Naslov vodje', hintText: '192.168.1.5'),
              onSubmitted: (s) => Navigator.pop(context, s),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
          TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Odpri')),
        ],
      ),
    );
    c.dispose();
    final ws = naslovWebSocket(vnos ?? '');
    if (ws == null) return;
    await prefs.setString(_kljucVodje, vnos!.trim());
    await launchUrl(Uri.parse('http://${ws.host}:${ws.port}/'), webOnlyWindowName: '_self');
  }

  Future<void> _meni(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (meni) => ListenableBuilder(
      listenable: spil,
      builder: (meni, _) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: _moznosti(meni, context)),
        ),
      ),
    ),
  );

  /// [meni] je odprt spodnji meni, [zaslon] pa zaslon pod njim (za dialoge, ko se meni zapre).
  List<Widget> _moznosti(BuildContext meni, BuildContext zaslon) {
    void zapri() => Navigator.pop(meni);
    final lahkoVodi = baza.smeVoditi && spil.lahkoVodi;
    return [
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(switch (spil.vloga) {
          VlogaSpila.vodja => 'Ta naprava vodi špil (sledi ${spil.sledilcev})',
          VlogaSpila.sledilec when spil.povezan => 'Povezan z vodjo ${spil.naslovVodje ?? ''}',
          VlogaSpila.sledilec =>
            spil.naslovVodje == null ? 'Iščem vodjo na WiFi-ju …' : 'Povezujem se z vodjo ${spil.naslovVodje} …',
          VlogaSpila.nic => 'Ni povezave z drugimi napravami',
        }),
        subtitle: spil.napaka == null ? null : Text(spil.napaka!),
      ),
      // Namesto besedila: velik naslov, stanje špila in statistika večera (vsak član na svoji napravi).
      ListTile(
        key: const ValueKey('nadzorna-plosca'),
        leading: const Icon(Icons.dashboard_outlined),
        title: const Text('Nadzorna plošča'),
        subtitle: const Text('Brez besedila: naslov, runda, snemanje in statistika špila'),
        onTap: () {
          zapri();
          NadzornaPlosca.odpri(Navigator.of(zaslon), spil: spil, baza: baza);
        },
      ),
      if (spil.lahkoPomikaVsem && !Config.prekoVodje)
        SwitchListTile(
          key: const ValueKey('pomikam-vsem'),
          secondary: const Icon(Icons.swap_vert),
          title: const Text('Pomikam besedilo vsem'),
          subtitle: const Text('Kdor ima odprto isto pesem, vidi isti del besedila ali PDF-ja'),
          value: spil.pomikamVsem,
          onChanged: spil.nastaviPomikamVsem,
        ),
      // Vodja takoj vidi, katere naprave so povezane.
      if (spil.vloga == VlogaSpila.vodja)
        for (final (i, kdo) in spil.povezani.indexed)
          ListTile(
            key: ValueKey('povezan-$i'),
            dense: true,
            leading: const Icon(Icons.tablet_android),
            title: Text(kdo),
          ),
      if (Config.prekoVodje)
        FutureBuilder(
          future: clanNaSpilu(),
          builder: (context, s) {
            final ime = baza.clani.where((c) => c.id == s.data).firstOrNull?.ime;
            return ListTile(
              leading: const Icon(Icons.person),
              title: Text(ime == null ? 'Izberi, kdo si' : 'Na tem iPadu: $ime'),
              subtitle: const Text('Za tvoje opombe in risbe'),
              onTap: () {
                zapri();
                izberiClana(zaslon, baza);
              },
            );
          },
        )
      else ...[
        if (spil.vloga == VlogaSpila.vodja) ...[
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: const Text('Pokaži kodo za iPade'),
            onTap: () {
              zapri();
              pokaziNaslovVodje(zaslon, spil);
            },
          ),
          ListTile(
            leading: const Icon(Icons.stop),
            title: const Text('Končaj vodenje'),
            onTap: () {
              spil.ustavi();
              zapri();
            },
          ),
        ],
        if (spil.vloga == VlogaSpila.sledilec) ...[
          // Več vodij na istem WiFi-ju: izbereš, komu slediš.
          if (spil.najdeniVodje.length > 1)
            for (final MapEntry(key: ws, value: ime) in spil.najdeniVodje.entries)
              ListTile(
                leading: Icon(ws == spil.vodja ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                title: Text(ime.isEmpty ? 'Vodja' : 'Vodi $ime'),
                subtitle: Text('${ws.host}:${ws.port}'),
                onTap: () async {
                  zapri();
                  spil.sledi(ws);
                  (await SharedPreferences.getInstance()).setString(_kljucVodje, '${ws.host}:${ws.port}');
                },
              ),
          if (spil.stanje != null)
            ListTile(
              leading: const Icon(Icons.music_note),
              title: const Text('Pokaži pesem vodje'),
              onTap: () {
                zapri();
                pokaziSledenje(Navigator.of(zaslon), spil: spil, baza: baza, prijava: prijava);
              },
            ),
          ListTile(
            leading: const Icon(Icons.stop),
            title: const Text('Nehaj slediti'),
            onTap: () {
              spil.ustavi();
              zapri();
            },
          ),
        ],
        if (spil.vloga == VlogaSpila.nic) ...[
          if (lahkoVodi)
            ListTile(
              leading: const Icon(Icons.cast),
              title: const Text('Vodi špil'),
              onTap: () async {
                zapri();
                await spil.zacniVoditi(baza);
              },
            ),
          ListTile(
            leading: const Icon(Icons.cast_connected),
            title: const Text('Sledi vodji'),
            subtitle: const Text('Vodjo poišče sam na istem WiFi-ju'),
            onTap: () async {
              zapri();
              final prefs = await SharedPreferences.getInstance();
              spil.samodejnoSledi(zadnji: naslovWebSocket(prefs.getString(_kljucVodje) ?? ''));
            },
          ),
        ],
        if (spil.vloga != VlogaSpila.vodja)
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Poveži z vpisanim naslovom'),
            onTap: () {
              zapri();
              zacniSlediti(zaslon, spil: spil, baza: baza, prijava: prijava);
            },
          ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: _IzbiraPrivzete(spil: spil, baza: baza, lahkoVodi: lahkoVodi),
        ),
      ],
    ];
  }
}

/// Utripanje (opozorilo, da je povezava padla).
class _Utripa extends StatefulWidget {
  const _Utripa({required this.child});

  final Widget child;

  @override
  State<_Utripa> createState() => _UtripaState();
}

class _UtripaState extends State<_Utripa> with SingleTickerProviderStateMixin {
  late final _animacija = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _animacija.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: Tween(begin: 1.0, end: 0.15).animate(_animacija), child: widget.child);
}

/// Nastavitev, ali je ta naprava ob zagonu vodja, sledilec ali sama zase.
class _IzbiraPrivzete extends StatefulWidget {
  const _IzbiraPrivzete({required this.spil, required this.baza, required this.lahkoVodi});

  final Spil spil;
  final Baza baza;
  final bool lahkoVodi;

  @override
  State<_IzbiraPrivzete> createState() => _IzbiraPrivzeteState();
}

class _IzbiraPrivzeteState extends State<_IzbiraPrivzete> {
  PrivzetaVloga? _vloga;

  @override
  void initState() {
    super.initState();
    privzetaVloga().then((v) {
      if (mounted) setState(() => _vloga = v);
    });
  }

  Future<void> _izberi(PrivzetaVloga v) async {
    setState(() => _vloga = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kljucVloge, v.name);
    // Izbira velja takoj, ne šele ob naslednjem zagonu.
    final spil = widget.spil;
    if (v == PrivzetaVloga.vodja && spil.vloga != VlogaSpila.vodja) await spil.zacniVoditi(widget.baza);
    if (v == PrivzetaVloga.sledilec && spil.vloga != VlogaSpila.sledilec) {
      if (spil.vloga == VlogaSpila.vodja) await spil.ustavi();
      spil.samodejnoSledi(zadnji: naslovWebSocket(prefs.getString(_kljucVodje) ?? ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _vloga;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ob zagonu aplikacije je ta naprava', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        if (v != null)
          SegmentedButton<PrivzetaVloga>(
            selected: {v},
            onSelectionChanged: (x) => _izberi(x.first),
            segments: [
              const ButtonSegment(value: PrivzetaVloga.sama, label: Text('Sama')),
              ButtonSegment(value: PrivzetaVloga.vodja, label: const Text('Vodja'), enabled: widget.lahkoVodi),
              const ButtonSegment(value: PrivzetaVloga.sledilec, label: Text('Sledilec')),
            ],
          ),
      ],
    );
  }
}

/// Pokaže zaslon sledenja (če še ni odprt) nad seznamom pesmi.
void pokaziSledenje(NavigatorState navigator, {required Spil spil, required Baza baza, required Prijava prijava}) {
  // Na nadzorni plošči se besedilo ne odpre.
  if (NadzornaPlosca.odprtih.value > 0) return;
  var odprt = false;
  navigator.popUntil((r) {
    odprt = r.settings.name == SledilecZaslon.ime;
    return true;
  });
  if (odprt) return;
  navigator.popUntil((r) => r.isFirst);
  navigator.push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: SledilecZaslon.ime),
      builder: (_) => SledilecZaslon(spil: spil, baza: baza, prijava: prijava),
    ),
  );
}

/// Povezan sledilec s pravico obračanja: pesem, ki jo odpre (s seznama, setliste, podrsajem …), pokaže vsem.
/// Vodja jo odpre in pošlje naprej, ta naprava pa se vrne na zaslon sledenja. Vrne false, če ne velja.
bool pokaziVsemKotSledilec(
  BuildContext context, {
  required Spil? spil,
  required Baza baza,
  required Prijava prijava,
  required Pesem pesem,
}) {
  if (spil == null || spil.vloga != VlogaSpila.sledilec || !spil.povezan || !baza.obracaZaVse) return false;
  spil.zamenjajVsem(StanjeSpila(pesem: pesem.id));
  final navigator = Navigator.of(context);
  var odprt = false;
  navigator.popUntil((r) {
    odprt = odprt || r.settings.name == SledilecZaslon.ime;
    return true;
  });
  if (odprt) {
    navigator.popUntil((r) => r.settings.name == SledilecZaslon.ime || r.isFirst);
  } else {
    pokaziSledenje(navigator, spil: spil, baza: baza, prijava: prijava);
  }
  return true;
}

/// Sledilec: ko vodja izbere drugo pesem, jo samodejno pokaže, kjerkoli je član v aplikaciji.
/// Med urejanjem ne zapre zaslona (ne izgubi sprememb), pesem se pokaže ob naslednji menjavi.
class SamodejnoSledenje {
  SamodejnoSledenje({required this.spil, required this.baza, required this.prijava, required this.navigator}) {
    spil.addListener(_sprememba);
  }

  final Spil spil;
  final Baza baza;
  final Prijava prijava;
  final GlobalKey<NavigatorState> navigator;
  StanjeSpila? _zadnje;

  void _sprememba() {
    if (spil.vloga != VlogaSpila.sledilec) {
      _zadnje = null;
      return;
    }
    // Med izpadom pozabi zadnjo pesem: po ponovni povezavi skoči na trenutno pesem vodje.
    if (!spil.povezan) {
      _zadnje = null;
      return;
    }
    final s = spil.stanje;
    if (s == null || s == _zadnje) return;
    _zadnje = s;
    final nav = navigator.currentState;
    // Odprta nadzorna plošča sama kaže pesem vodje, zato je sledenje ne zapre.
    if (nav == null ||
        OdprtoUrejanje.odprtih > 0 ||
        NadzornaPlosca.odprtih.value > 0 ||
        !Nastavitve.aplikacija.samodejnoSledenje) {
      return;
    }
    pokaziSledenje(nav, spil: spil, baza: baza, prijava: prijava);
  }
}

/// Naslov in QR koda, s katero se sledilci povežejo z vodjo.
Future<void> pokaziNaslovVodje(BuildContext context, Spil spil) => showDialog<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: spil,
    builder: (context, _) {
      final naslov = spil.naslov;
      return AlertDialog(
        title: const Text('Vodim špil'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spil.napaka != null)
                Text(spil.napaka!, style: TextStyle(color: Theme.of(context).colorScheme.error))
              else if (naslov != null) ...[
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(data: naslov, size: 200),
                ),
                const SizedBox(height: 12),
                SelectableText(naslov, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                const Text(
                  'iPad: s kamero skeniraj kodo ali vpiši naslov v Safari.\n'
                  'Android: Meni → Sledi vodji in vpiši ta naslov.\n'
                  'Vsi morajo biti na istem WiFi-ju.',
                ),
                const SizedBox(height: 8),
                Text('Sledilcev: ${spil.sledilcev}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              spil.ustavi();
              Navigator.pop(context);
            },
            child: const Text('Končaj vodenje'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zapri')),
        ],
      );
    },
  ),
);

/// Vpraša za naslov vodje (zapomni si zadnjega) in začne slediti.
Future<void> zacniSlediti(
  BuildContext context, {
  required Spil spil,
  required Baza baza,
  required Prijava prijava,
}) async {
  const kljuc = _kljucVodje;
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return;
  final c = TextEditingController(text: prefs.getString(kljuc) ?? '192.168.');
  final vnos = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sledi vodji'),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'Naslov vodje', helperText: 'Vodja ga vidi ob gumbu za vodenje'),
        onSubmitted: (s) => Navigator.pop(context, s),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
        TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Poveži')),
      ],
    ),
  );
  c.dispose();
  final ws = naslovWebSocket(vnos ?? '');
  if (ws == null || !context.mounted) return;
  await prefs.setString(kljuc, vnos!.trim());
  spil.samodejnoSledi(zadnji: ws);
  if (!context.mounted) return;
  pokaziSledenje(Navigator.of(context), spil: spil, baza: baza, prijava: prijava);
}

/// Sledilec: kaže pesem, ki jo je izbral vodja.
class SledilecZaslon extends StatelessWidget {
  const SledilecZaslon({super.key, required this.spil, required this.baza, required this.prijava, this.koren = false});

  static const ime = '/sledilec';

  final Spil spil;
  final Baza baza;
  final Prijava prijava;

  /// Prvi zaslon (iPad, odprt prek vodje): brez gumba za nazaj na seznam.
  final bool koren;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([spil, baza]),
      builder: (context, _) {
        final s = spil.stanje;
        final p = s == null ? null : baza.pesem(s.pesem);
        if (p == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Špil'),
              actions: [SpilGumb(spil: spil, baza: baza, prijava: prijava)],
            ),
            bottomNavigationBar: _vrstica(context, s, vedno: true),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s == null
                      ? (spil.povezan ? 'Čakam, da vodja izbere pesem …' : 'Povezujem se z vodjo …')
                      : 'Te pesmi ni v tvoji kopiji. Osveži pesmi, ko imaš internet.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return PesemZaslon(
          key: ValueKey(s),
          pesem: p,
          baza: baza,
          prijava: prijava,
          spil: spil,
          stanje: s,
          spodaj: _vrstica(context, s),
          odpri: (p) {
            // S pravico obračanja pesem (npr. s čakalne vrste) zamenja vsem; sledenje ostane.
            if (baza.obracaZaVse) return spil.zamenjajVsem(StanjeSpila(pesem: p.id));
            // iPad prek vodje brez pravice: pesem le predlaga, ne odpre je zase (ostane na sledenju).
            if (Config.samoKlicaji) {
              if (!spil.naslednje.any((n) => n.pesem == p.id)) spil.dodajNaslednjo(Naslednja(pesem: p.id));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${p.naslov}: samo vodja (ali kdor ima pravico) jo lahko pokaže vsem.')),
              );
              return;
            }
            // Prijavljen sledilec brez pravice: pesem se odpre nad sledenjem, da ostane povezan.
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PesemZaslon(pesem: p, baza: baza, prijava: prijava, spil: spil),
              ),
            );
          },
        );
      },
    );
  }

  /// Vrstica sledenja pod pesmijo: samo, ko povezave ni (rdeča ikona) ali ko vodja igra setlisto
  /// (mesto v setlisti, opomba in naslednja pesem). Sicer je ni, da ne jemlje prostora besedilu.
  Widget? _vrstica(BuildContext context, StanjeSpila? s, {bool vedno = false}) {
    final tema = Theme.of(context);
    final vrsta = s?.setlista == null ? null : baza.pesmiSetlist[s!.setlista];
    final i = s?.indeks;
    final naslednja = (vrsta != null && i != null && i + 1 < vrsta.length) ? baza.pesem(vrsta[i + 1].pesem) : null;
    final opomba = (vrsta != null && i != null && i < vrsta.length) ? vrsta[i].opomba : '';
    if (!vedno && spil.povezan && (vrsta == null || i == null)) return null;
    return Material(
      color: tema.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(
                spil.povezan ? Icons.cast_connected : Icons.cast,
                color: spil.povezan ? tema.colorScheme.primary : tema.colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        spil.povezan ? 'Sledim vodji' : 'Iščem vodjo …',
                        if (vrsta != null && i != null) '${i + 1} / ${vrsta.length}',
                        if (opomba.isNotEmpty) opomba,
                      ].join(' · '),
                      style: tema.textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (naslednja != null)
                      Text(
                        '→ ${napisVrste(naslednja)}',
                        style: tema.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Sledenje ostane vklopljeno: ob naslednji pesmi vodje se zaslon spet odpre.
              if (!koren)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.list),
                  label: const Text('Seznam'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Velik gumb člana s sličico (ali začetnicami) in imenom.
class GumbClana extends StatelessWidget {
  const GumbClana({super.key, required this.ime, this.slika, required this.onPressed});

  final String ime;
  final Uint8List? slika;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final barve = Theme.of(context).colorScheme;
    final zacetnice = ime.trim().split(RegExp(r'\s+')).where((d) => d.isNotEmpty).take(2).map((d) => d[0]).join();
    return SizedBox(
      width: 120,
      child: Material(
        color: barve.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: barve.primaryContainer,
                  foregroundImage: slika == null ? null : MemoryImage(slika!),
                  child: Text(zacetnice.toUpperCase(), style: TextStyle(fontSize: 28, color: barve.onPrimaryContainer)),
                ),
                const SizedBox(height: 8),
                Text(ime, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
