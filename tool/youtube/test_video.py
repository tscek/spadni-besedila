"""Preizkus časov v videu: python3 -m unittest tool/youtube/test_video.py"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from video import Kos, Pesem, cas, odmik, pesmi_v_videu, poglavja, prilagodi, PISAVA  # noqa: E402

KOSI = [Kos(0, cas('2026-11-02T19:00:00Z'), 600, Path('a')), Kos(1, cas('2026-11-02T19:20:00Z'), 600, Path('b'))]


class Casi(unittest.TestCase):
    def test_odmik_preskoci_pavzo(self):
        self.assertEqual(odmik(KOSI, cas('2026-11-02T19:05:00Z')), 300)
        self.assertEqual(odmik(KOSI, cas('2026-11-02T19:15:00Z')), 600)  # v pavzi: začetek naslednjega kosa
        self.assertEqual(odmik(KOSI, cas('2026-11-02T19:21:00Z')), 660)
        self.assertEqual(odmik(KOSI, cas('2026-11-02T18:55:00Z')), 0)

    def test_pesmi_in_poglavja(self):
        igranja = [
            {'cas': '2026-11-02T18:59:00Z', 'naslov': 'Prva'},
            {'cas': '2026-11-02T19:04:00Z', 'naslov': 'Le odprta'},
            {'cas': '2026-11-02T19:04:05Z', 'naslov': 'Druga'},
            {'cas': '2026-11-02T19:21:00Z', 'naslov': 'Tretja'},
        ]
        p = pesmi_v_videu(KOSI, igranja)
        self.assertEqual([x.naslov for x in p], ['Prva', 'Druga', 'Tretja'])
        self.assertEqual(poglavja(p), ['0:00 Prva', '4:00 Druga', '11:00 Tretja'])
        self.assertEqual(poglavja([Pesem(100, 'Ena')]), [])  # manj kot tri poglavja: brez

    def test_dolg_naslov_v_dveh_vrsticah(self):
        tekst, v = prilagodi('Zelo dolg naslov pesmi ' * 6, PISAVA, 48, 800, 30)
        self.assertEqual(v, 30)
        self.assertIn('\n', tekst)


if __name__ == '__main__':
    unittest.main()
