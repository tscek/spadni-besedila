/// Gumb nad XY padom: napis in ukazi (imena ukazov ali makrov, ločena s ;).
class GumbXy {
  const GumbXy(this.napis, this.ukazi);
  final String napis;
  final String ukazi;
}

/// XY pad na tej napravi: CC za vodoravno in navpično os ter do 4 gumbi nad padom.
class NastavitveXy {
  const NastavitveXy({this.x = '', this.y = '', this.gumbi = const []});

  factory NastavitveXy.izJson(Map<String, dynamic> j) => NastavitveXy(
    x: j['x']?.toString() ?? '',
    y: j['y']?.toString() ?? '',
    gumbi: [
      for (final g in (j['g'] as List?) ?? const [])
        if (g is Map) GumbXy(g['n']?.toString() ?? '', g['u']?.toString() ?? ''),
    ].take(najvecGumbov).toList(),
  );

  static const najvecGumbov = 4;

  /// CC ukaz za vodoravno os (levo 0, desno 127).
  final String x;

  /// CC ukaz za navpično os (spodaj 0, zgoraj 127).
  final String y;
  final List<GumbXy> gumbi;

  bool get nastavljen => x.isNotEmpty || y.isNotEmpty || gumbi.isNotEmpty;

  Map<String, dynamic> vJson() => {
    'x': x,
    'y': y,
    'g': [
      for (final g in gumbi) {'n': g.napis, 'u': g.ukazi},
    ],
  };

  NastavitveXy kopija({String? x, String? y, List<GumbXy>? gumbi}) =>
      NastavitveXy(x: x ?? this.x, y: y ?? this.y, gumbi: gumbi ?? this.gumbi);
}
