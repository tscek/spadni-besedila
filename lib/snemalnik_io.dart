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
