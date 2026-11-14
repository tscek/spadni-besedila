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

enum _Dejanje { shrani, izbrisi, izprazni, zasedba, gor, dol }

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
                  if (mapa != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (baza.skupine.length > 1)
                          OutlinedButton.icon(
                            key: const ValueKey('mapa-zasedba'),
                            onPressed: () => Navigator.pop(context, _Dejanje.zasedba),
                            icon: const Icon(Icons.drive_file_move_outline),
                            label: const Text('V drugo zasedbo'),
                          ),
                        if (polne > 0)
                          OutlinedButton.icon(
                            key: const ValueKey('mapa-izprazni'),
                            onPressed: () => Navigator.pop(context, _Dejanje.izprazni),
                            icon: const Icon(Icons.cleaning_services_outlined),
                            label: const Text('Izprazni'),
                          ),
                        OutlinedButton.icon(
                          key: const ValueKey('mapa-izbrisi'),
                          style: OutlinedButton.styleFrom(foregroundColor: tema.colorScheme.error),
                          onPressed: () => Navigator.pop(context, _Dejanje.izbrisi),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Izbriši mapo'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
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
            zasedba: mapa?.zasedba ?? baza.zasedba,
          ).vVrstico(),
        );
      case _Dejanje.izbrisi || _Dejanje.izprazni:
        if (!context.mounted) return;
        final izbris = dejanje == _Dejanje.izbrisi;
        final trajno = await _potrdiBrisanje(context, mapa!, polne, izbris: izbris);
        if (trajno == null) return;
        if (izbris && polne == 0) {
          await baza.shraniMidi(api, 'Mape', {'ID': mapa.id}, izbrisi: true);
        } else {
          messenger.showSnackBar(const SnackBar(content: Text('Delam …')));
          await baza.mapaUkaz(api, izbris ? 'izbrisi' : 'izprazni', mapa.id, trajno: trajno);
        }
        messenger.showSnackBar(
          SnackBar(content: Text(izbris ? 'Mapa ${mapa.ime} izbrisana' : 'Mapa ${mapa.ime} izpraznjena')),
        );
      case _Dejanje.zasedba:
        if (!context.mounted) return;
        final izbira = await _izberiZasedbo(context, baza, mapa!);
        if (izbira == null) return;
        messenger.showSnackBar(const SnackBar(content: Text('Delam …')));
        await baza.mapaUkaz(api, izbira.kopija ? 'kopiraj' : 'premakni', mapa.id, zasedba: izbira.zasedba);
        final ime = baza.skupine.where((s) => s.id == izbira.zasedba).firstOrNull?.ime ?? izbira.zasedba;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              izbira.kopija ? 'Kopija mape ${mapa.ime} je v zasedbi $ime' : 'Mapa ${mapa.ime} je zdaj v zasedbi $ime',
            ),
          ),
        );
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

/// Varovalka pred brisanjem: vpisati je treba ime mape. Vrne null (prekliči) ali ali naj pesmi izginejo za vedno.
Future<bool?> _potrdiBrisanje(BuildContext context, Mapa mapa, int pesmi, {required bool izbris}) {
  final vnos = TextEditingController();
  var trajno = false;
  return showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, nastavi) {
        final tema = Theme.of(context);
        final ujema = vnos.text.trim().toLowerCase() == mapa.ime.trim().toLowerCase();
        return AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: tema.colorScheme.error),
          title: Text(izbris ? 'Izbriši mapo ${mapa.ime}?' : 'Izprazni mapo ${mapa.ime}?'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pesmi > 0)
                  Text(
                    trajno
                        ? 'Vseh $pesmi pesmi (tudi arhiviranih) bo izbrisanih za vedno, z besedili, PDF-ji in skupnimi risbami.'
                        : 'Vseh $pesmi pesmi gre v Arhiv, od koder jih lahko vrneš.',
                  ),
                if (pesmi > 0)
                  CheckboxListTile(
                    key: const ValueKey('mapa-trajno'),
                    contentPadding: EdgeInsets.zero,
                    value: trajno,
                    onChanged: (v) => nastavi(() => trajno = v ?? false),
                    title: const Text('Pesmi izbriši za vedno'),
                  ),
                const SizedBox(height: 8),
                Text('Za potrditev vpiši ime mape: ${mapa.ime}'),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('mapa-potrdi-ime'),
                  controller: vnos,
                  autofocus: true,
                  onChanged: (_) => nastavi(() {}),
                  decoration: InputDecoration(border: const OutlineInputBorder(), hintText: mapa.ime),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
            FilledButton(
              key: const ValueKey('mapa-potrdi'),
              style: FilledButton.styleFrom(backgroundColor: tema.colorScheme.error),
              onPressed: ujema ? () => Navigator.pop(context, trajno) : null,
              child: Text(izbris ? 'Izbriši' : 'Izprazni'),
            ),
          ],
        );
      },
    ),
  ).whenComplete(vnos.dispose);
}

/// Izbira zasedbe za premik ali kopijo mape.
Future<({String zasedba, bool kopija})?> _izberiZasedbo(BuildContext context, Baza baza, Mapa mapa) {
  final druge = [
    for (final s in baza.skupine)
      if (s.id != mapa.zasedba) s,
  ];
  var zasedba = druge.isEmpty ? '' : druge.first.id;
  var kopija = false;
  return showDialog<({String zasedba, bool kopija})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, nastavi) => AlertDialog(
        title: Text('Mapa ${mapa.ime} v drugo zasedbo'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('mapa-nova-zasedba'),
                initialValue: zasedba.isEmpty ? null : zasedba,
                decoration: const InputDecoration(labelText: 'Zasedba', border: OutlineInputBorder()),
                items: [for (final s in druge) DropdownMenuItem(value: s.id, child: Text(s.ime))],
                onChanged: (v) => nastavi(() => zasedba = v ?? zasedba),
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Premakni'), icon: Icon(Icons.drive_file_move_outline)),
                  ButtonSegment(value: true, label: Text('Kopiraj'), icon: Icon(Icons.copy)),
                ],
                selected: {kopija},
                onSelectionChanged: (v) => nastavi(() => kopija = v.first),
              ),
              const SizedBox(height: 8),
              Text(
                kopija
                    ? 'Nova mapa s kopijami pesmi (besedila, PDF in skupne risbe). Ta mapa ostane, kot je.'
                    : 'Mapa in njene pesmi gredo v izbrano zasedbo; v tej je ne bo več.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Prekliči')),
          FilledButton(
            key: const ValueKey('mapa-zasedba-potrdi'),
            onPressed: zasedba.isEmpty ? null : () => Navigator.pop(context, (zasedba: zasedba, kopija: kopija)),
            child: Text(kopija ? 'Kopiraj' : 'Premakni'),
          ),
        ],
      ),
    ),
  );
}
