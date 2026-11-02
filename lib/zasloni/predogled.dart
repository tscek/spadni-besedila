import 'package:flutter/material.dart';

import '../baza.dart';
import 'besedilo_risanje.dart';

/// Naprava za predogled besedila: velikost zaslona v logičnih točkah (pokončno).
enum NapravaPredogleda {
  ta('Ta naprava', Icons.fit_screen_outlined, null),
  telefon('Telefon', Icons.smartphone, Size(393, 852)),
  ipad('iPad', Icons.tablet_mac, Size(820, 1180)),
  racunalnik('Računalnik', Icons.computer, Size(1366, 768));

  const NapravaPredogleda(this.ime, this.ikona, this.velikost);
  final String ime;
  final IconData ikona;
  final Size? velikost;
}

/// Višina zgornje in spodnje vrstice zaslona pesmi (približno), ki ju predogled odšteje.
const _vrstice = 56.0 + 48.0;

/// Predogled besedila, kot ga pokaže zaslon pesmi, na izbrani napravi (vrstice so povsod enake).
class PredogledBesedila extends StatefulWidget {
  const PredogledBesedila({
    super.key,
    required this.vsebina,
    required this.pesem,
    required this.baza,
    required this.pisava,
    this.obPisavi,
  });

  final String vsebina;

  /// Pisava pesmi na strani; [obPisavi] jo spremeni (urednik).
  final double pisava;
  final ValueChanged<double>? obPisavi;
  final String pesem;
  final Baza baza;

  @override
  State<PredogledBesedila> createState() => _PredogledBesedilaState();
}

class _PredogledBesedilaState extends State<PredogledBesedila> {
  var _naprava = NapravaPredogleda.ta;
  var _lezece = false;
  final _risanje = ValueNotifier(false);

  @override
  void dispose() {
    _risanje.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final besedilo = BesediloZRisanjem(
      key: ValueKey('predogled-${widget.pisava}-${_naprava.name}-$_lezece'),
      vsebina: widget.vsebina,
      pisava: widget.pisava,
      pesem: widget.pesem,
      risbe: widget.baza.risbe,
      risbeSkupne: widget.baza.risbeSkupne,
      risanje: _risanje,
      knjiznica: widget.baza.midi,
    );
    var velikost = _naprava.velikost;
    if (velikost != null && _lezece != (velikost.width > velikost.height)) velikost = velikost.flipped;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SegmentedButton<NapravaPredogleda>(
                  showSelectedIcon: false,
                  segments: [
                    for (final d in NapravaPredogleda.values)
                      ButtonSegment(value: d, icon: Icon(d.ikona), label: Text(d.ime)),
                  ],
                  selected: {_naprava},
                  onSelectionChanged: (v) => setState(() {
                    _naprava = v.first;
                    _lezece = _naprava == NapravaPredogleda.racunalnik;
                  }),
                ),
                if (widget.obPisavi case final obPisavi?) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Manjša pisava',
                    icon: const Icon(Icons.text_decrease),
                    onPressed: widget.pisava > 12 ? () => obPisavi(widget.pisava - 1) : null,
                  ),
                  Text('${widget.pisava.round()}', key: const ValueKey('pisava-pesmi')),
                  IconButton(
                    tooltip: 'Večja pisava',
                    icon: const Icon(Icons.text_increase),
                    onPressed: widget.pisava < 64 ? () => obPisavi(widget.pisava + 1) : null,
                  ),
                ],
                if (_naprava.velikost != null)
                  IconButton(
                    tooltip: _lezece ? 'Pokončno' : 'Ležeče',
                    icon: Icon(_lezece ? Icons.stay_current_portrait : Icons.stay_current_landscape),
                    onPressed: () => setState(() => _lezece = !_lezece),
                  ),
              ],
            ),
          ),
        ),
        if (velikost != null)
          Text(
            '${velikost.width.round()} × ${velikost.height.round()} točk, pisava pesmi ${widget.pisava.round()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        Expanded(
          child: velikost == null
              ? besedilo
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: FittedBox(
                    child: Container(
                      key: const ValueKey('okvir-predogleda'),
                      width: velikost.width,
                      height: velikost.height - _vrstice,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(color: Theme.of(context).colorScheme.outline, width: 3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(size: Size(velikost.width, velikost.height - _vrstice)),
                        child: besedilo,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
