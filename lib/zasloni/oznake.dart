import 'package:flutter/material.dart';

import '../baza.dart';
import '../models.dart';
import '../odigrane.dart';

/// Ikona in barva statusa pesmi.
(IconData, Color) ikonaStatusa(StatusPesmi s) => switch (s) {
  StatusPesmi.predlog => (Icons.lightbulb_outline, Colors.amber),
  StatusPesmi.vDelu => (Icons.construction, Colors.orange),
  StatusPesmi.narejen => (Icons.check_circle_outline, Colors.green),
  StatusPesmi.arhiv => (Icons.archive_outlined, Colors.grey),
};

class IkonaStatusa extends StatelessWidget {
  const IkonaStatusa(this.status, {super.key, this.velikost = 18});

  final StatusPesmi status;
  final double velikost;

  @override
  Widget build(BuildContext context) {
    final (ikona, barva) = ikonaStatusa(status);
    return Tooltip(
      message: status.ime,
      child: Icon(ikona, size: velikost, color: barva),
    );
  }
}

/// Barva harmonike s seznama harmonik (null, če je ni ali nima barve).
Color? barvaHarmonike(Baza baza, String ime) {
  final argb = baza.harmonika(ime)?.argb;
  return argb == null ? null : Color(argb);
}

/// Barva vrste pesmi s seznama vrst (null, če je ni).
Color? barvaVrste(Baza baza, String ime) {
  final argb = baza.vrsta(ime)?.argb;
  return argb == null ? null : Color(argb);
}

/// Podatki pesmi za podnaslov vrstice, ločeni s piko; vrsta in harmonika sta v svoji barvi.
/// Ocena in status sta prikazana posebej (zvezdice, ikona), zato ju tu ni.
List<InlineSpan> poljaVPodnaslovu(BuildContext context, Baza baza, Pesem p, List<PoljePesmi> polja) {
  final deli = <InlineSpan>[];
  for (final x in polja) {
    if (x == PoljePesmi.naslov || x == PoljePesmi.status || x == PoljePesmi.ocena) continue;
    final v = x.vrednost(p);
    if (v.isEmpty) continue;
    final barva = switch (x) {
      PoljePesmi.harmonika => barvaHarmonike(baza, v),
      PoljePesmi.vrsta => barvaVrste(baza, v),
      _ => null,
    };
    if (deli.isNotEmpty) deli.add(const TextSpan(text: ' · '));
    deli.add(
      TextSpan(
        text: v,
        style: barva == null ? null : TextStyle(color: barva, fontWeight: FontWeight.w600),
      ),
    );
  }
  return deli;
}

/// Ocena z zvezdicami (samo toliko zvezdic, kot je ocena); z [spremeni] se da klikniti
/// (pokaže vseh pet, ponoven klik iste zvezdice oceno pobriše).
class Zvezdice extends StatelessWidget {
  const Zvezdice({super.key, required this.ocena, this.spremeni, this.velikost = 16});

  final int ocena;
  final ValueChanged<int>? spremeni;
  final double velikost;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= (spremeni == null ? ocena : 5); i++)
          spremeni == null
              ? Icon(Icons.star, size: velikost, color: Colors.amber)
              : IconButton(
                  tooltip: '$i',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => spremeni!(i == ocena ? 0 : i),
                  icon: Icon(i <= ocena ? Icons.star : Icons.star_border, size: velikost, color: Colors.amber),
                ),
      ],
    );
  }
}

/// Rdeč klicaj (pesem za ponoviti na vaji); s [stevilo] več kot 1 jih je več (do tri, nato številka).
class Klicaj extends StatelessWidget {
  const Klicaj({super.key, this.velikost = 18, this.stevilo = 1});

  final double velikost;
  final int stevilo;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: stevilo > 1 ? 'Za ponoviti na vaji ($stevilo mesta)' : 'Za ponoviti na vaji',
    child: Text(
      stevilo > 3 ? '!$stevilo' : '!' * stevilo.clamp(1, 3),
      style: TextStyle(fontSize: velikost, fontWeight: FontWeight.w900, color: Colors.red, height: 1),
    ),
  );
}

/// Klicaj, ki utripa (na besedilu).
class UtripajociKlicaj extends StatefulWidget {
  const UtripajociKlicaj({super.key, this.velikost = 40});

  final double velikost;

  @override
  State<UtripajociKlicaj> createState() => _UtripajociKlicajState();
}

class _UtripajociKlicajState extends State<UtripajociKlicaj> with SingleTickerProviderStateMixin {
  late final _animacija = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void dispose() {
    _animacija.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Brez animacij (nastavitev dostopnosti) klicaj ne utripa.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _animacija.stop();
    } else if (!_animacija.isAnimating) {
      _animacija.repeat(reverse: true);
    }
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.25).animate(_animacija),
      child: Text(
        '!',
        style: TextStyle(
          fontSize: widget.velikost,
          fontWeight: FontWeight.w900,
          color: Colors.red,
          height: 1,
          shadows: const [Shadow(color: Colors.white, blurRadius: 4)],
        ),
      ),
    );
  }
}

/// Siva ikona predvajanja: pesem je bila ta večer že odigrana.
class IkonaOdigrane extends StatelessWidget {
  const IkonaOdigrane({super.key, this.velikost = 18});

  final double velikost;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Že odigrana',
    child: Icon(Icons.play_circle, size: velikost, color: Colors.grey),
  );
}

/// Oznake pred naslovom pesmi v vseh seznamih: odigrana in klicaj.
class OznakePesmi extends StatelessWidget {
  const OznakePesmi({super.key, required this.pesem});

  final Pesem pesem;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Odigrane.aplikacija,
      builder: (context, _) {
        final odigrana = Odigrane.aplikacija.je(pesem.id);
        if (!odigrana && !pesem.zaVajo) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pesem.zaVajo)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Klicaj(stevilo: pesem.klicaji),
              ),
            if (odigrana) const Padding(padding: EdgeInsets.only(right: 4), child: IkonaOdigrane()),
          ],
        );
      },
    );
  }
}

/// Naslov pesmi z oznakami (odigrana, klicaj) za vrstice seznamov.
class NaslovZOznakami extends StatelessWidget {
  const NaslovZOznakami({super.key, required this.pesem, this.slog, this.predpona = ''});

  final Pesem pesem;
  final TextStyle? slog;
  final String predpona;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OznakePesmi(pesem: pesem),
        Flexible(
          child: Text('$predpona${pesem.naslov}', style: slog, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// Bela ali črna, kar se bolje bere na [ozadje].
Color kontrastnaBarva(Color ozadje) =>
    ThemeData.estimateBrightnessForColor(ozadje) == Brightness.dark ? Colors.white : Colors.black;

/// Širina besedila v eni vrstici.
double sirinaBesedila(String besedilo, TextStyle? slog) {
  final tp = TextPainter(
    text: TextSpan(text: besedilo, style: slog),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}
