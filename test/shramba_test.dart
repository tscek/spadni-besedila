import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/shramba/shramba_datoteke.dart';

void main() {
  Future<void> preizkusi(Shramba s) async {
    expect(await s.beriBesedilo('baza.json'), isNull);
    await s.pisiBesedilo('baza.json', 'ščž');
    await s.pisiBajte('pdf/a.pdf', Uint8List.fromList([1, 2, 3]));
    await s.pisiBajte('pdf/b.pdf', Uint8List.fromList([4]));
    await s.pisiBesedilo('risbe/x.json', '{}');
    expect(await s.beriBesedilo('baza.json'), 'ščž');
    expect(await s.beriBajte('pdf/a.pdf'), [1, 2, 3]);
    expect(await s.kljuci('pdf/'), {'pdf/a.pdf', 'pdf/b.pdf'});
    await s.izbrisi('pdf/a.pdf');
    expect(await s.kljuci('pdf/'), {'pdf/b.pdf'});
    expect(await s.beriBajte('pdf/a.pdf'), isNull);
  }

  test('shramba v datotekah', () async {
    final mapa = await Directory.systemTemp.createTemp('shramba');
    addTearDown(() => mapa.delete(recursive: true));
    await preizkusi(ShrambaDatoteke(() async => mapa));
  });

  test('shramba v IndexedDB', () => preizkusi(ShrambaIdb(newIdbFactoryMemory())));

  test('Windows: poti z »\\« so ključi z »/« (PDF-ji se ne prenašajo znova)', () {
    expect(ShrambaDatoteke.kljucIzPoti(r'pdf\abc.pdf'), 'pdf/abc.pdf');
    expect(ShrambaDatoteke.kljucIzPoti('pdf/abc.pdf'), 'pdf/abc.pdf');
  });
}
