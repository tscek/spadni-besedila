import 'package:flutter/material.dart';

import '../api.dart';
import '../baza.dart';
import '../models.dart';
import '../prijava.dart';
import 'pesem_zaslon.dart';

class SeznamZaslon extends StatefulWidget {
  const SeznamZaslon({super.key, required this.prijava, required this.baza});

  final Prijava prijava;
  final Baza baza;

  @override
  State<SeznamZaslon> createState() => _SeznamZaslonState();
}

class _SeznamZaslonState extends State<SeznamZaslon> {
  final _iskanje = TextEditingController();
  String _zvrst = '';

  @override
  void dispose() {
    _iskanje.dispose();
    super.dispose();
  }

  void _osvezi() {
    if (widget.prijava.racun == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Za osvežitev se prijavi z Google računom (potreben je internet).')));
      widget.prijava.prijavi().then((_) {
        if (widget.prijava.racun != null) widget.baza.osvezi(Api(widget.prijava.zeton));
      });
      return;
    }
    widget.baza.osvezi(Api(widget.prijava.zeton));
  }

  @override
  Widget build(BuildContext context) {
    final baza = widget.baza;
    final zvrsti = baza.pesmi.map((p) => p.zvrst).where((z) => z.isNotEmpty).toSet().toList()..sort();
    final pesmi = baza.pesmi.where((p) => (_zvrst.isEmpty || p.zvrst == _zvrst) && p.ustreza(_iskanje.text)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesmi'),
        actions: [
          IconButton(
            tooltip: 'Osveži iz baze',
            icon: baza.osvezujem
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            onPressed: baza.osvezujem ? null : _osvezi,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'odjava') widget.prijava.odjavi();
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(widget.prijava.racun?.email ?? 'Ni prijave')),
              if (baza.zadnjaOsvezitev != null)
                PopupMenuItem(enabled: false, child: Text('Osveženo: ${_datum(baza.zadnjaOsvezitev!)}')),
              if (widget.prijava.racun != null) const PopupMenuItem(value: 'odjava', child: Text('Odjava')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _iskanje,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Išči po kodi, naslovu ali izvajalcu',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _iskanje.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(_iskanje.clear)),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final z in ['', ...zvrsti])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(z.isEmpty ? 'Vse' : z),
                          selected: _zvrst == z,
                          onSelected: (_) => setState(() => _zvrst = z),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (baza.stanje != null || baza.napaka != null)
            MaterialBanner(
              content: Text(baza.napaka ?? baza.stanje!),
              leading: Icon(baza.napaka != null ? Icons.error_outline : Icons.downloading),
              actions: [TextButton(onPressed: baza.osvezujem ? null : _osvezi, child: const Text('Znova'))],
            ),
          Expanded(
            child: pesmi.isEmpty
                ? Center(child: Text(baza.pesmi.isEmpty ? 'Ni pesmi. Osveži iz baze.' : 'Ni zadetkov.'))
                : ListView.builder(itemCount: pesmi.length, itemBuilder: (context, i) => _vrstica(context, pesmi[i])),
          ),
        ],
      ),
    );
  }

  Widget _vrstica(BuildContext context, Pesem p) {
    final imaBesedilo = widget.baza.besedilaPesmi.containsKey(p.id);
    final imaPdf = widget.baza.pdfjiPesmi.containsKey(p.id);
    return ListTile(
      leading: SizedBox(
        width: 52,
        child: Text(
          p.koda,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(p.naslov),
      subtitle: Text([p.izvajalec, p.tonaliteta].where((s) => s.isNotEmpty).join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imaBesedilo) const Icon(Icons.notes, size: 18),
          if (imaPdf) const Icon(Icons.picture_as_pdf, size: 18),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PesemZaslon(pesem: p, baza: widget.baza),
        ),
      ),
    );
  }

  static String _datum(DateTime d) {
    final l = d.toLocal();
    String dv(int x) => x.toString().padLeft(2, '0');
    return '${dv(l.day)}.${dv(l.month)}.${l.year} ${dv(l.hour)}:${dv(l.minute)}';
  }
}
