import 'package:flutter/material.dart';

import '../prijava.dart';

class PrijavaZaslon extends StatelessWidget {
  const PrijavaZaslon({super.key, required this.prijava, required this.onPrijavljen});

  final Prijava prijava;
  final VoidCallback onPrijavljen;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
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
              else
                FilledButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Prijava z Google računom'),
                  onPressed: () async {
                    await prijava.prijavi();
                    if (prijava.racun != null) onPrijavljen();
                  },
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
