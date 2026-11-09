"""Poišče YouTube videe za pesmi (yt-dlp ytsearch). Vhod: JSON [{"id","q"}], izhod: JSON z do 5 zadetki na pesem."""
import json
import subprocess
import sys

vhod = json.load(open(sys.argv[1], encoding="utf-8"))
izhod = []
for p in vhod:
    try:
        r = subprocess.run(
            ["yt-dlp", "--flat-playlist", "-J", "--no-warnings", f"ytsearch5:{p['q']}"],
            capture_output=True, text=True, timeout=90,
        )
        zadetki = [
            {"v": e.get("id"), "t": e.get("title"), "k": e.get("channel") or e.get("uploader"), "d": e.get("duration")}
            for e in (json.loads(r.stdout).get("entries") or [])
        ] if r.returncode == 0 else []
        napaka = None if r.returncode == 0 else r.stderr[-300:]
    except Exception as e:  # noqa: BLE001
        zadetki, napaka = [], str(e)
    izhod.append({**p, "z": zadetki, "napaka": napaka})
    print(p["q"], "->", zadetki[0]["t"] if zadetki else napaka, flush=True)
json.dump(izhod, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
