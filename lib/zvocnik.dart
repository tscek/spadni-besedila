import 'dart:typed_data';

import 'zvocnik_io.dart' if (dart.library.js_interop) 'zvocnik_web.dart' as izvedba;

/// Predvajalnik posnetkov. Zvok se pripravi vnaprej, da se predvajanje začne takoj ob dotiku
/// (Safari na iPadu sicer zavrne predvajanje z NotAllowedError).
abstract class Zvocnik {
  static Zvocnik Function() tovarna = izvedba.ustvari;

  bool pripravljen(String id);

  /// Pripravi zvok posnetka (prebere bajte vnaprej).
  void pripravi(String id, Uint8List bajti, String vrsta);

  /// Začne predvajanje pripravljenega posnetka. Klicati takoj ob dotiku, brez čakanja pred tem.
  Future<void> predvajaj(String id, {required bool zanka, required double hitrost});
  Future<void> ustavi();
  Future<void> pavza();
  Future<void> nadaljuj();
  Future<void> premakni(Duration d);
  Future<void> hitrost(double h);
  Future<void> zanka(bool z);

  Stream<Duration> get pozicija;
  Stream<Duration> get trajanje;
  Stream<void> get konec;

  void zapri();
}
