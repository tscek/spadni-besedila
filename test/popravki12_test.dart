import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/chordpro.dart' as cp;
import 'package:spadni_besedila/nastavitve.dart';
import 'package:spadni_besedila/spil/spil.dart';
import 'package:spadni_besedila/zasloni/pesem_zaslon.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Nastavitve.aplikacija = Nastavitve();
  });

  test('krepko: označeno postane krepko in obratno, po vrsticah, presledki ostanejo zunaj', () {
    const b = 'Belo obleko si\nže nosila';
    var (t, sel) = cp.preklopiKrepko(b, 0, 4);
    expect(t, '**Belo** obleko si\nže nosila');
    expect(t.substring(sel.$1, sel.$2), '**Belo**');
    // Ponovno na istem (z oznakami ali brez) odstrani.
    expect(cp.preklopiKrepko(t, sel.$1, sel.$2).$1, b);
    expect(cp.preklopiKrepko(t, 2, 6).$1, b);
    // Čez dve vrstici in s presledkom na koncu.
    (t, sel) = cp.preklopiKrepko(b, 5, b.length);
    expect(t, 'Belo **obleko si**\n**že nosila**');
    expect(cp.brezKrepkega(t), b);
  });

  test('krepko se lahko nadaljuje čez akord', () {
    final (deli, konec) = cp.deliKrepko('a **b', krepko: false);
    expect(deli, [('a ', false), ('b', true)]);
    expect(konec, isTrue);
    expect(cp.deliKrepko('c** d', krepko: true).$1, [('c', true), (' d', false)]);
  });

  testWidgets('krepko besedilo je prikazano krepko, brez zvezdic', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BesediloPogled(vsebina: 'Belo **obleko** si\n[C]la **[G]la** la', velikost: 20)),
      ),
    );
    expect(find.textContaining('**'), findsNothing);
    final rich = t.widget<RichText>(
      find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == 'Belo obleko si'),
    );
    final krepki = <String>[];
    rich.text.visitChildren((s) {
      if (s is TextSpan && s.style?.fontWeight == FontWeight.bold && s.text != null) krepki.add(s.text!);
      return true;
    });
    expect(krepki, ['obleko']);
    // Z akordi: krepko se začne v enem kosu (»la **«) in konča v drugem (»la** la«).
    final drugi = t.widget<RichText>(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == 'la la'));
    final k2 = <String>[];
    drugi.text.visitChildren((s) {
      if (s is TextSpan && s.style?.fontWeight == FontWeight.bold && s.text != null) k2.add(s.text!);
      return true;
    });
    expect(k2, ['la']);
  });

  test('nazaj po prikazanih pesmih tudi ko je čakalna vrsta prazna', () {
    final s = Spil();
    expect(s.imaNazaj, isFalse);
    s.prikazujem(const StanjeSpila(pesem: 'a'));
    s.prikazujem(const StanjeSpila(pesem: 'b'));
    expect(s.naslednje, isEmpty);
    expect(s.imaNazaj, isTrue);
    expect(s.nazaj(), 'a');
    // Pesem, iz katere smo šli nazaj, je spet naslednja.
    expect(s.naslednje.single.pesem, 'b');
  });
}
