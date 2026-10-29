import 'dart:typed_data';

import 'package:idb_shim/idb.dart';

import 'izbira_io.dart' if (dart.library.js_interop) 'izbira_web.dart' as izbira;

/// Lokalna shramba podatkov po ključih (npr. `baza.json`, `pdf/<id>.pdf`, `risbe/<pesem>.json`).
/// Na Androidu so to datoteke, v brskalniku IndexedDB.
abstract class Shramba {
  /// Privzeta shramba za trenutno platformo.
  factory Shramba() => izbira.privzetaShramba();

  Future<String?> beriBesedilo(String kljuc);
  Future<void> pisiBesedilo(String kljuc, String vsebina);
  Future<Uint8List?> beriBajte(String kljuc);
  Future<void> pisiBajte(String kljuc, Uint8List bajti);
  Future<void> izbrisi(String kljuc);

  /// Vsi ključi, ki se začnejo s [predpono].
  Future<Set<String>> kljuci(String predpona);
}

/// Shramba v IndexedDB (brskalnik) ali v pomnilniku (testi).
class ShrambaIdb implements Shramba {
  ShrambaIdb(this._tovarna, {this.ime = 'spadni_besedila'});

  static const _besedila = 'besedila';
  static const _bajti = 'bajti';

  final IdbFactory _tovarna;
  final String ime;
  Future<Database>? _baza;

  Future<Database> get _db => _baza ??= _tovarna.open(
    ime,
    version: 1,
    onUpgradeNeeded: (e) {
      e.database.createObjectStore(_besedila);
      e.database.createObjectStore(_bajti);
    },
  );

  Future<Object?> _beri(String shramba, String kljuc) async {
    final t = (await _db).transaction(shramba, idbModeReadOnly);
    final v = await t.objectStore(shramba).getObject(kljuc);
    await t.completed;
    return v;
  }

  Future<void> _pisi(String shramba, String kljuc, Object v) async {
    final t = (await _db).transaction(shramba, idbModeReadWrite);
    await t.objectStore(shramba).put(v, kljuc);
    await t.completed;
  }

  @override
  Future<String?> beriBesedilo(String kljuc) async => (await _beri(_besedila, kljuc)) as String?;

  @override
  Future<void> pisiBesedilo(String kljuc, String vsebina) => _pisi(_besedila, kljuc, vsebina);

  @override
  Future<Uint8List?> beriBajte(String kljuc) async {
    final v = await _beri(_bajti, kljuc);
    if (v == null) return null;
    return v is Uint8List ? v : Uint8List.fromList((v as List).cast<int>());
  }

  @override
  Future<void> pisiBajte(String kljuc, Uint8List bajti) => _pisi(_bajti, kljuc, bajti);

  @override
  Future<void> izbrisi(String kljuc) async {
    final t = (await _db).transaction([_besedila, _bajti], idbModeReadWrite);
    await t.objectStore(_besedila).delete(kljuc);
    await t.objectStore(_bajti).delete(kljuc);
    await t.completed;
  }

  @override
  Future<Set<String>> kljuci(String predpona) async {
    final t = (await _db).transaction([_besedila, _bajti], idbModeReadOnly);
    final out = <String>{};
    for (final s in [_besedila, _bajti]) {
      for (final k in await t.objectStore(s).getAllKeys()) {
        if (k is String && k.startsWith(predpona)) out.add(k);
      }
    }
    await t.completed;
    return out;
  }
}
