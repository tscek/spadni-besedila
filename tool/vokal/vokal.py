"""Odstranitev vokala iz playbacka pesmi (Demucs, model htdemucs, samo procesor).

Prenese playback prek skripte (playbackZaVokal), ga razdeli na vokal in spremljavo ter
spremljavo (no_vocals) kot MP3 vrne skripti (playbackBrezVokala). Ob napaki zapiše stanje (playbackNapaka).

Okolje: API_URL, UPLOAD_KLJUC, PESEM.
"""

import base64
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import requests

KONCNICE = {'audio/mpeg': 'mp3', 'audio/mp3': 'mp3', 'audio/wav': 'wav', 'audio/x-wav': 'wav', 'audio/ogg': 'ogg',
            'audio/webm': 'webm', 'audio/flac': 'flac', 'audio/aac': 'aac'}


def skripta(telo: dict, poskusov: int = 4) -> dict:
    telo = {**telo, 'kljuc': os.environ['UPLOAD_KLJUC']}
    for p in range(poskusov):
        try:
            r = requests.post(os.environ['API_URL'], data=json.dumps(telo), headers={'Content-Type': 'text/plain'},
                              timeout=300)
            j = r.json()
            if 'napaka' in j:
                raise RuntimeError(j['napaka'])
            return j
        except (requests.RequestException, ValueError) as e:
            if p == poskusov - 1:
                raise
            print(f'  skripta: {e}, ponovno čez {2 ** p * 5} s', flush=True)
            time.sleep(2 ** p * 5)
    raise AssertionError


def main() -> int:
    pesem = os.environ['PESEM'].strip()
    try:
        izvirnik = skripta({'akcija': 'playbackZaVokal', 'pesem': pesem})
        print(f"Pesem: {izvirnik.get('naslov', pesem)} ({izvirnik.get('vrsta')})", flush=True)
        mapa = Path(tempfile.mkdtemp())
        vhod = mapa / f"playback.{KONCNICE.get(izvirnik.get('vrsta', ''), 'm4a')}"
        vhod.write_bytes(base64.b64decode(izvirnik['base64']))
        # Demucs bere le, kar zna torchaudio; vse najprej v WAV (ffmpeg).
        wav = mapa / 'playback.wav'
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(vhod), '-ar', '44100',
                        '-ac', '2', str(wav)], check=True)
        subprocess.run([sys.executable, '-m', 'demucs', '--two-stems=vocals', '-n', 'htdemucs', '--mp3',
                        '--mp3-bitrate', '256', '-o', str(mapa / 'izhod'), str(wav)], check=True)
        brez = next((mapa / 'izhod').rglob('no_vocals.mp3'))
        print(f'Brez vokala: {brez.stat().st_size // 1024} KB', flush=True)
        skripta({'akcija': 'playbackBrezVokala', 'pesem': pesem, 'vrsta': 'audio/mpeg',
                 'base64': base64.b64encode(brez.read_bytes()).decode()})
        print('Shranjeno.')
        return 0
    except Exception as e:  # noqa: BLE001 - vsako napako zapišemo k pesmi
        print(f'::error::{e}', flush=True)
        try:
            skripta({'akcija': 'playbackNapaka', 'pesem': pesem, 'sporocilo': f'odstranitev vokala ni uspela ({e})'})
        except Exception as e2:  # noqa: BLE001
            print(f'Stanja ni bilo mogoče zapisati: {e2}')
        return 1


if __name__ == '__main__':
    sys.exit(main())
