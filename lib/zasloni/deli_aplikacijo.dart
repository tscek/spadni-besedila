import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../config.dart';

/// Administrator deli povezave za namestitev: Android (APK), Windows (ZIP) in spletno različico (iPad, računalnik).
Future<void> deliAplikacijo(BuildContext context, Api api) async {
  final povezave = Future.wait([
    api.verzija().catchError((_) => <String, dynamic>{}),
    api.verzija(platforma: 'windows').catchError((_) => <String, dynamic>{}),
  ]);
  await showDialog<void>(
    context: context,
    builder: (context) => FutureBuilder(
      future: povezave,
      builder: (context, stanje) {
        final odg = stanje.data;
        String? url(Map<String, dynamic>? m, String platforma) =>
            m != null && (platforma == 'android' || m['platforma'] == platforma) ? m['url'] as String? : null;
        final android = url(odg?[0], 'android');
        final windows = url(odg?[1], 'windows');
        final vrstice = [
          if (android != null) ('Android (tablica, telefon)', android),
          if (windows != null) ('Windows (razpakiraj in zaženi spadni_besedila.exe)', windows),
          ('Splet (iPad, računalnik): odpri v brskalniku, na iPadu Share → Add to Home Screen', Config.spletniNaslov),
        ];
        final besedilo = [
          'Aplikacija Špadni besedila. Prijava z Google računom, ki ima dostop.',
          for (final (ime, u) in vrstice) '$ime:\n$u',
          'Po prvi namestitvi se Android in Windows posodabljata sama (gumb Posodobi).',
        ].join('\n\n');
        return AlertDialog(
          title: const Text('Deli aplikacijo'),
          content: stanje.connectionState != ConnectionState.done
              ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
              : SizedBox(
                  width: 480,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final (ime, u) in vrstice)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(ime),
                          subtitle: Text(u, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            tooltip: 'Kopiraj povezavo',
                            icon: const Icon(Icons.copy),
                            onPressed: () => Clipboard.setData(ClipboardData(text: u)),
                          ),
                        ),
                      if (android == null || windows == null)
                        const Text('Povezave za Android ali Windows ni bilo mogoče dobiti (internet ali skripta).'),
                    ],
                  ),
                ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zapri')),
            FilledButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Deli vse'),
              onPressed: stanje.connectionState != ConnectionState.done
                  ? null
                  : () async {
                      try {
                        await SharePlus.instance.share(ShareParams(text: besedilo, subject: 'Špadni besedila'));
                      } catch (_) {
                        await Clipboard.setData(ClipboardData(text: besedilo));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Besedilo s povezavami je kopirano.')));
                        }
                      }
                    },
            ),
          ],
        );
      },
    ),
  );
}
