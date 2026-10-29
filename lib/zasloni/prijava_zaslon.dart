import 'package:flutter/material.dart';

import '../prijava.dart';
import 'gumb_prijave_io.dart' if (dart.library.js_interop) 'gumb_prijave_web.dart';

class PrijavaZaslon extends StatefulWidget {
  const PrijavaZaslon({super.key, required this.prijava, this.zapriObPrijavi = false});

  final Prijava prijava;

  /// Ko je zaslon odprt kot posebna stran, se po uspešni prijavi sam zapre.
  final bool zapriObPrijavi;

  @override
  State<PrijavaZaslon> createState() => _PrijavaZaslonState();
}

class _PrijavaZaslonState extends State<PrijavaZaslon> {
  Prijava get prijava => widget.prijava;

  @override
  void initState() {
    super.initState();
    prijava.addListener(_sprememba);
  }

  @override
  void dispose() {
    prijava.removeListener(_sprememba);
    super.dispose();
  }

  void _sprememba() {
    if (!mounted) return;
    if (widget.zapriObPrijavi && prijava.prijavljen) {
      Navigator.of(context).pop();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: widget.zapriObPrijavi ? AppBar() : null,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_music, size: 72, color: tema.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Špadni besedila', style: tema.textTheme.headlineMedium),
              const SizedBox(height: 32),
              if (!prijava.nastavljena)
                const Text('Google prijava še ni nastavljena v tej različici aplikacije.', textAlign: TextAlign.center)
              else if (gumbPrijaveBrskalnika() case final gumb?)
                FutureBuilder(
                  // Googlov gumb se lahko izriše šele, ko je prijava pripravljena.
                  future: prijava.zacni(),
                  builder: (context, s) => s.connectionState == ConnectionState.done
                      ? SizedBox(height: 48, child: gumb)
                      : const CircularProgressIndicator(),
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Prijava z Google računom'),
                  onPressed: prijava.prijavi,
                ),
              if (prijava.napaka != null) ...[
                const SizedBox(height: 16),
                Text(
                  prijava.napaka!,
                  style: TextStyle(color: tema.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
