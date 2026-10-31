import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/models.dart';
import 'package:spadni_besedila/nastavitve.dart';
import 'package:spadni_besedila/zasloni/pesem_zaslon.dart';

void main() {
  test('nastavitve pogleda administratorja: izvoz in prevzem, osebne ostanejo', () async {
    SharedPreferences.setMockInitialValues({});
    final admin = Nastavitve();
    await admin.nalozi();
    await admin.nastaviPisavo(30);
    await admin.nastaviBarvoVrstice(zgoraj: true, barva: 0xFF000000);
    await admin.nastaviZgoraj(2, InfoVrstice.ura);
    await admin.nastaviOrodje(Orodje.pisava, Mesto.zgoraj);
    await admin.nastaviPisavoPesmi('a', 40); // osebno, ne gre zraven
    final json = await admin.izvoziPogled();

    SharedPreferences.setMockInitialValues({'prelom_vrstic': false, 'zasedba': 's2', 'akordi': false});
    final clan = Nastavitve();
    await clan.nalozi();
    expect(clan.akordi, isFalse);
    await clan.uvoziPogled(json);
    expect(clan.pisava, 30);
    expect(clan.barvaZgoraj, 0xFF000000);
    expect(clan.zgoraj[2], InfoVrstice.ura);
    expect(clan.mesto(Orodje.pisava), Mesto.zgoraj);
    expect(clan.prelom, isTrue); // admin ima privzeto
    expect(clan.akordi, isTrue);
    expect(clan.zasedba, 's2'); // osebno ostane
    expect(clan.pisavePesmi, isEmpty);
  });

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

  test('orodja in spodnja vrstica: privzeto in shranjena izbira', () async {
    SharedPreferences.setMockInitialValues({});
    final n = Nastavitve();
    await n.nalozi();
    expect(n.orodjaNa(Mesto.spodaj), isEmpty);
    expect(n.mesto(Orodje.ura), Mesto.skrito);
    await n.nastaviOrodje(Orodje.ura, Mesto.spodaj);
    await n.nastaviOrodje(Orodje.runda, Mesto.skrito);
    await n.nastaviSpodaj(1, InfoVrstice.tempo);
    await n.nastaviPoljaSeznama([PoljePesmi.harmonika]);
    await n.nastaviRazvrscanje(PoljePesmi.naslov, true);
    final shranjeno = Nastavitve();
    await shranjeno.nalozi();
    expect(shranjeno.orodjaNa(Mesto.spodaj), [Orodje.ura]);
    expect(shranjeno.mesto(Orodje.runda), Mesto.skrito);
    expect(shranjeno.spodaj[1], InfoVrstice.tempo);
    expect(shranjeno.poljaSeznama, [PoljePesmi.harmonika]);
    expect(shranjeno.razvrsti, PoljePesmi.naslov);
    expect(shranjeno.padajoce, isTrue);
  });
}
