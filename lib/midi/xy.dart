/// Gumb nad XY padom: napis in ukazi (imena ukazov ali makrov, ločena s ;).
class GumbXy {
  const GumbXy(this.napis, this.ukazi);
  final String napis;
  final String ukazi;
}

/// Skupina kontrol XY pada: ime in CC ukaza za vodoravno in navpično os.
class SkupinaXy {
  const SkupinaXy(this.ime, this.x, this.y);

  /// Ime (gumb pod padom), npr. »Efekt« ali »Mešalka«.
  final String ime;

  /// CC ukaz za vodoravno os (levo 0, desno 127).
  final String x;

  /// CC ukaz za navpično os (spodaj 0, zgoraj 127).
  final String y;
}

/// XY pad na tej napravi: skupine osi (izbiraš jih z gumbi pod padom) in do 4 gumbi nad padom.
class NastavitveXy {
  const NastavitveXy({this.skupine = const [], this.gumbi = const []});

  factory NastavitveXy.izJson(Map<String, dynamic> j) {
    final skupine = [
      for (final s in (j['s'] as List?) ?? const [])
        if (s is Map) SkupinaXy(s['n']?.toString() ?? '', s['x']?.toString() ?? '', s['y']?.toString() ?? ''),
    ];
    // Prejšnji zapis z eno samo parom osi.
    final x = j['x']?.toString() ?? '';
    final y = j['y']?.toString() ?? '';
    if (skupine.isEmpty && (x.isNotEmpty || y.isNotEmpty)) skupine.add(SkupinaXy('XY', x, y));
    return NastavitveXy(
      skupine: skupine.take(najvecSkupin).toList(),
      gumbi: [
        for (final g in (j['g'] as List?) ?? const [])
          if (g is Map) GumbXy(g['n']?.toString() ?? '', g['u']?.toString() ?? ''),
      ].take(najvecGumbov).toList(),
    );
  }

  static const najvecGumbov = 4;
  static const najvecSkupin = 8;

  final List<SkupinaXy> skupine;
  final List<GumbXy> gumbi;

  bool get nastavljen => skupine.isNotEmpty || gumbi.isNotEmpty;

  Map<String, dynamic> vJson() => {
    's': [
      for (final s in skupine) {'n': s.ime, 'x': s.x, 'y': s.y},
    ],
    'g': [
      for (final g in gumbi) {'n': g.napis, 'u': g.ukazi},
    ],
  };

  NastavitveXy kopija({List<SkupinaXy>? skupine, List<GumbXy>? gumbi}) =>
      NastavitveXy(skupine: skupine ?? this.skupine, gumbi: gumbi ?? this.gumbi);
}
