# Špadni besedila

Aplikacija za besedila, PDF-je in setliste ansambla Špadni fantje (po vzoru SongBook in BandHelper).
Podatki so v Google preglednici **Besedila baza** (mapa APLIKACIJA BESEDILA na Drivu računa skupine),
do nje aplikacija dostopa prek Apps Script skripte `besedila-api.gs`.

## Kaj zna različica 0.1

- prijava z Google računom (dostop imajo samo člani z lista Člani),
- prenos pesmi, besedil in PDF-jev v tablico,
- prikaz brez interneta: iskanje po kodi, naslovu in izvajalcu, filter po zvrsti,
- PDF ali besedilo z akordi v oglatih oklepajih (`[C]Belo obleko si [G]že nosila`), nastavljiva pisava.

Sledi: sinhronizacija na špilu, MIDI, risanje, setliste.

## Gradnja

APK se zgradi sam ob vsaki spremembi na veji `main` (GitHub Actions) in se objavi na strani **Releases**.

Potrebne nastavitve repozitorija (Settings → Secrets and variables → Actions):

| Vrsta | Ime | Vsebina |
|---|---|---|
| Secret | `ANDROID_KEYSTORE_BASE64` | podpisni ključ (base64) |
| Secret | `ANDROID_KEYSTORE_PASSWORD` | geslo ključa |
| Variable | `GOOGLE_SERVER_CLIENT_ID` | OAuth client ID vrste *Web application* iz Google Cloud |

Lokalno: `flutter test`, `flutter build apk --dart-define=GOOGLE_SERVER_CLIENT_ID=...`.
