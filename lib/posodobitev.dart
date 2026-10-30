import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api.dart';
import 'posodobitev_windows_web.dart' if (dart.library.io) 'posodobitev_windows_io.dart';

/// Preveri, ali je na Drivu novejša različica aplikacije (Android ali Windows), in jo namesti.
class Posodobitev extends ChangeNotifier {
  int? trenutna;
  int? nova;
  String? _url;

  /// Napredek prenosa v odstotkih, dokler poteka.
  int? napredek;
  String? napaka;

  bool get naVoljo => nova != null && trenutna != null && nova! > trenutna!;

  static bool get _windows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> preveri(Api api) async {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && !_windows)) return;
    try {
      trenutna = int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
      final odg = await api.verzija(platforma: _windows ? 'windows' : null);
      // Stara skripta ne pozna Windows in vrne različico APK-ja.
      if (_windows && odg['platforma'] != 'windows') return;
      nova = (odg['verzija'] as num?)?.toInt();
      _url = odg['url'] as String?;
      notifyListeners();
    } catch (_) {
      // Brez interneta ali brez objavljene različice: poskusimo ob naslednji osvežitvi.
    }
  }

  void namesti() {
    final url = _url;
    if (url == null || napredek != null) return;
    napaka = null;
    napredek = 0;
    notifyListeners();
    if (_windows) {
      namestiWindows(url, (n) {
        napredek = n;
        notifyListeners();
      }).catchError((Object e) {
        napredek = null;
        napaka = 'Posodobitev ni uspela: $e';
        notifyListeners();
      });
      return;
    }
    OtaUpdate()
        .execute(url, destinationFilename: 'spadni-besedila.apk')
        .listen(
          (dogodek) {
            switch (dogodek.status) {
              case OtaStatus.DOWNLOADING:
                napredek = int.tryParse(dogodek.value ?? '') ?? napredek;
              case OtaStatus.INSTALLING:
              case OtaStatus.INSTALLATION_DONE:
                napredek = null;
              default:
                napredek = null;
                napaka =
                    'Posodobitev ni uspela (${dogodek.status.name}${dogodek.value != null ? ': ${dogodek.value}' : ''})';
            }
            notifyListeners();
          },
          onError: (Object e) {
            napredek = null;
            napaka = 'Posodobitev ni uspela: $e';
            notifyListeners();
          },
        );
  }
}
