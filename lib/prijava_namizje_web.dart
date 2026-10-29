/// V brskalniku namizne prijave ni (prijava gre prek Googlovega gumba).
class PrijavaNamizje {
  static bool get nastavljena => false;

  static Future<({String idZeton, String? osvezilni})> prijavi() => throw UnsupportedError('Ni na voljo');

  static Future<String> osvezi(String osvezilni) => throw UnsupportedError('Ni na voljo');
}
