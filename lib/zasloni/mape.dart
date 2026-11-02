import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../models.dart';
import 'nastavitve_zaslon.dart' show IzbiraBarve;

/// Ikone, med katerimi se izbira pri mapi (ključ je zapisan v stolpcu Ikona).
const ikoneMap = <String, IconData>{
  'mapa': Icons.folder_outlined,
  'note': Icons.music_note,
  'knjiznica': Icons.library_music_outlined,
  'playlista': Icons.queue_music,
  'album': Icons.album_outlined,
  'mikrofon': Icons.mic_none,
  'klaviature': Icons.piano,
  'kitara': Icons.music_video_outlined,
  'zvocnik': Icons.speaker_outlined,
  'slusalke': Icons.headphones,
  'srce': Icons.favorite_outline,
  'zvezda': Icons.star_outline,
  'poroka': Icons.diversity_1_outlined,
  'zabava': Icons.celebration_outlined,
  'torta': Icons.cake_outlined,
  'pijaca': Icons.local_bar_outlined,
  'vino': Icons.wine_bar_outlined,
  'ples': Icons.nightlife,
  'cerkev': Icons.church_outlined,
  'otroci': Icons.child_care,
  'bozic': Icons.ac_unit,
  'sonce': Icons.wb_sunny_outlined,
  'ogenj': Icons.local_fire_department_outlined,
  'gore': Icons.landscape_outlined,
  'dom': Icons.home_outlined,
  'vaja': Icons.school_outlined,
  'nova': Icons.fiber_new_outlined,
  'cas': Icons.schedule,
  'zastava': Icons.flag_outlined,
  'arhiv': Icons.inventory_2_outlined,
};

IconData ikonaMape(Mapa m) => ikoneMap[m.ikona] ?? Icons.folder_outlined;

/// Pesmi v mapi, tudi arhivirane (mape s pesmimi se ne sme izbrisati).
int steviloVMapi(Baza baza, String id) => baza.pesmi.where((p) => p.mapa == id).length;

enum _Dejanje { shrani, izbrisi, gor, dol }

/// Okno za novo mapo ali urejanje obstoječe; shrani v list Mape.
Future<void> urediMapo(BuildContext context, Baza baza, Api api, {Mapa? mapa}) async {
  final messenger = ScaffoldMessenger.of(context);
  final ime = TextEditingController(text: mapa?.ime ?? '');
  final opis = TextEditingController(text: mapa?.opis ?? '');
  var barva = mapa?.argb;
  var ikona = mapa?.ikona.isNotEmpty ?? false ? mapa!.ikona : 'mapa';
  var pavza = mapa?.pavza ?? '';
  final i = mapa == null ? -1 : baza.mape.indexWhere((m) => m.id == mapa.id);
  final polne = mapa == null ? 0 : steviloVMapi(baza, mapa.id);
  final pesmi = mapa == null ? <Pesem>[] : (baza.pesmiMape(mapa.id)..sort((a, b) => a.naslov.compareTo(b.naslov)));
  if (pavza.isNotEmpty && !pesmi.any((p) => p.id == pavza)) {
    if (baza.pesem(pavza) case final p?) pesmi.insert(0, p);
  }

  final dejanje = await showDialog<_Dejanje>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, nastavi) {
        final tema = Theme.of(context);
        return AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text(mapa == null ? 'Nova mapa' : 'Uredi mapo')),
              if (mapa != null) ...[
                IconButton(
                  tooltip: 'Premakni gor',
                  onPressed: i > 0 ? () => Navigator.pop(context, _Dejanje.gor) : null,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Premakni dol',
                  onPressed: i < baza.mape.length - 1 ? () => Navigator.pop(context, _Dejanje.dol) : null,
                  icon: const Icon(Icons.arrow_downward),
                ),
              ],
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('ime-mape'),
                    controller: ime,
                    autofocus: mapa == null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Ime', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('opis-mape'),
                    controller: opis,
                    maxLines: 2,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Opis', border: OutlineInputBorder()),
                  ),
                  IzbiraBarve(naslov: 'Barva', barva: barva, izberi: (b) => nastavi(() => barva = b)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text('Ikona', style: tema.textTheme.bodyLarge),
                  ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final e in ikoneMap.entries)
                        IconButton(
                          key: ValueKey('ikona-${e.key}'),
                          isSelected: e.key == ikona,
                          style: IconButton.styleFrom(
                            backgroundColor: e.key == ikona ? tema.colorScheme.primaryContainer : null,
                          ),
                          color: barva == null ? tema.colorScheme.primary : Color(barva!),
                          onPressed: () => nastavi(() => ikona = e.key),
                          icon: Icon(e.value),
                        ),
                    ],
                  ),
                  if (pesmi.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: pavza,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Pesem za pavzo', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Brez')),
                        for (final p in pesmi)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(p.naslov, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => pavza = v ?? '',
                    ),
                  ],
                  if (mapa != null && polne > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Mapo lahko izbrišeš, ko je prazna (zdaj ima $polne pesmi, tudi arhivirane).',
                        style: tema.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (mapa != null)
              TextButton(
                onPressed: polne == 0 ? () => Navigator.pop(context, _Dejanje.izbrisi) : null,
                child: const Text('Izbriši'),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
            FilledButton(
              key: const ValueKey('shrani-mapo'),
              onPressed: () {
                if (ime.text.trim().isEmpty) return;
                Navigator.pop(context, _Dejanje.shrani);
              },
              child: const Text('Shrani'),
            ),
          ],
        );
      },
    ),
  );
  if (dejanje == null) return;
  try {
    switch (dejanje) {
      case _Dejanje.shrani:
        final vrstniRed = mapa?.vrstniRed ?? baza.mape.fold<int>(0, (m, x) => x.vrstniRed > m ? x.vrstniRed : m) + 1;
        await baza.shraniMidi(
          api,
          'Mape',
          Mapa(
            id: mapa?.id ?? '',
            ime: ime.text.trim(),
            vrstniRed: vrstniRed,
            pavza: pavza,
            opis: opis.text.trim(),
            barva: hexBarva(barva),
            ikona: ikona,
          ).vVrstico(),
        );
      case _Dejanje.izbrisi:
        await baza.shraniMidi(api, 'Mape', {'ID': mapa!.id}, izbrisi: true);
        messenger.showSnackBar(SnackBar(content: Text('Mapa ${mapa.ime} izbrisana')));
      case _Dejanje.gor || _Dejanje.dol:
        final vrsta = List.of(baza.mape);
        final m = vrsta.removeAt(i);
        vrsta.insert(dejanje == _Dejanje.gor ? i - 1 : i + 1, m);
        for (var j = 0; j < vrsta.length; j++) {
          if (vrsta[j].vrstniRed != j + 1) {
            await baza.shraniMidi(api, 'Mape', {'ID': vrsta[j].id, 'Ime': vrsta[j].ime, 'Vrstni red': j + 1});
          }
        }
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Shranjevanje ni uspelo: $e')));
  }
}
