/// V brskalniku posodobitev Windows ni mogoča.
Future<void> namestiWindows(String url, void Function(int odstotek) napredek) async =>
    throw UnsupportedError('Posodobitev Windows ni na voljo v brskalniku');

/// V brskalniku ni namestitve.
Future<bool> dokoncajNamestitev(List<String> argumenti) async => false;
