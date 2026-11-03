/// Razčlenjevanje besedil z akordi v oglatih oklepajih (ChordPro), npr.
/// "[C]Belo obleko si [G]že nosila".
library;

/// Del vrstice: akord (lahko prazen) in besedilo pod njim.
class Kos {
  const Kos(this.akord, this.besedilo);
  final String akord;
  final String besedilo;

  @override
  bool operator ==(Object other) => other is Kos && other.akord == akord && other.besedilo == besedilo;

  @override
  int get hashCode => Object.hash(akord, besedilo);

  @override
  String toString() => 'Kos($akord, $besedilo)';
}

enum VrstaVrstice { besedilo, komentar, prazna }

class Vrstica {
  const Vrstica(this.vrsta, this.kosi, [this.komentar = '']);
  final VrstaVrstice vrsta;
  final List<Kos> kosi;
  final String komentar;

  bool get imaAkorde => kosi.any((k) => k.akord.isNotEmpty);
}

final _direktiva = RegExp(r'^\{\s*([a-zA-Z_]+)\s*(?::\s*(.*?))?\s*\}$');
final _akord = RegExp(r'\[([^\]]*)\]');

List<Vrstica> razcleni(String vsebina) {
  final out = <Vrstica>[];
  for (final surova in vsebina.replaceAll('\r\n', '\n').split('\n')) {
    final vrstica = surova.trimRight();
    if (vrstica.trim().isEmpty) {
      out.add(const Vrstica(VrstaVrstice.prazna, []));
      continue;
    }
    final d = _direktiva.firstMatch(vrstica.trim());
    if (d != null) {
      final ime = d.group(1)!.toLowerCase();
      if (ime == 'c' || ime == 'comment' || ime == 'ci' || ime == 'comment_italic') {
        out.add(Vrstica(VrstaVrstice.komentar, const [], d.group(2) ?? ''));
      }
      continue; // ostale direktive (title, key ...) prikaz ignorira
    }
    out.add(Vrstica(VrstaVrstice.besedilo, razcleniVrstico(vrstica)));
  }
  return out;
}

List<Kos> razcleniVrstico(String vrstica) {
  final kosi = <Kos>[];
  var akord = '';
  var zacetek = 0;
  for (final m in _akord.allMatches(vrstica)) {
    final pred = vrstica.substring(zacetek, m.start);
    if (pred.isNotEmpty || akord.isNotEmpty) kosi.add(Kos(akord, pred));
    akord = m.group(1)!.trim();
    zacetek = m.end;
  }
  final ostanek = vrstica.substring(zacetek);
  if (ostanek.isNotEmpty || akord.isNotEmpty) kosi.add(Kos(akord, ostanek));
  return kosi;
}

final _tonAkorda = RegExp(
  r'^[A-H](?:is|es|s|#|b)?(?:m|mi|min|maj|dim|aug|sus|add|\+|°)*\d*(?:\/[A-H](?:is|es|s|#|b)?)?$',
);

/// Ali je vrstica sestavljena samo iz akordov (npr. "C      G7    Am").
bool jeVrsticaAkordov(String vrstica) {
  final besede = vrstica.trim().split(RegExp(r'\s+'));
  return vrstica.trim().isNotEmpty && besede.every(_tonAkorda.hasMatch);
}

/// Pretvori besedilo z akordi v vrstici nad besedilom (kot ga najdeš na spletu) v zapis z akordi
/// v oglatih oklepajih. Akord pride pred črko, nad katero stoji.
String akordiNadBesedilom(String vsebina) {
  final vrstice = vsebina.replaceAll('\r\n', '\n').split('\n');
  final out = <String>[];
  for (var i = 0; i < vrstice.length; i++) {
    final v = vrstice[i].trimRight();
    if (!jeVrsticaAkordov(v)) {
      out.add(v);
      continue;
    }
    final akordi = [for (final m in RegExp(r'\S+').allMatches(v)) (m.start, m.group(0)!)];
    final naslednja = i + 1 < vrstice.length ? vrstice[i + 1].trimRight() : '';
    if (naslednja.trim().isEmpty || jeVrsticaAkordov(naslednja) || naslednja.trim().startsWith('{')) {
      out.add(akordi.map((a) => '[${a.$2}]').join(' '));
      continue;
    }
    var besedilo = naslednja.padRight(akordi.last.$1);
    for (final (pozicija, akord) in akordi.reversed) {
      besedilo = '${besedilo.substring(0, pozicija)}[$akord]${besedilo.substring(pozicija)}';
    }
    out.add(besedilo.trimRight());
    i++;
  }
  return out.join('\n');
}

/// Krepko besedilo je zapisano kot **besedilo** (znotraj vrstice; ob izbiri čez več vrstic vsaka posebej).
const oznakaKrepko = '**';

/// Besedilo brez oznak za krepko (za iskanje in primerjavo vrstic).
String brezKrepkega(String s) => s.replaceAll(oznakaKrepko, '');

/// Deli besedila z vedenjem, ali so krepki; [krepko] je stanje na začetku (nadaljevanje iz prejšnjega kosa
/// iste vrstice). Vrne dele in stanje na koncu.
(List<(String, bool)>, bool) deliKrepko(String s, {bool krepko = false}) {
  final deli = <(String, bool)>[];
  var k = krepko;
  final kosi = s.split(oznakaKrepko);
  for (var i = 0; i < kosi.length; i++) {
    if (i > 0) k = !k;
    if (kosi[i].isNotEmpty) deli.add((kosi[i], k));
  }
  return (deli, k);
}

/// Izbira [od]–[do] v besedilu postane krepka ali (če je že vsa krepka) ni več krepka.
/// Vsaka vrstica izbire dobi svoje oznake. Vrne novo besedilo in novo izbiro.
(String, (int, int)) preklopiKrepko(String besedilo, int od, int doo) {
  var izbrano = besedilo.substring(od, doo);
  var zacetek = od;
  var konec = doo;
  // Že krepko: oznake okoli izbire ali na njenih robovih se odstranijo.
  final okoli =
      zacetek >= 2 &&
      konec + 2 <= besedilo.length &&
      besedilo.substring(zacetek - 2, zacetek) == oznakaKrepko &&
      besedilo.substring(konec, konec + 2) == oznakaKrepko;
  if (okoli) {
    final novo = besedilo.substring(0, zacetek - 2) + izbrano + besedilo.substring(konec + 2);
    return (novo, (zacetek - 2, konec - 2));
  }
  if (izbrano.length >= 4 && izbrano.startsWith(oznakaKrepko) && izbrano.endsWith(oznakaKrepko)) {
    final notri = izbrano.substring(2, izbrano.length - 2);
    return (besedilo.substring(0, zacetek) + notri + besedilo.substring(konec), (zacetek, zacetek + notri.length));
  }
  // Presledki na robovih ostanejo zunaj oznak.
  while (izbrano.isNotEmpty && izbrano[0].trim().isEmpty) {
    izbrano = izbrano.substring(1);
    zacetek++;
  }
  while (izbrano.isNotEmpty && izbrano[izbrano.length - 1].trim().isEmpty) {
    izbrano = izbrano.substring(0, izbrano.length - 1);
    konec--;
  }
  if (izbrano.isEmpty) return (besedilo, (od, doo));
  final ovito = izbrano
      .split('\n')
      .map((v) {
        final t = v.trim();
        if (t.isEmpty) return v;
        final i = v.indexOf(t);
        return '${v.substring(0, i)}$oznakaKrepko$t$oznakaKrepko${v.substring(i + t.length)}';
      })
      .join('\n');
  final novo = besedilo.substring(0, zacetek) + ovito + besedilo.substring(konec);
  return (novo, (zacetek, zacetek + ovito.length));
}
