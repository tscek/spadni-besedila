import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../prijava.dart';

/// Oblaček s številko sprememb, ki še niso na strežniku (v zgornji vrstici).
/// Brez čakajočih sprememb ga ni; dotik jih poskusi poslati takoj.
class IkonaNeposlanih extends StatelessWidget {
  const IkonaNeposlanih({super.key, required this.baza, required this.prijava});

  final Baza baza;
  final Prijava prijava;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: baza,
    builder: (context, _) {
      final n = baza.steviloNeposlanih;
      if (n == 0) return const SizedBox.shrink();
      final brezPovezave = baza.cakaPovezavo;
      return IconButton(
        tooltip: brezPovezave ? '$n sprememb čaka na internet' : 'Pošiljam $n sprememb …',
        icon: Badge.count(
          count: n,
          child: Icon(
            brezPovezave ? Icons.cloud_off_outlined : Icons.cloud_upload_outlined,
            color: brezPovezave ? Theme.of(context).colorScheme.error : null,
          ),
        ),
        onPressed: () {
          final sporocila = ScaffoldMessenger.of(context);
          if (!prijava.prijavljen) {
            sporocila.showSnackBar(
              SnackBar(content: Text('$n sprememb je na napravi. Za pošiljanje se prijavi (potreben je internet).')),
            );
            return;
          }
          baza.posljiZdaj(Api(prijava.zeton));
          sporocila.showSnackBar(
            SnackBar(
              content: Text(
                brezPovezave ? '$n sprememb čaka na internet. Poskušam znova …' : 'Pošiljam $n sprememb na strežnik …',
              ),
            ),
          );
        },
      );
    },
  );
}
