import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'zvocnik.dart';

Zvocnik ustvari() => _ZvocnikIo();

class _ZvocnikIo implements Zvocnik {
  AudioPlayer? _p;
  AudioPlayer get _pl => _p ??= AudioPlayer();
  final _zvoki = <String, ({Uint8List bajti, String vrsta})>{};

  @override
  bool pripravljen(String id) => _zvoki.containsKey(id);

  @override
  void pripravi(String id, Uint8List bajti, String vrsta) => _zvoki[id] = (bajti: bajti, vrsta: vrsta);

  @override
  Future<void> predvajaj(String id, {required bool zanka, required double hitrost}) async {
    final z = _zvoki[id]!;
    await _pl.stop();
    await _pl.setReleaseMode(zanka ? ReleaseMode.loop : ReleaseMode.stop);
    await _pl.play(BytesSource(z.bajti, mimeType: z.vrsta));
    if (hitrost != 1) await _pl.setPlaybackRate(hitrost);
  }

  @override
  Future<void> ustavi() => _pl.stop();
  @override
  Future<void> pavza() => _pl.pause();
  @override
  Future<void> nadaljuj() => _pl.resume();
  @override
  Future<void> premakni(Duration d) => _pl.seek(d);
  @override
  Future<void> hitrost(double h) => _pl.setPlaybackRate(h);
  @override
  Future<void> zanka(bool z) => _pl.setReleaseMode(z ? ReleaseMode.loop : ReleaseMode.stop);

  @override
  Stream<Duration> get pozicija => _pl.onPositionChanged;
  @override
  Stream<Duration> get trajanje => _pl.onDurationChanged;
  @override
  Stream<void> get konec => _pl.onPlayerComplete;

  @override
  void zapri() => _p?.dispose();
}
