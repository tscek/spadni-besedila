/// Tap tempo: tempo iz povprečja zadnjih udarcev; po premoru, daljšem od [premor], začne znova.
class TapTempo {
  TapTempo({this.premor = const Duration(seconds: 2), this.najvec = 8});

  final Duration premor;

  /// Koliko zadnjih udarcev šteje v povprečje.
  final int najvec;

  final _udarci = <DateTime>[];

  /// Zabeleži udarec in vrne tempo (BPM) ali null, dokler ni vsaj dveh udarcev.
  int? udari([DateTime? cas]) {
    final t = cas ?? DateTime.now();
    if (_udarci.isNotEmpty && t.difference(_udarci.last) > premor) _udarci.clear();
    _udarci.add(t);
    if (_udarci.length > najvec) _udarci.removeAt(0);
    if (_udarci.length < 2) return null;
    final ms = _udarci.last.difference(_udarci.first).inMicroseconds / 1000 / (_udarci.length - 1);
    if (ms <= 0) return null;
    return (60000 / ms).round();
  }

  int get steviloUdarcev => _udarci.length;
}
