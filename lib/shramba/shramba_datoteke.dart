import 'dart:io';
import 'dart:typed_data';

import 'shramba.dart';

/// Shramba v datotekah podatkovne mape aplikacije (Android, namizje).
class ShrambaDatoteke implements Shramba {
  ShrambaDatoteke(this._koren);

  final Future<Directory> Function() _koren;

  Future<File> _datoteka(String kljuc) async => File('${(await _koren()).path}/$kljuc');

  @override
  Future<String?> beriBesedilo(String kljuc) async {
    final f = await _datoteka(kljuc);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> pisiBesedilo(String kljuc, String vsebina) async {
    final f = await _datoteka(kljuc);
    await f.parent.create(recursive: true);
    await f.writeAsString(vsebina);
  }

  @override
  Future<Uint8List?> beriBajte(String kljuc) async {
    final f = await _datoteka(kljuc);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> pisiBajte(String kljuc, Uint8List bajti) async {
    final f = await _datoteka(kljuc);
    await f.parent.create(recursive: true);
    // Najprej začasna datoteka, da prekinjen zapis ne pusti pokvarjene datoteke.
    final zacasna = File('${f.path}.del');
    await zacasna.writeAsBytes(bajti, flush: true);
    await zacasna.rename(f.path);
  }

  @override
  Future<void> izbrisi(String kljuc) async {
    final f = await _datoteka(kljuc);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<Set<String>> kljuci(String predpona) async {
    final koren = (await _koren()).path;
    final i = predpona.lastIndexOf('/');
    final mapa = Directory(i < 0 ? koren : '$koren/${predpona.substring(0, i)}');
    if (!await mapa.exists()) return {};
    return {
      await for (final e in mapa.list(recursive: true))
        if (e is File)
          if (e.path.substring(koren.length + 1) case final k when k.startsWith(predpona) && !k.endsWith('.del')) k,
    };
  }
}
