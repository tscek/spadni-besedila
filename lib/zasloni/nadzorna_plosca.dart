import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../baza.dart';
import '../filtri.dart' show sekundeTrajanja;
import '../midi/midi.dart';
import '../models.dart';
import '../nastavitve.dart';
import '../odigrane.dart';
import '../runda.dart';
import '../snemanje.dart';
import '../spil/spil.dart';
import 'iskalnik_pesmi.dart';
import 'naslednje.dart' show menjaHarmoniko, UtripajocaVrstica, pokaziNaslednje, vCakalnoVrsto;
import 'ohranjevalnik.dart' show nastopZaOhranjevalnik;
import 'oznake.dart' show barvaHarmonike, barvaVrste;

/// Odsek večera na časovnici: runda ali pavza.
typedef OdsekSpila = ({bool pavza, DateTime od, DateTime doo});

/// Odigrana pesem na časovnici (od kdaj do kdaj približno).
typedef PesemSpila = ({String id, Pesem? pesem, DateTime od, DateTime doo});

/// Na nadzorni plošči pesem [id] postane trenutna za vse, ne da bi se odprlo besedilo:
/// vodja (ali naprava brez špila) jo pokaže sam, sledilec s pravico jo zamenja vsem prek vodje.
void pokaziNaPlosci(Spil spil, Baza baza, String id) {
  if (baza.pesem(id) == null) return;
  final s = StanjeSpila(pesem: id);
  if (spil.vloga == VlogaSpila.sledilec) {
    if (lahkoZamenjaVsem(spil, baza)) spil.zamenjajVsem(s);
    return;
  }
  spil.prikazujem(s);
}

/// Ali ta naprava sme pesem zamenjati (vodja, sama zase ali sledilec, ki sme obračati za vse).
bool lahkoZamenjaVsem(Spil spil, Baza baza) => spil.vloga != VlogaSpila.sledilec || baza.obracaZaVse;

const _nz = 'Narodno-zabavna';

/// Zvrst pesmi poenotena na glavni dve (Narodno-zabavna, Zabavna); drugo ostane, kot je vpisano.
String zvrstPesmi(Pesem p) {
  final z = p.zvrst.trim().toLowerCase();
  if (z.isEmpty) return '';
  if (z.contains('narod')) return _nz;
  if (z.startsWith('zabav')) return 'Zabavna';
  return p.zvrst.trim();
}

/// Barvi glavnih zvrsti (drugo vijolično, brez zvrsti sivo).
Color barvaZvrsti(String z) => switch (z) {
  _nz => const Color(0xFFFF8F00),
  'Zabavna' => const Color(0xFF1E88E5),
  '' => const Color(0xFF64748B),
  _ => const Color(0xFFAB47BC),
};

/// Statistika tega večera iz časovnika runde in odigranih pesmi (vse je skupno na špilu prek vodje).
class StatistikaSpila {
  StatistikaSpila._({
    required this.odseki,
    required this.pesmi,
    required this.zacetek,
    required this.runda,
    required this.vRundi,
    required this.povprecje,
    required this.vrste,
    required this.harmonike,
    required this.zvrsti,
    required this.tempo,
  });

  /// Ena pesem, ki ni označena kot odigrana, a teče (trenutna), se na časovnici riše do zdaj.
  factory StatistikaSpila.izracunaj({
    required Baza baza,
    required Runda runda,
    required Map<String, DateTime> odigrane,
    required DateTime zdaj,
    Duration zamikOznake = const Duration(minutes: 2),
    String? trenutna,
    DateTime? trenutnaOd,
  }) {
    final meja = zdaj.subtract(Odigrane.trajanje);
    // Odseki od najstarejšega; prejšnji špil (več kot 2 uri premora) odpade.
    final vsi = <OdsekSpila>[
      for (final o in runda.zgodovina.reversed)
        if (o.zacetek.isAfter(meja)) (pavza: o.pavza, od: o.zacetek, doo: o.zacetek.add(o.trajanje)),
      if (runda.pavza != null && runda.zacetek != null) (pavza: runda.pavza!, od: runda.zacetek!, doo: zdaj),
    ];
    var prvi = 0;
    for (var i = 1; i < vsi.length; i++) {
      if (vsi[i].od.difference(vsi[i - 1].doo) > const Duration(hours: 2)) prvi = i;
    }
    final odseki = vsi.sublist(prvi);
    final mejaSpila = odseki.isEmpty ? meja : odseki.first.od.subtract(const Duration(minutes: 30));

    // Odigrane: oznaka pride [zamikOznake] po odprtju, zato pesem začne tako prej.
    final casi = odigrane.entries.where((e) => e.value.isAfter(mejaSpila) && e.key != trenutna).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final pesmi = <PesemSpila>[];
    for (var i = 0; i < casi.length; i++) {
      final p = baza.pesem(casi[i].key);
      final od = casi[i].value.subtract(zamikOznake);
      final dolzina = Duration(seconds: sekundeTrajanja(besedilo(p?.vrstica['Trajanje'])) ?? 210);
      var doo = od.add(dolzina);
      final naslednja = i + 1 < casi.length ? casi[i + 1].value.subtract(zamikOznake) : (trenutnaOd ?? zdaj);
      if (doo.isAfter(naslednja)) doo = naslednja;
      final pavza = odseki.where((o) => o.pavza && o.od.isAfter(od)).firstOrNull;
      if (pavza != null && doo.isAfter(pavza.od)) doo = pavza.od;
      if (doo.isAfter(zdaj)) doo = zdaj;
      pesmi.add((id: casi[i].key, pesem: p, od: od, doo: doo.isAfter(od) ? doo : od.add(const Duration(seconds: 30))));
    }
    if (trenutna != null && trenutnaOd != null) {
      pesmi.add((id: trenutna, pesem: baza.pesem(trenutna), od: trenutnaOd, doo: zdaj));
    }

    final zacetki = [?odseki.firstOrNull?.od, ?pesmi.firstOrNull?.od];
    final zacetek = zacetki.isEmpty ? null : zacetki.reduce((a, b) => a.isBefore(b) ? a : b);
    final rundaOd = runda.pavza == false ? runda.zacetek : null;

    // Povprečna dolžina: razmik med zaporednima pesmima iste runde (brez pavz in dolgih premorov).
    final razmiki = <Duration>[
      for (var i = 1; i < casi.length; i++)
        if (casi[i].value.difference(casi[i - 1].value) case final d
            when d < const Duration(minutes: 12) &&
                !odseki.any((o) => o.pavza && o.od.isAfter(casi[i - 1].value) && o.od.isBefore(casi[i].value)))
          d,
    ];

    Map<String, int> prestej(String Function(Pesem) polje) {
      final m = <String, int>{};
      for (final x in pesmi) {
        final v = x.pesem == null ? '' : polje(x.pesem!);
        m[v.isEmpty ? 'Brez' : v] = (m[v.isEmpty ? 'Brez' : v] ?? 0) + 1;
      }
      return Map.fromEntries(
        m.entries.toList()
          // Največ prvi, »Brez« vedno na koncu.
          ..sort((a, b) => a.key == 'Brez' ? 1 : (b.key == 'Brez' ? -1 : b.value.compareTo(a.value))),
      );
    }

    return StatistikaSpila._(
      odseki: odseki,
      pesmi: pesmi,
      zacetek: zacetek,
      runda: odseki.where((o) => !o.pavza).length,
      vRundi: rundaOd == null
          ? 0
          : pesmi.where((p) => !p.od.isBefore(rundaOd.subtract(const Duration(minutes: 1)))).length,
      povprecje: razmiki.isEmpty
          ? null
          : Duration(seconds: razmiki.fold(0, (s, d) => s + d.inSeconds) ~/ razmiki.length),
      vrste: prestej((p) => p.vrsta),
      harmonike: prestej((p) => p.harmonika),
      zvrsti: prestej((p) => zvrstPesmi(p)),
      tempo: [for (final x in pesmi) num.tryParse(besedilo(x.pesem?.vrstica['Tempo (BPM)']).replaceAll(',', '.'))],
    );
  }

  final List<OdsekSpila> odseki;
  final List<PesemSpila> pesmi;
  final DateTime? zacetek;

  /// Številka runde (število rund do zdaj) in pesmi v trenutni rundi.
  final int runda;
  final int vRundi;
  final Duration? povprecje;
  final Map<String, int> vrste;
  final Map<String, int> harmonike;

  /// Narodno-zabavna in Zabavna (glavni zvrsti) ter ostalo.
  final Map<String, int> zvrsti;
  final List<num?> tempo;
}

/// Nadzorna plošča: namesto besedila velik naslov, stanje špila in statistika večera.
/// Izbere jo lahko vsak član v meniju Špil; sledi vodji kot zaslon pesmi.
class NadzornaPlosca extends StatefulWidget {
  const NadzornaPlosca({super.key, required this.spil, required this.baza});

  final Spil spil;
  final Baza baza;

  static const ime = 'nadzorna-plosca';

  /// Odprte plošče: samodejno sledenje in ohranjevalnik ob pavzi jih ne prekrijeta.
  static final odprtih = ValueNotifier<int>(0);

  static Future<void> odpri(NavigatorState navigator, {required Spil spil, required Baza baza}) => navigator.push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: ime),
      builder: (_) => NadzornaPlosca(spil: spil, baza: baza),
    ),
  );

  @override
  State<NadzornaPlosca> createState() => _NadzornaPloscaState();
}

const _ozadje = Color(0xFF0E1116);
const _kartica = Color(0xFF171C24);
const _crte = Color(0xFF3A4252);
const _bela = Color(0xFFE8ECF2);
const _siva = Color(0xFF8A94A6);
const _zelena = Color(0xFF6EE08A);
const _rdeca = Color(0xFFFF5252);
const _oranzna = Color(0xFFFFB74D);
const _rezervne = [Color(0xFF1E88E5), Color(0xFFAB47BC), Color(0xFF26A69A), Color(0xFFFF7043), Color(0xFF8D6E63)];

class _NadzornaPloscaState extends State<NadzornaPlosca> {
  Timer? _ura;
  String? _pesem;
  DateTime? _pesemOd;

  @override
  void initState() {
    super.initState();
    NadzornaPlosca.odprtih.value++;
    _ura = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ura?.cancel();
    NadzornaPlosca.odprtih.value--;
    super.dispose();
  }

  String? get _trenutnaId => widget.spil.prikazano?.pesem ?? widget.spil.stanje?.pesem;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.spil,
      widget.baza,
      Runda.aplikacija,
      Odigrane.aplikacija,
      SnemanjeSpila.aplikacija,
    ]),
    builder: (context, _) {
      final zdaj = DateTime.now();
      final id = _trenutnaId;
      if (id != _pesem) {
        _pesem = id;
        _pesemOd = id == null ? null : zdaj;
      }
      final pesem = id == null ? null : widget.baza.pesem(id);
      final stat = StatistikaSpila.izracunaj(
        baza: widget.baza,
        runda: Runda.aplikacija,
        odigrane: Odigrane.aplikacija.casi,
        zdaj: zdaj,
        zamikOznake: Duration(minutes: Nastavitve.aplikacija.minuteOdigrane),
        trenutna: pesem?.id,
        trenutnaOd: _pesemOd,
      );
      return Theme(
        data: ThemeData(brightness: Brightness.dark, colorSchemeSeed: Colors.amber, fontFamily: 'Roboto'),
        child: Scaffold(
          backgroundColor: _ozadje,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, meje) {
                final lezece = meje.maxWidth > meje.maxHeight;
                final d = _Deli(this, context, pesem, stat, zdaj);
                if (lezece) return Padding(padding: const EdgeInsets.all(10), child: d.lezece());
                // Nizek zaslon (telefon): plošča se pomika, grafi imajo stalno višino.
                if (meje.maxHeight < 860) {
                  return SingleChildScrollView(padding: const EdgeInsets.all(10), child: d.pokoncno(drsi: true));
                }
                return Padding(padding: const EdgeInsets.all(10), child: d.pokoncno());
              },
            ),
          ),
        ),
      );
    },
  );
}

/// Sestavni deli plošče in njihova razporeditev za pokončno in ležečo napravo.
class _Deli {
  _Deli(this.s, this.context, this.pesem, this.stat, this.zdaj);

  final _NadzornaPloscaState s;
  final BuildContext context;
  final Pesem? pesem;
  final StatistikaSpila stat;
  final DateTime zdaj;

  Baza get baza => s.widget.baza;
  Spil get spil => s.widget.spil;
  static const _razmik = SizedBox.square(dimension: 10);

  Widget pokoncno({bool drsi = false}) {
    Widget raste(Widget w) => drsi ? SizedBox(height: 180, child: w) : Expanded(child: w);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        vrh(),
        _razmik,
        zdajIgramo(),
        _razmik,
        SizedBox(height: 120, child: stevilke()),
        _razmik,
        SizedBox(height: 150, child: casovnica()),
        _razmik,
        raste(
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: krog('Zvrst', stat.zvrsti, barvaZvrsti, ime: (k) => k == _nz ? 'NZ' : k)),
              _razmik,
              Expanded(child: krog('Vrste', stat.vrste, (v) => barvaVrste(baza, v))),
              _razmik,
              Expanded(child: krog('Harmonike', stat.harmonike, (v) => barvaHarmonike(baza, v))),
            ],
          ),
        ),
        _razmik,
        raste(tempo()),
        _razmik,
        naslednja(),
        _razmik,
        spodaj(),
      ],
    );
  }

  Widget lezece() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      vrh(),
      _razmik,
      Expanded(
        flex: 5,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: zdajIgramo()),
            _razmik,
            Expanded(
              flex: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 110, child: stevilke()),
                  _razmik,
                  Expanded(child: casovnica()),
                ],
              ),
            ),
          ],
        ),
      ),
      _razmik,
      Expanded(
        flex: 4,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: krog('Zvrst', stat.zvrsti, barvaZvrsti, ime: (k) => k == _nz ? 'NZ' : k)),
            _razmik,
            Expanded(child: krog('Vrste', stat.vrste, (v) => barvaVrste(baza, v))),
            _razmik,
            Expanded(child: krog('Harmonike', stat.harmonike, (v) => barvaHarmonike(baza, v))),
            _razmik,
            Expanded(child: tempo()),
          ],
        ),
      ),
      _razmik,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: naslednja()),
          _razmik,
          Expanded(child: spodaj()),
        ],
      ),
    ],
  );

  static Widget kartica({required Widget child, String? naslov, EdgeInsets? odmik}) => Container(
    padding: odmik ?? const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(color: _kartica, borderRadius: BorderRadius.circular(18)),
    child: naslov == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(naslov.toUpperCase(), style: const TextStyle(color: _siva, fontSize: 13, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Expanded(child: child),
            ],
          ),
  );

  static Widget znacka(String besedilo, Color barva, {Color? ozadje, Widget? ikona}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(color: ozadje ?? barva.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ikona != null) ...[ikona, const SizedBox(width: 6)],
        Text(
          besedilo,
          style: TextStyle(color: barva, fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ],
    ),
  );

  Widget vrh() {
    final r = Runda.aplikacija;
    final sn = SnemanjeSpila.aplikacija;
    final nastop = nastopZaOhranjevalnik(baza, zdaj);
    final stanje = switch (r.pavza) {
      true => znacka(
        'PAVZA ${casBesedilo(r.trenutno(zdaj: zdaj))}',
        _oranzna,
        ikona: const Icon(Icons.pause, size: 18, color: _oranzna),
      ),
      false => znacka(
        'ŠPILEJ · runda ${stat.runda}',
        _zelena,
        ikona: const Icon(Icons.play_arrow, size: 18, color: _zelena),
      ),
      null => znacka('Runda ne teče', _siva),
    };
    return kartica(
      odmik: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          const Text(
            'Nadzorna plošča',
            style: TextStyle(color: _bela, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (nastop != null)
            Flexible(
              child: Text(
                '  ·  ${[nastop.naslov, nastop.kraj].where((x) => x.isNotEmpty).join(' · ')}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _siva, fontSize: 15),
              ),
            ),
          const Spacer(),
          stanje,
          if (sn.aktivno) ...[
            const SizedBox(width: 8),
            znacka(
              '${sn.pavza ? 'REC ❚❚' : 'REC'} ${casBesedilo(sn.posneto(zdaj: zdaj))}',
              _rdeca,
              ikona: const _Pika(),
            ),
          ],
          const SizedBox(width: 12),
          Text(
            '${zdaj.hour}:${zdaj.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: _bela,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            tooltip: 'Zapri ploščo',
            icon: const Icon(Icons.close, color: _siva),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget zdajIgramo() {
    final p = pesem;
    if (p == null) {
      return kartica(
        child: const Center(
          child: Text('Pesem še ni izbrana', style: TextStyle(color: _siva, fontSize: 24)),
        ),
      );
    }
    final avtorji = [p.avtorGlasbe, p.avtorBesedila].where((x) => x.isNotEmpty).toSet().join(' / ');
    final podnaslov = [p.izvajalec, avtorji].where((x) => x.isNotEmpty).join(' · ');
    final tempo = besedilo(p.vrstica['Tempo (BPM)']);
    final trajanje = sekundeTrajanja(besedilo(p.vrstica['Trajanje']));
    final tece = s._pesemOd == null ? Duration.zero : zdaj.difference(s._pesemOd!);
    final vrsta = barvaVrste(baza, p.vrsta);
    final harmonika = barvaHarmonike(baza, p.harmonika);
    return kartica(
      odmik: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ZDAJ IGRAMO${stat.pesmi.isEmpty ? '' : ' · ${stat.pesmi.length}. PESEM'}',
            style: const TextStyle(color: _siva, fontSize: 13, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            p.naslov,
            key: const ValueKey('plosca-naslov'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _bela, fontSize: 44, fontWeight: FontWeight.w800, height: 1.05),
          ),
          if (podnaslov.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                podnaslov,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _siva, fontSize: 20),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (p.vrsta.isNotEmpty) znacka(p.vrsta, vrsta ?? _bela),
              if (p.harmonika.isNotEmpty) znacka(p.harmonika, harmonika ?? _bela),
              if (p.tonaliteta.isNotEmpty) znacka(p.tonaliteta, _bela, ozadje: Colors.white10),
              if (tempo.isNotEmpty) znacka('$tempo BPM', _bela, ozadje: Colors.white10),
            ],
          ),
          if (s._pesemOd != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Pesem ${casBesedilo(tece)}', style: const TextStyle(color: _siva, fontSize: 14)),
                const Spacer(),
                if (trajanje != null)
                  Text(
                    '≈ ${casBesedilo(Duration(seconds: trajanje))}',
                    style: const TextStyle(color: _siva, fontSize: 14),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: trajanje == null || trajanje == 0 ? null : min(1, tece.inSeconds / trajanje),
                backgroundColor: Colors.white10,
                color: harmonika ?? _oranzna,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget stevilke() {
    final r = Runda.aplikacija;
    final igramo = stat.zacetek == null ? null : zdaj.difference(stat.zacetek!);
    final naUro = igramo == null || igramo.inMinutes < 10 ? null : stat.pesmi.length / (igramo.inSeconds / 3600);
    Widget ploscica(String naslov, String vrednost, String opis, {Key? key}) => Expanded(
      child: kartica(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(naslov.toUpperCase(), style: const TextStyle(color: _siva, fontSize: 13, letterSpacing: 1.2)),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  vrednost,
                  key: key,
                  style: const TextStyle(
                    color: _bela,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            Text(
              opis,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _siva, fontSize: 14),
            ),
          ],
        ),
      ),
    );
    String ura(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ploscica(
          'Igramo',
          igramo == null ? '–' : '${igramo.inHours}:${(igramo.inMinutes % 60).toString().padLeft(2, '0')}',
          [
            if (stat.zacetek != null) 'od ${ura(stat.zacetek!)}',
            if (r.zacetek != null) '${r.pavza == true ? 'pavza' : 'runda'} ${casBesedilo(r.trenutno(zdaj: zdaj))}',
          ].join(' · '),
        ),
        const SizedBox(width: 10),
        ploscica(
          'Odigranih',
          '${stat.pesmi.length}',
          [
            for (final e in stat.zvrsti.entries)
              if (e.key != 'Brez') '${e.key == _nz ? 'NZ' : e.key.toLowerCase()} ${e.value}',
            if (r.pavza == false) 'v rundi ${stat.vRundi}',
          ].join(' · '),
          key: const ValueKey('plosca-odigranih'),
        ),
        const SizedBox(width: 10),
        ploscica(
          'Povprečna pesem',
          stat.povprecje == null ? '–' : casBesedilo(stat.povprecje!),
          [
            if (naUro != null) '${naUro.toStringAsFixed(0)} na uro',
            stat.odseki.where((o) => o.pavza).isEmpty
                ? 'brez pavze'
                : 'pavze ${casBesedilo(stat.odseki.where((o) => o.pavza).fold(Duration.zero, (a, o) => a + o.doo.difference(o.od)))}',
          ].join(' · '),
        ),
      ],
    );
  }

  /// Na časovnici je pesem v barvi zvrsti (narodno-zabavna ali zabavna); brez zvrsti je siva.
  Color barvaPesmi(Pesem? p, int i) => barvaZvrsti(p == null ? '' : zvrstPesmi(p));

  Widget casovnica() {
    final zvrsti = {for (final k in stat.zvrsti.keys) k: barvaZvrsti(k == 'Brez' ? '' : k)};
    return kartica(
      naslov: 'Časovnica špila',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: stat.zacetek == null
                ? const Center(
                    child: Text('Špil se še ni začel', style: TextStyle(color: _siva)),
                  )
                : CustomPaint(
                    size: Size.infinite,
                    painter: _Casovnica(stat: stat, zdaj: zdaj, barva: barvaPesmi),
                  ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final e in zvrsti.entries) _Legenda(e.key == 'Brez' ? 'Brez zvrsti' : e.key, e.value),
              const _Legenda('Pavza', _crte),
            ],
          ),
        ],
      ),
    );
  }

  Widget krog(String naslov, Map<String, int> podatki, Color? Function(String) barva, {String Function(String)? ime}) {
    final barve = [
      for (final (i, k) in podatki.keys.indexed) k == 'Brez' ? _crte : (barva(k) ?? _rezervne[i % _rezervne.length]),
    ];
    return kartica(
      naslov: naslov,
      child: podatki.isEmpty
          ? const Center(
              child: Text('Še ni pesmi', style: TextStyle(color: _siva)),
            )
          : Row(
              children: [
                Expanded(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _Krog(vrednosti: podatki.values.toList(), barve: barve),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, e) in podatki.entries.indexed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: _Legenda('${ime?.call(e.key) ?? e.key} ${e.value}', barve[i], velikost: 14),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget tempo() {
    final t = [for (final x in stat.tempo) x?.toDouble()];
    return kartica(
      naslov: 'Tempo skozi špil',
      child: t.whereType<double>().length < 2
          ? const Center(
              child: Text('Premalo pesmi s tempom', style: TextStyle(color: _siva)),
            )
          : CustomPaint(size: Size.infinite, painter: _Tempo(t)),
    );
  }

  /// Iskalnik pesmi: izbrana pesem gre na prvo mesto čakalne vrste (naslednja).
  Future<void> izberiNaslednjo() {
    final mapa = pesem?.mapa ?? '';
    return showDialog<void>(
      context: context,
      builder: (dialog) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 480,
          height: min(640, MediaQuery.sizeOf(dialog).height - 64),
          child: IskalnikPesmi(
            baza: baza,
            pesmi: baza.pesmiMape(mapa.isEmpty ? null : mapa),
            mapa: mapa,
            pavza: baza.pesem(baza.mapa(mapa)?.pavza ?? ''),
            trenutna: pesem,
            vVrsti: {for (final (i, n) in spil.naslednje.indexed) n.pesem: i + 1},
            odpri: (p) {
              Navigator.pop(dialog);
              vCakalnoVrsto(context, spil, baza, p, naPrvo: true);
            },
            zapri: () => Navigator.pop(dialog),
          ),
        ),
      ),
    );
  }

  Widget naslednja() {
    final n = spil.prvaNaslednja();
    final p = n == null ? null : baza.pesem(n.pesem);
    final menjava = p != null && menjaHarmoniko(pesem, p);
    final harmonika = p == null ? null : barvaHarmonike(baza, p.harmonika);
    final ostalih = spil.naslednje.length - 1;
    final vsebina = InkWell(
      // Dotik odpre čakalno vrsto; izbrana pesem v njej postane naslednja (besedilo se ne odpre).
      onTap: () => pokaziNaslednje(context, spil, baza, (x) => vCakalnoVrsto(context, spil, baza, x, naPrvo: true)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(menjava ? Icons.swap_horiz : Icons.queue_music, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    menjava ? 'NASLEDNJA · MENJAVA HARMONIKE' : 'NASLEDNJA',
                    style: const TextStyle(fontSize: 13, letterSpacing: 1.2),
                  ),
                  Text(
                    p?.naslov ?? 'Ni izbrane',
                    key: const ValueKey('plosca-naslednja'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  if (p != null)
                    Text(
                      [
                        p.vrsta,
                        p.harmonika,
                        p.tonaliteta,
                        if (n!.kdo.isNotEmpty) 'predlaga ${n.kdo}',
                        if (ostalih > 0) '+$ostalih v vrsti',
                      ].where((x) => x.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                ],
              ),
            ),
            IconButton.filledTonal(
              key: const ValueKey('plosca-izberi'),
              tooltip: 'Izberi naslednjo pesem',
              iconSize: 28,
              icon: const Icon(Icons.search),
              onPressed: izberiNaslednjo,
            ),
            if (p != null && lahkoZamenjaVsem(spil, baza)) ...[
              const SizedBox(width: 8),
              IconButton.filled(
                key: const ValueKey('plosca-igraj'),
                tooltip: 'Igraj zdaj (vsem pokaže naslednjo pesem)',
                iconSize: 28,
                icon: const Icon(Icons.skip_next),
                onPressed: () => pokaziNaPlosci(spil, baza, p.id),
              ),
            ],
          ],
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: menjava
          ? UtripajocaVrstica(
              key: const ValueKey('plosca-menjava'),
              osnovna: _kartica,
              barva: harmonika ?? Colors.orange,
              child: vsebina,
            )
          : Material(
              color: _kartica,
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: _bela),
                child: IconTheme.merge(
                  data: const IconThemeData(color: _bela),
                  child: vsebina,
                ),
              ),
            ),
    );
  }

  Widget spodaj() {
    final midi = Midi.aplikacija.naprave.where((n) => n.povezana).map((n) => n.ime).toList();
    final povezava = switch (spil.vloga) {
      VlogaSpila.vodja => 'Vodim · ${spil.povezani.isEmpty ? 'ni sledilcev' : spil.povezani.join(', ')}',
      VlogaSpila.sledilec when spil.povezan => 'Sledim vodji ${spil.naslovVodje ?? ''}',
      VlogaSpila.sledilec => 'Povezava z vodjo je padla',
      VlogaSpila.nic => 'Ni povezave z drugimi napravami',
    };
    final predlogi = [
      for (final n in spil.naslednje.skip(1))
        if (n.kdo.isNotEmpty) n,
    ].take(2).toList();
    return kartica(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                spil.vloga == VlogaSpila.sledilec && !spil.povezan ? Icons.cast : Icons.cast_connected,
                size: 18,
                color: spil.vloga == VlogaSpila.sledilec && !spil.povezan ? _rdeca : _zelena,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  povezava,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _bela, fontSize: 15),
                ),
              ),
            ],
          ),
          if (midi.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'MIDI ✓ ${midi.join(', ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _siva, fontSize: 14),
            ),
          ],
          for (final n in predlogi)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: '! ',
                      style: TextStyle(color: _oranzna, fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: '${n.kdo}: ${baza.pesem(n.pesem)?.naslov ?? n.pesem}'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _bela, fontSize: 15),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pika extends StatelessWidget {
  const _Pika();

  @override
  Widget build(BuildContext context) => Container(
    width: 11,
    height: 11,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: Color(0xFFFF3B3B),
      boxShadow: [BoxShadow(color: Color(0xFFFF3B3B), blurRadius: 8)],
    ),
  );
}

class _Legenda extends StatelessWidget {
  const _Legenda(this.besedilo, this.barva, {this.velikost = 13});

  final String besedilo;
  final Color barva;
  final double velikost;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: barva, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          besedilo,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: const Color(0xFFC8D0DC), fontSize: velikost),
        ),
      ),
    ],
  );
}

TextPainter _napis(String s, {Color barva = _siva, double velikost = 12}) => TextPainter(
  text: TextSpan(
    text: s,
    style: TextStyle(color: barva, fontSize: velikost, fontFamily: 'Roboto'),
  ),
  textDirection: TextDirection.ltr,
)..layout();

/// Trak večera: runde in pavze, vsaka pesem v barvi svoje vrste, bela črta je zdaj.
class _Casovnica extends CustomPainter {
  _Casovnica({required this.stat, required this.zdaj, required this.barva});

  final StatistikaSpila stat;
  final DateTime zdaj;
  final Color Function(Pesem?, int) barva;

  @override
  void paint(Canvas canvas, Size size) {
    final od = stat.zacetek!;
    // Os: od začetka do zdaj in še četrtina naprej (prostor za preostanek večera).
    final dolzina = max(zdaj.difference(od).inSeconds * 1.25, 3600.0);
    double x(DateTime t) => (t.difference(od).inSeconds / dolzina * size.width).clamp(0, size.width);
    final vrh = 18.0;
    final visina = max(16.0, size.height - 38);
    String ura(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

    var runda = 0;
    for (final o in stat.odseki) {
      final r = Rect.fromLTRB(x(o.od), vrh, max(x(o.od) + 2, x(o.doo) - 2), vrh + visina);
      if (o.pavza) {
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = _crte);
        final t = _napis('pavza', barva: const Color(0xFF9AA4B5));
        if (r.width > t.width + 6) t.paint(canvas, r.center - Offset(t.width / 2, t.height / 2));
      } else {
        runda++;
        final t = _napis('runda $runda');
        if (x(o.doo) - x(o.od) > t.width) t.paint(canvas, Offset(x(o.od), 0));
      }
    }
    for (final (i, p) in stat.pesmi.indexed) {
      final r = Rect.fromLTRB(x(p.od), vrh, max(x(p.od) + 3, x(p.doo) - 2), vrh + visina);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = barva(p.pesem, i));
    }
    // Preostanek večera črtkano.
    final zx = x(zdaj);
    final ostanek = Path();
    for (var d = zx + 4; d < size.width; d += 11) {
      ostanek
        ..moveTo(d, vrh)
        ..lineTo(min(d + 6, size.width), vrh)
        ..moveTo(d, vrh + visina)
        ..lineTo(min(d + 6, size.width), vrh + visina);
    }
    canvas.drawPath(
      ostanek,
      Paint()
        ..color = _crte
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(zx, vrh - 8),
      Offset(zx, vrh + visina + 6),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3,
    );
    final spodaj = vrh + visina + 6;
    _napis(ura(od)).paint(canvas, Offset(0, spodaj));
    final t = _napis(ura(zdaj), barva: Colors.white);
    t.paint(canvas, Offset((zx - t.width / 2).clamp(0, size.width - t.width), spodaj));
  }

  @override
  bool shouldRepaint(_Casovnica old) => true;
}

/// Kolobar deležev s skupnim številom na sredini.
class _Krog extends CustomPainter {
  _Krog({required this.vrednosti, required this.barve});

  final List<int> vrednosti;
  final List<Color> barve;

  @override
  void paint(Canvas canvas, Size size) {
    final vsota = vrednosti.fold(0, (a, b) => a + b);
    final r = min(size.width, size.height) / 2 - 2;
    if (vsota == 0 || r <= 8) return;
    final c = size.center(Offset.zero);
    final debelina = r * 0.38;
    var kot = -pi / 2;
    for (final (i, v) in vrednosti.indexed) {
      final lok = v / vsota * 2 * pi;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - debelina / 2),
        kot,
        max(0, lok - (vrednosti.length > 1 ? 0.03 : 0)),
        false,
        Paint()
          ..color = barve[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = debelina,
      );
      kot += lok;
    }
    final t = _napis('$vsota', barva: _bela, velikost: max(14, r * 0.42));
    t.paint(canvas, c - Offset(t.width / 2, t.height / 2));
  }

  @override
  bool shouldRepaint(_Krog old) => true;
}

/// Krivulja tempa (BPM) po odigranih pesmih; pesmi brez tempa so presledki, zadnja točka je bela.
class _Tempo extends CustomPainter {
  _Tempo(this.tempo);

  final List<double?> tempo;

  @override
  void paint(Canvas canvas, Size size) {
    final znane = tempo.whereType<double>();
    final najmanj = (znane.reduce(min) / 20).floor() * 20.0;
    final najvec = max(najmanj + 40, (znane.reduce(max) / 20).ceil() * 20.0);
    const levo = 34.0;
    final spodaj = size.height - 18;
    double y(double v) => spodaj - (v - najmanj) / (najvec - najmanj) * (spodaj - 6);
    double x(int i) => levo + (tempo.length == 1 ? 0 : i / (tempo.length - 1)) * (size.width - levo - 8);
    final korak = (najvec - najmanj) > 120 ? 40.0 : 20.0;
    for (var v = najmanj; v <= najvec; v += korak) {
      canvas.drawLine(Offset(levo, y(v)), Offset(size.width, y(v)), Paint()..color = Colors.white12);
      final t = _napis(v.toStringAsFixed(0));
      t.paint(canvas, Offset(0, y(v) - t.height / 2));
    }
    final crta = Paint()
      ..color = const Color(0xFFFFC107)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    final pot = Path();
    var zacni = true;
    for (final (i, v) in tempo.indexed) {
      if (v == null) {
        zacni = true;
        continue;
      }
      zacni ? pot.moveTo(x(i), y(v)) : pot.lineTo(x(i), y(v));
      zacni = false;
    }
    canvas.drawPath(pot, crta);
    for (final (i, v) in tempo.indexed) {
      if (v == null) continue;
      final zadnja = i == tempo.length - 1;
      canvas.drawCircle(
        Offset(x(i), y(v)),
        zadnja ? 5 : 3,
        Paint()..color = zadnja ? Colors.white : const Color(0xFFFFC107),
      );
    }
    _napis('1').paint(canvas, Offset(levo - 3, spodaj + 4));
    final t = _napis('${tempo.length}');
    t.paint(canvas, Offset(size.width - t.width - 4, spodaj + 4));
  }

  @override
  bool shouldRepaint(_Tempo old) => true;
}
