import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/midi/ukazi.dart' show DejanjeMidi;
import 'package:spadni_besedila/tipkovnica.dart';
import 'package:spadni_besedila/zasloni/tipkovnica_zaslon.dart';

KeyDownEvent _dol(LogicalKeyboardKey k, {String? znak}) =>
    KeyDownEvent(physicalKey: PhysicalKeyboardKey.keyA, logicalKey: k, character: znak, timeStamp: Duration.zero);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('privzete tipke sprožijo dejanja, učenje doda novo tipko', () async {
    final t = Tipkovnica();
    final sprozena = <DejanjeMidi>[];
    t.sprozi = (d) {
      sprozena.add(d);
      return true;
    };
    expect(t.obTipki(_dol(LogicalKeyboardKey.keyI, znak: 'i')), isTrue);
    expect(t.obTipki(_dol(LogicalKeyboardKey.arrowDown)), isTrue);
    expect(t.obTipki(_dol(LogicalKeyboardKey.arrowRight)), isTrue);
    expect(t.obTipki(_dol(LogicalKeyboardKey.enter)), isTrue);
    expect(t.obTipki(_dol(LogicalKeyboardKey.keyQ, znak: 'q')), isFalse);
    expect(sprozena, [DejanjeMidi.iskalnik, DejanjeMidi.dol, DejanjeMidi.naslednja, DejanjeMidi.potrdi]);

    // Nožno stikalo BT pošilja npr. Page Down.
    t.uci(DejanjeMidi.naslednja);
    expect(t.obTipki(_dol(LogicalKeyboardKey.pageDown)), isTrue);
    expect(t.ucim, isNull);
    sprozena.clear();
    t.obTipki(_dol(LogicalKeyboardKey.pageDown));
    expect(sprozena, [DejanjeMidi.naslednja]);
    expect(t.tipkeZa(DejanjeMidi.naslednja), containsAll([LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.pageDown]));

    // Shranjeno na napravi.
    await pumpEventQueue();
    final druga = Tipkovnica();
    await druga.nalozi();
    expect(druga.bliznjice[LogicalKeyboardKey.pageDown.keyId], DejanjeMidi.naslednja);
    await druga.ponastavi();
    expect(druga.bliznjice[LogicalKeyboardKey.pageDown.keyId], isNull);
  });

  testWidgets('v vnosnem polju črke ostanejo polju, gor in Enter pa delujeta', (tester) async {
    final t = Tipkovnica();
    final sprozena = <DejanjeMidi>[];
    t.sprozi = (d) {
      sprozena.add(d);
      return true;
    };
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TextField(autofocus: true))));
    await tester.pump();
    expect(t.obTipki(_dol(LogicalKeyboardKey.keyI, znak: 'i')), isFalse);
    expect(t.obTipki(_dol(LogicalKeyboardKey.arrowLeft)), isFalse);
    expect(t.obTipki(_dol(LogicalKeyboardKey.arrowUp)), isTrue);
    expect(sprozena, [DejanjeMidi.gor]);
  });

  testWidgets('zaslon bližnjic pokaže tipke in jih zna odstraniti', (tester) async {
    final t = Tipkovnica();
    await tester.pumpWidget(MaterialApp(home: TipkovnicaZaslon(tipkovnica: t)));
    expect(find.text('I'), findsOneWidget);
    tester
        .widget<InputChip>(
          find.descendant(of: find.byKey(const ValueKey('tipka-iskalnik')), matching: find.byType(InputChip)),
        )
        .onDeleted!();
    await tester.pump();
    expect(t.tipkeZa(DejanjeMidi.iskalnik), isEmpty);
  });
}
