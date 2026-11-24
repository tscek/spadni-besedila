import 'package:flutter/foundation.dart';

import '../baza.dart';
import '../config.dart';
import '../midi/midi.dart';

/// Preizkus pred špilom: kaj je na tej napravi pripravljeno (PDF-ji, risbe, MIDI, neposlane spremembe).
/// Vodja zahteva poročila vseh povezanih naprav in jih pokaže v eni tabeli.
@immutable
class PorociloNaprave {
  const PorociloNaprave({
    required this.kdo,
    this.manjkaPdf = 0,
    this.vsehPdf = 0,
    this.risb = 0,
    this.skupnihRisb = 0,
    this.midi = const [],
    this.midiManjka = const [],
    this.neposlanih = 0,
    this.brezVloge = false,
    this.prekoVodje = false,
  });

  factory PorociloNaprave.izJson(Map<String, dynamic> j) => PorociloNaprave(
    kdo: j['kdo']?.toString() ?? '?',
    manjkaPdf: (j['manjkaPdf'] as num?)?.toInt() ?? 0,
    vsehPdf: (j['vsehPdf'] as num?)?.toInt() ?? 0,
    risb: (j['risb'] as num?)?.toInt() ?? 0,
    skupnihRisb: (j['skupnihRisb'] as num?)?.toInt() ?? 0,
    midi: [for (final m in (j['midi'] as List?) ?? const []) m.toString()],
    midiManjka: [for (final m in (j['midiManjka'] as List?) ?? const []) m.toString()],
    neposlanih: (j['neposlanih'] as num?)?.toInt() ?? 0,
    brezVloge: j['brezVloge'] == true,
    prekoVodje: j['prekoVodje'] == true,
  );

  final String kdo;
  final int manjkaPdf;
  final int vsehPdf;
  final int risb;
  final int skupnihRisb;

  /// Povezane MIDI naprave.
  final List<String> midi;

  /// MIDI naprave, ki jih ta naprava uporablja, pa zdaj niso povezane.
  final List<String> midiManjka;
  final int neposlanih;
  final bool brezVloge;

  /// iPad prek vodje: PDF-je in risbe dobi od vodje, zato se ne preverjajo.
  final bool prekoVodje;

  Map<String, dynamic> vJson() => {
    'kdo': kdo,
    'manjkaPdf': manjkaPdf,
    'vsehPdf': vsehPdf,
    'risb': risb,
    'skupnihRisb': skupnihRisb,
    'midi': midi,
    'midiManjka': midiManjka,
    'neposlanih': neposlanih,
    'brezVloge': brezVloge,
    'prekoVodje': prekoVodje,
  };

  /// Opozorila (prazno = vse v redu).
  List<String> get tezave => [
    if (manjkaPdf > 0) 'manjka $manjkaPdf od $vsehPdf PDF-jev (Osveži)',
    if (midiManjka.isNotEmpty) 'MIDI ni povezan: ${midiManjka.join(', ')}',
    if (neposlanih > 0) '$neposlanih sprememb ni poslanih',
    if (brezVloge) 'član nima vloge',
  ];

  /// Kar je v redu, na kratko.
  String get povzetek => [
    if (!prekoVodje) 'PDF ${vsehPdf - manjkaPdf}/$vsehPdf',
    if (!prekoVodje) 'risbe $risb + skupne $skupnihRisb',
    midi.isEmpty ? 'brez MIDI' : 'MIDI: ${midi.join(', ')}',
  ].join(' · ');
}

/// Poročilo te naprave.
Future<PorociloNaprave> porociloTeNaprave(Baza baza, {String kdo = ''}) async {
  var manjka = 0;
  var vseh = 0;
  if (!Config.prekoVodje) {
    final preneseni = await baza.shramba.kljuci('pdf/');
    for (final p in baza.pdfjiPesmi.values.expand((l) => l)) {
      vseh++;
      if (!preneseni.contains('pdf/${p.driveId}.pdf')) manjka++;
    }
  }
  final osebne = await baza.risbe.povzetek();
  final skupne = await baza.risbeSkupne.povzetek();
  final midi = Midi.aplikacija;
  final povezane = [
    for (final n in midi.naprave)
      if (n.povezana) n.ime,
  ];
  return PorociloNaprave(
    kdo: kdo.isNotEmpty ? kdo : (baza.imeClana.isNotEmpty ? baza.imeClana : 'Ta naprava'),
    manjkaPdf: manjka,
    vsehPdf: vseh,
    risb: osebne.stevilo,
    skupnihRisb: skupne.stevilo,
    midi: povezane,
    midiManjka: [
      for (final n in midi.shranjeneNaprave)
        if (!povezane.contains(n)) n,
    ],
    neposlanih: baza.steviloNeposlanih,
    brezVloge: baza.brezVloge,
    prekoVodje: Config.prekoVodje,
  );
}
