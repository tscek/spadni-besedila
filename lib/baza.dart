import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';
import 'risbe.dart';
import 'shramba/shramba.dart';

/// Lokalna kopija baze: podatki v baza.json, PDF-ji pod pdf/. Na špilu se bere samo od tu.
class Baza extends ChangeNotifier {
  Baza({Shramba? shramba}) : shramba = shramba ?? Shramba() {
    risbe = Risbe(this.shramba);
  }

  final Shramba shramba;
  List<Pesem> pesmi = [];
  Map<String, List<PdfDatoteka>> pdfjiPesmi = {};
  Map<String, List<BesediloPesmi>> besedilaPesmi = {};
  Map<String, Pesem> _poId = {};
  List<Setlista> setliste = [];
  Map<String, List<SetlistaPesem>> pesmiSetlist = {};
  List<Skupina> skupine = [];
  List<Vloga> vloge = [];
  DateTime? zadnjaOsvezitev;
  Map<String, dynamic> _podatki = {};

  /// Osebne risbe prijavljenega člana.
  late final Risbe risbe;

  static const hkratniPrenosi = 6;

  bool osvezujem = false;
  String? stanje;
  String? napaka;

  static const _kljucPodatkov = 'baza.json';
  static String _kljucPdf(String driveId) => 'pdf/$driveId.pdf';

  /// Lokalno shranjen PDF ali null, če še ni prenesen.
  Future<Uint8List?> pdf(String driveId) => shramba.beriBajte(_kljucPdf(driveId));

  Future<void> nalozi() async {
    final s = await shramba.beriBesedilo(_kljucPodatkov);
    if (s != null) _uporabi(jsonDecode(s) as Map<String, dynamic>);
    notifyListeners();
  }

  void _uporabi(Map<String, dynamic> podatki) {
    _podatki = podatki;
    final tabele = (podatki['tabele'] as Map<String, dynamic>?) ?? {};
    List<Zapis> t(String ime) => ((tabele[ime] as List?) ?? []).cast<Map<String, dynamic>>();

    pesmi = t('Pesmi').map(Pesem.izVrstice).where((p) => p.id.isNotEmpty && p.aktivna).toList()
      ..sort((a, b) => a.kodaStevilka.compareTo(b.kodaStevilka));
    _poId = {for (final p in pesmi) p.id: p};

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

    setliste = t('Setliste').map(Setlista.izVrstice).where((s) => s.id.isNotEmpty).toList()
      // Najnovejše najprej, brez datuma na konec.
      ..sort((a, b) => (b.datum ?? DateTime(0)).compareTo(a.datum ?? DateTime(0)));
    pesmiSetlist = {};
    for (final p in t('Setlista pesmi').map(SetlistaPesem.izVrstice).where((p) => p.pesem.isNotEmpty)) {
      pesmiSetlist.putIfAbsent(p.setlista, () => []).add(p);
    }
    for (final l in pesmiSetlist.values) {
      l.sort((a, b) => a.zaporedje.compareTo(b.zaporedje));
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
      await shramba.pisiBesedilo(_kljucPodatkov, jsonEncode(podatki));
      _uporabi(podatki);

      final preneseni = await shramba.kljuci('pdf/');
      final manjkajo = [
        for (final p in pdfjiPesmi.values.expand((l) => l))
          if (!preneseni.contains(_kljucPdf(p.driveId))) p,
      ];
      var koncanih = 0;
      final neuspeli = <String>[];
      final vrsta = List.of(manjkajo);

      // Več hkratnih prenosov, ker vsak PDF posebej čaka na odziv skripte.
      Future<void> delavec() async {
        while (vrsta.isNotEmpty) {
          final p = vrsta.removeLast();
          try {
            await shramba.pisiBajte(_kljucPdf(p.driveId), await api.pdf(p.driveId));
          } catch (e) {
            neuspeli.add(p.driveId);
          }
          koncanih++;
          stanje = 'Prenašam PDF-je: $koncanih od ${manjkajo.length} …';
          notifyListeners();
        }
      }

      await Future.wait(List.generate(hkratniPrenosi, (_) => delavec()));

      stanje = 'Usklajujem risbe …';
      notifyListeners();
      var risbeNapaka = false;
      try {
        await risbe.sinhroniziraj(api);
      } catch (e) {
        risbeNapaka = true;
      }
      stanje = [
        if (neuspeli.isNotEmpty) '${neuspeli.length} PDF-jev ni bilo mogoče prenesti.',
        if (risbeNapaka) 'Risb ni bilo mogoče uskladiti.',
      ].join(' ');
      if (stanje!.isEmpty) {
        stanje = null;
      } else {
        stanje = '$stanje Poskusi znova.';
      }
    } catch (e) {
      napaka = e.toString();
      stanje = null;
    } finally {
      osvezujem = false;
      notifyListeners();
    }
  }

  static const _urednikeVloge = {'Administrator', 'Urejevalec'};

  /// Skupine, v katerih sme prijavljeni član urejati pesmi.
  List<String> get urednikSkupine => {
    for (final v in vloge)
      if (_urednikeVloge.contains(v.vloga)) v.skupina,
  }.toList();

  bool get smeUrejati => urednikSkupine.isNotEmpty;

  bool smeUrejatiPesem(Pesem p) => smeUrejati && (p.skupine.isEmpty || p.skupine.any(urednikSkupine.contains));

  /// Različne vrednosti stolpca med pesmimi, za predloge pri vnosu.
  List<String> vrednosti(String stolpec) =>
      pesmi.map((p) => besedilo(p.vrstica[stolpec])).where((v) => v.isNotEmpty).toSet().toList()..sort();

  /// Shrani pesem na strežnik in v lokalno kopijo. Vrne shranjeno pesem.
  Future<Pesem> shraniPesem(Api api, Zapis podatki) async {
    final odg = await api.shraniPesem(podatki);
    final vrstica = (odg['vrstica'] as Map).cast<String, dynamic>();
    await _zamenjajVrstico('Pesmi', vrstica);
    return Pesem.izVrstice(vrstica);
  }

  Pesem? pesem(String id) => _poId[id];

  bool smeUrejatiSetlisto(Setlista s) => urednikSkupine.contains(s.skupina);

  /// Shrani setlisto in njene pesmi (ID-ji pesmi v vrstnem redu). Vrne shranjeno setlisto.
  Future<Setlista> shraniSetlisto(Api api, Zapis setlista, List<({String pesem, String opomba})> vrsta) async {
    final odg = await api.shraniSetlisto(setlista, [
      for (final v in vrsta) {'Pesem': v.pesem, 'Opomba': v.opomba},
    ]);
    final vrstica = (odg['setlista'] as Map).cast<String, dynamic>();
    final id = besedilo(vrstica['ID']);
    await _zamenjajVrstice(
      'Setlista pesmi',
      odstrani: (r) => besedilo(r['Setlista']) == id,
      dodaj: ((odg['pesmi'] as List?) ?? []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList(),
    );
    await _zamenjajVrstico('Setliste', vrstica);
    return Setlista.izVrstice(vrstica);
  }

  Future<void> izbrisiSetlisto(Api api, String id) async {
    await api.izbrisiSetlisto(id);
    await _zamenjajVrstice('Setlista pesmi', odstrani: (r) => besedilo(r['Setlista']) == id);
    await _zamenjajVrstico('Setliste', null, izbrisi: id);
  }

  Future<void> shraniBesedilo(Api api, Zapis podatki) async {
    final odg = await api.shraniBesedilo(podatki);
    if (odg['izbrisano'] != null) {
      await _zamenjajVrstico('Besedila', null, izbrisi: odg['izbrisano'].toString());
    } else {
      await _zamenjajVrstico('Besedila', (odg['vrstica'] as Map).cast<String, dynamic>());
    }
  }

  /// Odstrani vrstice, ki ustrezajo pogoju, in doda nove (brez shranjevanja na disk; to naredi naslednji klic).
  Future<void> _zamenjajVrstice(
    String tabela, {
    required bool Function(Zapis) odstrani,
    List<Zapis> dodaj = const [],
  }) async {
    final tabele = (_podatki['tabele'] as Map<String, dynamic>?) ?? (_podatki['tabele'] = <String, dynamic>{});
    tabele[tabela] = [
      ...((tabele[tabela] as List?) ?? []).cast<Map<String, dynamic>>().where((r) => !odstrani(r)),
      ...dodaj,
    ];
  }

  /// Zamenja (ali doda) vrstico po ID-ju v lokalni kopiji tabele, da ni treba čakati na celotno osvežitev.
  Future<void> _zamenjajVrstico(String tabela, Zapis? vrstica, {String? izbrisi}) async {
    final tabele = (_podatki['tabele'] as Map<String, dynamic>?) ?? (_podatki['tabele'] = <String, dynamic>{});
    final vrstice = ((tabele[tabela] as List?) ?? []).cast<Map<String, dynamic>>().toList();
    final id = izbrisi ?? besedilo(vrstica!['ID']);
    final i = vrstice.indexWhere((r) => besedilo(r['ID']) == id);
    if (vrstica == null) {
      if (i >= 0) vrstice.removeAt(i);
    } else if (i >= 0) {
      vrstice[i] = vrstica;
    } else {
      vrstice.add(vrstica);
    }
    tabele[tabela] = vrstice;
    await shramba.pisiBesedilo(_kljucPodatkov, jsonEncode(_podatki));
    _uporabi(_podatki);
    notifyListeners();
  }
}
