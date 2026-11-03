import '../models.dart';

/// Kaj pošilja naprava v tempu pesmi.
enum NacinTakta {
  izklop('Izklopljeno'),
  clock('MIDI clock (24 na dobo)'),
  ukaz('Ukaz na dobo');

  const NacinTakta(this.ime);
  final String ime;
}

/// Nastavitve takta na tej napravi.
class NastavitveTakta {
  const NastavitveTakta({
    this.nacin = NacinTakta.izklop,
    this.ukaz = '',
    this.delitelj = 1,
    this.udarcev = 4,
    this.izhod = '',
  });

  factory NastavitveTakta.izJson(Map<String, dynamic> j) => NastavitveTakta(
    nacin: NacinTakta.values.where((n) => n.name == j['n']).firstOrNull ?? NacinTakta.izklop,
    ukaz: j['u']?.toString() ?? '',
    delitelj: ((j['d'] as num?)?.toInt() ?? 1).clamp(1, 4),
    udarcev: ((j['s'] as num?)?.toInt() ?? 4).clamp(0, 64),
    izhod: j['i']?.toString() ?? '',
  );

  final NacinTakta nacin;

  /// Ime ukaza ali makra (ali neposreden zapis) za način [NacinTakta.ukaz].
  final String ukaz;

  /// Ukaz gre na vsako [delitelj]-to dobo (1 = vsaka doba).
  final int delitelj;

  /// Koliko udarcev (dob, pri katerih gre ukaz) ob odprtju pesmi; 0 = ves čas, dokler je pesem odprta.
  final int udarcev;

  /// Logični izhod za MIDI clock (prazno = Privzeti).
  final String izhod;

  bool get vesCas => udarcev == 0;

  Map<String, dynamic> vJson() => {'n': nacin.name, 'u': ukaz, 'd': delitelj, 's': udarcev, 'i': izhod};

  NastavitveTakta kopija({NacinTakta? nacin, String? ukaz, int? delitelj, int? udarcev, String? izhod}) =>
      NastavitveTakta(
        nacin: nacin ?? this.nacin,
        ukaz: ukaz ?? this.ukaz,
        delitelj: delitelj ?? this.delitelj,
        udarcev: udarcev ?? this.udarcev,
        izhod: izhod ?? this.izhod,
      );

  /// Razmik med poslanimi sporočili v mikrosekundah pri tempu [bpm].
  double razmik(num bpm) {
    final doba = 60e6 / bpm;
    return nacin == NacinTakta.clock ? doba / 24 : doba * delitelj;
  }

  /// Koliko sporočil pošlje ob odprtju (null = ves čas).
  int? sporocil() => vesCas ? null : (nacin == NacinTakta.clock ? udarcev * 24 : udarcev);
}

/// Tempo pesmi (BPM) ali null, če ni vpisan ali je nesmiseln.
num? tempoPesmi(Pesem p) {
  final t = num.tryParse(besedilo(p.vrstica['Tempo (BPM)']).replaceAll(',', '.'));
  return t == null || t < 20 || t > 400 ? null : t;
}
