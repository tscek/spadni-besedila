import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'models.dart';

/// Lokalna kopija baze: podatki v baza.json, PDF-ji v mapi pdf/. Na špilu se bere samo od tu.
class Baza extends ChangeNotifier {
  Baza({this.mapa});

  /// Mapa za lokalno kopijo; privzeto podatkovna mapa aplikacije.
  Directory? mapa;
  List<Pesem> pesmi = [];
  Map<String, List<PdfDatoteka>> pdfjiPesmi = {};
  Map<String, List<BesediloPesmi>> besedilaPesmi = {};
  List<Skupina> skupine = [];
  List<Vloga> vloge = [];
  DateTime? zadnjaOsvezitev;

  bool osvezujem = false;
  String? stanje;
  String? napaka;

  Future<Directory> _koren() async => mapa ??= await getApplicationSupportDirectory();
  Future<File> _datotekaPodatkov() async => File('${(await _koren()).path}/baza.json');
  Future<File> datotekaPdf(String driveId) async => File('${(await _koren()).path}/pdf/$driveId.pdf');

  Future<void> nalozi() async {
    final f = await _datotekaPodatkov();
    if (await f.exists()) {
      _uporabi(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    }
    notifyListeners();
  }

  void _uporabi(Map<String, dynamic> podatki) {
    final tabele = (podatki['tabele'] as Map<String, dynamic>?) ?? {};
    List<Zapis> t(String ime) => ((tabele[ime] as List?) ?? []).cast<Map<String, dynamic>>();

    pesmi = t('Pesmi').map(Pesem.izVrstice).where((p) => p.id.isNotEmpty && p.aktivna).toList()
      ..sort((a, b) => a.kodaStevilka.compareTo(b.kodaStevilka));

    pdfjiPesmi = {};
    for (final p in t('PDF').map(PdfDatoteka.izVrstice).where((p) => p.driveId.isNotEmpty)) {
      pdfjiPesmi.putIfAbsent(p.pesem, () => []).add(p);
    }
    for (final l in pdfjiPesmi.values) {
      l.sort((a, b) => a.vrstniRed.compareTo(b.vrstniRed));
    }

    besedilaPesmi = {};
    for (final b in t('Besedila').map(BesediloPesmi.izVrstice).where((b) => b.vsebina.trim().isNotEmpty)) {
      besedilaPesmi.putIfAbsent(b.pesem, () => []).add(b);
    }

    skupine = t('Skupine').map(Skupina.izVrstice).toList();
    vloge = ((podatki['vloge'] as List?) ?? []).cast<Map<String, dynamic>>().map(Vloga.izVrstice).toList();
    zadnjaOsvezitev = DateTime.tryParse(podatki['cas']?.toString() ?? '');
  }

  /// Prenese podatke in manjkajoče PDF-je. Že preneseni PDF-ji ostanejo.
  Future<void> osvezi(Api api) async {
    if (osvezujem) return;
    osvezujem = true;
    napaka = null;
    stanje = 'Prenašam seznam pesmi …';
    notifyListeners();
    try {
      final podatki = await api.podatki();
      final f = await _datotekaPodatkov();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(podatki));
      _uporabi(podatki);

      final vsi = pdfjiPesmi.values.expand((l) => l).toList();
      final manjkajo = <PdfDatoteka>[];
      for (final p in vsi) {
        if (!await (await datotekaPdf(p.driveId)).exists()) manjkajo.add(p);
      }
      var i = 0;
      final neuspeli = <String>[];
      for (final p in manjkajo) {
        i++;
        stanje = 'Prenašam PDF $i od ${manjkajo.length} …';
        notifyListeners();
        try {
          final bytes = await api.pdf(p.driveId);
          final cilj = await datotekaPdf(p.driveId);
          await cilj.parent.create(recursive: true);
          // Najprej začasna datoteka, da prekinjen prenos ne pusti pokvarjenega PDF-ja.
          final zacasna = File('${cilj.path}.del');
          await zacasna.writeAsBytes(bytes, flush: true);
          await zacasna.rename(cilj.path);
        } catch (e) {
          neuspeli.add(p.driveId);
        }
      }
      stanje = neuspeli.isEmpty ? null : '${neuspeli.length} PDF-jev ni bilo mogoče prenesti. Poskusi znova.';
    } catch (e) {
      napaka = e.toString();
      stanje = null;
    } finally {
      osvezujem = false;
      notifyListeners();
    }
  }

  bool smeUrejati(String skupina) =>
      vloge.any((v) => v.skupina == skupina && (v.vloga == 'Administrator' || v.vloga == 'Urejevalec'));
}
