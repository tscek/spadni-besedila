import '../models.dart';

/// Izhod, na katerega gre ukaz, ki nima izbranega svojega (vsaka naprava ga preslika na pravo MIDI napravo).
const privzetiIzhod = 'Privzeti';

enum VrstaUkaza {
  pc('PC'),
  cc('CC'),
  nota('Nota');

  const VrstaUkaza(this.oznaka);
  final String oznaka;

  static VrstaUkaza? iz(String s) {
    final m = s.trim().toUpperCase();
    for (final v in values) {
      if (v.oznaka.toUpperCase() == m) return v;
    }
    return null;
  }
}

/// En MIDI ukaz: Program Change, Control Change ali nota. Kanal je 1–16 (kot na napravah).
class MidiUkaz {
  MidiUkaz({
    this.id = '',
    this.skupina = '',
    this.ime = '',
    required this.vrsta,
    required this.kanal,
    required this.stevilka,
    this.vrednost = 127,
    this.izhod = '',
    this.opombe = '',
  });

  factory MidiUkaz.izVrstice(Zapis r) => MidiUkaz(
    id: besedilo(r['ID']),
    skupina: besedilo(r['Skupina']),
    ime: besedilo(r['Ime']),
    vrsta: VrstaUkaza.iz(besedilo(r['Vrsta'])) ?? VrstaUkaza.cc,
    kanal: _stevilo(r['Kanal'], 1).clamp(1, 16),
    stevilka: _stevilo(r['Številka'], 0).clamp(0, 127),
    vrednost: _stevilo(r['Vrednost'], 127).clamp(0, 127),
    izhod: besedilo(r['Izhod']),
    opombe: besedilo(r['Opombe']),
  );

  final String id;
  final String skupina;
  final String ime;
  final VrstaUkaza vrsta;
  final int kanal;
  final int stevilka;
  final int vrednost;
  final String izhod;
  final String opombe;

  Zapis vVrstico() => {
    if (id.isNotEmpty) 'ID': id,
    'Skupina': skupina,
    'Ime': ime,
    'Vrsta': vrsta.oznaka,
    'Kanal': kanal,
    'Številka': stevilka,
    'Vrednost': vrsta == VrstaUkaza.pc ? '' : vrednost,
    'Izhod': izhod,
    'Opombe': opombe,
  };

  /// Bajti za pošiljanje (nota: samo Note On; Note Off pošlje pošiljatelj malo kasneje).
  List<int> get bajti {
    final k = kanal - 1;
    return switch (vrsta) {
      VrstaUkaza.pc => [0xC0 | k, stevilka],
      VrstaUkaza.cc => [0xB0 | k, stevilka, vrednost],
      VrstaUkaza.nota => [0x90 | k, stevilka, vrednost],
    };
  }

  List<int>? get bajtiKonca => vrsta == VrstaUkaza.nota && vrednost > 0 ? [0x80 | (kanal - 1), stevilka, 0] : null;

  /// Kratek zapis, ki ga razume [razcleniUkaz], npr. "CC 9 12 127".
  String get zapis => switch (vrsta) {
    VrstaUkaza.pc => 'PC $kanal $stevilka',
    _ => '${vrsta.oznaka} $kanal $stevilka $vrednost',
  };

  /// Berljiv opis za zaslon; [imeKanala] doda ime naprave na kanalu.
  String opis([String imeKanala = '']) {
    final k = imeKanala.isEmpty ? 'kanal $kanal' : 'kanal $kanal ($imeKanala)';
    return switch (vrsta) {
      VrstaUkaza.pc => 'PC · $k · program $stevilka',
      VrstaUkaza.cc => 'CC · $k · kontroler $stevilka = $vrednost',
      VrstaUkaza.nota => 'Nota · $k · nota $stevilka, hitrost $vrednost',
    };
  }

  MidiUkaz kopija({String? ime, String? izhod}) => MidiUkaz(
    id: id,
    skupina: skupina,
    ime: ime ?? this.ime,
    vrsta: vrsta,
    kanal: kanal,
    stevilka: stevilka,
    vrednost: vrednost,
    izhod: izhod ?? this.izhod,
    opombe: opombe,
  );
}

/// Makro: zaporedje ukazov in drugih makrov (po imenih).
class Makro {
  Makro({this.id = '', this.skupina = '', required this.ime, required this.koraki, this.izhod = ''});

  factory Makro.izVrstice(Zapis r) => Makro(
    id: besedilo(r['ID']),
    skupina: besedilo(r['Skupina']),
    ime: besedilo(r['Ime']),
    koraki: razdeliZapis(besedilo(r['Ukazi'])),
    izhod: besedilo(r['Izhod']),
  );

  final String id;
  final String skupina;
  final String ime;
  final List<String> koraki;
  final String izhod;

  Zapis vVrstico() => {
    if (id.isNotEmpty) 'ID': id,
    'Skupina': skupina,
    'Ime': ime,
    'Ukazi': koraki.join('; '),
    'Izhod': izhod,
  };
}

/// Ukaz, pripravljen za pošiljanje, z izhodom, na katerega gre.
class PoslaniUkaz {
  const PoslaniUkaz(this.ukaz, this.izhod);
  final MidiUkaz ukaz;
  final String izhod;
}

List<String> razdeliZapis(String s) => [
  for (final d in s.split(';'))
    if (d.trim().isNotEmpty) d.trim(),
];

/// Ukaz, zapisan neposredno: "CC 9 12 127", "PC 7 1", "Nota 10 20 1" ali po SongBooku "3|7|9|12|127".
/// Vrne null, če zapis ni ukaz (torej je ime ukaza ali makra).
MidiUkaz? razcleniUkaz(String t) {
  final s = t.trim();
  if (s.startsWith('3|')) {
    final d = s.split('|');
    if (d.length < 4) return null;
    final vrsta = switch (d[1]) {
      '7' => VrstaUkaza.cc,
      '5' => VrstaUkaza.pc,
      '4' => VrstaUkaza.nota,
      _ => null,
    };
    if (vrsta == null) return null;
    final kanal = int.tryParse(d[2]);
    final st = int.tryParse(d[3]);
    if (kanal == null || st == null) return null;
    return MidiUkaz(
      vrsta: vrsta,
      kanal: kanal.clamp(1, 16),
      stevilka: st.clamp(0, 127),
      vrednost: (d.length > 4 ? int.tryParse(d[4]) ?? 127 : 127).clamp(0, 127),
    );
  }
  final d = s.split(RegExp(r'\s+'));
  final vrsta = VrstaUkaza.iz(d.first);
  if (vrsta == null || d.length < 3) return null;
  final kanal = int.tryParse(d[1]);
  final st = int.tryParse(d[2]);
  if (kanal == null || st == null) return null;
  return MidiUkaz(
    vrsta: vrsta,
    kanal: kanal.clamp(1, 16),
    stevilka: st.clamp(0, 127),
    vrednost: (d.length > 3 ? int.tryParse(d[3]) ?? 127 : 127).clamp(0, 127),
  );
}

/// Vsi ukazi, makri in imena kanalov zasedbe.
class KnjiznicaMidi {
  KnjiznicaMidi({this.ukazi = const [], this.makri = const [], this.kanali = const {}});

  factory KnjiznicaMidi.izTabel(Map<String, dynamic> tabele) {
    List<Zapis> t(String ime) => ((tabele[ime] as List?) ?? []).cast<Map<String, dynamic>>();
    return KnjiznicaMidi(
      ukazi: [
        for (final r in t('MIDI ukazi'))
          if (besedilo(r['Ime']).isNotEmpty) MidiUkaz.izVrstice(r),
      ]..sort((a, b) => a.ime.toLowerCase().compareTo(b.ime.toLowerCase())),
      makri: [
        // Stari zapis Makrov (brez ID) ima ukaze po SongBooku; tudi te razumemo.
        for (final r in t('Makri'))
          if (besedilo(r['Ime']).isNotEmpty) Makro.izVrstice(r),
      ]..sort((a, b) => a.ime.toLowerCase().compareTo(b.ime.toLowerCase())),
      kanali: {
        for (final r in t('MIDI kanali'))
          if (int.tryParse(besedilo(r['Kanal'])) case final k? when besedilo(r['Ime']).isNotEmpty)
            k: besedilo(r['Ime']),
      },
    );
  }

  final List<MidiUkaz> ukazi;
  final List<Makro> makri;
  final Map<int, String> kanali;

  String imeKanala(int kanal) => kanali[kanal] ?? '';

  MidiUkaz? ukaz(String ime) => _najdi(ukazi, ime, (u) => u.ime);
  Makro? makro(String ime) => _najdi(makri, ime, (m) => m.ime);

  static T? _najdi<T>(List<T> s, String ime, String Function(T) imeOd) {
    final i = ime.trim();
    return s.where((x) => imeOd(x) == i).firstOrNull ??
        s.where((x) => imeOd(x).toLowerCase() == i.toLowerCase()).firstOrNull;
  }

  /// Vsa imena, ki jih lahko uporabiš v makru ali pri pesmi.
  List<String> get imena =>
      {...makri.map((m) => m.ime), ...ukazi.map((u) => u.ime)}.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// Vsi izhodi, ki jih uporabljajo ukazi in makri (vsaka naprava jih preslika na svoje MIDI naprave).
  List<String> get izhodi => {
    privzetiIzhod,
    ...ukazi.map((u) => u.izhod).where((i) => i.isNotEmpty),
    ...makri.map((m) => m.izhod).where((i) => i.isNotEmpty),
  }.toList();

  /// Razširi zapis (imena in ukaze, ločene s ;) v zaporedje ukazov za pošiljanje.
  /// Ukaz s svojim izhodom gre tja, sicer na izhod makra, sicer na privzetega.
  List<PoslaniUkaz> razsiri(String zapis, {String izhod = ''}) {
    final out = <PoslaniUkaz>[];
    // Makri, ki se trenutno razširjajo: makro, ki kliče samega sebe (tudi posredno), se preskoči.
    final aktivni = <String>{};
    void dodaj(String korak, String podedovan) {
      final s = korak.trim();
      if (s.startsWith('3|10|')) {
        dodaj(s.substring(5), podedovan);
        return;
      }
      final neposredni = razcleniUkaz(s);
      if (neposredni != null) {
        out.add(PoslaniUkaz(neposredni, podedovan.isEmpty ? privzetiIzhod : podedovan));
        return;
      }
      final m = makro(s);
      if (m != null) {
        if (!aktivni.add(m.ime)) return;
        for (final k in m.koraki) {
          dodaj(k, m.izhod.isNotEmpty ? m.izhod : podedovan);
        }
        aktivni.remove(m.ime);
        return;
      }
      final u = ukaz(s);
      if (u != null) {
        out.add(PoslaniUkaz(u, u.izhod.isNotEmpty ? u.izhod : (podedovan.isEmpty ? privzetiIzhod : podedovan)));
      }
    }

    for (final k in razdeliZapis(zapis)) {
      dodaj(k, izhod);
    }
    return out;
  }

  /// Ukazi ob odprtju pesmi: najprej ukaz pesmi (MIDI ob odprtju), nato makro ob odprtju.
  List<PoslaniUkaz> obOdprtju(Pesem p) =>
      razsiri('${besedilo(p.vrstica['MIDI ob odprtju'])}; ${besedilo(p.vrstica['Makro ob odprtju'])}');

  List<PoslaniUkaz> obZaprtju(Pesem p) => razsiri(besedilo(p.vrstica['Makro ob zaprtju']));
}

int _stevilo(dynamic v, int privzeto) =>
    v is num ? v.toInt() : int.tryParse(besedilo(v)) ?? double.tryParse(besedilo(v))?.toInt() ?? privzeto;
