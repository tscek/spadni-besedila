import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/api.dart';
import 'package:spadni_besedila/baza.dart';
import 'package:spadni_besedila/runda.dart';
import 'package:spadni_besedila/shramba/shramba.dart';
import 'package:spadni_besedila/zasloni/ohranjevalnik.dart';

String _dan(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<Baza> _baza() async {
  final danes = DateTime.now();
  final api = Api(
    () async => 'z',
    url: 'https://example.com/exec',
    client: MockClient(
      (r) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'vloge': [],
            'tabele': {
              'Pesmi': [],
              'Nastopi': [
                {
                  'ID': 'n2',
                  'Datum': _dan(danes.add(const Duration(days: 20))),
                  'Dogodek': 'Veselica',
                  'Kraj': 'Bovec',
                },
                {'ID': 'n1', 'Datum': _dan(danes), 'Dogodek': 'Poroka', 'Kraj': 'Ajdovščina', 'ZasedbaIme': 'Špadni'},
              ],
            },
          }),
        ),
        200,
      ),
    ),
  );
  final baza = Baza(shramba: ShrambaIdb(newIdbFactoryMemory()));
  await baza.osvezi(api);
  return baza;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nastopi so v lokalni bazi: današnji brez interneta', () async {
    final baza = await _baza();
    expect(baza.nastopi.length, 2);
    expect(baza.nastopiOkrog(DateTime.now()).map((n) => n['ID']), ['n1']);
    expect(nastopZaOhranjevalnik(baza, DateTime.now()), (naslov: 'Poroka · Špadni', kraj: 'Ajdovščina'));
    expect(datumBesedilo(DateTime(2026, 11, 3)), 'torek, 3. 11. 2026');
  });

  testWidgets('ohranjevalnik ob pavzi: tap ga zapre tu, nova pavza ga spet pokaže, igranje ga skrije', (tester) async {
    late Baza baza;
    await tester.runAsync(() async => baza = await _baza());
    final runda = Runda();
    await tester.pumpWidget(
      MaterialApp(
        home: Ohranjevalnik(baza: baza, runda: runda, child: const Text('besedilo')),
      ),
    );
    expect(find.byKey(const ValueKey('ohranjevalnik')), findsNothing);

    await tester.runAsync(() => runda.zacni(true));
    await tester.pump();
    expect(find.byKey(const ValueKey('ohranjevalnik')), findsOneWidget);
    expect(find.text('Poroka · Špadni'), findsOneWidget);
    expect(find.text('Ajdovščina'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ohranjevalnik')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ohranjevalnik')), findsNothing);

    await tester.runAsync(() => runda.zacni(false));
    await tester.pump();
    await tester.runAsync(() => runda.zacni(true));
    await tester.pump();
    expect(find.byKey(const ValueKey('ohranjevalnik')), findsOneWidget);

    await tester.runAsync(() => runda.zacni(false));
    await tester.pump();
    expect(find.byKey(const ValueKey('ohranjevalnik')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
