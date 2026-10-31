import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';
import 'nastavitve.dart';
import 'config.dart';
import 'midi/ukazi.dart';
import 'risbe.dart';
import 'shramba/shramba.dart';

/// Lokalna kopija baze: podatki v baza.json, PDF-ji pod pdf/. Na špilu se bere samo od tu.
class Baza extends ChangeNotifier {
  Baza({Shramba? shramba}) : shramba = shramba ?? Shramba() {
    risbe = Risbe(this.shramba);
    risbeSkupne = Risbe(this.shramba, skupne: true);
    risbeClanov = RisbeClanov(this.shramba);
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
  List<Mapa> mape = [];
  List<Harmonika> harmonike = [];

  /// Vrste pesmi z barvami (list Vrste).
  List<Harmonika> vrste = [];

  /// Klicaji po pesmih (skupni za vse člane).
  Map<String, List<KlicajPesmi>> klicaji = {};

  /// Zvočni posnetki po pesmih: skupni in svoji.
  Map<String, List<PosnetekPesmi>> posnetki = {};
  KnjiznicaMidi midi = KnjiznicaMidi();
  DateTime? zadnjaOsvezitev;
  Map<String, dynamic> _podatki = {};

  /// Osebne risbe prijavljenega člana.
  late final Risbe risbe;

  /// Skupne risbe pesmi (npr. pobarvani refreni), enake za vse; rišejo jih urejevalci.
  late final Risbe risbeSkupne;

  /// Vodja: risbe ostalih članov za iPade na špilu.
  late final RisbeClanov risbeClanov;

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
    final n = await shramba.beriBesedilo(_kljucNeposlanih);
    if (n != null) neposlano = (jsonDecode(n) as List).cast<Map<String, dynamic>>();
    final d = await shramba.beriBesedilo(_kljucDnevnika);
    if (d != null) dnevnik = (jsonDecode(d) as List).cast<Map<String, dynamic>>();
    notifyListeners();
  }

  // ---------- Dnevnik odprtih pesmi ----------

  static const _kljucDnevnika = 'dnevnik.json';

  /// Zapisi odprtih pesmi, ki še niso na strežniku (list Dnevnik igranja).
  List<Map<String, dynamic>> dnevnik = [];
  bool _posiljamDnevnik = false;

  /// Zabeleži odprto pesem; na strežnik gre takoj, ko je internet (sicer ob naslednji osvežitvi).
  Future<void> zabelezi(Api? api, Map<String, dynamic> zapis) async {
    dnevnik.add({'id': _novId(), ...zapis});
    await shramba.pisiBesedilo(_kljucDnevnika, jsonEncode(dnevnik));
    if (api != null) await posljiDnevnik(api);
  }

  Future<void> posljiDnevnik(Api api) async {
    if (_posiljamDnevnik || dnevnik.isEmpty) return;
    _posiljamDnevnik = true;
    try {
      final paket = List.of(dnevnik.take(200));
      await api.dnevnik(paket);
      final poslani = {for (final z in paket) z['id']};
      dnevnik.removeWhere((z) => poslani.contains(z['id']));
      await shramba.pisiBesedilo(_kljucDnevnika, jsonEncode(dnevnik));
    } catch (_) {
      // ostane za naslednjič
    } finally {
      _posiljamDnevnik = false;
    }
  }

  static int _stevec = 0;

  /// Kratek ID, ki ga določi naprava (klicaj, zapis dnevnika), da ga je mogoče izbrisati tudi brez interneta.
  static String _novId() {
    _stevec = (_stevec + 1) % 1296;
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '${t.substring(t.length - 6)}${_stevec.toRadixString(36).padLeft(2, '0')}';
  }

  // ---------- Urejanje brez interneta ----------

  static const _kljucNeposlanih = 'neposlano.json';
  static const _zacasni = 'lokalno-';

  /// Spremembe, shranjene brez interneta, ki čakajo na pošiljanje (po vrsti).
  List<Map<String, dynamic>> neposlano = [];

  /// Napaka ni od strežnika (ta vrne ApiNapaka), torej ni povezave ali prijave.
  static bool _brezPovezave(Object e) => e is NiPovezave || e is! ApiNapaka;

  Future<void> _shraniNeposlano() => shramba.pisiBesedilo(_kljucNeposlanih, jsonEncode(neposlano));

  Future<void> _dodajNeposlano(String akcija, Zapis podatki) async {
    final id = besedilo(podatki['ID']);
    // Novo besedilo, ki se je vmes spet spremenilo: pošlje se samo zadnja različica.
    final prej = id.startsWith(_zacasni) ? neposlano.indexWhere((n) => n['zacasniId'] == id) : -1;
    final vnos = {
      'akcija': akcija,
      'podatki': id.startsWith(_zacasni) ? ({...podatki}..remove('ID')) : podatki,
      if (id.startsWith(_zacasni)) 'zacasniId': id,
    };
    if (prej >= 0 && besedilo(podatki['Besedilo']).isEmpty && podatki.containsKey('Besedilo')) {
      // Novo besedilo, ki je bilo izbrisano, preden je prišlo na strežnik.
      neposlano.removeAt(prej);
    } else if (prej >= 0) {
      neposlano[prej] = vnos;
    } else {
      neposlano.add(vnos);
    }
    await _shraniNeposlano();
  }

  Zapis? _vrstica(String tabela, String id) => ((_podatki['tabele'] as Map?)?[tabela] as List?)
      ?.cast<Map<String, dynamic>>()
      .where((r) => besedilo(r['ID']) == id)
      .firstOrNull;

  /// Pošlje spremembe, shranjene brez interneta. Ustavi se ob prvi napaki povezave.
  /// Spremembo, ki jo strežnik zavrne, zavrže in vrne opis; vrne null, če je vse poslano.
  Future<String?> posljiNeposlano(Api api) async {
    // Hkrati pošilja samo en klic, da se ista sprememba ne pošlje dvakrat.
    if (_posiljamNeposlano) return null;
    _posiljamNeposlano = true;
    try {
      return await _posljiNeposlano(api);
    } finally {
      _posiljamNeposlano = false;
    }
  }

  bool _posiljamNeposlano = false;

  Future<String?> _posljiNeposlano(Api api) async {
    final zavrnjene = <String>[];
    while (neposlano.isNotEmpty) {
      final n = neposlano.first;
      final podatki = (n['podatki'] as Map).cast<String, dynamic>();
      try {
        if (n['akcija'] == 'pesem') {
          final odg = await api.shraniPesem(podatki);
          await _zamenjajVrstico('Pesmi', (odg['vrstica'] as Map).cast<String, dynamic>());
        } else if (n['akcija'] == 'zaVajo') {
          // Star zapis klicaja (pred klicaji na mestu): samo še pošlje.
          await api.zaVajo(besedilo(podatki['ID']), daNe(podatki['Za vajo']));
        } else if (n['akcija'] == 'posnetek') {
          await _posljiPosnetek(api, n, podatki);
        } else if (n['akcija'] == 'klicaj') {
          final odg = await api.klicaj(podatki, izbrisi: n['izbrisi'] == true);
          if (odg['vrstica'] case final Map v) await _zamenjajVrstico('Klicaji', v.cast<String, dynamic>());
        } else {
          final odg = await api.shraniBesedilo(podatki);
          if (n['zacasniId'] case final String z) await _zamenjajVrstico('Besedila', null, izbrisi: z);
          if (odg['izbrisano'] != null) {
            await _zamenjajVrstico('Besedila', null, izbrisi: odg['izbrisano'].toString());
          } else {
            await _zamenjajVrstico('Besedila', (odg['vrstica'] as Map).cast<String, dynamic>());
          }
        }
      } on ApiNapaka catch (e) {
        if (e is NiPovezave) break;
        zavrnjene.add(
          '${switch (n['akcija']) {
            'besedilo' => 'Besedilo',
            'klicaj' => 'Klicaj',
            'posnetek' => 'Posnetek',
            _ => 'Pesem',
          }}: $e',
        );
      } catch (_) {
        break; // še vedno brez povezave
      }
      neposlano.removeAt(0);
      await _shraniNeposlano();
      notifyListeners();
    }
    if (neposlano.isNotEmpty) return '${neposlano.length} sprememb še čaka na internet.';
    return zavrnjene.isEmpty ? null : 'Strežnik ni sprejel: ${zavrnjene.join('; ')}';
  }

  void _uporabi(Map<String, dynamic> podatki) {
    _podatki = podatki;
    final tabele = (podatki['tabele'] as Map<String, dynamic>?) ?? {};
    List<Zapis> t(String ime) => ((tabele[ime] as List?) ?? []).cast<Map<String, dynamic>>();

    klicaji = {};
    for (final k in t('Klicaji').map(KlicajPesmi.izVrstice).where((k) => k.id.isNotEmpty)) {
      klicaji.putIfAbsent(k.pesem, () => []).add(k);
    }
    posnetki = {};
    for (final p in t('Posnetki').map(PosnetekPesmi.izVrstice).where((p) => p.id.isNotEmpty)) {
      posnetki.putIfAbsent(p.pesem, () => []).add(p);
    }
    for (final l in posnetki.values) {
      l.sort((a, b) => (b.cas ?? DateTime(0)).compareTo(a.cas ?? DateTime(0)));
    }
    vloge = ((podatki['vloge'] as List?) ?? []).cast<Map<String, dynamic>>().map(Vloga.izVrstice).toList();
    final zasedba = this.zasedba;
    bool zaZasedbo(List<String> z) => zasedba.isEmpty || z.isEmpty || z.contains(zasedba);
    pesmi = [
      for (final r in t('Pesmi'))
        if (Pesem.izVrstice(r, klicaji: klicaji[besedilo(r['ID'])]?.length ?? 0) case final p
            when p.id.isNotEmpty && p.aktivna && zaZasedbo(p.skupine))
          p,
    ]..sort((a, b) => a.kodaStevilka.compareTo(b.kodaStevilka));
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

    setliste =
        t('Setliste')
            .map(Setlista.izVrstice)
            .where((s) => s.id.isNotEmpty && zaZasedbo([if (s.skupina.isNotEmpty) s.skupina]))
            .toList()
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
    mape = t('Mape').map(Mapa.izVrstice).where((m) => m.id.isNotEmpty).toList()
      ..sort((a, b) => a.vrstniRed.compareTo(b.vrstniRed));
    harmonike = t('Harmonike').map(Harmonika.izVrstice).where((h) => h.id.isNotEmpty && h.ime.isNotEmpty).toList()
      ..sort((a, b) => a.vrstniRed.compareTo(b.vrstniRed));
    vrste = t('Vrste').map(Harmonika.izVrstice).where((h) => h.id.isNotEmpty && h.ime.isNotEmpty).toList()
      ..sort((a, b) => a.vrstniRed.compareTo(b.vrstniRed));
    midi = KnjiznicaMidi.izTabel(tabele);
    zadnjaOsvezitev = DateTime.tryParse(podatki['cas']?.toString() ?? '');
  }

  /// Prenese podatke in manjkajoče PDF-je. Že preneseni PDF-ji ostanejo.
  Future<void> osvezi(Api api) async {
    if (osvezujem) return;
    osvezujem = true;
    napaka = null;
    stanje = 'Prenašam seznam pesmi …';
    notifyListeners();
    String? zavrnjene;
    try {
      // Najprej spremembe, shranjene brez interneta; dokler niso poslane, se lokalna kopija ne zamenja.
      if (neposlano.isNotEmpty) {
        stanje = 'Pošiljam spremembe, shranjene brez interneta …';
        notifyListeners();
        zavrnjene = await posljiNeposlano(api);
        if (neposlano.isNotEmpty) {
          stanje = zavrnjene;
          return;
        }
      }
      await posljiDnevnik(api);
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
        await risbeSkupne.sinhroniziraj(api);
      } catch (e) {
        risbeNapaka = true;
      }
      String? risbeClanovNapaka;
      if (smeVoditi && !Config.prekoVodje) {
        stanje = 'Prenašam risbe članov za špil …';
        notifyListeners();
        try {
          await risbeClanov.sinhroniziraj(api);
        } on ApiNapaka catch (e) {
          risbeClanovNapaka = e.sporocilo.contains('Neznana akcija')
              ? 'Skripta še nima risb članov za špil (uvedi novo različico).'
              : 'Risb članov za špil ni bilo mogoče prenesti.';
        } catch (_) {
          risbeClanovNapaka = 'Risb članov za špil ni bilo mogoče prenesti.';
        }
      }
      stanje = [
        ?zavrnjene,
        if (neuspeli.isNotEmpty) '${neuspeli.length} PDF-jev ni bilo mogoče prenesti.',
        if (risbeNapaka) 'Risb ni bilo mogoče uskladiti.',
        ?risbeClanovNapaka,
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
  /// Brez interneta se sprememba obstoječe pesmi shrani na napravo in pošlje pozneje ([neposlano]).
  Future<Pesem> shraniPesem(Api api, Zapis podatki) async {
    final Map<String, dynamic> odg;
    try {
      // Prejšnje spremembe morajo na strežnik prve; če ne gredo, gre tudi ta v čakalno vrsto.
      if (neposlano.isNotEmpty) await posljiNeposlano(api);
      if (neposlano.isNotEmpty) throw StateError('Prejšnje spremembe še niso poslane');
      odg = await api.shraniPesem(podatki);
    } catch (e) {
      final stara = _vrstica('Pesmi', besedilo(podatki['ID']));
      if (!_brezPovezave(e)) rethrow;
      if (stara == null) throw StateError('Za novo pesem je potreben internet.');
      final vrstica = {...stara, ...podatki};
      await _dodajNeposlano('pesem', podatki);
      await _zamenjajVrstico('Pesmi', vrstica);
      return Pesem.izVrstice(vrstica);
    }
    final vrstica = (odg['vrstica'] as Map).cast<String, dynamic>();
    await _zamenjajVrstico('Pesmi', vrstica);
    return Pesem.izVrstice(vrstica);
  }

  Pesem? pesem(String id) => _poId[id];

  /// Pesmi v mapi brez arhiviranih; [mapa] null pomeni vse mape.
  List<Pesem> pesmiMape(String? mapa) => [
    for (final p in pesmi)
      if (!p.vArhivu && (mapa == null || p.mapa == mapa)) p,
  ];

  List<Pesem> get arhiv => [
    for (final p in pesmi)
      if (p.vArhivu) p,
  ];

  Mapa? mapa(String id) => mape.where((m) => m.id == id).firstOrNull;

  /// Harmonika po imenu (stolpec Harmonika pri pesmi).
  Harmonika? harmonika(String ime) => harmonike.where((h) => h.ime == ime).firstOrNull;

  /// Vrsta pesmi z barvo po imenu (stolpec Vrsta pri pesmi).
  Harmonika? vrsta(String ime) => vrste.where((h) => h.ime == ime).firstOrNull;

  /// Pesmi s klicaji (brez arhiviranih), za mapo »Za vajo«.
  List<Pesem> get pesmiSKlicaji => [
    for (final p in pesmi)
      if (!p.vArhivu && p.zaVajo) p,
  ];

  /// ID-ji zasedb prijavljenega člana, kot jih pošlje skripta (stara skripta jih ne pošlje: brez izbire).
  List<String> get zasedbeClana {
    final z = (_podatki['clan'] as Map?)?['Zasedbe'];
    return z is List ? [for (final x in z) besedilo(x)] : const [];
  }

  /// Zasedbe člana z imeni (za izbiro).
  List<Skupina> get mojeZasedbe => [
    for (final id in zasedbeClana) skupine.where((s) => s.id == id).firstOrNull ?? Skupina(id: id, ime: id),
  ];

  /// Zasedba, katere pesmi so prikazane: izbrana, edina ali prazno (vse, ki jih je skripta poslala).
  String get zasedba {
    final z = zasedbeClana;
    final izbrana = Nastavitve.aplikacija.zasedba;
    if (z.contains(izbrana)) return izbrana;
    return z.length == 1 ? z.first : '';
  }

  /// Član je v več zasedbah in še ni izbral, katero gleda.
  bool get moraIzbratiZasedbo => zasedbeClana.length > 1 && !zasedbeClana.contains(Nastavitve.aplikacija.zasedba);

  /// Nastavitve pogleda, ki jih je poslal administrator (JSON), ali null.
  String? get pogled => (_podatki['pogled'] as Map?)?['vsebina']?.toString();

  /// Ali naj aplikacija ponudi prevzem nastavitev pogleda administratorja.
  bool get novPogled => pogled != null && pogled != Nastavitve.aplikacija.pogledPrevzet;

  bool get jeAdministrator => vloge.any((v) => v.vloga == 'Administrator');

  /// Zamenja prikazano zasedbo (zapomni si jo na napravi).
  Future<void> izberiZasedbo(String id) async {
    await Nastavitve.aplikacija.nastaviZasedbo(id);
    _uporabi(_podatki);
    notifyListeners();
  }

  /// ID prijavljenega člana (prazno, če ni prijave).
  String get clanId => besedilo((_podatki['clan'] as Map?)?['ID']);

  /// Ime člana po ID-ju (npr. kdo je dodal klicaj).
  String imeClanaZ(String id) => clani.where((c) => c.id == id).firstOrNull?.ime ?? id;

  /// Nov klicaj na mestu ([stran] 0 je besedilo): takoj na napravi, na strežnik takoj ali pozneje.
  /// Brez [api] (npr. vodja brez prijave) počaka med neposlanimi.
  Future<KlicajPesmi> dodajKlicaj(Api? api, String pesem, int stran, double x, double y, {String? clan}) async {
    final k = KlicajPesmi(
      id: _novId(),
      pesem: pesem,
      stran: stran,
      x: x,
      y: y,
      clan: clan ?? clanId,
      cas: DateTime.now(),
    );
    await shraniKlicaj(api, k.vVrstico());
    return k;
  }

  /// Shrani klicaj (tudi tistega, ki ga vodji pošlje iPad).
  Future<void> shraniKlicaj(Api? api, Zapis vrstica) async {
    neposlano.add({'akcija': 'klicaj', 'podatki': vrstica});
    await _shraniNeposlano();
    await _zamenjajVrstico('Klicaji', vrstica);
    if (api != null) await _posljiTiho(api);
  }

  Future<void> izbrisiKlicaj(Api? api, String id) async {
    final vrstica = _vrstica('Klicaji', id) ?? {'ID': id};
    // Klicaj, ki še ni bil poslan, se samo umakne.
    final prej = neposlano.indexWhere(
      (n) => n['akcija'] == 'klicaj' && n['izbrisi'] != true && besedilo((n['podatki'] as Map)['ID']) == id,
    );
    if (prej >= 0) {
      neposlano.removeAt(prej);
    } else {
      neposlano.add({'akcija': 'klicaj', 'podatki': vrstica, 'izbrisi': true});
    }
    await _shraniNeposlano();
    await _zamenjajVrstico('Klicaji', null, izbrisi: id);
    if (api != null) await _posljiTiho(api);
  }

  // ---------- Zvočni posnetki ----------

  static String _kljucPosnetka(String id) => 'posnetki/$id';

  /// Nov posnetek: zvok ostane na napravi, na strežnik gre takoj ali pozneje (kot klicaji).
  Future<PosnetekPesmi> dodajPosnetek(
    Api? api,
    String pesem,
    Uint8List bajti, {
    required bool skupno,
    required String ime,
    required String vrsta,
    required int trajanje,
  }) async {
    final p = PosnetekPesmi(
      id: _novId(),
      pesem: pesem,
      clan: clanId,
      skupno: skupno,
      ime: ime,
      vrsta: vrsta,
      trajanje: trajanje,
      velikostKb: (bajti.length / 1024).round(),
      cas: DateTime.now(),
    );
    await shramba.pisiBajte(_kljucPosnetka(p.id), bajti);
    neposlano.add({'akcija': 'posnetek', 'podatki': p.vVrstico()});
    await _shraniNeposlano();
    await _zamenjajVrstico('Posnetki', p.vVrstico());
    if (api != null) await _posljiTiho(api);
    return p;
  }

  Future<void> _posljiPosnetek(Api api, Map<String, dynamic> n, Zapis podatki) async {
    final id = besedilo(podatki['ID']);
    if (n['izbrisi'] == true) {
      await api.izbrisiPosnetek(id);
      return;
    }
    final bajti = await shramba.beriBajte(_kljucPosnetka(id));
    if (bajti == null) return; // zvoka ni več na napravi
    final odg = await api.dodajPosnetek(podatki, bajti);
    if (odg['vrstica'] case final Map v) await _zamenjajVrstico('Posnetki', v.cast<String, dynamic>());
  }

  /// Zvok posnetka: z naprave ali s strežnika (in se shrani za brez interneta).
  Future<Uint8List?> zvokPosnetka(Api? api, PosnetekPesmi p) async {
    final lokalno = await shramba.beriBajte(_kljucPosnetka(p.id));
    if (lokalno != null || api == null || p.driveId.isEmpty) return lokalno;
    final bajti = await api.posnetek(p.id);
    await shramba.pisiBajte(_kljucPosnetka(p.id), bajti);
    return bajti;
  }

  /// Ali sme član izbrisati posnetek (svojega; administrator vse).
  bool smeIzbrisatiPosnetek(PosnetekPesmi p) => p.clan == clanId || jeAdministrator;

  Future<void> izbrisiPosnetek(Api? api, String id) async {
    final vrstica = _vrstica('Posnetki', id) ?? {'ID': id};
    final prej = neposlano.indexWhere(
      (n) => n['akcija'] == 'posnetek' && n['izbrisi'] != true && besedilo((n['podatki'] as Map)['ID']) == id,
    );
    if (prej >= 0) {
      neposlano.removeAt(prej);
    } else {
      neposlano.add({'akcija': 'posnetek', 'podatki': vrstica, 'izbrisi': true});
    }
    await _shraniNeposlano();
    await shramba.izbrisi(_kljucPosnetka(id));
    await _zamenjajVrstico('Posnetki', null, izbrisi: id);
    if (api != null) await _posljiTiho(api);
  }

  Future<void> _posljiTiho(Api api) async {
    try {
      await posljiNeposlano(api);
    } catch (_) {
      // ostane med neposlanimi
    }
  }

  /// Vrstica lista Pesmi, kot je v lokalni kopiji.
  Zapis? vrsticaPesmi(String id) => _vrstica('Pesmi', id);

  /// Doda PDF pesmi; shrani ga tudi na napravo, da ga ni treba prenašati.
  Future<void> dodajPdf(Api api, String pesem, String ime, String vrsta, Uint8List bajti) async {
    final odg = await api.dodajPdf(pesem, ime, vrsta, bajti);
    final vrstica = (odg['vrstica'] as Map).cast<String, dynamic>();
    await shramba.pisiBajte(_kljucPdf(besedilo(vrstica['Drive ID'])), bajti);
    await _zamenjajVrstico('PDF', vrstica);
  }

  Future<void> izbrisiPdf(Api api, PdfDatoteka pdf) async {
    await api.izbrisiPdf(pdf.id);
    await _zamenjajVrstico('PDF', null, izbrisi: pdf.id);
    await shramba.izbrisi(_kljucPdf(pdf.driveId));
  }

  /// Ime prijavljenega člana (npr. za oglašanje vodje na omrežju).
  String get imeClana => ((_podatki['clan'] as Map?)?['Ime'] ?? '').toString();

  /// Ali sme prijavljeni član na špilu voditi (stolpec Sme voditi na listu Vloge).
  bool get smeVoditi => vloge.any((v) => v.smeVoditi);

  /// Podatki, ki jih vodja na špilu da iPadom: vse razen svojih vlog (sledilci ne urejajo).
  /// Podatki za iPade na špilu: brez vlog in brez e-naslovov članov.
  String podatkiZaSledilce() {
    final tabele = (_podatki['tabele'] as Map<String, dynamic>?) ?? const {};
    return jsonEncode({
      ..._podatki,
      'vloge': const [],
      'clan': null,
      'tabele': {
        ...tabele,
        'Člani': [
          for (final c in (tabele['Člani'] as List?) ?? const [])
            if (c is Map) {...c}..remove('Email'),
        ],
      },
    });
  }

  /// Aktivni člani (ID, ime), npr. za izbiro na iPadu prek vodje.
  List<({String id, String ime})> get clani => [
    for (final c in ((_podatki['tabele'] as Map?)?['Člani'] as List?) ?? const [])
      if (c is Map &&
          c['ID'] != null &&
          c['ID'].toString().isNotEmpty &&
          c['Aktiven'] != false &&
          c['Aktiven'] != 'FALSE')
        (id: c['ID'].toString(), ime: (c['Ime'] ?? c['ID']).toString()),
  ]..sort((a, b) => a.ime.compareTo(b.ime));

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
    final Map<String, dynamic> odg;
    try {
      // Prejšnje spremembe morajo na strežnik prve; če ne gredo, gre tudi ta v čakalno vrsto.
      if (neposlano.isNotEmpty) await posljiNeposlano(api);
      if (neposlano.isNotEmpty) throw StateError('Prejšnje spremembe še niso poslane');
      odg = await api.shraniBesedilo(podatki);
    } catch (e) {
      if (!_brezPovezave(e)) rethrow;
      // Brez interneta: na napravo (novo besedilo dobi začasen ID), na strežnik pozneje.
      final id = besedilo(podatki['ID']).isEmpty
          ? '$_zacasni${DateTime.now().microsecondsSinceEpoch}'
          : besedilo(podatki['ID']);
      final zapis = {...podatki, 'ID': id};
      await _dodajNeposlano('besedilo', zapis);
      if (besedilo(podatki['Besedilo']).isEmpty) {
        await _zamenjajVrstico('Besedila', null, izbrisi: id);
      } else {
        await _zamenjajVrstico('Besedila', {...?_vrstica('Besedila', id), ...zapis});
      }
      return;
    }
    if (odg['izbrisano'] != null) {
      await _zamenjajVrstico('Besedila', null, izbrisi: odg['izbrisano'].toString());
    } else {
      await _zamenjajVrstico('Besedila', (odg['vrstica'] as Map).cast<String, dynamic>());
    }
  }

  /// Shrani (ali izbriše) ukaz, makro, gumb, ime kanala ali harmoniko. Kanali imajo za ID številko kanala.
  Future<void> shraniMidi(Api api, String tabela, Zapis vrstica, {bool izbrisi = false}) async {
    final odg = await api.shraniMidi(tabela, vrstica, izbrisi: izbrisi);
    final kljuc = tabela == 'MIDI kanali' ? 'Kanal' : 'ID';
    if (odg['izbrisano'] != null) {
      await _zamenjajVrstico(tabela, null, izbrisi: odg['izbrisano'].toString(), kljuc: kljuc);
    } else {
      await _zamenjajVrstico(tabela, (odg['vrstica'] as Map).cast<String, dynamic>(), kljuc: kljuc);
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
  Future<void> _zamenjajVrstico(String tabela, Zapis? vrstica, {String? izbrisi, String kljuc = 'ID'}) async {
    final tabele = (_podatki['tabele'] as Map<String, dynamic>?) ?? (_podatki['tabele'] = <String, dynamic>{});
    final vrstice = ((tabele[tabela] as List?) ?? []).cast<Map<String, dynamic>>().toList();
    final id = izbrisi ?? besedilo(vrstica![kljuc]);
    final i = vrstice.indexWhere((r) => besedilo(r[kljuc]) == id);
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
