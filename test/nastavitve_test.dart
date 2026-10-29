import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/nastavitve.dart';
import 'package:spadni_besedila/zasloni/pesem_zaslon.dart';

void main() {
  testWidgets('akordi se skrijejo, nastavitve ostanejo shranjene', (tester) async {
    SharedPreferences.setMockInitialValues({'velikost_pisave': 30.0});
    final n = Nastavitve();
    Nastavitve.aplikacija = n;
    await tester.runAsync(n.nalozi);
    expect(n.pisava, 30);
    expect(n.akordi, isTrue);

    Widget pogled() => MaterialApp(
      home: Scaffold(body: BesediloPogled(vsebina: '[C]Belo o[G]bleko', velikost: 20)),
    );
    await tester.pumpWidget(pogled());
    expect(find.text('C '), findsOneWidget);

    await tester.runAsync(() => n.nastaviAkorde(false));
    await tester.pumpWidget(Container());
    await tester.pumpWidget(pogled());
    expect(find.text('C '), findsNothing);
    expect(find.text('Belo obleko'), findsOneWidget);

    final shranjeno = Nastavitve();
    await tester.runAsync(shranjeno.nalozi);
    expect(shranjeno.akordi, isFalse);
  });

  test('orodja: privzeto iskanje spodaj, izbira se shrani', () async {
    SharedPreferences.setMockInitialValues({});
    final n = Nastavitve();
    await n.nalozi();
    expect(n.orodjaNa(Mesto.spodaj), [Orodje.iskanje]);
    expect(n.mesto(Orodje.ura), Mesto.skrito);
    await n.nastaviOrodje(Orodje.ura, Mesto.spodaj);
    await n.nastaviOrodje(Orodje.iskanje, Mesto.zgoraj);
    final shranjeno = Nastavitve();
    await shranjeno.nalozi();
    expect(shranjeno.orodjaNa(Mesto.spodaj), [Orodje.ura]);
    expect(shranjeno.mesto(Orodje.iskanje), Mesto.zgoraj);
  });
}
