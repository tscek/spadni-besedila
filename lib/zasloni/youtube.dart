import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// YouTube pri pesmi: majhno okno s predvajalnikom čez spodnji del besedila (Android, iOS, splet).
/// Na Windows vgrajenega predvajalnika ni, zato se povezava odpre v brskalniku.
class YoutubePesmi {
  /// Ali se video predvaja v aplikaciji (sicer v brskalniku).
  static bool get vAplikaciji =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  /// Za teste: nadomestni predvajalnik (prava spletna stran v testih ne deluje).
  static Widget Function(String id)? predvajalnikZaTest;

  static Future<void> odpriZunaj(String povezava, String id) => launchUrl(
    Uri.tryParse(povezava.contains('://') ? povezava : 'https://$povezava') ??
        Uri.parse('https://www.youtube.com/watch?v=$id'),
    mode: LaunchMode.externalApplication,
  );
}

/// Okno s predvajalnikom: video (YouTube zahteva, da je viden), gumb za YouTube in zapri.
class YoutubeOkno extends StatefulWidget {
  const YoutubeOkno({super.key, required this.id, required this.povezava, required this.zapri});

  final String id;
  final String povezava;
  final VoidCallback zapri;

  @override
  State<YoutubeOkno> createState() => _YoutubeOknoState();
}

class _YoutubeOknoState extends State<YoutubeOkno> {
  YoutubePlayerController? _k;

  @override
  void initState() {
    super.initState();
    if (YoutubePesmi.predvajalnikZaTest == null) {
      _k = YoutubePlayerController.fromVideoId(
        videoId: widget.id,
        autoPlay: true,
        params: const YoutubePlayerParams(showFullscreenButton: true, strictRelatedVideos: true),
      );
    }
  }

  @override
  void dispose() {
    _k?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sirina = (MediaQuery.sizeOf(context).width - 16).clamp(220.0, 400.0);
    final k = _k;
    return Material(
      key: const ValueKey('youtube-okno'),
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: sirina,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: k == null ? YoutubePesmi.predvajalnikZaTest!(widget.id) : YoutubePlayer(controller: k),
            ),
            Row(
              children: [
                const SizedBox(width: 8),
                const Expanded(child: Text('YouTube', overflow: TextOverflow.ellipsis)),
                IconButton(
                  key: const ValueKey('youtube-zunaj'),
                  tooltip: 'Odpri v YouTube',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () {
                    YoutubePesmi.odpriZunaj(widget.povezava, widget.id);
                    widget.zapri();
                  },
                ),
                IconButton(
                  key: const ValueKey('youtube-zapri'),
                  tooltip: 'Zapri',
                  icon: const Icon(Icons.close),
                  onPressed: widget.zapri,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
