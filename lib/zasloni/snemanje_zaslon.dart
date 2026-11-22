import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../baza.dart';
import '../config.dart';
import '../models.dart';
import '../runda.dart' show casBesedilo;
import '../snemanje.dart';
import 'youtube.dart';

/// Ali sme ta naprava voditi snemanje: administrator v aplikaciji (ne iPad prek vodje).
/// Snema vodja; brez špila snema naprava sama (ne v brskalniku).
bool smeSnemati(Baza baza) =>
    baza.jeAdministrator && !Config.prekoVodje && (SnemanjeSpila.aplikacija.vodji != null || !kIsWeb);

/// Stanje snemanja v oknu Runda in pavza: kje se snema in koliko je posneto; administrator ga začne in konča.
class PloscaSnemanja extends StatefulWidget {
  const PloscaSnemanja({super.key, required this.baza});

  final Baza baza;

  @override
  State<PloscaSnemanja> createState() => _PloscaSnemanjaState();
}

class _PloscaSnemanjaState extends State<PloscaSnemanja> {
  late final Timer _ura = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted && SnemanjeSpila.aplikacija.aktivno) setState(() {});
  });

  @override
  void dispose() {
    _ura.cancel();
    super.dispose();
  }

  Future<void> _zakljuci() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zaključim snemanje špila?'),
        content: const Text('Posnetek se pošlje na Drive in iz njega nastane video na YouTubu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Prekliči')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Zaključi')),
        ],
      ),
    );
    if (ok == true) await SnemanjeSpila.aplikacija.zakljuci();
  }

  @override
  Widget build(BuildContext context) {
    final s = SnemanjeSpila.aplikacija;
    final tema = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s, widget.baza]),
      builder: (context, _) {
        final sme = smeSnemati(widget.baza);
        final vrstice = <Widget>[
          if (s.aktivno)
            Row(
              children: [
                Icon(Icons.fiber_manual_record, color: s.pavza ? Colors.grey : Colors.red, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Snema: ${s.naprava.isEmpty ? 'vodja' : s.naprava} · ${casBesedilo(s.posneto())}'
                    '${s.pavza ? ' · pavza' : ''}',
                    key: const ValueKey('stanje-snemanja'),
                    style: tema.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (sme)
                  TextButton(
                    key: const ValueKey('zakljuci-snemanje'),
                    onPressed: _zakljuci,
                    child: const Text('Zaključi'),
                  ),
              ],
            ),
          if (s.aktivno && s.naslov.isNotEmpty) Text(s.naslov, style: tema.textTheme.bodySmall),
          if (!s.aktivno && sme)
            OutlinedButton.icon(
              key: const ValueKey('zacni-snemanje'),
              onPressed: () => zacniSnemanje(context, widget.baza),
              icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
              label: const Text('Začni snemanje špila'),
            ),
          if (!s.aktivno)
            if (widget.baza.snemanja.firstOrNull case final z?) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Zadnji posneti špil: ${z.naslov}${z.youtube.isEmpty ? ' (${z.opisVidea().toLowerCase()})' : ''}',
                      style: tema.textTheme.bodySmall,
                    ),
                  ),
                  if (z.povezava() case final url?)
                    IconButton(
                      tooltip: 'Celoten posnetek na YouTubu',
                      icon: const ZnakYt(izbran: false),
                      onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                    ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (widget.baza.smeZahtevatiVideo && z.lahkoNarediVideo())
                    GumbNarediVideo(baza: widget.baza, snemanje: z),
                  TextButton.icon(
                    key: const ValueKey('vsa-snemanja'),
                    onPressed: () => pokaziSnemanja(context, widget.baza),
                    icon: const Icon(Icons.video_library_outlined),
                    label: Text('Vsa snemanja (${widget.baza.snemanja.length})'),
                  ),
                ],
              ),
            ],
          if (s.cakajo > 0) Text('Na Drive čaka kosov: ${s.cakajo}', style: tema.textTheme.bodySmall),
          if (s.napaka case final n?) Text(n, style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.error)),
        ];
        if (vrstice.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: vrstice),
        );
      },
    );
  }
}

/// Gumb »Naredi video zdaj«: skripta sproži GitHub, ki iz kosov naredi video in ga naloži na YouTube.
class GumbNarediVideo extends StatefulWidget {
  const GumbNarediVideo({super.key, required this.baza, required this.snemanje});

  final Baza baza;
  final Snemanje snemanje;

  @override
  State<GumbNarediVideo> createState() => _GumbNarediVideoState();
}

class _GumbNarediVideoState extends State<GumbNarediVideo> {
  var _posiljam = false;

  Future<void> _naredi() async {
    final messenger = ScaffoldMessenger.of(context);
    final api = SnemanjeSpila.aplikacija.api?.call();
    if (api == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Za video je potreben internet in prijava.')));
      return;
    }
    setState(() => _posiljam = true);
    try {
      await widget.baza.narediVideo(api, widget.snemanje.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Video je zahtevan. Na YouTubu bo v 10 do 30 minutah (nato Osveži).')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Videa ni bilo mogoče zahtevati: $e')));
    } finally {
      if (mounted) setState(() => _posiljam = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    key: ValueKey('naredi-video-${widget.snemanje.id}'),
    onPressed: _posiljam ? null : _naredi,
    icon: _posiljam
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.movie_creation_outlined),
    label: const Text('Naredi video zdaj'),
  );
}

/// Seznam vseh snemanj špilov s stanjem videa.
Future<void> pokaziSnemanja(BuildContext context, Baza baza) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => ListenableBuilder(
    listenable: baza,
    builder: (context, _) {
      final tema = Theme.of(context);
      String datum(DateTime? d) {
        if (d == null) return '';
        final l = d.toLocal();
        return '${l.day}. ${l.month}. ${l.year}';
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Snemanja špilov', style: tema.textTheme.titleLarge),
              ),
              if (baza.snemanja.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('Ni še posnetih špilov.')),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final sn in baza.snemanja)
                      ListTile(
                        key: ValueKey('snemanje-${sn.id}'),
                        leading: Icon(
                          sn.youtube.isNotEmpty
                              ? Icons.check_circle_outline
                              : sn.video.startsWith('napaka')
                              ? Icons.error_outline
                              : Icons.schedule,
                          color: sn.youtube.isNotEmpty
                              ? Colors.green
                              : sn.video.startsWith('napaka')
                              ? tema.colorScheme.error
                              : null,
                        ),
                        title: Text(sn.naslov),
                        subtitle: Text(
                          [
                            datum(sn.zacetek),
                            if (sn.kosi.isNotEmpty) casBesedilo(sn.trajanje),
                            sn.opisVidea(),
                          ].where((x) => x.isNotEmpty).join(' · '),
                        ),
                        trailing: sn.povezava() != null
                            ? IconButton(
                                tooltip: 'Odpri na YouTubu',
                                icon: const ZnakYt(izbran: false),
                                onPressed: () =>
                                    launchUrl(Uri.parse(sn.povezava()!), mode: LaunchMode.externalApplication),
                              )
                            : baza.smeZahtevatiVideo && sn.lahkoNarediVideo()
                            ? GumbNarediVideo(baza: baza, snemanje: sn)
                            : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  ),
);

/// Nastop iz Nastopov (predlog za naslov snemanja).
typedef PredlogNastopa = ({String id, String naslov, String zasedba});

/// Naslov snemanja iz nastopa: »Poroka, Ajdovščina (2. 11. 2026)«.
PredlogNastopa predlogIzNastopa(Map<String, dynamic> n) {
  final d = DateTime.tryParse(n['Datum']?.toString() ?? '');
  final opis = [n['Dogodek'], n['Kraj']].map((x) => x?.toString().trim() ?? '').where((x) => x.isNotEmpty).join(', ');
  final datum = d == null ? '' : '${d.day}. ${d.month}. ${d.year}';
  final zasedba = n['ZasedbaIme']?.toString() ?? '';
  return (
    id: n['ID']?.toString() ?? '',
    naslov: [
      if (opis.isNotEmpty) opis else 'Nastop',
      if (datum.isNotEmpty) '($datum)',
      if (zasedba.isNotEmpty) '· $zasedba',
    ].join(' '),
    zasedba: n['Zasedba']?.toString() ?? '',
  );
}

/// Okno za začetek snemanja: predlagan današnji nastop iz Nastopov ali »Brez nastopa« (naslov je datum in ura),
/// na napravi, ki snema, še zvočni vhod.
Future<void> zacniSnemanje(BuildContext context, Baza baza) async {
  final s = SnemanjeSpila.aplikacija;
  final api = s.api?.call();
  // Sledilec v aplikaciji lahko snema sam ali naroči vodji; brez špila snema ta naprava.
  final lahkoTu = !kIsWeb;
  var tuSnema = s.vodji == null;
  // Nastopi so v lokalni bazi (tudi brez interneta); če jih tam ni, vpraša skripto.
  final lokalni = [for (final n in baza.nastopiOkrog(DateTime.now())) predlogIzNastopa(n)];
  final nastopi = lokalni.isNotEmpty || api == null
      ? Future.value(lokalni)
      : api
            .nastopi(DateTime.now())
            .then(
              (o) => [for (final n in (o['nastopi'] as List? ?? const []).whereType<Map>()) predlogIzNastopa(n.cast())],
            )
            .timeout(const Duration(seconds: 10))
            .catchError((Object _) => const <PredlogNastopa>[]);
  final vhodi = lahkoTu ? s.vhodi() : Future.value(const <VhodZvoka>[]);
  var vhod = lahkoTu ? await s.shranjenVhod() : null;
  if (!context.mounted) return;
  final brez = SnemanjeSpila.privzetNaslov(DateTime.now());
  final naslov = TextEditingController(text: brez);
  PredlogNastopa? izbran;
  var prvic = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, nastavi) => AlertDialog(
        title: const Text('Snemanje špila'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FutureBuilder(
                  future: nastopi,
                  builder: (context, p) {
                    if (p.connectionState != ConnectionState.done) {
                      return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
                    }
                    final seznam = p.data ?? const <PredlogNastopa>[];
                    // Prvi današnji nastop je predlagan.
                    if (prvic && seznam.isNotEmpty) {
                      prvic = false;
                      izbran = seznam.first;
                      naslov.text = izbran!.naslov;
                    }
                    void izberi(PredlogNastopa? n) => nastavi(() {
                      izbran = n;
                      naslov.text = n?.naslov ?? brez;
                    });
                    return RadioGroup<String>(
                      groupValue: izbran?.id ?? '',
                      onChanged: (v) => izberi(seznam.where((n) => n.id == v).firstOrNull),
                      child: Column(
                        children: [
                          for (final n in seznam)
                            RadioListTile<String>(contentPadding: EdgeInsets.zero, value: n.id, title: Text(n.naslov)),
                          RadioListTile<String>(
                            key: const ValueKey('brez-nastopa'),
                            contentPadding: EdgeInsets.zero,
                            value: '',
                            title: const Text('Brez nastopa'),
                            subtitle: Text(seznam.isEmpty ? 'Nastopa za danes ni bilo mogoče najti.' : brez),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('naslov-snemanja'),
                  controller: naslov,
                  decoration: const InputDecoration(labelText: 'Naslov na videu', border: OutlineInputBorder()),
                ),
                if (s.vodji != null && lahkoTu) ...[
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    key: const ValueKey('kdo-snema'),
                    segments: const [
                      ButtonSegment(value: false, icon: Icon(Icons.cast), label: Text('Snema vodja')),
                      ButtonSegment(value: true, icon: Icon(Icons.phone_android), label: Text('Snema ta naprava')),
                    ],
                    selected: {tuSnema},
                    onSelectionChanged: (v) => nastavi(() => tuSnema = v.first),
                  ),
                ],
                if (tuSnema) ...[
                  const SizedBox(height: 12),
                  FutureBuilder(
                    future: vhodi,
                    builder: (context, p) {
                      final seznam = p.data ?? const <VhodZvoka>[];
                      if (seznam.isEmpty) return const SizedBox.shrink();
                      return DropdownButtonFormField<String>(
                        initialValue: seznam.any((v) => v.id == vhod) ? vhod : '',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Zvočni vhod', border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('Privzeti')),
                          for (final v in seznam)
                            DropdownMenuItem(
                              value: v.id,
                              child: Text(v.ime, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => vhod = v == null || v.isEmpty ? null : v,
                      );
                    },
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Snemala bo naprava, ki vodi špil (z njenim izbranim vhodom).'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Prekliči')),
          FilledButton.icon(
            key: const ValueKey('potrdi-snemanje'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.fiber_manual_record),
            label: const Text('Snemaj'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  if (tuSnema) await s.nastaviVhod(vhod);
  await s.zacni(naslov: naslov.text, nastop: izbran?.id ?? '', zasedba: izbran?.zasedba ?? baza.zasedba, tu: tuSnema);
}
