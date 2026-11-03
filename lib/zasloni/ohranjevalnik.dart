import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../baza.dart';
import '../models.dart' show besedilo;
import '../runda.dart';

const _dnevi = ['ponedeljek', 'torek', 'sreda', 'četrtek', 'petek', 'sobota', 'nedelja'];

/// Datum v obliki »torek, 3. 11. 2026«.
String datumBesedilo(DateTime t) => '${_dnevi[t.weekday - 1]}, ${t.day}. ${t.month}. ${t.year}';

/// Naslov in kraj današnjega nastopa (iz lokalne baze), npr. »Poroka · Ajdovščina«.
({String naslov, String kraj})? nastopZaOhranjevalnik(Baza baza, DateTime t) {
  final n = baza.nastopDanes(t);
  if (n == null) return null;
  final naslov = [besedilo(n['Dogodek']), besedilo(n['ZasedbaIme'])].where((x) => x.isNotEmpty).join(' · ');
  return (naslov: naslov.isEmpty ? 'Nastop' : naslov, kraj: besedilo(n['Kraj']));
}

/// Ob PAVZI (skupni na špilu) pokaže čez vse temen zaslon z uro, datumom in nastopom.
/// Tap ga zapre na tej napravi, ŠPILEJ!! povsod.
class Ohranjevalnik extends StatefulWidget {
  const Ohranjevalnik({super.key, required this.baza, required this.child, this.runda});

  final Baza baza;
  final Widget child;
  final Runda? runda;

  /// Pavza, starejša od tega, je ostala od prejšnjega špila.
  static const najdlje = Duration(hours: 3);

  @override
  State<Ohranjevalnik> createState() => _OhranjevalnikState();
}

class _OhranjevalnikState extends State<Ohranjevalnik> {
  Runda get _runda => widget.runda ?? Runda.aplikacija;
  DateTime? _zaprtaPavza;
  Timer? _ura;
  final _nakljucno = Random();
  Alignment _mesto = Alignment.center;
  int _minuta = -1;

  bool get _prikazan {
    final r = _runda;
    return r.pavza == true && r.zacetek != null && r.zacetek != _zaprtaPavza && r.trenutno() < Ohranjevalnik.najdlje;
  }

  @override
  void initState() {
    super.initState();
    _runda.addListener(_obRundi);
    _obRundi();
  }

  @override
  void dispose() {
    _runda.removeListener(_obRundi);
    _ura?.cancel();
    super.dispose();
  }

  void _obRundi() {
    if (_prikazan) {
      _ura ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        // Vsako minuto se vsebina malo premakne, da se zaslon ne zapeče.
        final m = DateTime.now().minute;
        if (m != _minuta) {
          _minuta = m;
          _mesto = Alignment(_nakljucno.nextDouble() * 0.6 - 0.3, _nakljucno.nextDouble() * 0.6 - 0.3);
        }
        setState(() {});
      });
    } else {
      _ura?.cancel();
      _ura = null;
    }
    if (mounted) setState(() {});
  }

  void _zapri() {
    _zaprtaPavza = _runda.zacetek;
    _obRundi();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_prikazan) Positioned.fill(child: _zaslon(context)),
      ],
    );
  }

  Widget _zaslon(BuildContext context) {
    final zdaj = DateTime.now();
    final nastop = nastopZaOhranjevalnik(widget.baza, zdaj);
    String dv(int x) => x.toString().padLeft(2, '0');
    const bela = Color(0xFFE8E8E8);
    const siva = Color(0xFF9AA0A6);
    return GestureDetector(
      key: const ValueKey('ohranjevalnik'),
      behavior: HitTestBehavior.opaque,
      onTap: _zapri,
      child: ColoredBox(
        color: const Color(0xFF050608),
        child: SafeArea(
          child: AnimatedAlign(
            duration: const Duration(seconds: 3),
            alignment: _mesto,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${zdaj.hour}:${dv(zdaj.minute)}',
                      style: const TextStyle(
                        color: bela,
                        fontSize: 140,
                        fontWeight: FontWeight.w300,
                        fontFeatures: [FontFeature.tabularFigures()],
                        decoration: TextDecoration.none,
                      ),
                    ),
                    Text(
                      datumBesedilo(zdaj),
                      style: const TextStyle(color: siva, fontSize: 30, decoration: TextDecoration.none),
                    ),
                    if (nastop != null) ...[
                      const SizedBox(height: 28),
                      Text(
                        nastop.naslov,
                        key: const ValueKey('ohranjevalnik-nastop'),
                        style: const TextStyle(color: bela, fontSize: 34, decoration: TextDecoration.none),
                      ),
                      if (nastop.kraj.isNotEmpty)
                        Text(
                          nastop.kraj,
                          style: const TextStyle(color: siva, fontSize: 28, decoration: TextDecoration.none),
                        ),
                    ],
                    const SizedBox(height: 28),
                    Text(
                      'Pavza ${casBesedilo(_runda.trenutno(zdaj: zdaj))}',
                      style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 26, decoration: TextDecoration.none),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
