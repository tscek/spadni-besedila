import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Začasna datoteka, v katero snema snemalnik.
Future<String> potZaPosnetek(String koncnica) async =>
    '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}posnetek_${DateTime.now().millisecondsSinceEpoch}.$koncnica';

/// Prebere posneto datoteko in jo pobriše.
Future<Uint8List> preberiPosnetek(String pot) async {
  final f = File(pot);
  final bajti = await f.readAsBytes();
  try {
    await f.delete();
  } catch (_) {}
  return bajti;
}

/// Datoteka kosa posnetka špila (ostane, dokler ni na Drivu).
Future<String> potKosa(String snemanje, int i) async {
  final mapa = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}snemanja');
  await mapa.create(recursive: true);
  return '${mapa.path}${Platform.pathSeparator}${snemanje}_${i.toString().padLeft(3, '0')}.m4a';
}

/// Vsebina datoteke ali null, če je ni.
Future<Uint8List?> beriDatoteko(String pot) async {
  final f = File(pot);
  return await f.exists() ? f.readAsBytes() : null;
}

Future<void> izbrisiDatoteko(String pot) async {
  try {
    await File(pot).delete();
  } catch (_) {}
}
