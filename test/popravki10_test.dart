import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/midi/midi.dart';
import 'package:spadni_besedila/midi/prenos.dart';
import 'package:spadni_besedila/midi/takt.dart';
import 'package:spadni_besedila/midi/ukazi.dart';
import 'package:spadni_besedila/models.dart';
import 'package:spadni_besedila/tap_tempo.dart';

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
}
