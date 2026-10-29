import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Googlov gumb za prijavo v brskalniku (prijava brez njega v brskalniku ni mogoča).
Widget? gumbPrijaveBrskalnika() => web.renderButton(
  configuration: web.GSIButtonConfiguration(
    theme: web.GSIButtonTheme.filledBlack,
    size: web.GSIButtonSize.large,
    text: web.GSIButtonText.signinWith,
    locale: 'sl',
  ),
);
