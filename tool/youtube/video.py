"""Video posnetega špila za YouTube.

Iz skripte (Apps Script) vzame posnete špile brez videa, prenese kose zvoka, s ffmpeg naredi video
(logotip, naslov špila, tekoča ura, naslov trenutne pesmi), ga naloži na YouTube kot zasebnega
s poglavji (pesmi) v opisu in skripti vrne ID videa. Skripta nato kose z Drive pobriše.

Okolje: API_URL, UPLOAD_KLJUC, YT_CLIENT_ID, YT_CLIENT_SECRET, YT_REFRESH_TOKEN.
Brez YouTube skrivnosti (ali z --suho) video samo naredi in ga pusti v mapi --izhod.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import requests

PISAVA = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
PISAVA_KREPKO = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
LOGO = Path(__file__).resolve().parents[2] / 'assets' / 'ikona' / 'ikona.png'
SIRINA, VISINA = 1280, 720


def cas(s: str) -> datetime:
    return datetime.fromisoformat(s.replace('Z', '+00:00')).astimezone(timezone.utc)


@dataclass
class Kos:
    i: int
    zacetek: datetime
    sekund: float  # dejansko trajanje datoteke (ffprobe)
    pot: Path


@dataclass
class Pesem:
    odmik: float  # sekunde v videu
    naslov: str


# ---------- skripta ----------


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


# ---------- časi ----------


def odmik(kosi: list[Kos], t: datetime) -> float:
    """Mesto v videu za trenutek t: pavze med kosi so izpuščene."""
    pred = 0.0
    for k in kosi:
        od = (t - k.zacetek).total_seconds()
        if od < 0:
            return pred
        if od <= k.sekund:
            return pred + od
        pred += k.sekund
    return pred


def pesmi_v_videu(kosi: list[Kos], igranja: list[dict]) -> list[Pesem]:
    out: list[Pesem] = []
    for ig in sorted(igranja, key=lambda x: x['cas']):
        naslov = (ig.get('naslov') or '').strip()
        if not naslov:
            continue
        o = odmik(kosi, cas(ig['cas']))
        if out and out[-1].naslov == naslov:
            continue
        # Pesem, ki se zamenja v nekaj sekundah, je bila le odprta: velja zadnja.
        if out and o - out[-1].odmik < 10:
            out[-1] = Pesem(out[-1].odmik, naslov)
        else:
            out.append(Pesem(o, naslov))
    return out


def hms(s: float) -> str:
    s = int(s)
    h, m, sek = s // 3600, s // 60 % 60, s % 60
    return f'{h}:{m:02d}:{sek:02d}' if h else f'{m}:{sek:02d}'


def poglavja(pesmi: list[Pesem]) -> list[str]:
    """Poglavja za opis: prvo mora biti 0:00, vsaj tri, vsako vsaj 10 s."""
    vrstice = [(0.0, 'Začetek')]
    for p in pesmi:
        if p.odmik < 10:
            vrstice[0] = (0.0, p.naslov)
        elif p.odmik - vrstice[-1][0] >= 10:
            vrstice.append((p.odmik, p.naslov))
    if len(vrstice) < 3:
        return []
    return [f'{hms(o)} {n}' for o, n in vrstice]


def cisto(s: str) -> str:
    """YouTube ne sprejme < in > v naslovu in opisu."""
    return s.replace('<', '‹').replace('>', '›')


# ---------- video ----------


def trajanje(pot: Path) -> float:
    r = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(pot)],
                       capture_output=True, text=True, check=True)
    return float(r.stdout.strip())


def ubezi(s: str) -> str:
    """Pot ali besedilo v vrednosti možnosti filtra ffmpeg."""
    return s.replace('\\', '\\\\').replace(':', '\\:').replace("'", "\\'")


def sirina_besedila(besedilo: str, pisava: str, velikost: int) -> float:
    try:
        from PIL import ImageFont
        return max(ImageFont.truetype(pisava, velikost).getlength(v) for v in besedilo.split('\n'))
    except (ImportError, OSError):
        return max(len(v) for v in besedilo.split('\n')) * velikost * 0.62


def prilagodi(besedilo: str, pisava: str, velikost: int, sirina: int, najmanj: int) -> tuple[str, int]:
    """Pomanjša pisavo, da besedilo gre v širino; predolgo razdeli v dve vrstici."""
    besedilo = ' '.join(besedilo.split())
    v = velikost
    while v > najmanj and sirina_besedila(besedilo, pisava, v) > sirina:
        v -= 2
    if sirina_besedila(besedilo, pisava, v) <= sirina:
        return besedilo, v
    # Predolgo: razdeli po besedah v več vrstic (največ tri).
    vrstice: list[str] = []
    for beseda in besedilo.split(' '):
        if vrstice and sirina_besedila(vrstice[-1] + ' ' + beseda, pisava, v) <= sirina:
            vrstice[-1] += ' ' + beseda
        else:
            vrstice.append(beseda)
    if len(vrstice) > 3:
        vrstice = vrstice[:3]
        vrstice[-1] += ' …'
    return '\n'.join(vrstice), v


def naredi_video(naslov: str, zasedba: str, kosi: list[Kos], pesmi: list[Pesem], mapa: Path) -> Path:
    mapa.mkdir(parents=True, exist_ok=True)
    seznam = mapa / 'kosi.txt'
    seznam.write_text(''.join(f"file '{k.pot.resolve()}'\n" for k in kosi), encoding='utf-8')
    skupaj = sum(k.sekund for k in kosi)

    def besedilo(ime: str, vsebina: str) -> str:
        p = mapa / ime
        p.write_text(vsebina, encoding='utf-8')
        return ubezi(str(p))

    def napis(ime: str, vsebina: str, pisava: str, velikost: int, barva: str, y: int, najmanj: int,
              kdaj: str = '') -> None:
        tekst, v = prilagodi(vsebina, pisava, velikost, SIRINA - levo - 40, najmanj)
        dodaj(f"drawtext=fontfile={pisava}:textfile='{besedilo(ime, tekst)}':expansion=none"
              f':fontsize={v}:fontcolor={barva}:line_spacing=8:x={levo}:y={y}{kdaj}')

    levo = 440
    f = [f'color=c=0x15171c:s={SIRINA}x{VISINA}:r=2:d={skupaj + 1:.3f}[ozadje]',
         f'[1:v]scale=300:300[logo]',
         '[ozadje][logo]overlay=x=80:y=(H-h)/2-40[v0]']
    zadnji = 'v0'

    def dodaj(filter_: str) -> None:
        nonlocal zadnji
        f.append(f'[{zadnji}]{filter_}[v{len(f)}]')
        zadnji = f'v{len(f) - 1}'

    napis('naslov.txt', naslov, PISAVA_KREPKO, 40, 'white', 140, 26)
    if zasedba and zasedba not in naslov:
        napis('zasedba.txt', zasedba, PISAVA, 30, '0xb0b4bc', 200, 22)
    # Ura: vsak kos ima svoj začetek (pavze so izpuščene), zato po en drawtext na kos.
    od = 0.0
    for k in kosi:
        osnova = k.zacetek.timestamp() - od
        dodaj(f"drawtext=fontfile={PISAVA_KREPKO}:text='%{{pts\\:localtime\\:{osnova:.3f}\\:%H\\\\\\:%M\\\\\\:%S}}'"
              f":fontsize=110:fontcolor=white:x={levo}:y=290:enable='between(t,{od:.3f},{od + k.sekund:.3f})'")
        od += k.sekund
    for j, p in enumerate(pesmi):
        do = pesmi[j + 1].odmik if j + 1 < len(pesmi) else skupaj + 1
        napis(f'pesem{j:03d}.txt', p.naslov, PISAVA, 48, '0xffd166', 470, 30,
              f":enable='between(t,{p.odmik:.3f},{do:.3f})'")
    filtri = mapa / 'filtri.txt'
    filtri.write_text(';\n'.join(f), encoding='utf-8')

    izhod = mapa / 'video.mp4'
    ukaz = ['ffmpeg', '-hide_banner', '-loglevel', 'warning', '-stats', '-y',
            '-f', 'concat', '-safe', '0', '-i', str(seznam),
            '-loop', '1', '-framerate', '2', '-i', str(LOGO),
            '-filter_complex_script', str(filtri),
            '-map', f'[{zadnji}]', '-map', '0:a',
            '-c:v', 'libx264', '-preset', 'veryfast', '-tune', 'stillimage', '-pix_fmt', 'yuv420p', '-r', '2',
            '-c:a', 'copy', '-t', f'{skupaj:.3f}', '-movflags', '+faststart', str(izhod)]
    okolje = {**os.environ, 'TZ': 'Europe/Ljubljana'}
    # Kosi so AAC iz istega snemalnika, zato se zvok le prepiše; če ne gre, se kodira znova.
    if subprocess.run(ukaz, env=okolje).returncode != 0:
        i = ukaz.index('copy')
        subprocess.run(ukaz[:i] + ['aac', '-b:a', '160k'] + ukaz[i + 1:], check=True, env=okolje)
    return izhod


# ---------- YouTube ----------


def youtube_zeton() -> str:
    r = requests.post('https://oauth2.googleapis.com/token', data={
        'client_id': os.environ['YT_CLIENT_ID'], 'client_secret': os.environ['YT_CLIENT_SECRET'],
        'refresh_token': os.environ['YT_REFRESH_TOKEN'], 'grant_type': 'refresh_token'}, timeout=60)
    if r.status_code != 200:
        raise RuntimeError(f'YouTube prijava ni uspela: {r.text}')
    return r.json()['access_token']


def nalozi_youtube(video: Path, naslov: str, opis: str) -> str:
    zeton = youtube_zeton()
    meta = {
        'snippet': {'title': cisto(naslov)[:100], 'description': cisto(opis)[:4900], 'categoryId': '10'},
        'status': {'privacyStatus': 'private', 'selfDeclaredMadeForKids': False},
    }
    velikost = video.stat().st_size
    r = requests.post('https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status',
                      headers={'Authorization': f'Bearer {zeton}', 'Content-Type': 'application/json; charset=UTF-8',
                               'X-Upload-Content-Type': 'video/mp4', 'X-Upload-Content-Length': str(velikost)},
                      data=json.dumps(meta), timeout=60)
    if r.status_code != 200:
        raise RuntimeError(f'YouTube ni sprejel nalaganja: {r.status_code} {r.text}')
    url = r.headers['Location']
    kos = 32 * 1024 * 1024
    poslano = 0
    napake = 0
    with video.open('rb') as f:
        while poslano < velikost:
            f.seek(poslano)
            podatki = f.read(kos)
            konec = poslano + len(podatki) - 1
            try:
                r = requests.put(url, data=podatki, timeout=600, headers={
                    'Authorization': f'Bearer {zeton}', 'Content-Range': f'bytes {poslano}-{konec}/{velikost}'})
            except requests.RequestException as e:
                r = None
                print(f'  nalaganje: {e}', flush=True)
            if r is not None and r.status_code in (200, 201):
                return r.json()['id']
            if r is not None and r.status_code == 308:
                obseg = r.headers.get('Range')
                poslano = int(obseg.split('-')[1]) + 1 if obseg else 0
                napake = 0
                print(f'  naloženo {poslano * 100 // velikost} %', flush=True)
                continue
            napake += 1
            if napake > 5:
                raise RuntimeError(f'Nalaganje na YouTube ni uspelo: {r.status_code if r else ""} {r.text if r else ""}')
            time.sleep(2 ** napake)
            # Vprašamo, koliko je YouTube že prejel.
            q = requests.put(url, timeout=60, headers={'Authorization': f'Bearer {zeton}',
                                                       'Content-Range': f'bytes */{velikost}'})
            if q.status_code in (200, 201):
                return q.json()['id']
            obseg = q.headers.get('Range')
            poslano = int(obseg.split('-')[1]) + 1 if obseg else 0
    raise RuntimeError('Nalaganje na YouTube se je končalo brez ID-ja')


# ---------- glavno ----------


def opis_videa(s: dict, kosi: list[Kos], pesmi: list[Pesem]) -> str:
    zacetek = kosi[0].zacetek.astimezone()
    vrstice = [s['Naslov']]
    if s.get('ZasedbaIme'):
        vrstice.append(s['ZasedbaIme'])
    vrstice.append(f'Posneto {zacetek:%-d. %-m. %Y}, posnetek aplikacije Špadni besedila.')
    pog = poglavja(pesmi)
    if pog:
        vrstice += ['', 'Pesmi:', *pog]
    return '\n'.join(vrstice)


def obdelaj(s: dict, izhod: Path, suho: bool) -> None:
    print(f"== {s['ID']}: {s['Naslov']} ({len(s['Kosi'])} kosov, {len(s['igranja'])} igranj)", flush=True)
    mapa = izhod / s['ID']
    mapa.mkdir(parents=True, exist_ok=True)
    kosi: list[Kos] = []
    for k in sorted(s['Kosi'], key=lambda x: x['i']):
        pot = mapa / f"{k['i']:03d}.m4a"
        if not pot.exists():
            j = skripta({'akcija': 'kosSnemanja', 'id': s['ID'], 'd': k['d']})
            pot.write_bytes(base64.b64decode(j['base64']))
        kosi.append(Kos(k['i'], cas(k['z']), trajanje(pot), pot))
        print(f'  kos {k["i"]}: {kosi[-1].sekund:.1f} s', flush=True)
    pesmi = pesmi_v_videu(kosi, s['igranja'])
    video = naredi_video(s['Naslov'], s.get('ZasedbaIme', ''), kosi, pesmi, mapa)
    opis = opis_videa(s, kosi, pesmi)
    print(opis, flush=True)
    if suho:
        print(f'  video: {video} (brez nalaganja)', flush=True)
        return
    yt = nalozi_youtube(video, s['Naslov'], opis)
    print(f'  YouTube: https://youtu.be/{yt}', flush=True)
    skripta({'akcija': 'snemanjeVideo', 'id': s['ID'], 'youtube': yt}, poskusov=8)
    video.unlink()  # je na YouTubu; ne gre med artefakte gradnje


def stanje(s: dict, video: str, suho: bool) -> None:
    """Stanje videa v listu Snemanja (aplikacija ga pokaže); stara skripta ga ne pozna, zato napaka ne ustavi."""
    if suho:
        return
    try:
        skripta({'akcija': 'snemanjeStanje', 'id': s['ID'], 'video': video}, poskusov=2)
    except Exception as e:  # noqa: BLE001
        print(f'  stanje ni zapisano: {e}', flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--izhod', type=Path, default=Path('video'))
    ap.add_argument('--suho', action='store_true', help='samo naredi video, brez YouTuba in zapisa v skripto')
    ap.add_argument('--podatki', type=Path, help='JSON s snemanji namesto skripte (preizkus)')
    a = ap.parse_args()
    suho = a.suho or not os.environ.get('YT_REFRESH_TOKEN')
    if a.podatki:
        snemanja = json.loads(a.podatki.read_text(encoding='utf-8'))['snemanja']
    else:
        snemanja = skripta({'akcija': 'snemanjaZaVideo'})['snemanja']
    if not snemanja:
        print('Ni posnetih špilov brez videa.')
        return 0
    napake = 0
    for s in snemanja:
        try:
            stanje(s, 'obdelava', suho)
            obdelaj(s, a.izhod, suho)
        except Exception as e:  # noqa: BLE001 - en neuspel špil ne ustavi ostalih
            napake += 1
            print(f'::error::{s["ID"]}: {e}', flush=True)
            stanje(s, f'napaka: {e}', suho)
    return 1 if napake else 0


if __name__ == '__main__':
    sys.exit(main())
