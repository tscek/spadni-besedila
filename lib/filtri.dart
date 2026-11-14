import 'dart:convert';

import 'baza.dart';
import 'models.dart';

/// Polje, po katerem so lahko hitri filtri (čipi nad seznamom pesmi in v iskalniku).
enum PoljeFiltra {
  vrsta('Vrsta'),
  harmonika('Harmonika'),
  tonaliteta('Tonaliteta'),
  status('Status'),
  ocena('Ocena'),
  zvrst('Zvrst'),
  oznaka('Oznaka'),
  izvajalec('Izvajalec'),
  avtorGlasbe('Avtor glasbe'),
  avtorBesedila('Avtor besedila'),
  tempo('Tempo'),
  trajanje('Trajanje'),
  ima('Ima');

  const PoljeFiltra(this.ime);
  final String ime;

  /// Razredi za tempo, trajanje in »Ima« (v tem vrstnem redu); pri ostalih poljih so čipi kar vrednosti.
  static const razrediTempa = ['Počasne (do 90)', 'Srednje (90–130)', 'Hitre (nad 130)'];
  static const razrediTrajanja = ['Do 3 min', '3–4 min', 'Nad 4 min'];
  static const kajIma = ['Playback', 'Uvod', 'YouTube', 'Besedilo', 'PDF', 'Tyros'];

  /// Vrednosti (čipi), v katere spada pesem; prazno, če polje pri pesmi ni izpolnjeno.
  List<String> vrednosti(Pesem p, Baza baza) {
    String? razred(num? v, List<num> meje, List<String> imena) {
      if (v == null || v <= 0) return null;
      for (var i = 0; i < meje.length; i++) {
        if (v < meje[i]) return imena[i];
      }
      return imena.last;
    }

    final s = switch (this) {
      vrsta => p.vrsta,
      harmonika => p.harmonika,
      tonaliteta => p.tonaliteta,
      status => p.status.ime,
      ocena => p.ocena > 0 ? '★' * p.ocena : '',
      zvrst => p.zvrst,
      oznaka => besedilo(p.vrstica['Oznaka']),
      izvajalec => p.izvajalec,
      avtorGlasbe => p.avtorGlasbe,
      avtorBesedila => p.avtorBesedila,
      tempo =>
        razred(num.tryParse(besedilo(p.vrstica['Tempo (BPM)']).replaceAll(',', '.')), [90, 131], razrediTempa) ?? '',
      trajanje => razred(sekundeTrajanja(besedilo(p.vrstica['Trajanje'])), [180, 241], razrediTrajanja) ?? '',
      ima => null,
    };
    if (s != null) return s.trim().isEmpty ? const [] : [s.trim()];
    return [
      if (p.playback.isNotEmpty) 'Playback',
      if (p.uvod.isNotEmpty) 'Uvod',
      if (p.youtubeId != null) 'YouTube',
      if ((baza.besedilaPesmi[p.id] ?? const []).isNotEmpty) 'Besedilo',
      if ((baza.pdfjiPesmi[p.id] ?? const []).isNotEmpty) 'PDF',
      if (p.tyros != null) 'Tyros',
    ];
  }

  /// Vsi čipi polja za te pesmi, v smiselnem vrstnem redu.
  List<String> cipi(List<Pesem> pesmi, Baza baza) {
    final vse = {for (final p in pesmi) ...vrednosti(p, baza)};
    List<String> poVrsti(List<String> red) => [...red.where(vse.contains), ...vse.where((v) => !red.contains(v))];
    return switch (this) {
      tempo => poVrsti(razrediTempa),
      trajanje => poVrsti(razrediTrajanja),
      ima => poVrsti(kajIma),
      status => poVrsti([for (final s in StatusPesmi.values) s.ime]),
      ocena => vse.toList()..sort((a, b) => b.length.compareTo(a.length)),
      harmonika => poVrsti([for (final h in baza.harmonike) h.ime]),
      vrsta => poVrsti([for (final v in baza.vrste) v.ime]),
      _ => vse.toList()..sort((a, b) => poenostavi(a).compareTo(poenostavi(b))),
    };
  }
}

/// »3:45« → 225 sekund; null, če zapis ni čas.
int? sekundeTrajanja(String s) {
  final m = RegExp(r'^(\d{1,3}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  return int.parse(m[1]!) * 60 + int.parse(m[2]!);
}

/// Kaj se ob odprtju pesmi v mapi pokaže najprej, ko ima pesem besedilo in PDF.
enum PrikazMape {
  samodejno('Kot na napravi'),
  pdf('PDF'),
  besedilo('Besedilo');

  const PrikazMape(this.ime);
  final String ime;
}

/// Prikaz pesmi ob odprtju: stolpec Prikaz pri pesmi, nato izbira člana za mapo, nato nastavitev naprave.
bool pdfNajprej(Pesem p, PrikazMape mapa, {required bool naprava}) =>
    switch (besedilo(p.vrstica['Prikaz']).toLowerCase()) {
      'pdf' => true,
      'besedilo' => false,
      _ => switch (mapa) {
        PrikazMape.pdf => true,
        PrikazMape.besedilo => false,
        PrikazMape.samodejno => naprava,
      },
    };

/// Hitri filtri ene mape: katera polja so prikazana in kateri čipi so skriti, ter prikaz PDF ali besedila.
/// Brez shranjene nastavitve sta prikazana Vrsta in Harmonika (kot prej).
class FiltriMape {
  const FiltriMape({this.polja = privzeta, this.skriti = const {}, this.prikaz = PrikazMape.samodejno});

  static const privzeta = [PoljeFiltra.vrsta, PoljeFiltra.harmonika];

  factory FiltriMape.izJson(Map<String, dynamic> j) => FiltriMape(
    polja: [for (final p in (j['p'] as List?) ?? const []) ?PoljeFiltra.values.asNameMap()[p.toString()]],
    skriti: {
      for (final e in ((j['s'] as Map?) ?? const {}).entries)
        ?PoljeFiltra.values.asNameMap()[e.key.toString()]: {
          for (final v in (e.value as List? ?? const [])) v.toString(),
        },
    },
    prikaz: PrikazMape.values.asNameMap()[j['x']?.toString()] ?? PrikazMape.samodejno,
  );

  /// Prikaz PDF ali besedila ob odprtju pesmi v tej mapi.
  final PrikazMape prikaz;

  final List<PoljeFiltra> polja;

  /// Čipi, ki jih je član skril (novi se torej pokažejo sami).
  final Map<PoljeFiltra, Set<String>> skriti;

  Map<String, dynamic> vJson() => {
    'p': [for (final p in polja) p.name],
    's': {
      for (final e in skriti.entries)
        if (e.value.isNotEmpty) e.key.name: e.value.toList()..sort(),
    },
    if (prikaz != PrikazMape.samodejno) 'x': prikaz.name,
  };

  bool skrit(PoljeFiltra p, String v) => skriti[p]?.contains(v) ?? false;
}

/// Hitri filtri vseh map enega člana (ključ = mapa, kot pri razvrščanju).
class FiltriClana {
  const FiltriClana([this.mape = const {}]);

  /// Ključ nastavitve člana v bazi.
  static const kljuc = 'FILTRI';

  factory FiltriClana.izBesedila(String s) {
    try {
      final j = jsonDecode(s);
      if (j is Map) {
        return FiltriClana({
          for (final e in j.entries)
            if (e.value is Map) e.key.toString(): FiltriMape.izJson((e.value as Map).cast<String, dynamic>()),
        });
      }
    } catch (_) {}
    return const FiltriClana();
  }

  final Map<String, FiltriMape> mape;

  FiltriMape za(String mapa) => mape[mapa] ?? const FiltriMape();

  FiltriClana z(String mapa, FiltriMape f) => FiltriClana({...mape, mapa: f});

  String vBesedilo() => jsonEncode({for (final e in mape.entries) e.key: e.value.vJson()});
}

/// Izbrani čipi (en na polje); pesem ustreza, če ustreza vsem izbranim.
bool ustrezaFiltrom(Pesem p, Map<PoljeFiltra, String> izbrani, Baza baza) =>
    izbrani.entries.every((e) => e.value.isEmpty || e.key.vrednosti(p, baza).contains(e.value));
