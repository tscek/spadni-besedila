/// Vrstica iz preglednice Besedila baza, kot jo vrne skripta (ključ = ime stolpca).
typedef Zapis = Map<String, dynamic>;

String besedilo(dynamic v) {
  if (v == null) return '';
  if (v is double && v == v.truncateToDouble()) return v.toInt().toString();
  return v.toString().trim();
}

bool daNe(dynamic v) => v == true || besedilo(v).toUpperCase() == 'TRUE';

class Pesem {
  Pesem({
    required this.id,
    required this.koda,
    required this.naslov,
    this.izvajalec = '',
    this.avtorGlasbe = '',
    this.avtorBesedila = '',
    this.zvrst = '',
    this.vrsta = '',
    this.tonaliteta = '',
    this.midiObOdprtju = '',
    this.makro = '',
    this.aktivna = true,
    this.skupine = const [],
    this.vrstica = const {},
    this.mapa = '',
    this.status = StatusPesmi.narejen,
    this.harmonika = '',
    this.midiZaUvod = '',
    this.zaVajo = false,
    this.ocena = 0,
  });

  factory Pesem.izVrstice(Zapis r) => Pesem(
    id: besedilo(r['ID']),
    koda: besedilo(r['Koda']),
    naslov: besedilo(r['Naslov']),
    izvajalec: besedilo(r['Izvajalec']),
    avtorGlasbe: besedilo(r['Avtor glasbe']),
    avtorBesedila: besedilo(r['Avtor besedila']),
    zvrst: besedilo(r['Zvrst']),
    vrsta: besedilo(r['Vrsta']),
    tonaliteta: besedilo(r['Tonaliteta']),
    midiObOdprtju: besedilo(r['MIDI ob odprtju']),
    makro: besedilo(r['Makro ob odprtju']),
    aktivna: r['Aktivna'] == null || r['Aktivna'] == '' || daNe(r['Aktivna']),
    skupine: besedilo(r['Skupine']).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
    vrstica: r,
    mapa: besedilo(r['Mapa']),
    status: StatusPesmi.iz(besedilo(r['Status'])),
    harmonika: besedilo(r['Harmonika']),
    midiZaUvod: besedilo(r['MIDI za uvod']),
    zaVajo: daNe(r['Za vajo']),
    ocena: (int.tryParse(besedilo(r['Ocena'])) ?? 0).clamp(0, 5),
  );

  final String id;
  final String koda;
  final String naslov;
  final String izvajalec;
  final String avtorGlasbe;
  final String avtorBesedila;
  final String zvrst;
  final String vrsta;
  final String tonaliteta;
  final String midiObOdprtju;
  final String makro;
  final bool aktivna;
  final List<String> skupine;

  /// ID mape (list Mape), npr. nz za narodno-zabavne.
  final String mapa;
  final StatusPesmi status;
  final String harmonika;

  /// MIDI ukaz za uvod (npr. »PC 1 23«), neposredno zapisan, brez imena iz knjižnice.
  final String midiZaUvod;

  /// Rdeč klicaj: pesem je treba ponoviti na vaji.
  final bool zaVajo;

  /// Ocena 1 do 5 (0 = brez).
  final int ocena;

  /// Arhivirana pesem ni vidna v mapah in iskalnikih (samo v arhivu).
  bool get vArhivu => status == StatusPesmi.arhiv;

  /// Celotna vrstica iz lista Pesmi, za urejanje stolpcev, ki jih prikaz ne potrebuje.
  final Zapis vrstica;

  int get kodaStevilka => int.tryParse(koda) ?? 1 << 30;

  /// Iskanje po kodi, naslovu ali izvajalcu, brez razlike med velikimi in malimi črkami ter šumniki.
  bool ustreza(String iskanje) {
    final q = poenostavi(iskanje);
    if (q.isEmpty) return true;
    return koda.startsWith(q) || poenostavi(naslov).contains(q) || poenostavi(izvajalec).contains(q);
  }
}

enum StatusPesmi {
  predlog('Predlog'),
  vDelu('V delu'),
  narejen('Narejen'),
  arhiv('Arhiv');

  const StatusPesmi(this.ime);
  final String ime;

  /// Iz stolpca Status; prazno (starejše pesmi) pomeni narejeno.
  static StatusPesmi iz(String s) => values.where((v) => v.ime.toLowerCase() == s.toLowerCase()).firstOrNull ?? narejen;
}

/// Tonalitete, kot jih pišemo: dur z veliko, mol z malo začetnico (As in Es, ne Ab in Eb).
const tonalitete = [
  'C', 'Cis', 'Des', 'D', 'Es', 'E', 'F', 'Fis', 'G', 'As', 'A', 'B', 'H', //
  'c', 'cis', 'd', 'dis', 'es', 'e', 'f', 'fis', 'g', 'gis', 'as', 'a', 'b', 'h',
];

/// Podatek pesmi za prikaz v vrstici seznama, za razvrščanje in v čakalni vrsti.
enum PoljePesmi {
  koda('Koda'),
  naslov('Naslov'),
  izvajalec('Izvajalec'),
  avtorGlasbe('Avtor glasbe'),
  avtorBesedila('Avtor besedila'),
  vrsta('Vrsta'),
  tonaliteta('Tonaliteta'),
  harmonika('Harmonika'),
  tempo('Tempo (BPM)'),
  trajanje('Trajanje'),
  ocena('Ocena'),
  status('Status'),
  oznaka('Oznaka'),
  spremenjeno('Spremenjeno');

  const PoljePesmi(this.ime);

  /// Ime je tudi ime stolpca na listu Pesmi.
  final String ime;

  String vrednost(Pesem p) => switch (this) {
    koda => p.koda,
    naslov => p.naslov,
    izvajalec => p.izvajalec,
    avtorGlasbe => p.avtorGlasbe,
    avtorBesedila => p.avtorBesedila,
    vrsta => p.vrsta,
    tonaliteta => p.tonaliteta,
    harmonika => p.harmonika,
    status => p.status.ime,
    ocena => p.ocena == 0 ? '' : '★' * p.ocena,
    _ => besedilo(p.vrstica[ime]),
  };

  /// Primerjava za razvrščanje; prazne vrednosti so vedno na koncu.
  int primerjaj(Pesem a, Pesem b) {
    switch (this) {
      case koda:
        return a.kodaStevilka.compareTo(b.kodaStevilka);
      case ocena:
        return a.ocena.compareTo(b.ocena);
      case status:
        return a.status.index.compareTo(b.status.index);
      case tempo:
        return (num.tryParse(vrednost(a)) ?? 1 << 30).compareTo(num.tryParse(vrednost(b)) ?? 1 << 30);
      case tonaliteta:
        int i(Pesem p) => switch (tonalitete.indexOf(p.tonaliteta)) {
          -1 => p.tonaliteta.isEmpty ? 1 << 30 : 1 << 29,
          final x => x,
        };
        return i(a).compareTo(i(b));
      default:
        final x = poenostavi(vrednost(a));
        final y = poenostavi(vrednost(b));
        if (x.isEmpty != y.isEmpty) return x.isEmpty ? 1 : -1;
        return x.compareTo(y);
    }
  }
}

/// Mapa pesmi (list Mape), npr. Narodno-zabavne ali Vaje zabavne.
class Mapa {
  Mapa({required this.id, required this.ime, this.vrstniRed = 0});

  factory Mapa.izVrstice(Zapis r) =>
      Mapa(id: besedilo(r['ID']), ime: besedilo(r['Ime']), vrstniRed: int.tryParse(besedilo(r['Vrstni red'])) ?? 0);

  final String id;
  final String ime;
  final int vrstniRed;
}

/// Harmonika z barvo (list Harmonike).
class Harmonika {
  Harmonika({required this.id, required this.ime, this.barva = '', this.vrstniRed = 0});

  factory Harmonika.izVrstice(Zapis r) => Harmonika(
    id: besedilo(r['ID']),
    ime: besedilo(r['Ime']),
    barva: besedilo(r['Barva']),
    vrstniRed: int.tryParse(besedilo(r['Vrstni red'])) ?? 0,
  );

  final String id;
  final String ime;

  /// Barva kot #RRGGBB.
  final String barva;
  final int vrstniRed;

  /// Barva kot 0xAARRGGBB ali null, če ni nastavljena.
  int? get argb {
    final h = barva.replaceFirst('#', '');
    final v = int.tryParse(h, radix: 16);
    return v == null || h.length != 6 ? null : 0xFF000000 | v;
  }
}

class PdfDatoteka {
  PdfDatoteka({
    required this.id,
    required this.pesem,
    required this.vrsta,
    required this.driveId,
    this.vrstniRed = 1,
    this.imeDatoteke = '',
  });

  factory PdfDatoteka.izVrstice(Zapis r) => PdfDatoteka(
    id: besedilo(r['ID']),
    pesem: besedilo(r['Pesem']),
    vrsta: besedilo(r['Vrsta']),
    driveId: besedilo(r['Drive ID']),
    vrstniRed: int.tryParse(besedilo(r['Vrstni red'])) ?? 1,
    imeDatoteke: besedilo(r['Ime datoteke']),
  );

  final String id;
  final String pesem;
  final String vrsta;
  final String driveId;
  final int vrstniRed;
  final String imeDatoteke;
}

class BesediloPesmi {
  BesediloPesmi({required this.id, required this.pesem, required this.vrsta, required this.vsebina, this.opombe = ''});

  factory BesediloPesmi.izVrstice(Zapis r) => BesediloPesmi(
    id: besedilo(r['ID']),
    pesem: besedilo(r['Pesem']),
    vrsta: besedilo(r['Vrsta']),
    vsebina: r['Besedilo']?.toString() ?? '',
    opombe: besedilo(r['Opombe']),
  );

  static const vrste = ['Besedilo z akordi', 'Besedilo'];

  final String id;
  final String pesem;
  final String vrsta;
  final String vsebina;
  final String opombe;
}

class Setlista {
  Setlista({
    required this.id,
    required this.skupina,
    required this.ime,
    this.datum,
    this.nastop = '',
    this.opombe = '',
    this.mapa = '',
  });

  factory Setlista.izVrstice(Zapis r) => Setlista(
    id: besedilo(r['ID']),
    skupina: besedilo(r['Skupina']),
    ime: besedilo(r['Ime']),
    datum: datumIz(r['Datum']),
    nastop: besedilo(r['Nastop']),
    opombe: besedilo(r['Opombe']),
    mapa: besedilo(r['Mapa']),
  );

  final String id;
  final String skupina;

  /// Mapa, v kateri je playlista (prazno: vidna samo pod »Vse«).
  final String mapa;
  final String ime;
  final DateTime? datum;
  final String nastop;
  final String opombe;
}

class SetlistaPesem {
  SetlistaPesem({required this.setlista, required this.zaporedje, required this.pesem, this.opomba = ''});

  factory SetlistaPesem.izVrstice(Zapis r) => SetlistaPesem(
    setlista: besedilo(r['Setlista']),
    zaporedje: int.tryParse(besedilo(r['Zaporedje'])) ?? 0,
    pesem: besedilo(r['Pesem']),
    opomba: besedilo(r['Opomba']),
  );

  final String setlista;
  final int zaporedje;
  final String pesem;
  final String opomba;
}

/// Datum iz preglednice: ISO čas (datumska celica, v UTC) ali besedilo `yyyy-MM-dd`. Vrne lokalni dan.
DateTime? datumIz(dynamic v) {
  final s = besedilo(v);
  if (s.isEmpty) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  final l = d.isUtc ? d.toLocal() : d;
  return DateTime(l.year, l.month, l.day);
}

String datumBesedilo(DateTime d) => '${d.day}. ${d.month}. ${d.year}';

String datumIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Skupina {
  Skupina({required this.id, required this.ime});

  factory Skupina.izVrstice(Zapis r) => Skupina(id: besedilo(r['ID']), ime: besedilo(r['Ime']));

  final String id;
  final String ime;
}

class Vloga {
  Vloga({required this.skupina, required this.vloga, required this.smeVoditi});

  factory Vloga.izVrstice(Zapis r) =>
      Vloga(skupina: besedilo(r['Skupina']), vloga: besedilo(r['Vloga']), smeVoditi: daNe(r['Sme voditi']));

  final String skupina;
  final String vloga;
  final bool smeVoditi;
}

String poenostavi(String s) {
  const zamenjave = {'č': 'c', 'š': 's', 'ž': 'z', 'ć': 'c', 'đ': 'd'};
  final mala = s.toLowerCase().trim();
  final b = StringBuffer();
  for (final ch in mala.split('')) {
    b.write(zamenjave[ch] ?? ch);
  }
  return b.toString();
}
