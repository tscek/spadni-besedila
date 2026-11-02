import 'dart:convert';

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
    this.klicaji = 0,
    this.ocena = 0,
    this.pisava = 22,
  });

  /// [klicaji] je število klicajev pesmi (list Klicaji).
  factory Pesem.izVrstice(Zapis r, {int klicaji = 0}) => Pesem(
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
    klicaji: klicaji,
    ocena: (int.tryParse(besedilo(r['Ocena'])) ?? 0).clamp(0, 5),
    pisava: (double.tryParse(besedilo(r['Pisava']).replaceAll(',', '.')) ?? 22).clamp(12, 64).toDouble(),
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

  /// Število rdečih klicajev (mesta, ki jih je treba ponoviti na vaji).
  final int klicaji;

  bool get zaVajo => klicaji > 0;

  /// Ocena 1 do 5 (0 = brez).
  final int ocena;

  /// Velikost pisave besedila na strani (skupna vsem, nastavi jo urednik).
  final double pisava;

  /// Arhivirana pesem ni vidna v mapah in iskalnikih (samo v arhivu).
  bool get vArhivu => status == StatusPesmi.arhiv;

  /// Celotna vrstica iz lista Pesmi, za urejanje stolpcev, ki jih prikaz ne potrebuje.
  final Zapis vrstica;

  int get kodaStevilka => int.tryParse(koda) ?? 1 << 30;

  /// Iskanje po naslovu ali izvajalcu, brez razlike med velikimi in malimi črkami ter šumniki.
  bool ustreza(String iskanje) {
    final q = poenostavi(iskanje);
    if (q.isEmpty) return true;
    return poenostavi(naslov).contains(q) || poenostavi(izvajalec).contains(q);
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
  Mapa({
    required this.id,
    required this.ime,
    this.vrstniRed = 0,
    this.pavza = '',
    this.opis = '',
    this.barva = '',
    this.ikona = '',
  });

  factory Mapa.izVrstice(Zapis r) => Mapa(
    id: besedilo(r['ID']),
    ime: besedilo(r['Ime']),
    vrstniRed: int.tryParse(besedilo(r['Vrstni red'])) ?? 0,
    pavza: besedilo(r['Pavza']),
    opis: besedilo(r['Opis']),
    barva: besedilo(r['Barva']),
    ikona: besedilo(r['Ikona']),
  );

  final String id;
  final String ime;
  final int vrstniRed;

  /// ID pesmi, ki se odpre z izbiro »Pavza« v iskalniku.
  final String pavza;
  final String opis;

  /// Barva kot #RRGGBB (prazno: barva teme).
  final String barva;

  /// Ime ikone (glej ikoneMap v zaslonu map).
  final String ikona;

  /// Barva kot 0xAARRGGBB ali null, če ni nastavljena.
  int? get argb {
    final h = barva.replaceFirst('#', '');
    final v = int.tryParse(h, radix: 16);
    return v == null || h.length != 6 ? null : 0xFF000000 | v;
  }

  Zapis vVrstico() => {
    if (id.isNotEmpty) 'ID': id,
    'Ime': ime,
    'Vrstni red': vrstniRed,
    'Pavza': pavza,
    'Opis': opis,
    'Barva': barva,
    'Ikona': ikona,
  };
}

/// Barva 0xAARRGGBB kot #RRGGBB (null: prazno).
String hexBarva(int? argb) =>
    argb == null ? '' : '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Klicaj na mestu v besedilu (stran 0) ali na strani PDF-ja; x in y sta relativna kot pri risbah.
class KlicajPesmi {
  KlicajPesmi({
    required this.id,
    required this.pesem,
    required this.stran,
    required this.x,
    required this.y,
    this.clan = '',
    this.cas,
  });

  factory KlicajPesmi.izVrstice(Zapis r) => KlicajPesmi(
    id: besedilo(r['ID']),
    pesem: besedilo(r['Pesem']),
    stran: int.tryParse(besedilo(r['Stran'])) ?? 0,
    x: double.tryParse(besedilo(r['X']).replaceAll(',', '.')) ?? 0,
    y: double.tryParse(besedilo(r['Y']).replaceAll(',', '.')) ?? 0,
    clan: besedilo(r['Član']),
    cas: DateTime.tryParse(besedilo(r['Čas']))?.toLocal(),
  );

  final String id;
  final String pesem;
  final int stran;
  final double x;
  final double y;

  /// ID člana, ki je klicaj dodal.
  final String clan;
  final DateTime? cas;

  Zapis vVrstico() => {
    'ID': id,
    'Pesem': pesem,
    'Stran': stran,
    'X': x,
    'Y': y,
    'Član': clan,
    'Čas': (cas ?? DateTime.now()).toUtc().toIso8601String(),
  };
}

/// Ime z barvo (list Harmonike, enako list Vrste).
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

/// Zvočni posnetek pesmi (list Posnetki): osebni ali skupni za vse.
class PosnetekPesmi {
  PosnetekPesmi({
    required this.id,
    required this.pesem,
    this.clan = '',
    this.skupno = false,
    this.ime = '',
    this.vrsta = 'audio/mp4',
    this.trajanje = 0,
    this.velikostKb = 0,
    this.driveId = '',
    this.cas,
  });

  factory PosnetekPesmi.izVrstice(Zapis r) => PosnetekPesmi(
    id: besedilo(r['ID']),
    pesem: besedilo(r['Pesem']),
    clan: besedilo(r['Član']),
    skupno: daNe(r['Skupno']),
    ime: besedilo(r['Ime']),
    vrsta: besedilo(r['Vrsta']).isEmpty ? 'audio/mp4' : besedilo(r['Vrsta']),
    trajanje: int.tryParse(besedilo(r['Trajanje (s)'])) ?? 0,
    velikostKb: int.tryParse(besedilo(r['Velikost (KB)'])) ?? 0,
    driveId: besedilo(r['Drive ID']),
    cas: DateTime.tryParse(besedilo(r['Čas']))?.toLocal(),
  );

  final String id;
  final String pesem;

  /// ID člana, ki je posnel.
  final String clan;
  final bool skupno;
  final String ime;

  /// MIME vrsta zvoka (audio/mp4 = AAC, audio/webm = Opus iz brskalnika).
  final String vrsta;

  /// Dolžina v sekundah.
  final int trajanje;
  final int velikostKb;

  /// Prazno, dokler posnetek ni na strežniku.
  final String driveId;
  final DateTime? cas;

  Zapis vVrstico() => {
    'ID': id,
    'Pesem': pesem,
    'Član': clan,
    'Skupno': skupno,
    'Ime': ime,
    'Vrsta': vrsta,
    'Trajanje (s)': trajanje,
    'Velikost (KB)': velikostKb,
    'Drive ID': driveId,
    'Čas': cas?.toUtc().toIso8601String() ?? '',
  };
}

/// Kos posnetka špila: zaporedna številka, začetek (prava ura) in dolžina.
typedef KosSnemanja = ({int i, DateTime zacetek, int sekund});

/// Posneti špil (list Snemanja): naslov (nastop ali datum), stanje in video na YouTubu.
class Snemanje {
  Snemanje({
    required this.id,
    required this.naslov,
    this.nastop = '',
    this.zasedba = '',
    this.zacetek,
    this.konec,
    this.naprava = '',
    this.stanje = '',
    this.youtube = '',
    this.kosi = const [],
  });

  factory Snemanje.izVrstice(Zapis r) {
    var kosi = <KosSnemanja>[];
    try {
      final j = jsonDecode(besedilo(r['Kosi']).isEmpty ? '[]' : besedilo(r['Kosi'])) as List;
      kosi = [
        for (final k in j.whereType<Map>())
          if (DateTime.tryParse(k['z']?.toString() ?? '') case final z?)
            (i: (k['i'] as num).toInt(), zacetek: z, sekund: (k['t'] as num? ?? 0).toInt()),
      ]..sort((a, b) => a.i.compareTo(b.i));
    } catch (_) {}
    return Snemanje(
      id: besedilo(r['ID']),
      naslov: besedilo(r['Naslov']),
      nastop: besedilo(r['Nastop']),
      zasedba: besedilo(r['Zasedba']),
      zacetek: DateTime.tryParse(besedilo(r['Začetek'])),
      konec: DateTime.tryParse(besedilo(r['Konec'])),
      naprava: besedilo(r['Naprava']),
      stanje: besedilo(r['Stanje']),
      youtube: besedilo(r['YouTube ID']),
      kosi: kosi,
    );
  }

  final String id;
  final String naslov;
  final String nastop;
  final String zasedba;
  final DateTime? zacetek;
  final DateTime? konec;
  final String naprava;
  final String stanje;

  /// ID videa na YouTubu (ko je video narejen).
  final String youtube;
  final List<KosSnemanja> kosi;

  /// Ali je trenutek [t] znotraj tega snemanja (od začetka do konca, z nekaj minutami rezerve).
  bool vsebuje(DateTime t) {
    final z = zacetek;
    if (z == null || t.isBefore(z.subtract(const Duration(minutes: 1)))) return false;
    final k = konec ?? (kosi.isEmpty ? null : kosi.last.zacetek.add(Duration(seconds: kosi.last.sekund)));
    return k == null || !t.isAfter(k.add(const Duration(minutes: 1)));
  }

  /// Mesto v videu (sekunde), kjer je trenutek [t]: pavze so izpuščene, zato se šteje po kosih.
  int? odmik(DateTime t) {
    var pred = 0;
    for (final k in kosi) {
      final od = t.difference(k.zacetek).inSeconds;
      if (od < 0) return pred; // v pavzi pred tem kosom: začetek kosa
      if (od <= k.sekund) return pred + od;
      pred += k.sekund;
    }
    return kosi.isEmpty ? null : pred;
  }

  /// Povezava na YouTube na mestu [t] (ali na začetek videa).
  String? povezava([DateTime? t]) {
    if (youtube.isEmpty) return null;
    final s = t == null ? null : odmik(t);
    return 'https://youtu.be/$youtube${s == null || s == 0 ? '' : '?t=$s'}';
  }
}

/// Igranje pesmi na špilu (iz dnevnika vodje in sledilcev).
typedef Igranje = ({String pesem, DateTime cas, int sekund});
