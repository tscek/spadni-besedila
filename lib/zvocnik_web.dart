import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'zvocnik.dart';

Zvocnik ustvari() => _ZvocnikWeb();

/// En sam HTML audio element; posnetki so pripravljeni kot blob: naslovi, zato se `play()`
/// pokliče sinhrono v dotiku in ga Safari dovoli.
class _ZvocnikWeb implements Zvocnik {
  _ZvocnikWeb() {
    _el.preload = 'auto';
    _narocnine
      ..add(web.EventStreamProviders.timeUpdateEvent.forTarget(_el).listen((_) => _pozicija.add(_cas(_el.currentTime))))
      ..add(
        web.EventStreamProviders.durationChangeEvent.forTarget(_el).listen((_) {
          if (_el.duration.isFinite && _el.duration > 0) _trajanje.add(_cas(_el.duration));
        }),
      )
      ..add(web.EventStreamProviders.endedEvent.forTarget(_el).listen((_) => _konec.add(null)));
  }

  final _el = web.HTMLAudioElement();
  final _naslovi = <String, String>{};
  final _narocnine = <StreamSubscription<web.Event>>[];
  final _pozicija = StreamController<Duration>.broadcast();
  final _trajanje = StreamController<Duration>.broadcast();
  final _konec = StreamController<void>.broadcast();

  static Duration _cas(double s) => Duration(milliseconds: (s * 1000).round());

  @override
  bool pripravljen(String id) => _naslovi.containsKey(id);

  @override
  void pripravi(String id, Uint8List bajti, String vrsta) {
    final blob = web.Blob([bajti.toJS].toJS, web.BlobPropertyBag(type: vrsta));
    _naslovi[id] = web.URL.createObjectURL(blob);
  }

  @override
  Future<void> predvajaj(String id, {required bool zanka, required double hitrost}) {
    // Vse sinhrono do play(), da Safari to šteje kot predvajanje ob dotiku.
    _el.src = _naslovi[id]!;
    _el.loop = zanka;
    _el.defaultPlaybackRate = hitrost;
    _el.playbackRate = hitrost;
    return _el.play().toDart;
  }

  @override
  Future<void> ustavi() async {
    _el.pause();
    if (_el.src.isNotEmpty) _el.currentTime = 0;
  }

  @override
  Future<void> pavza() async => _el.pause();
  @override
  Future<void> nadaljuj() => _el.play().toDart;
  @override
  Future<void> premakni(Duration d) async => _el.currentTime = d.inMilliseconds / 1000;
  @override
  Future<void> hitrost(double h) async => _el.playbackRate = h;
  @override
  Future<void> zanka(bool z) async => _el.loop = z;

  @override
  Stream<Duration> get pozicija => _pozicija.stream;
  @override
  Stream<Duration> get trajanje => _trajanje.stream;
  @override
  Stream<void> get konec => _konec.stream;

  @override
  void zapri() {
    _el.pause();
    _el.removeAttribute('src');
    for (final n in _narocnine) {
      n.cancel();
    }
    for (final u in _naslovi.values) {
      web.URL.revokeObjectURL(u);
    }
    _pozicija.close();
    _trajanje.close();
    _konec.close();
  }
}
