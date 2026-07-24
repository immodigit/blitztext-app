# Blitztext über Homebrew installieren

Blitztext wird über einen **eigenen Tap** verteilt (kein offizielles homebrew-cask —
das verlangt zusätzlich „Notability", also eine gewisse Bekanntheit der App).

```sh
brew install --cask immodigit/blitztext/blitztext
```

Das setzt einmalig einen Tap voraus (macht Homebrew beim ersten Befehl automatisch),
der auf das Repo `github.com/immodigit/homebrew-blitztext` zeigt.

---

## Empfohlen: Release über GitHub Actions

Der Workflow [`.github/workflows/release.yml`](../.github/workflows/release.yml) baut,
**signiert und notarisiert** das DMG in der Cloud, veröffentlicht das GitHub Release
und aktualisiert (optional) die Cask im Tap-Repo. Du brauchst lokal dann **kein**
Zertifikat mehr.

### Einmalig: Repository-Secrets anlegen

Unter `github.com/immodigit/blitztext-app` → Settings → Secrets and variables → Actions:

| Secret | Inhalt |
|---|---|
| `MACOS_CERTIFICATE_P12` | base64 des exportierten „Developer ID Application"-Zertifikats (`.p12`) |
| `MACOS_CERTIFICATE_PWD` | Passwort des `.p12`-Exports |
| `NOTARY_APPLE_ID` | Apple-ID für die Notarisierung (`info@immojump.de`) |
| `NOTARY_TEAM_ID` | 10-stellige Team-ID |
| `NOTARY_PWD` | App-spezifisches Passwort (account.apple.com) |
| `TAP_GITHUB_TOKEN` | *(optional)* PAT mit `repo`-Schreibrecht auf `immodigit/homebrew-blitztext` |

**Zertifikat als `.p12` exportieren** (einmalig auf einem Mac mit dem Cert in der Keychain):

```sh
# Schlüsselbund → "Developer ID Application"-Eintrag + zugehörigen privaten Schlüssel
# markieren → Rechtsklick → "2 Objekte exportieren" → .p12 mit Passwort speichern.
base64 -i DeveloperID.p12 | pbcopy   # → als MACOS_CERTIFICATE_P12 einfügen
```

### Release auslösen

```sh
# MARKETING_VERSION in BlitztextMac/project.yml muss zum Tag passen (z. B. 1.5 → v1.5).
git tag v1.5 && git push origin v1.5
```

Oder manuell über Actions → „Release" → „Run workflow". Der Rest läuft automatisch:
DMG bauen → notarisieren → Release veröffentlichen → Cask aktualisieren.

---

## Alternative: Release von Hand (lokal)

Nur nötig, wenn du **nicht** über CI baust.

### Einmalige Einrichtung (für dich als Entwickler)

### 1. Voraussetzungen für die Notarisierung

Ohne diese Schritte blockt Gatekeeper die per `brew` installierte App.

- **Apple Developer Program** ($99/Jahr) → https://developer.apple.com/programs/
- **„Developer ID Application"-Zertifikat** in der Keychain
  (Xcode → Settings → Accounts → Manage Certificates → „+" → Developer ID Application,
  oder über das Developer-Portal erzeugen und importieren).
- **Notar-Zugang als Keychain-Profil** (App-spezifisches Passwort unter
  https://account.apple.com → Anmeldung & Sicherheit → App-spezifische Passwörter):

  ```sh
  xcrun notarytool store-credentials "blitztext-notary" \
    --apple-id "info@immojump.de" \
    --team-id "DEINE_TEAM_ID" \
    --password "xxxx-xxxx-xxxx-xxxx"
  ```

### 2. Release bauen

Team-ID und Signatur-Namen findest du mit `security find-identity -v -p codesigning`.

```sh
BLITZTEXT_SIGN_IDENTITY="Developer ID Application: Dein Name (DEINE_TEAM_ID)" \
BLITZTEXT_NOTARY_PROFILE="blitztext-notary" \
./make-release.sh
```

Das Skript baut, signiert mit Hardened Runtime, verpackt als DMG, notarisiert,
heftet das Ticket an und gibt am Ende **Version + SHA256** aus.

### 3. GitHub Release veröffentlichen

```sh
gh release create v1.5 "Blitztext-1.5.dmg" \
  --title "Blitztext 1.5" \
  --notes "Transkript-Verlauf, festes Status-Overlay, sauberere lokale Umformung."
```

### 4. Tap-Repo einrichten (nur beim allerersten Mal)

Homebrew-Taps müssen `homebrew-` im Namen tragen:

```sh
# Neues Repo github.com/immodigit/homebrew-blitztext anlegen, dann:
mkdir -p homebrew-blitztext/Casks
cp homebrew/Casks/blitztext.rb homebrew-blitztext/Casks/
cd homebrew-blitztext
git init && git add . && git commit -m "Blitztext Cask"
gh repo create immodigit/homebrew-blitztext --public --source=. --push
```

### 5. Bei jedem neuen Release

1. `./make-release.sh` ausführen
2. In `Casks/blitztext.rb` `version` und `sha256` aktualisieren
3. GitHub Release hochladen + Cask-Repo pushen

Testen vor dem Push:

```sh
brew install --cask ./homebrew/Casks/blitztext.rb   # lokal aus der Datei
brew audit --cask --new ./homebrew/Casks/blitztext.rb
```

---

**Hinweis zum Owner:** Die URLs zeigen auf die Organisation `immodigit`
(Remote `git@github.com:immodigit/blitztext-app.git`). Sowohl das Code-Repo
`immodigit/blitztext-app` (Releases/DMG) als auch der Tap `immodigit/homebrew-blitztext`
liegen dort. Ein persönliches Fork-Remote (`cmagnussen`) existiert daneben, ist
aber nicht der Vertriebsort.
