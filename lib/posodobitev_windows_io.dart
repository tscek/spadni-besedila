import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;

/// Prenese ZIP nove različice, ga razpakira in z majhnim skriptom PowerShell zamenja datoteke,
/// ko se aplikacija zapre; nato jo spet zažene. [napredek] dobi odstotke prenosa.
Future<void> namestiWindows(String url, void Function(int odstotek) napredek) async {
  final exe = File(Platform.resolvedExecutable);
  final cilj = exe.parent;
  // Aplikacija mora biti v mapi, kamor lahko piše (npr. Dokumenti, ne Program Files).
  final proba = File('${cilj.path}${Platform.pathSeparator}.posodobitev');
  try {
    await proba.writeAsString('ok');
    await proba.delete();
  } on FileSystemException {
    throw Exception('mapa ${cilj.path} ni zapisljiva. Premakni aplikacijo v svojo mapo (npr. Dokumenti).');
  }

  final tmp = await Directory.systemTemp.createTemp('spadni-posodobitev-');
  final zip = File('${tmp.path}${Platform.pathSeparator}nova.zip');
  final odg = await http.Client().send(http.Request('GET', Uri.parse(url)));
  if (odg.statusCode != 200) throw Exception('prenos ni uspel (${odg.statusCode})');
  final skupaj = odg.contentLength ?? 0;
  var preneseno = 0;
  final izhod = zip.openWrite();
  await for (final kos in odg.stream) {
    izhod.add(kos);
    preneseno += kos.length;
    if (skupaj > 0) napredek((preneseno * 100 ~/ skupaj).clamp(0, 99));
  }
  await izhod.close();

  final novo = Directory('${tmp.path}${Platform.pathSeparator}novo');
  await extractFileToDisk(zip.path, novo.path);
  // V ZIP-u je mapa spadni-besedila z exe-jem; poiščemo mapo, kjer je exe z enakim imenom.
  final ime = exe.uri.pathSegments.last;
  final najden = novo
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.toLowerCase() == ime.toLowerCase())
      .firstOrNull;
  if (najden == null) throw Exception('v prenesenem ZIP-u ni $ime');

  // Novo različico zažene kar iz začasne mape: počaka, da se ta aplikacija zapre, prepiše njene datoteke
  // in zažene posodobljeno (glej [dokoncajNamestitev]). Brez skripte PowerShell, ki jo Windows lahko ustavi.
  _zapisi('Prenos končan, zaganjam namestitev iz ${najden.path} v ${cilj.path}');
  await Process.start(
    najden.path,
    ['--namesti', cilj.path, '--pid', '$pid'],
    workingDirectory: najden.parent.path,
    mode: ProcessStartMode.detached,
  );
  exit(0);
}

/// Dnevnik posodobitve v začasni mapi (za iskanje napak).
File get dnevnikPosodobitve => File('${Directory.systemTemp.path}${Platform.pathSeparator}spadni-posodobitev.log');

void _zapisi(String s) {
  try {
    dnevnikPosodobitve.writeAsStringSync('${DateTime.now().toIso8601String()} $s\r\n', mode: FileMode.append);
  } catch (_) {}
}

bool _tece(int id) {
  if (!Platform.isWindows) return false;
  try {
    final r = Process.runSync('tasklist', ['/FI', 'PID eq $id', '/NH']);
    return r.stdout.toString().contains(' $id ');
  } catch (_) {
    return false;
  }
}

Future<void> _kopiraj(Directory iz, Directory v) async {
  await v.create(recursive: true);
  await for (final e in iz.list()) {
    final ime = e.uri.pathSegments.lastWhere((x) => x.isNotEmpty);
    final cilj = '${v.path}${Platform.pathSeparator}$ime';
    if (e is Directory) {
      await _kopiraj(e, Directory(cilj));
    } else if (e is File) {
      await e.copy(cilj);
    }
  }
}

/// Če je aplikacija zagnana z `--namesti <mapa> --pid <id>`, je to nova različica iz začasne mape:
/// počaka, da se stara zapre, prepiše njene datoteke, jo zažene in se konča. Sicer vrne false.
Future<bool> dokoncajNamestitev(List<String> argumenti) async {
  final i = argumenti.indexOf('--namesti');
  if (i < 0 || i + 1 >= argumenti.length) {
    _pocisti();
    return false;
  }
  final cilj = Directory(argumenti[i + 1]);
  final p = argumenti.indexOf('--pid');
  final stari = p >= 0 && p + 1 < argumenti.length ? int.tryParse(argumenti[p + 1]) : null;
  final iz = File(Platform.resolvedExecutable).parent;
  final exe = '${cilj.path}${Platform.pathSeparator}${Platform.resolvedExecutable.split(Platform.pathSeparator).last}';
  _zapisi('Namestitev: iz ${iz.path} v ${cilj.path}, čakam na proces $stari');
  for (var t = 0; stari != null && t < 120 && _tece(stari); t++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  Object? napaka;
  for (var poskus = 0; poskus < 30; poskus++) {
    try {
      await _kopiraj(iz, cilj);
      napaka = null;
      break;
    } catch (e) {
      napaka = e;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  _zapisi(napaka == null ? 'Datoteke zamenjane, zaganjam $exe' : 'NAPAKA pri kopiranju: $napaka');
  try {
    await Process.start(exe, const [], workingDirectory: cilj.path, mode: ProcessStartMode.detached);
  } catch (e) {
    _zapisi('NAPAKA pri zagonu: $e');
  }
  exit(0);
}

/// Ob običajnem zagonu pobriše začasne mape prejšnjih posodobitev.
void _pocisti() {
  try {
    for (final d in Directory.systemTemp.listSync().whereType<Directory>()) {
      if (d.path.split(Platform.pathSeparator).last.startsWith('spadni-posodobitev-')) {
        d.deleteSync(recursive: true);
      }
    }
  } catch (_) {}
}
