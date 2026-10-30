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

/// Ocena z zvezdicami; z [spremeni] se da klikniti (ponoven klik iste zvezdice oceno pobriše).
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
        for (var i = 1; i <= 5; i++)
          spremeni == null
              ? Icon(i <= ocena ? Icons.star : Icons.star_border, size: velikost, color: Colors.amber)
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

/// Rdeč klicaj (pesem za ponoviti na vaji).
class Klicaj extends StatelessWidget {
  const Klicaj({super.key, this.velikost = 18});

  final double velikost;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Za ponoviti na vaji',
    child: Text(
      '!',
      style: TextStyle(fontSize: velikost, fontWeight: FontWeight.w900, color: Colors.red, height: 1),
    ),
  );
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
            if (pesem.zaVajo) const Padding(padding: EdgeInsets.only(right: 4), child: Klicaj()),
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
