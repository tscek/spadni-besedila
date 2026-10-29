import 'package:flutter/material.dart';

/// Pot do druge pesmi: z [smer] 1 (naslednja) pride od desne, z -1 (prejšnja) od leve, sicer običajen prehod.
Route<void> potDoPesmi(WidgetBuilder stran, {int smer = 0}) {
  if (smer == 0) return MaterialPageRoute<void>(builder: stran);
  return PageRouteBuilder<void>(
    pageBuilder: (context, _, _) => stran(context),
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animacija, _, child) => SlideTransition(
      position: Tween(
        begin: Offset(smer.toDouble(), 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animacija, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Zamenjava pesmi na istem zaslonu (setlista): nova pesem pride od desne ([smer] 1) ali leve (-1), stara gre ven.
class PrehodPesmi extends StatelessWidget {
  const PrehodPesmi({super.key, required this.smer, required this.child});

  final int smer;

  /// Vsaka pesem mora imeti svoj ključ.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: smer == 0 ? 0 : 250),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        layoutBuilder: (trenutna, prejsnje) => Stack(children: [...prejsnje, ?trenutna]),
        transitionBuilder: (otrok, animacija) {
          // Nova pesem pride z ene strani, stara (animacija teče nazaj) gre na drugo.
          final nova = otrok.key == child.key;
          final zacetek = Offset((nova ? smer : -smer).toDouble(), 0);
          return SlideTransition(
            position: Tween(begin: zacetek, end: Offset.zero).animate(animacija),
            child: otrok,
          );
        },
        child: child,
      ),
    );
  }
}
