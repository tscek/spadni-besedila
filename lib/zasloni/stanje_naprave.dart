import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api.dart';
import '../baza.dart';
import '../config.dart';
import '../prijava.dart';
import '../risbe.dart';
import '../spil/spil.dart';

/// Pregled za iskanje težav na napravi: različica, vloge, obračanje za vse, risbe na napravi.
/// Z gumbom »Prenesi vse risbe znova« se risbe prenesejo s strežnika ne glede na zadnjo uskladitev.
class StanjeNapraveZaslon extends StatefulWidget {
  const StanjeNapraveZaslon({super.key, required this.baza, required this.prijava, required this.spil});

  final Baza baza;
  final Prijava prijava;
  final Spil spil;

  @override
  State<StanjeNapraveZaslon> createState() => _StanjeNapraveZaslonState();
}

typedef _Povzetek = ({int stevilo, String usklajeno, int neposlanih});

class _StanjeNapraveZaslonState extends State<StanjeNapraveZaslon> {
  String _verzija = '';
  _Povzetek? _osebne;
  _Povzetek? _skupne;
  bool _prenasam = false;
  String? _rezultat;

  Baza get baza => widget.baza;

  @override
  void initState() {
    super.initState();
    _beri();
  }

  Future<void> _beri() async {
    try {
      final i = await PackageInfo.fromPlatform();
      _verzija = '${i.version} (${i.buildNumber})';
    } catch (_) {
      _verzija = '?';
    }
    final o = await baza.risbe.povzetek();
    final s = await baza.risbeSkupne.povzetek();
    if (!mounted) return;
    setState(() {
      _osebne = o;
      _skupne = s;
    });
  }

  Future<String> _prenesi(Risbe r, Api api, {String clan = ''}) async {
    try {
      await r.pozabiUskladitev();
      return '${await r.sinhroniziraj(api, clan: clan)} prenesenih';
    } catch (e) {
      return 'napaka: $e';
    }
  }

  Future<void> _prenesiVse() async {
    setState(() {
      _prenasam = true;
      _rezultat = null;
    });
    final api = Api(widget.prijava.zeton);
    final osebne = await _prenesi(baza.risbe, api, clan: baza.clanId);
    final skupne = await _prenesi(baza.risbeSkupne, api);
    await _beri();
    if (!mounted) return;
    setState(() {
      _prenasam = false;
      _rezultat = 'Osebne risbe: $osebne. Skupne risbe: $skupne.';
    });
  }

  String _naprava() {
    if (kIsWeb) return Config.prekoVodje ? 'brskalnik prek vodje' : 'brskalnik';
    return defaultTargetPlatform.name;
  }

  String _risbe(_Povzetek? p) {
    if (p == null) return '…';
    final cas = p.usklajeno.contains('|') ? p.usklajeno.substring(p.usklajeno.lastIndexOf('|') + 1) : p.usklajeno;
    return '${p.stevilo} na napravi, usklajeno ${cas.isEmpty ? 'še nikoli' : cas.replaceFirst('T', ' ').split('.').first}'
        '${p.neposlanih > 0 ? ', ${p.neposlanih} čaka na pošiljanje' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final o = baza.obracanje;
    final vloge = baza.vloge.map((v) => '${v.vloga}${v.smeVoditi ? ' (sme voditi)' : ''}').toSet();
    final vrstice = <(String, String)>[
      ('Različica', _verzija),
      ('Naprava', _naprava()),
      ('Član', '${baza.clanId.isEmpty ? '-' : baza.clanId} ${widget.prijava.email ?? ''}'.trim()),
      ('Vloge', vloge.isEmpty ? 'nobene (samo ogled)' : vloge.join(', ')),
      ('Sme urejati pesmi in skupne risbe', baza.smeUrejati ? 'da' : 'ne'),
      ('Obračanje za vse (nastavitev)', o.vsi ? 'vsi${o.neprijavljeni ? ', tudi neprijavljeni' : ''}' : 'samo vodja'),
      ('Ta naprava sme obračati za vse', baza.obracaZaVse ? 'da' : 'ne'),
      (
        'Špil',
        switch (widget.spil.vloga) {
          VlogaSpila.nic => 'ni povezana (za obračanje za vse se poveži na špil)',
          VlogaSpila.vodja => 'vodja',
          VlogaSpila.sledilec => widget.spil.povezan ? 'sledilec, povezan' : 'sledilec, ni povezan',
        },
      ),
      ('Osebne risbe', _risbe(_osebne)),
      ('Skupne risbe', _risbe(_skupne)),
      ('Zadnja osvežitev', baza.zadnjaOsvezitev?.toLocal().toString().split('.').first ?? 'še nikoli'),
      if (baza.neposlano.isNotEmpty) ('Neposlane spremembe', '${baza.neposlano.length}'),
      if (baza.stanje != null) ('Sporočilo osvežitve', baza.stanje!),
      if (baza.napaka != null) ('Napaka osvežitve', baza.napaka!),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Stanje naprave')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (k, v) in vrstice)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 200,
                    child: Text(k, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: SelectableText(v)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (!Config.prekoVodje)
            FilledButton.icon(
              onPressed: _prenasam ? null : _prenesiVse,
              icon: _prenasam
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download),
              label: Text(_prenasam ? 'Prenašam risbe …' : 'Prenesi vse risbe znova'),
            ),
          if (_rezultat != null) Padding(padding: const EdgeInsets.only(top: 12), child: SelectableText(_rezultat!)),
        ],
      ),
    );
  }
}
