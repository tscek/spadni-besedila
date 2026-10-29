import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../risbe.dart';
import 'pdf_risanje.dart';
import 'pesem_zaslon.dart';

/// Besedilo kot stran stalne širine z risbami in opombami (enako kot pri PDF-ju).
/// Vrstice se vedno prelomijo enako, zato risba ostane na istem mestu na vsakem zaslonu;
/// večja pisava stran le poveča. Risbe besedila so v isti risbi pesmi kot stran 0.
class BesediloZRisanjem extends StatefulWidget {
  const BesediloZRisanjem({
    super.key,
    required this.vsebina,
    required this.povecava,
    required this.pesem,
    required this.risbe,
  });

  /// Širina strani v logičnih točkah in pisava, pri kateri je povečava 1.
  static const sirinaStrani = 600.0;
  static const osnovnaPisava = 22.0;

  /// Stran 0 v risbi pesmi je besedilo (PDF ima strani od 1 naprej).
  static const stran = 0;

  final String vsebina;
  final double povecava;
  final String pesem;
  final Risbe risbe;

  @override
  State<BesediloZRisanjem> createState() => _BesediloZRisanjemState();
}

class _BesediloZRisanjemState extends State<BesediloZRisanjem> with RisanjeNaStrani {
  @override
  Risbe get risbe => widget.risbe;

  @override
  String get pesem => widget.pesem;

  @override
  bool mojaStran(int stran) => stran == BesediloZRisanjem.stran;

  @override
  bool get temnoOzadje => Theme.of(context).brightness == Brightness.dark;

  @override
  String get opisIzbrisa => 'Izbrišem vse risbe in opombe na besedilu?';

  @override
  Widget build(BuildContext context) {
    const sirina = BesediloZRisanjem.sirinaStrani;
    final premikanje = risem ? const NeverScrollableScrollPhysics() : null;
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, omejitve) {
            // Pri povečavi 1 je stran široka kot zaslon; večja pisava jo poveča (premikanje tudi vstran).
            final prikazano = math.max(omejitve.maxWidth * widget.povecava, 1.0);
            return SingleChildScrollView(
              physics: premikanje,
              padding: EdgeInsets.only(bottom: risem ? 160 : 88),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: premikanje,
                child: SizedBox(
                  width: math.max(prikazano, omejitve.maxWidth),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: prikazano,
                      child: FittedBox(
                        fit: BoxFit.fitWidth,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: sirina,
                          child: _Stran(
                            sloj: (velikost) => slojStrani(BesediloZRisanjem.stran, velikost, enotaY: sirina),
                            // Prostor pod kratkim besedilom za opombe.
                            child: Container(
                              constraints: const BoxConstraints(minHeight: sirina),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: BesediloPogled.vrstice(
                                  context,
                                  widget.vsebina,
                                  BesediloZRisanjem.osnovnaPisava,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        ...kontrole(context),
      ],
    );
  }
}

/// Besedilo s slojem risb čez celo stran (velikost sloja = velikost besedila).
class _Stran extends StatelessWidget {
  const _Stran({required this.sloj, required this.child});

  final Widget Function(Size velikost) sloj;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(child: LayoutBuilder(builder: (context, o) => sloj(Size(o.maxWidth, o.maxHeight)))),
      ],
    );
  }
}
