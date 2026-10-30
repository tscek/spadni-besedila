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

  String q(String s) => "'${s.replaceAll("'", "''")}'";
  final skripta = File('${Directory.systemTemp.path}${Platform.pathSeparator}spadni-posodobitev-$pid.ps1');
  await skripta.writeAsString(
    '﻿'
    '\$ErrorActionPreference = "SilentlyContinue"\r\n'
    'Wait-Process -Id $pid -Timeout 60\r\n'
    'Start-Sleep -Milliseconds 500\r\n'
    // Datoteke so lahko še nekaj trenutkov zaklenjene, zato poskusimo večkrat.
    'for (\$i = 0; \$i -lt 20; \$i++) {\r\n'
    '  try { Copy-Item -Path (Join-Path ${q(najden.parent.path)} "*") -Destination ${q(cilj.path)} '
    '-Recurse -Force -ErrorAction Stop; break } catch { Start-Sleep -Seconds 1 }\r\n'
    '}\r\n'
    'Start-Process -FilePath ${q(exe.path)}\r\n'
    'Remove-Item -Path ${q(tmp.path)} -Recurse -Force\r\n'
    'Remove-Item -Path \$MyInvocation.MyCommand.Path -Force\r\n',
  );
  await Process.start('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-File',
    skripta.path,
  ], mode: ProcessStartMode.detached);
  exit(0);
}
