import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';
import 'nastavitve.dart';
import 'config.dart';
import 'efekti.dart';
import 'filtri.dart';
import 'midi/ukazi.dart';
import 'risbe.dart';
import 'shramba/shramba.dart';

/// Lokalna kopija baze: podatki v baza.json, PDF-ji pod pdf/. Na špilu se bere samo od tu.
class Baza extends ChangeNotifier {
  Baza({Shramba? shramba}) : shramba = shramba ?? Shramba() {
    risbe = Risbe(this.shramba)..obNeposlanih = notifyListeners;
    risbeSkupne = Risbe(this.shramba, skupne: true)..obNeposlanih = notifyListeners;
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

  /// Posneti špili (najnovejši prvi) in igranja po pesmih (najnovejša prva).
  List<Snemanje> snemanja = [];

  /// Nastopi od včeraj do 90 dni naprej (iz Nastopov, samo branje); ostanejo tudi brez interneta.
  List<Map<String, dynamic>> nastopi = [];

  /// Nastopi na dan [t] in dan prej ali potem (najprej današnji), za naslov snemanja.
  List<Map<String, dynamic>> nastopiOkrog(DateTime t) {
    String dan(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final danes = dan(t);
    final okrog = {dan(t.subtract(const Duration(days: 1))), danes, dan(t.add(const Duration(days: 1)))};
    return nastopi.where((n) => okrog.contains(besedilo(n['Datum']))).toList()
      ..sort((a, b) => (besedilo(a['Datum']) == danes ? 0 : 1).compareTo(besedilo(b['Datum']) == danes ? 0 : 1));
  }

  /// Današnji nastop (prvi), npr. za ohranjevalnik zaslona.
  Map<String, dynamic>? nastopDanes(DateTime t) {
    final d = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    return nastopi.where((n) => besedilo(n['Datum']) == d).firstOrNull;
  }

  Map<String, List<Igranje>> igranja = {};

  /// Snemanje, v katerem je bila pesem igrana ob [cas].
  Snemanje? snemanjeOb(DateTime cas) => snemanja.where((s) => s.vsebuje(cas)).firstOrNull;

  /// Video lahko zahteva vodja ali administrator (ne iPad prek vodje).
  bool get smeZahtevatiVideo => (smeVoditi || jeAdministrator) && !Config.prekoVodje;

  /// Video posnetega špila zdaj (GitHub ga naredi v nekaj deset minutah); stanje se zapiše takoj.
  Future<void> narediVideo(Api api, String id) async {
    final odg = await api.narediVideo(id);
    if (odg['vrstica'] case final Map v) await _zamenjajVrstico('Snemanja', v.cast<String, dynamic>());
  }

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

  /// Napredek trenutnega prenosa (0–1) za vrstico pod sporočilom; null = ne vemo, koliko je še.
  double? napredek;

  /// Administrator: aktivni člani brez vrstice na listu Vloge (pošlje skripta).
  List<String> get claniBrezVloge => [for (final c in (_podatki['brezVloge'] as List?) ?? const []) c.toString()];

  /// Prijavljen član nima nobene vloge (na listu Vloge ga ni): v aplikaciji je samo gledalec.
  bool get brezVloge => clanId.isNotEmpty && vloge.isEmpty;

  static const _kljucPodatkov = 'baza.json';
  static String _kljucPdf(String driveId) => 'pdf/$driveId.pdf';

  /// Lokalno shranjen PDF ali null, če še ni prenesen.
  Future<Uint8List?> pdf(String driveId) => shramba.beriBajte(_kljucPdf(driveId));

  Future<void> nalozi() async {
    // Prebere neposlane risbe z naprave (za oblaček čakajočih sprememb).
    await risbe.posljiNeposlane();
    await risbeSkupne.posljiNeposlane();
    // Najprej neposlano, da so neposlani posnetki vidni takoj.
    final n = await shramba.beriBesedilo(_kljucNeposlanih);
    if (n != null) neposlano = (jsonDecode(n) as List).cast<Map<String, dynamic>>();
    final s = await shramba.beriBesedilo(_kljucPodatkov);
    if (s != null) _uporabi(jsonDecode(s) as Map<String, dynamic>);
    final slike = await shramba.beriBesedilo(_kljucSlik);
    if (slike != null) {
      try {
        _uporabiSlike((jsonDecode(slike) as Map).cast<String, dynamic>());
      } catch (_) {}
    }
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
  static String novId() => _novId();

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
  Future<String?> posljiNeposlano(Api api) {
    // Hkrati pošilja samo en klic, da se ista sprememba ne pošlje dvakrat; drugi počaka nanj in nato
    // poskusi še sam (prejšnji je lahko odnehal brez povezave).
    if (_posiljam case final tece?) {
      return tece.then((_) => null, onError: (_) => null).then((_) => posljiNeposlano(api));
    }
    final f = _posljiNeposlano(api).whenComplete(() => _posiljam = null);
    return _posiljam = f;
  }

  Future<String?>? _posiljam;

  /// Počaka, da se konča pošiljanje, ki teče v ozadju.
  Future<void> pocakajPosiljanje() async {
    try {
      await _posiljam;
    } catch (_) {}
  }

  /// Ali kaj čaka na internet (posnetki, ki čakajo na novo skripto, ne zadržijo osvežitve).
  bool get _cakaInternet => neposlano.any((n) => n['cakaSkripto'] != true);

  Future<String?> _posljiNeposlano(Api api) async {
    final zavrnjene = <String>[];
    var i = 0;
    while (i < neposlano.length) {
      final n = neposlano[i];
      final podatki = (n['podatki'] as Map).cast<String, dynamic>();
      try {
        if (n['akcija'] == 'pesem') {
          final odg = await api.shraniPesem(podatki);
          await _zamenjajVrstico('Pesmi', (odg['vrstica'] as Map).cast<String, dynamic>());
        } else if (n['akcija'] == 'pesmi') {
          await _posljiPesmi(api, [for (final p in podatki['pesmi'] as List) (p as Map).cast<String, dynamic>()]);
        } else if (n['akcija'] == 'zaVajo') {
          // Star zapis klicaja (pred klicaji na mestu): samo še pošlje.
          await api.zaVajo(besedilo(podatki['ID']), daNe(podatki['Za vajo']));
        } else if (n['akcija'] == 'posnetek') {
          await _posljiPosnetek(api, n, podatki);
        } else if (n['akcija'] == 'nastavitev') {
          await api.mojaNastavitev(besedilo(podatki['Ključ']), besedilo(podatki['Vrednost']));
        } else if (n['akcija'] == 'klicaj') {
          final odg = await api.klicaj(podatki, izbrisi: n['izbrisi'] == true);
          if (odg['vrstica'] case final Map v) await _zamenjajVrstico('Klicaji', v.cast<String, dynamic>());
        } else {
          final odg = await api.shraniBesedilo(podatki);
          final zacasni = n['zacasniId'] as String?;
          if ((zacasni, odg['vrstica']) case (final String zacasni, final Map v)) {
            // Začasno vrstico zamenja prava v enem zapisu (vmesnega stanja brez besedila ni).
            _praviId[zacasni] = besedilo(v['ID']);
            await _zamenjajVrstico('Besedila', v.cast<String, dynamic>(), izbrisi: zacasni);
          } else if (zacasni != null) {
            await _zamenjajVrstico('Besedila', null, izbrisi: zacasni);
          } else if (odg['izbrisano'] != null) {
            await _zamenjajVrstico('Besedila', null, izbrisi: odg['izbrisano'].toString());
          } else {
            await _zamenjajVrstico('Besedila', (odg['vrstica'] as Map).cast<String, dynamic>());
          }
        }
      } on ApiNapaka catch (e) {
        if (e is NiPovezave) break;
        // Stara skripta posnetkov še ne pozna: posnetek ostane na napravi, dokler ni nove različice.
        if ((n['akcija'] == 'posnetek' || n['akcija'] == 'nastavitev') && e.sporocilo.contains('Neznana akcija')) {
          n['cakaSkripto'] = true;
          i++;
          continue;
        }
        zavrnjene.add(
          '${switch (n['akcija']) {
            'besedilo' => 'Besedilo',
            'klicaj' => 'Klicaj',
            'posnetek' => 'Posnetek',
            'nastavitev' => 'Nastavitev',
            'pesmi' => 'Pesmi',
            _ => 'Pesem',
          }}: $e',
        );
      } catch (_) {
        break; // še vedno brez povezave
      }
      neposlano.removeAt(i);
      await _shraniNeposlano();
      notifyListeners();
    }
    await _shraniNeposlano();
    if (_cakaInternet) return '${neposlano.length} sprememb še čaka na internet.';
    if (neposlano.isNotEmpty) {
      zavrnjene.add('Skripta teh sprememb še ne pozna (uvedi novo različico skripte), ostanejo na napravi');
    }
    return zavrnjene.isEmpty ? null : '$_zavrnil: ${zavrnjene.join('; ')}';
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
    // Neposlani posnetki ostanejo vidni tudi po osvežitvi (dokler jih strežnik ne sprejme).
    final neposlaniPosnetki = [
      for (final n in neposlano)
        if (n['akcija'] == 'posnetek' && n['ime'] != true)
          (izbrisi: n['izbrisi'] == true, vrstica: (n['podatki'] as Map).cast<String, dynamic>()),
    ];
    final noviNaslovi = {
      for (final n in neposlano)
        if (n['akcija'] == 'posnetek' && n['ime'] == true)
          besedilo((n['podatki'] as Map)['ID']): besedilo((n['podatki'] as Map)['Ime']),
    };
    final izbrisani = {
      for (final n in neposlaniPosnetki)
        if (n.izbrisi) besedilo(n.vrstica['ID']),
    };
    final streznik = t('Posnetki');
    final ids = {for (final r in streznik) besedilo(r['ID'])};
    final vrsticePosnetkov = [
      for (final r in streznik)
        if (noviNaslovi[besedilo(r['ID'])] case final ime?) {...r, 'Ime': ime} else r,
      for (final n in neposlaniPosnetki)
        if (!n.izbrisi && !ids.contains(besedilo(n.vrstica['ID']))) n.vrstica,
    ];
    for (final p
        in vrsticePosnetkov.map(PosnetekPesmi.izVrstice).where((p) => p.id.isNotEmpty && !izbrisani.contains(p.id))) {
      posnetki.putIfAbsent(p.pesem, () => []).add(p);
    }
    for (final l in posnetki.values) {
      l.sort((a, b) => (b.cas ?? DateTime(0)).compareTo(a.cas ?? DateTime(0)));
    }
    nastopi = [for (final r in t('Nastopi')) Map<String, dynamic>.from(r)]
      ..sort(
        (a, b) =>
            '${besedilo(a['Datum'])} ${besedilo(a['Od'])}'.compareTo('${besedilo(b['Datum'])} ${besedilo(b['Od'])}'),
      );
    snemanja = t('Snemanja').map(Snemanje.izVrstice).where((s) => s.id.isNotEmpty).toList()
      ..sort((a, b) => (b.zacetek ?? DateTime(0)).compareTo(a.zacetek ?? DateTime(0)));
    igranja = {};
    for (final r in t('Igranja')) {
      final cas = DateTime.tryParse(besedilo(r['Čas']));
      final pesem = besedilo(r['Pesem']);
      if (cas == null || pesem.isEmpty) continue;
      igranja.putIfAbsent(pesem, () => []).add((
        pesem: pesem,
        cas: cas,
        sekund: int.tryParse(besedilo(r['Trajanje (s)'])) ?? 0,
      ));
    }
    for (final l in igranja.values) {
      l.sort((a, b) => b.cas.compareTo(a.cas));
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
    // Član vidi mape zasedbe, ki jo gleda (mapa brez zasedbe je skupna).
    mape =
        t('Mape')
            .map(Mapa.izVrstice)
            .where((m) => m.id.isNotEmpty && zaZasedbo([if (m.zasedba.isNotEmpty) m.zasedba]))
            .toList()
          ..sort((a, b) => a.vrstniRed.compareTo(b.vrstniRed));
    harmonike = t('Harmonike').map(Harmonika.izVrstice).where((h) => h.id.isNotEmpty && h.ime.isNotEmpty).toList()
      ..sort((a, b) => a.vrstniRed.compareTo(b.vrstniRed));
    vrste = t('Vrste').map(Harmonika.izVrstice).where((h) => h.id.isNotEmpty && h.ime.isNotEmpty).toList()
      ..sort((a, b) => a.vrstniRed.compareTo(b.vrstniRed));
    midi = KnjiznicaMidi.izTabel(tabele);
    zadnjaOsvezitev = DateTime.tryParse(podatki['cas']?.toString() ?? '');
  }

  /// Prenese podatke in manjkajoče PDF-je. Že preneseni PDF-ji ostanejo.
  /// Napaka za obvestilo: največ 120 znakov.
  static String _kratko(Object e) {
    final s = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 120 ? '${s.substring(0, 120)} …' : s;
  }

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
        if (_cakaInternet) {
          stanje = zavrnjene;
          return;
        }
      }
      await posljiDnevnik(api);
      var podatki = await api.podatki();
      if (_cakaInternet) {
        // Med prenosom shranjene spremembe: najprej na strežnik, sicer bi jih prenos prepisal.
        await posljiNeposlano(api);
        if (_cakaInternet) {
          stanje = '${neposlano.length} sprememb še čaka na internet.';
          return;
        }
        podatki = await api.podatki();
      }
      await shramba.pisiBesedilo(_kljucPodatkov, jsonEncode(podatki));
      _uporabi(podatki);
      try {
        await osveziSlikeClanov(api);
      } catch (_) {
        // slike niso nujne (npr. stara skripta)
      }

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
          napredek = koncanih / manjkajo.length;
          stanje = 'Prenašam PDF-je: $koncanih od ${manjkajo.length} …';
          notifyListeners();
        }
      }

      await Future.wait(List.generate(hkratniPrenosi, (_) => delavec()));

      for (final v in VrstaZvoka.values) {
        if (!Nastavitve.aplikacija.hrani(v)) continue;
        stanje = 'Prenašam: ${v.ime} …';
        notifyListeners();
        await prenesiZvoke(api, v);
      }
      if (Nastavitve.aplikacija.hraniEfekte) {
        stanje = 'Prenašam: efekti …';
        notifyListeners();
        await prenesiEfekte(api);
      }

      napredek = null;
      stanje = 'Usklajujem risbe …';
      notifyListeners();
      String? risbeNapaka;
      var prenesenihRisb = 0;
      void obRisbah(int n) {
        stanje = 'Usklajujem risbe: ${prenesenihRisb + n} prenesenih …';
        notifyListeners();
      }

      try {
        prenesenihRisb += await risbe.sinhroniziraj(api, clan: clanId, obNapredku: obRisbah);
      } catch (e) {
        risbeNapaka = 'Tvojih risb ni bilo mogoče uskladiti (${_kratko(e)}).';
      }
      try {
        prenesenihRisb += await risbeSkupne.sinhroniziraj(api, obNapredku: obRisbah);
      } catch (e) {
        risbeNapaka = '${risbeNapaka ?? ''} Skupnih risb ni bilo mogoče uskladiti (${_kratko(e)}).'.trim();
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
        ?risbeNapaka,
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
      napredek = null;
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
  /// Kopija pesmi v drugi mapi (z besedili, PDF-ji in skupnimi risbami); potrebuje internet.
  Future<Pesem> kopirajPesem(Api api, String pesem, String mapa) async {
    if (_cakaInternet) await posljiNeposlano(api);
    final odg = await api.kopirajPesem(pesem, mapa);
    final vrstica = (odg['pesem'] as Map).cast<String, dynamic>();
    for (final b in (odg['besedila'] as List? ?? const [])) {
      await _zamenjajVrstico('Besedila', (b as Map).cast<String, dynamic>());
    }
    for (final d in (odg['pdf'] as List? ?? const [])) {
      await _zamenjajVrstico('PDF', (d as Map).cast<String, dynamic>());
    }
    await _zamenjajVrstico('Pesmi', vrstica);
    try {
      await risbeSkupne.sinhroniziraj(api);
    } catch (_) {}
    return Pesem.izVrstice(vrstica);
  }

  /// Obstoječa pesem se shrani takoj na napravo in pošlje v ozadju; nova pesem počaka na strežnik (dobi ID).
  Future<Pesem> shraniPesem(Api api, Zapis podatki) async {
    final obstojeca = _vrstica('Pesmi', besedilo(podatki['ID']));
    if (obstojeca != null) {
      final vrstica = {...obstojeca, ...podatki};
      await _dodajNeposlano('pesem', podatki);
      await _zamenjajVrstico('Pesmi', vrstica);
      _posljiVOzadju(api);
      return Pesem.izVrstice(vrstica);
    }
    final Map<String, dynamic> odg;
    try {
      // Prejšnje spremembe morajo na strežnik prve; če ne gredo, gre tudi ta v čakalno vrsto.
      if (_cakaInternet) await posljiNeposlano(api);
      if (_cakaInternet) throw StateError('Prejšnje spremembe še niso poslane');
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

  /// Hitro urejanje: shrani spremembe več pesmi (vsaka ima ID in spremenjena polja).
  /// Če skripta še ne pozna akcije »pesmi« ali ni interneta, gre vsaka pesem posebej (cela vrstica).
  Future<void> shraniPesmi(Api api, List<Zapis> spremembe, {void Function(int, int)? napredek}) async {
    if (spremembe.isEmpty) return;
    // Takoj na napravo (en zapis za vse), na strežnik v ozadju.
    final tabele = (_podatki['tabele'] as Map<String, dynamic>?) ?? (_podatki['tabele'] = <String, dynamic>{});
    final vrstice = ((tabele['Pesmi'] as List?) ?? []).cast<Map<String, dynamic>>().toList();
    for (final s in spremembe) {
      final i = vrstice.indexWhere((r) => besedilo(r['ID']) == besedilo(s['ID']));
      if (i >= 0) vrstice[i] = {...vrstice[i], ...s};
    }
    tabele['Pesmi'] = vrstice;
    neposlano.add({
      'akcija': 'pesmi',
      'podatki': {'pesmi': spremembe},
    });
    await _shraniNeposlano();
    await shramba.pisiBesedilo(_kljucPodatkov, jsonEncode(_podatki));
    _uporabi(_podatki);
    notifyListeners();
    napredek?.call(spremembe.length, spremembe.length);
    _posljiVOzadju(api);
  }

  /// Pošlje spremembe več pesmi; stara skripta akcije »pesmi« ne pozna, zato tam vsako posebej s celo vrstico.
  Future<void> _posljiPesmi(Api api, List<Zapis> spremembe) async {
    try {
      final odg = await api.shraniPesmi(spremembe);
      for (final v in (odg['vrstice'] as List).cast<Map<String, dynamic>>()) {
        await _zamenjajVrstico('Pesmi', v);
      }
      return;
    } on ApiNapaka catch (e) {
      if (e is NiPovezave || !e.sporocilo.contains('Neznana akcija')) rethrow;
    }
    for (final s in spremembe) {
      final stara = _vrstica('Pesmi', besedilo(s['ID']));
      if (stara == null) continue;
      final odg = await api.shraniPesem({...stara, ...s});
      await _zamenjajVrstico('Pesmi', (odg['vrstica'] as Map).cast<String, dynamic>());
    }
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

  /// Nastavitve špila (administrator): ali vsak obrne pesem za vse, tudi neprijavljene naprave.
  ({bool vsi, bool neprijavljeni}) get obracanje {
    final j = _spil;
    return (vsi: j['vsi'] == true, neprijavljeni: j['vsi'] == true && j['neprijavljeni'] == true);
  }

  /// Skupne nastavitve špila (JSON v Nastavitve pod SPIL).
  Map<String, dynamic> get _spil {
    try {
      final j = jsonDecode(besedilo(_podatki['spil']));
      if (j is Map) return j.cast<String, dynamic>();
    } catch (_) {}
    return {};
  }

  /// Klaviatura Tyros (administrator): kanal 1–16 in ali gre pred Program Change še banka (CC 0).
  ({int kanal, bool banka}) get tyros {
    final t = _spil['tyros'];
    if (t is! Map) return (kanal: 1, banka: true);
    return (kanal: ((t['kanal'] as num?)?.toInt() ?? 1).clamp(1, 16), banka: t['banka'] != false);
  }

  Future<void> shraniTyros(Api api, {required int kanal, required bool banka}) => _shraniSpil(api, {
    ..._spil,
    'tyros': {'kanal': kanal, 'banka': banka},
  });

  Future<void> _shraniSpil(Api api, Map<String, dynamic> j) async {
    final vsebina = jsonEncode(j);
    await api.shraniSpil(vsebina);
    _podatki['spil'] = vsebina;
    await shramba.pisiBesedilo(_kljucPodatkov, jsonEncode(_podatki));
    notifyListeners();
  }

  /// Ali sme ta naprava (sledilec) obrniti pesem za vse.
  bool get obracaZaVse =>
      (Config.samoKlicaji ? obracanje.neprijavljeni : obracanje.vsi) && Nastavitve.aplikacija.posiljamObracanje;

  Future<void> shraniObracanje(Api api, {required bool vsi, required bool neprijavljeni}) =>
      _shraniSpil(api, {..._spil, 'vsi': vsi, 'neprijavljeni': neprijavljeni});

  /// Osebne nastavitve člana iz baze, z neposlanimi spremembami s te naprave.
  Map<String, String> get mojeNastavitve => {
    for (final e in ((_podatki['moje'] as Map?) ?? const {}).entries) e.key.toString(): besedilo(e.value),
    for (final n in neposlano)
      if (n['akcija'] == 'nastavitev')
        besedilo((n['podatki'] as Map)['Ključ']): besedilo((n['podatki'] as Map)['Vrednost']),
  };

  /// Hitri filtri člana po mapah.
  FiltriClana get filtri => FiltriClana.izBesedila(mojeNastavitve[FiltriClana.kljuc] ?? '');

  Future<void> shraniFiltre(Api? api, String mapa, FiltriMape f) =>
      shraniMojoNastavitev(api, FiltriClana.kljuc, filtri.z(mapa, f).vBesedilo());

  /// Shrani osebno nastavitev: takoj na napravi, nato na strežnik (brez interneta počaka v neposlanih).
  Future<void> shraniMojoNastavitev(Api? api, String kljuc, String vrednost) async {
    _podatki['moje'] = {...((_podatki['moje'] as Map?) ?? const {}), kljuc: vrednost};
    neposlano.removeWhere((n) => n['akcija'] == 'nastavitev' && besedilo((n['podatki'] as Map)['Ključ']) == kljuc);
    await shramba.pisiBesedilo(_kljucPodatkov, jsonEncode(_podatki));
    notifyListeners();
    if (Config.samoKlicaji) {
      // Neprijavljena naprava (iPad prek vodje) nastavitev ohrani le pri sebi, če je vodja ne sprejme.
      await _shraniNeposlano();
      try {
        await api?.mojaNastavitev(kljuc, vrednost);
      } catch (_) {}
      return;
    }
    neposlano.add({
      'akcija': 'nastavitev',
      'podatki': {'Ključ': kljuc, 'Vrednost': vrednost},
    });
    await _shraniNeposlano();
    if (api != null) _posljiVOzadju(api);
  }

  /// Skupna postavitev FX panela in XY pada.
  PostavitevFx get fx {
    final b = besedilo(_podatki['fx']);
    if (b != _fxBesedilo) {
      _fxBesedilo = b;
      _fx = PostavitevFx.izBesedila(b);
    }
    return _fx;
  }

  String _fxBesedilo = '';
  PostavitevFx _fx = const PostavitevFx();

  /// Knjižnica zvočnih efektov.
  List<Efekt> get efekti => [
    for (final r in ((_podatki['tabele'] as Map?)?['Efekti'] as List?) ?? const [])
      if (r is Map) Efekt.izVrstice(r.cast<String, dynamic>()),
  ].where((e) => e.id.isNotEmpty).toList()..sort((a, b) => a.ime.toLowerCase().compareTo(b.ime.toLowerCase()));

  Efekt? efekt(String id) => efekti.where((e) => e.id == id).firstOrNull;

  /// Administrator shrani postavitev FX (potrebuje internet).
  Future<void> shraniFx(Api api, PostavitevFx p) async {
    final vsebina = p.vBesedilo();
    await api.shraniFx(vsebina);
    _podatki['fx'] = vsebina;
    await shramba.pisiBesedilo(_kljucPodatkov, jsonEncode(_podatki));
    notifyListeners();
  }

  /// Nov efekt, preimenovanje ali zamenjava zvoka (samo administrator, potrebuje internet).
  Future<Efekt?> shraniEfekt(Api api, {String? id, required String ime, Uint8List? bajti, String vrsta = ''}) async {
    final odg = await api.shraniEfekt(id: id, ime: ime, bajti: bajti, vrsta: vrsta);
    final v = (odg['vrstica'] as Map?)?.cast<String, dynamic>();
    if (v == null) return null;
    await _zamenjajVrstico('Efekti', v);
    if (bajti != null) _efektiVSeji.remove(besedilo(v['Datoteka']));
    return Efekt.izVrstice(v);
  }

  Future<void> izbrisiEfekt(Api api, String id) async {
    await api.shraniEfekt(id: id, izbrisi: true);
    await _zamenjajVrstico('Efekti', null, izbrisi: id);
  }

  static String _kljucEfekta(String datoteka) => 'efekti/$datoteka';
  final _efektiVSeji = <String, Uint8List>{};

  /// Zvok efekta: iz pomnilnika, z naprave ali s spleta (in ga shrani, če je »Hrani efekte lokalno«).
  Future<({Uint8List bajti, String vrsta})?> bajtiEfekta(Api? api, String id) async {
    final e = efekt(id);
    if (e == null || e.datoteka.isEmpty) return null;
    final vrsta = e.vrsta;
    if (_efektiVSeji[e.datoteka] case final b?) return (bajti: b, vrsta: vrsta);
    final lokalno = await shramba.beriBajte(_kljucEfekta(e.datoteka));
    if (lokalno != null) return (bajti: _efektiVSeji[e.datoteka] = lokalno, vrsta: vrsta);
    if (api == null) return null;
    final b = await api.efekt(e.id);
    if (Nastavitve.aplikacija.hraniEfekte) await shramba.pisiBajte(_kljucEfekta(e.datoteka), b.bajti);
    _efektiVSeji[e.datoteka] = b.bajti;
    return (bajti: b.bajti, vrsta: vrsta.isEmpty ? b.vrsta : vrsta);
  }

  /// Prenese manjkajoče efekte na napravo in pobriše tiste, ki jih ni več. Vrne število neuspelih.
  Future<int> prenesiEfekte(Api api) async {
    final preneseni = await shramba.kljuci('efekti/');
    final zdaj = {
      for (final e in efekti)
        if (e.datoteka.isNotEmpty) _kljucEfekta(e.datoteka): e,
    };
    for (final k in preneseni.difference(zdaj.keys.toSet())) {
      await shramba.izbrisi(k);
    }
    var neuspeli = 0;
    for (final MapEntry(key: k, value: e) in zdaj.entries) {
      if (preneseni.contains(k)) continue;
      try {
        await shramba.pisiBajte(k, _efektiVSeji[e.datoteka] ?? (await api.efekt(e.id)).bajti);
      } catch (_) {
        neuspeli++;
      }
    }
    return neuspeli;
  }

  Future<void> izbrisiLokalneEfekte() async {
    for (final k in await shramba.kljuci('efekti/')) {
      await shramba.izbrisi(k);
    }
  }

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

  /// Sledilec na špilu: klicaj gre tudi vodji, ta pa ga takoj pokaže vsem.
  void Function(Zapis vrstica, bool izbrisi)? obKlicaju;

  /// Vrstice klicajev, kot so v lokalni kopiji (vodja jih pošilja sledilcem).
  List<Zapis> get vrsticeKlicajev =>
      (((_podatki['tabele'] as Map?)?['Klicaji'] as List?) ?? const []).cast<Map<String, dynamic>>();

  /// Sledilec: klicaji od vodje. Lastni klicaji, ki še niso na strežniku, ostanejo.
  Future<void> prevzemiKlicaje(List<Zapis> vrstice) async {
    final cakajo = [
      for (final n in neposlano)
        if (n['akcija'] == 'klicaj')
          (izbrisi: n['izbrisi'] == true, vrstica: (n['podatki'] as Map).cast<String, dynamic>()),
    ];
    final izbrisani = {
      for (final c in cakajo)
        if (c.izbrisi) besedilo(c.vrstica['ID']),
    };
    final ids = {for (final v in vrstice) besedilo(v['ID'])};
    final nove = [
      for (final v in vrstice)
        if (!izbrisani.contains(besedilo(v['ID']))) v,
      for (final c in cakajo)
        if (!c.izbrisi && !ids.contains(besedilo(c.vrstica['ID']))) c.vrstica,
    ];
    final tabele = (_podatki['tabele'] as Map<String, dynamic>?) ?? (_podatki['tabele'] = <String, dynamic>{});
    if (jsonEncode(tabele['Klicaji']) == jsonEncode(nove)) return;
    tabele['Klicaji'] = nove;
    await shramba.pisiBesedilo(_kljucPodatkov, jsonEncode(_podatki));
    _uporabi(_podatki);
    notifyListeners();
  }

  /// Shrani klicaj (tudi tistega, ki ga vodji pošlje iPad).
  Future<void> shraniKlicaj(Api? api, Zapis vrstica) async {
    obKlicaju?.call(vrstica, false);
    neposlano.add({'akcija': 'klicaj', 'podatki': vrstica});
    await _shraniNeposlano();
    await _zamenjajVrstico('Klicaji', vrstica);
    if (api != null) _posljiVOzadju(api);
  }

  Future<void> izbrisiKlicaj(Api? api, String id) async {
    final vrstica = _vrstica('Klicaji', id) ?? {'ID': id};
    obKlicaju?.call(vrstica, true);
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
    if (api != null) _posljiVOzadju(api);
  }

  // ---------- Zvočni uvodi in playback ----------

  static String _kljucZvoka(VrstaZvoka v, String driveId) => '${v.kljuc}/$driveId';

  /// Zvoki, prebrani v tej seji (brez »Hrani lokalno« se ne shranijo na napravo).
  final _zvokiVSeji = <String, Uint8List>{};

  /// Zvok uvoda ali playbacka: z naprave, iz te seje ali s strežnika. Null, če ga pesem nima ali ni dostopen.
  Future<Uint8List?> zvok(Api? api, Pesem p, VrstaZvoka v) async {
    final id = p.zvok(v);
    if (id.isEmpty) return null;
    final vSeji = _zvokiVSeji[id];
    if (vSeji != null) return vSeji;
    final lokalno = await shramba.beriBajte(_kljucZvoka(v, id));
    if (lokalno != null) return _zvokiVSeji[id] = lokalno;
    if (api == null) return null;
    final bajti = await api.zvok(v.kaj, p.id);
    if (Nastavitve.aplikacija.hrani(v)) await shramba.pisiBajte(_kljucZvoka(v, id), bajti);
    return _zvokiVSeji[id] = bajti;
  }

  /// Prenese manjkajoče zvoke na napravo in pobriše tiste, ki jih ni več. Vrne število neuspelih.
  Future<int> prenesiZvoke(Api api, VrstaZvoka v) async {
    final preneseni = await shramba.kljuci('${v.kljuc}/');
    final zdaj = {
      for (final p in pesmi)
        if (p.zvok(v).isNotEmpty) _kljucZvoka(v, p.zvok(v)): p,
    };
    for (final k in preneseni.difference(zdaj.keys.toSet())) {
      await shramba.izbrisi(k);
    }
    var neuspeli = 0;
    for (final MapEntry(key: k, value: p) in zdaj.entries) {
      if (preneseni.contains(k)) continue;
      try {
        final bajti = _zvokiVSeji[p.zvok(v)] ?? await api.zvok(v.kaj, p.id);
        await shramba.pisiBajte(k, bajti);
      } catch (_) {
        neuspeli++;
      }
    }
    return neuspeli;
  }

  /// Pobriše zvoke z naprave (ko izklopiš »Hrani lokalno«).
  Future<void> izbrisiLokalneZvoke(VrstaZvoka v) async {
    for (final k in await shramba.kljuci('${v.kljuc}/')) {
      await shramba.izbrisi(k);
    }
  }

  /// Nov uvod ali playback pesmi (zamenja starega) ali brez [bajti] izbris. Potrebuje internet.
  Future<Pesem> shraniZvok(
    Api api,
    String pesem,
    VrstaZvoka v,
    Uint8List? bajti, {
    String vrsta = '',
    double od = 0,
    double? doo,
    bool posnet = false,
  }) async {
    final odg = await api.shraniZvok(v.kaj, pesem, bajti, vrsta: vrsta, od: od, doo: doo, posnet: posnet);
    final vrstica = (odg['vrstica'] as Map).cast<String, dynamic>();
    final id = besedilo(vrstica[v.stolpec]);
    if (bajti != null && id.isNotEmpty) {
      _zvokiVSeji[id] = bajti;
      if (Nastavitve.aplikacija.hrani(v)) await shramba.pisiBajte(_kljucZvoka(v, id), bajti);
    }
    await _zamenjajVrstico('Pesmi', vrstica);
    return Pesem.izVrstice(vrstica);
  }

  /// Odstranitev vokala (GitHub) ali vrnitev izvirnika playbacka.
  Future<Pesem> obdelajPlayback(Api api, String pesem, {required bool izvirnik}) async {
    final odg = izvirnik ? await api.vrniIzvirnik(pesem) : await api.odstraniVokal(pesem);
    final vrstica = (odg['vrstica'] as Map).cast<String, dynamic>();
    await _zamenjajVrstico('Pesmi', vrstica);
    return Pesem.izVrstice(vrstica);
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
    if (api != null) _posljiVOzadju(api);
    return p;
  }

  Future<void> _posljiPosnetek(Api api, Map<String, dynamic> n, Zapis podatki) async {
    final id = besedilo(podatki['ID']);
    if (n['izbrisi'] == true) {
      await api.izbrisiPosnetek(id);
      return;
    }
    if (n['ime'] == true) {
      final odg = await api.preimenujPosnetek(id, besedilo(podatki['Ime']));
      if (odg['vrstica'] case final Map v) await _zamenjajVrstico('Posnetki', v.cast<String, dynamic>());
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

  /// Nov naslov posnetka. Če posnetek še čaka na pošiljanje, se popravi kar tam.
  Future<void> preimenujPosnetek(Api? api, String id, String ime) async {
    final vrstica = {...?_vrstica('Posnetki', id), 'ID': id, 'Ime': ime};
    final caka = neposlano.where(
      (n) =>
          n['akcija'] == 'posnetek' &&
          n['izbrisi'] != true &&
          n['ime'] != true &&
          besedilo((n['podatki'] as Map)['ID']) == id,
    );
    if (caka.firstOrNull case final n?) {
      n['podatki'] = {...(n['podatki'] as Map).cast<String, dynamic>(), 'Ime': ime};
    } else {
      neposlano.add({
        'akcija': 'posnetek',
        'ime': true,
        'podatki': {'ID': id, 'Ime': ime},
      });
    }
    await _shraniNeposlano();
    await _zamenjajVrstico('Posnetki', vrstica);
    if (api != null) _posljiVOzadju(api);
  }

  /// Ali sme član izbrisati ali preimenovati posnetek (svojega; administrator vse).
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
    if (api != null) _posljiVOzadju(api);
  }

  /// Sporočilo, ko strežnik spremembe, poslane v ozadju, ne sprejme (pokaže ga aplikacija).
  void Function(String sporocilo)? obZavrnjenem;

  /// Zadnje pošiljanje v ozadju ni uspelo (ni interneta): spremembe čakajo na napravi.
  bool cakaPovezavo = false;

  Timer? _ponovnoPoslji;
  var _cakanje = const Duration(seconds: 15);

  /// Shranjevanje ne čaka na strežnik: spremembe gredo na napravo in se pošljejo v ozadju.
  /// Brez interneta poskusi znova (vse redkeje, najdlje na 5 minut).
  void _posljiVOzadju(Api api) {
    _ponovnoPoslji?.cancel();
    _ponovnoPoslji = null;
    unawaited(() async {
      String? sporocilo;
      try {
        sporocilo = await posljiNeposlano(api);
      } catch (_) {}
      if (sporocilo != null && sporocilo.startsWith(_zavrnil)) obZavrnjenem?.call(sporocilo);
      final caka = _cakaInternet;
      if (caka != cakaPovezavo) {
        cakaPovezavo = caka;
        notifyListeners();
      }
      if (!caka) {
        _cakanje = const Duration(seconds: 15);
      } else if (!_zaprta) {
        _ponovnoPoslji = Timer(_cakanje, () => _posljiVOzadju(api));
        _cakanje = _cakanje * 2 > const Duration(minutes: 5) ? const Duration(minutes: 5) : _cakanje * 2;
      }
    }());
  }

  /// Gumb ikone čakajočih sprememb: pošlji takoj (ne čakaj na naslednji poskus).
  void posljiZdaj(Api api) {
    _cakanje = const Duration(seconds: 15);
    _posljiVOzadju(api);
    risbe.posljiNeposlane().ignore();
    risbeSkupne.posljiNeposlane().ignore();
  }

  /// Vse spremembe na napravi, ki še niso na strežniku (pesmi, nastavitve, klicaji, risbe).
  int get steviloNeposlanih => neposlano.length + risbe.steviloNeposlanih + risbeSkupne.steviloNeposlanih;

  static const _zavrnil = 'Strežnik ni sprejel';
  var _zaprta = false;

  @override
  void dispose() {
    _zaprta = true;
    _ponovnoPoslji?.cancel();
    super.dispose();
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

  /// Več PDF-jev naenkrat (hitro urejanje).
  Future<void> izbrisiPdfje(Api api, List<PdfDatoteka> pdfji) async {
    final odg = await api.izbrisiPdfje([for (final p in pdfji) p.id]);
    final izbrisani = {for (final id in (odg['izbrisani'] as List? ?? const [])) id.toString()};
    await _zamenjajVrstice('PDF', odstrani: (r) => izbrisani.contains(besedilo(r['ID'])));
    for (final p in pdfji) {
      if (izbrisani.contains(p.id)) await shramba.izbrisi(_kljucPdf(p.driveId));
    }
    await shramba.pisiBesedilo(_kljucPodatkov, jsonEncode(_podatki));
    _uporabi(_podatki);
    notifyListeners();
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

  // ---------- Slike članov ----------

  static const _kljucSlik = 'slike_clanov.json';

  /// Sličice članov po ID-ju (za izbiro člana na iPadu).
  Map<String, Uint8List> slikeClanov = {};
  Map<String, dynamic> _slike = {};

  /// Za vodjo: sličice, kot jih da skripta (iPadi jih dobijo od vodje).
  String get slikeClanovJson => jsonEncode(_slike);

  /// Poti slik v podatkih članov (prazno = brez slike).
  Map<String, String> get _potiSlik => {
    for (final c in ((_podatki['tabele'] as Map?)?['Člani'] as List?) ?? const [])
      if (c is Map && besedilo(c['Slika']).isNotEmpty) besedilo(c['ID']): besedilo(c['Slika']),
  };

  void _uporabiSlike(Map<String, dynamic> s) {
    _slike = s;
    slikeClanov = {
      for (final e in s.entries)
        if (e.value is Map && (e.value as Map)['base64'] is String)
          e.key: base64Decode((e.value as Map)['base64'] as String),
    };
  }

  /// Prenese sličice članov, kadar se je kakšna slika spremenila.
  Future<void> osveziSlikeClanov(Api api) async {
    final poti = _potiSlik;
    final imamo = {for (final e in _slike.entries) e.key: besedilo((e.value as Map?)?['slika'])};
    if (mapEquals(poti, imamo)) return;
    if (poti.isEmpty) {
      _uporabiSlike({});
    } else {
      _uporabiSlike(await api.slikeClanov());
    }
    await shramba.pisiBesedilo(_kljucSlik, jsonEncode(_slike));
    notifyListeners();
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

  /// Besedilo se shrani takoj na napravo (novo dobi začasen ID) in pošlje v ozadju.
  Future<void> shraniBesedilo(Api api, Zapis podatki) async {
    var id = besedilo(podatki['ID']);
    // Zaslon ima lahko še začasen ID besedila, ki je medtem že prišlo na strežnik.
    id = _praviId[id] ?? id;
    if (id.isEmpty) id = '$_zacasni${DateTime.now().microsecondsSinceEpoch}';
    final zapis = {...podatki, 'ID': id};
    await _dodajNeposlano('besedilo', zapis);
    if (besedilo(podatki['Besedilo']).isEmpty) {
      await _zamenjajVrstico('Besedila', null, izbrisi: id);
    } else {
      await _zamenjajVrstico('Besedila', {...?_vrstica('Besedila', id), ...zapis});
    }
    _posljiVOzadju(api);
  }

  /// Začasni ID besedila → ID, ki ga je dal strežnik.
  final _praviId = <String, String>{};

  /// Shrani (ali izbriše) ukaz, makro, gumb, ime kanala ali harmoniko. Kanali imajo za ID številko kanala.
  /// Mapa v drugo zasedbo ([ukaz] premakni ali kopiraj), izpraznitev ali izbris (pesmi v Arhiv ali [trajno]).
  /// Spremeni veliko vrstic, zato nato osveži vse podatke.
  Future<void> mapaUkaz(Api api, String ukaz, String mapa, {String? zasedba, bool trajno = false}) async {
    if (_cakaInternet) await posljiNeposlano(api);
    await api.mapaUkaz(ukaz, mapa, zasedba: zasedba, trajno: trajno);
    await osvezi(api);
  }

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
