import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_ble/flutter_midi_command_ble.dart';

class NapravaMidi {
  const NapravaMidi(this.id, this.ime, this.vrsta, this.povezana);
  final String id;
  final String ime;

  /// Bluetooth, USB, ...
  final String vrsta;
  final bool povezana;
}

/// Dostop do MIDI naprav (v testih ga zamenja ponaredek).
abstract class MidiPrenos {
  Future<List<NapravaMidi>> naprave();
  Future<void> zacniIskanje();
  void ustaviIskanje();
  Future<void> povezi(String id);
  void prekini(String id);
  void poslji(Uint8List bajti, String id);

  /// Javi, ko se seznam naprav spremeni.
  Stream<void> get spremembe;

  /// Prejeti ukazi (ime naprave, bajti enega ukaza).
  Stream<(String, Uint8List)> get prejeto;
}

/// Prave naprave prek flutter_midi_command: Bluetooth in USB na Androidu, Web MIDI v brskalniku (ne v Safariju).
class MidiPrenosNaprave implements MidiPrenos {
  MidiCommand? _midi;
  final Map<String, MidiDevice> _naprave = {};

  MidiCommand get _m {
    final m = _midi;
    if (m != null) return m;
    final nov = MidiCommand();
    if (!kIsWeb) nov.configureBleTransport(UniversalBleMidiTransport());
    return _midi = nov;
  }

  bool get _bluetooth => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<List<NapravaMidi>> naprave() async {
    final s = await _m.devices ?? const <MidiDevice>[];
    _naprave
      ..clear()
      ..addEntries(s.map((d) => MapEntry(d.id, d)));
    return [
      for (final d in s)
        NapravaMidi(d.id, d.name, switch (d.type) {
          MidiDeviceType.ble => 'Bluetooth',
          MidiDeviceType.serial => 'USB',
          MidiDeviceType.virtual => 'Navidezna',
          _ => '',
        }, d.connected),
    ];
  }

  @override
  Future<void> zacniIskanje() async {
    if (!_bluetooth) return;
    await _m.startBluetooth();
    await _m.waitUntilBluetoothIsInitialized().timeout(const Duration(seconds: 5), onTimeout: () {});
    if (_m.bluetoothState != BluetoothState.poweredOn) {
      throw StateError('Bluetooth ni vklopljen ali aplikacija nima dovoljenja.');
    }
    await _m.startScanningForBluetoothDevices();
  }

  @override
  void ustaviIskanje() {
    if (!_bluetooth || _midi == null) return;
    try {
      _m.stopScanningForBluetoothDevices();
    } catch (_) {}
  }

  @override
  Future<void> povezi(String id) async {
    final d = _naprave[id];
    if (d != null) await _m.connectToDevice(d);
  }

  @override
  void prekini(String id) {
    final d = _naprave[id];
    if (d != null) _m.disconnectDevice(d);
  }

  @override
  void poslji(Uint8List bajti, String id) => _m.sendData(bajti, deviceId: id);

  @override
  Stream<void> get spremembe => _m.onMidiSetupChanged ?? const Stream.empty();

  @override
  Stream<(String, Uint8List)> get prejeto =>
      _m.onMidiPacketReceived?.map((p) => (p.device.name, p.data)) ?? const Stream.empty();
}
