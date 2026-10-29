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

class PdfDatoteka {
  PdfDatoteka({required this.id, required this.pesem, required this.vrsta, required this.driveId, this.vrstniRed = 1});

  factory PdfDatoteka.izVrstice(Zapis r) => PdfDatoteka(
    id: besedilo(r['ID']),
    pesem: besedilo(r['Pesem']),
    vrsta: besedilo(r['Vrsta']),
    driveId: besedilo(r['Drive ID']),
    vrstniRed: int.tryParse(besedilo(r['Vrstni red'])) ?? 1,
  );

  final String id;
  final String pesem;
  final String vrsta;
  final String driveId;
  final int vrstniRed;
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
  });

  factory Setlista.izVrstice(Zapis r) => Setlista(
    id: besedilo(r['ID']),
    skupina: besedilo(r['Skupina']),
    ime: besedilo(r['Ime']),
    datum: datumIz(r['Datum']),
    nastop: besedilo(r['Nastop']),
    opombe: besedilo(r['Opombe']),
  );

  final String id;
  final String skupina;
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
