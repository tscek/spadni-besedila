import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// V brskalniku snemalnik ne piše v datoteko (pot se ne uporabi).
Future<String> potZaPosnetek(String koncnica) async => 'posnetek.$koncnica';

/// Posnetek v brskalniku je blob: naslov, ki ga vrne snemalnik.
Future<Uint8List> preberiPosnetek(String pot) async => (await http.get(Uri.parse(pot))).bodyBytes;

/// V brskalniku se špila ne snema (snema vodja).
Future<String> potKosa(String snemanje, int i) async => throw UnsupportedError('Snemanje špila v brskalniku ni mogoče');

Future<Uint8List?> beriDatoteko(String pot) async => null;

Future<void> izbrisiDatoteko(String pot) async {}
