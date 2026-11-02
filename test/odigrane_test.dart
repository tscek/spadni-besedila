import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spadni_besedila/odigrane.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('odigrane so skupne na špilu: sledilec pošlje vodji, vodja vsem', () async {
    final vodja = Odigrane();
    final sledilec = Odigrane();
    final poslano = <Map<String, dynamic>>[];
    await sledilec.oznaci('prej'); // pred povezavo

    // Ob povezavi sledilec pošlje svoje oznake, vodja jih združi in pošlje seznam nazaj.
    sledilec.vodji = poslano.add;
    await vodja.izvedi(sledilec.zaZdruzitev());
    await vodja.oznaci('a');
    await sledilec.prevzemi(vodja.vJson());
    expect(sledilec.je('prej') && sledilec.je('a'), isTrue);

    // Oznaka na sledilcu gre vodji in je takoj vidna tudi lokalno.
    await sledilec.oznaci('b');
    expect(sledilec.je('b'), isTrue);
    await vodja.izvedi(poslano.last);
    expect(vodja.je('b'), isTrue);

    // Počisti na sledilcu počisti pri vodji, ta pa vsem.
    await sledilec.ponastavi();
    await vodja.izvedi(poslano.last);
    await sledilec.prevzemi(vodja.vJson());
    expect(vodja.stevilo + sledilec.stevilo, 0);
  });
}
