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
