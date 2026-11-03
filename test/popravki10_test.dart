import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/midi/midi.dart';
import 'package:spadni_besedila/midi/prenos.dart';
import 'package:spadni_besedila/midi/takt.dart';
import 'package:spadni_besedila/midi/ukazi.dart';
import 'package:spadni_besedila/midi/xy.dart';
import 'package:spadni_besedila/models.dart';
import 'package:spadni_besedila/risbe.dart';
import 'package:spadni_besedila/tap_tempo.dart';
import 'package:spadni_besedila/zasloni/drsnik.dart';
import 'package:spadni_besedila/zasloni/pdf_risanje.dart' show NozniGumbi;
import 'package:spadni_besedila/zasloni/xy_pad.dart';

class _Prenos implements MidiPrenos {
  final poslano = <String>[];

  @override
  Future<List<NapravaMidi>> naprave() async => const [NapravaMidi('a', 'WIDI', 'Bluetooth', true)];
  @override
  Future<void> zacniIskanje() async {}
  @override
  void ustaviIskanje() {}
  @override
  Future<void> povezi(String id) async {}
  @override
  void prekini(String id) {}
  @override
  void poslji(Uint8List bajti, String id) => poslano.add(bajti.join(' '));
  @override
  Stream<void> get spremembe => const Stream.empty();
  @override
  Stream<(String, Uint8List)> get prejeto => const Stream.empty();
}

void main() {
  test('tap tempo: povprečje udarcev, po premoru znova', () {
    final t = TapTempo();
    final z = DateTime(2026, 11, 3, 20);
    expect(t.udari(z), isNull);
    expect(t.udari(z.add(const Duration(milliseconds: 500))), 120);
    expect(t.udari(z.add(const Duration(milliseconds: 1000))), 120);
    expect(t.udari(z.add(const Duration(milliseconds: 1700))), 106);
    // Po več kot 2 s začne znova.
    expect(t.udari(z.add(const Duration(seconds: 5))), isNull);
    expect(t.udari(z.add(const Duration(milliseconds: 5600))), 100);
  });

  test('nastavitve takta: razmik in število sporočil', () {
    const clock = NastavitveTakta(nacin: NacinTakta.clock);
    expect(clock.razmik(120), closeTo(500000 / 24, 0.01));
    expect(clock.sporocil(), 96);
    const ukaz = NastavitveTakta(nacin: NacinTakta.ukaz, delitelj: 2, udarcev: 0);
    expect(ukaz.razmik(120), 1000000);
    expect(ukaz.sporocil(), isNull);
    final j = NastavitveTakta.izJson(ukaz.vJson());
    expect((j.nacin, j.delitelj, j.vesCas), (NacinTakta.ukaz, 2, true));
    expect(tempoPesmi(Pesem.izVrstice({'ID': 'x', 'Tempo (BPM)': '96'})), 96);
    expect(tempoPesmi(Pesem.izVrstice({'ID': 'x', 'Tempo (BPM)': ''})), isNull);
  });

  Future<(Midi, _Prenos)> midi() async {
    SharedPreferences.setMockInitialValues({'midi_vklop': true, 'midi_ob_odprtju': true});
    final prenos = _Prenos();
    final m = Midi(prenos);
    await m.nalozi();
    await m.osveziNaprave();
    return (m, prenos);
  }

  final pesem = Pesem.izVrstice({'ID': 'p', 'Koda': 1, 'Naslov': 'P', 'Tempo (BPM)': 120});

  test('MIDI clock ob odprtju: 4 dobe po 24 utripov, nato utihne', () async {
    final (m, prenos) = await midi();
    await m.nastaviTakt(const NastavitveTakta(nacin: NacinTakta.clock));
    fakeAsync((f) {
      final z = DateTime(2026);
      m.zacniTakt(pesem, KnjiznicaMidi(), ura: () => z.add(f.elapsed));
      f.elapse(const Duration(milliseconds: 1000));
      expect(prenos.poslano.length, inInclusiveRange(48, 50));
      f.elapse(const Duration(seconds: 3));
      expect(prenos.poslano.length, 96);
      expect(prenos.poslano.toSet(), {'248'});
      expect(m.taktTece, isFalse);
    });
  });

  test('ukaz na vsako drugo dobo teče ves čas, do zaprtja', () async {
    final (m, prenos) = await midi();
    await m.nastaviTakt(const NastavitveTakta(nacin: NacinTakta.ukaz, ukaz: 'CC 5 10 127', delitelj: 2, udarcev: 0));
    fakeAsync((f) {
      final z = DateTime(2026);
      m.zacniTakt(pesem, KnjiznicaMidi(), ura: () => z.add(f.elapsed));
      f.elapse(const Duration(milliseconds: 4500));
      // Pri 120 BPM je doba 0,5 s, vsaka druga doba 1 s: 0, 1, 2, 3, 4 s.
      expect(prenos.poslano, List.filled(5, '180 10 127'));
      expect(m.taktTece, isTrue);
      m.ustaviTakt();
      f.elapse(const Duration(seconds: 3));
      expect(prenos.poslano.length, 5);
    });
  });

  test('brez Uvodov gre ob odprtju vse razen MIDI za uvod', () {
    final k = KnjiznicaMidi();
    final p = Pesem.izVrstice({'ID': 'u', 'MIDI ob odprtju': 'PC 1 1', 'MIDI za uvod': 'CC 9 12 127'});
    expect(k.obOdprtju(p).map((u) => u.ukaz.zapis), ['PC 1 1', 'CC 9 12 127']);
    expect(k.obOdprtju(p, uvod: false).map((u) => u.ukaz.zapis), ['PC 1 1']);
  });

  test('barve kanalov iz lista MIDI kanali', () {
    final k = KnjiznicaMidi.izTabel({
      'MIDI kanali': [
        {'Kanal': '1', 'Ime': 'Luči', 'Barva': '#C62828'},
        {'Kanal': '2', 'Ime': 'Miza', 'Barva': ''},
      ],
    });
    expect(k.barveKanalov, {1: 0xFFC62828});
    expect(k.imeKanala(1), 'Luči');
  });

  test('gumb na besedilu si zapomni nožno stikalo', () {
    final g = GumbNaStrani(napis: 'Solo', midi: 'PC 1 5', barva: 0xFF1565C0, nozno: 3);
    final j = g.vJson();
    expect(j['n'], 3);
    expect(GumbNaStrani.izJson(j).nozno, 3);
    expect(GumbNaStrani(napis: 'x', midi: '', barva: 0).vJson().containsKey('n'), isFalse);
    expect(g.kopija(velikost: 2).nozno, 3);
    // Brez odprtega besedila ni gumba, ki bi ga stikalo sprožilo.
    expect(NozniGumbi.sprozi('ni', 1), isFalse);
  });

  test('drsnik: CC ukaz iz knjižnice z vrednostjo drsnika', () {
    final k = KnjiznicaMidi.izTabel({
      'MIDI ukazi': [
        {'Ime': 'Nivo glasbe', 'Vrsta': 'CC', 'Kanal': 3, 'Številka': 7, 'Vrednost': 100, 'Izhod': 'Miza'},
      ],
    });
    final u = ukazDrsnika(k, 'Nivo glasbe', 64)!;
    expect((u.ukaz.zapis, u.izhod), ('CC 3 7 64', 'Miza'));
    expect(ukazDrsnika(k, 'CC 1 11', 200)!.ukaz.zapis, 'CC 1 11 127');
    expect(ukazDrsnika(k, 'PC 1 5', 10), isNull);
  });

  testWidgets('drsnik ne pošlje nič, dokler ga ne premakneš', (t) async {
    final (m, prenos) = await t.runAsync(midi) ?? (throw StateError(''));
    Midi.aplikacija = m;
    final g = GumbNaStrani(napis: 'Glasba', midi: 'CC 1 7', barva: 0xFF1565C0, oblika: OblikaGumba.drsnik);
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: DrsnikVOpombah(gumb: g, velikost: 20, knjiznica: KnjiznicaMidi()),
        ),
      ),
    );
    expect(prenos.poslano, isEmpty);
    // Drsnik je širok 200: vlečenje do desnega roba pošlje 127.
    final levo = t.getTopLeft(find.byType(DrsnikVOpombah));
    final g1 = await t.startGesture(levo + const Offset(100, 24));
    await t.pump(const Duration(milliseconds: 50));
    await g1.moveTo(levo + const Offset(199.9, 24));
    await t.pump(const Duration(milliseconds: 50));
    await g1.up();
    await t.pump(const Duration(milliseconds: 50));
    expect(prenos.poslano.first, '176 7 64');
    expect(prenos.poslano.last, '176 7 127');
  });

  testWidgets('XY pad: gumbi nad padom, osi pošiljata CC po položaju', (t) async {
    final (m, prenos) = await t.runAsync(midi) ?? (throw StateError(''));
    Midi.aplikacija = m;
    await t.runAsync(
      () => m.nastaviXy(
        const NastavitveXy(
          skupine: [SkupinaXy('Efekt', 'CC 2 20', 'CC 2 21'), SkupinaXy('Mešalka', 'CC 3 7', '')],
          gumbi: [GumbXy('Efekt', 'PC 2 4')],
        ),
      ),
    );
    final j = NastavitveXy.izJson(m.xy.vJson());
    expect((j.skupine.first.x, j.skupine.last.ime, j.gumbi.single.napis), ('CC 2 20', 'Mešalka', 'Efekt'));
    // Star zapis z enim parom osi postane ena skupina.
    expect(NastavitveXy.izJson({'x': 'CC 1 1', 'y': ''}).skupine.single.x, 'CC 1 1');
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 320, child: XyPad(knjiznica: KnjiznicaMidi())),
          ),
        ),
      ),
    );
    expect(prenos.poslano, isEmpty);
    final p = t.getTopLeft(find.byKey(const ValueKey('xy-ploskev')));
    final g = await t.startGesture(p + const Offset(144, 144));
    await t.pump(const Duration(milliseconds: 50));
    await g.moveTo(p + const Offset(287.9, 0.1));
    await t.pump(const Duration(milliseconds: 50));
    await g.up();
    await t.pump(const Duration(milliseconds: 50));
    expect(prenos.poslano.take(2), ['177 20 64', '177 21 64']);
    expect(prenos.poslano.skip(prenos.poslano.length - 2), ['177 20 127', '177 21 127']);
    await t.tap(find.widgetWithText(FilledButton, 'Efekt'));
    await t.pump(const Duration(milliseconds: 50));
    expect(prenos.poslano.last, '193 4');
    // Druga skupina: pad pošilja samo CC 3 7.
    await t.tap(find.byKey(const ValueKey('xy-skupina-1')));
    await t.pump();
    final g2 = await t.startGesture(p + const Offset(0.1, 144));
    await t.pump(const Duration(milliseconds: 50));
    await g2.up();
    await t.pump(const Duration(milliseconds: 50));
    expect(prenos.poslano.last, '178 7 0');
  });
}
