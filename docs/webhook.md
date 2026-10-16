# Webhook (z. B. n8n)

Blitztext kann fertige Transkripte als JSON an einen Webhook schicken. Was danach
passiert, entscheidet dein Workflow: analysieren, zusammenfassen, in die
Wissensdatenbank ablegen, Aufgaben anlegen.

Blitztext selbst analysiert nichts und speichert nichts auf einem Server.

## Einrichten

1. **Einstellungen → Anpassen → Webhook (z. B. n8n)** einschalten.
2. **Webhook-URL** eintragen. Über das Netz nur `https://`. Unverschlüsseltes
   `http://` ist nur für `localhost` / `127.0.0.1` erlaubt.
3. Optional ein **Token**. Blitztext schickt es im Header `X-Blitztext-Token`.
   In n8n am Webhook-Knoten *Authentication → Header Auth* mit Name
   `X-Blitztext-Token` und demselben Wert einstellen.
4. Unter **Automatisch senden** wählen, was rausgeht:
   - **Sprachnachrichten** (Datei-Transkription, auch „Öffnen mit → Blitztext“) — ab Werk gewählt
   - **Diktate** (Blitztext, Blitztext Lokal)
   - **Umformungen** (Blitztext+, $%&!, :)) — es wird das umgeformte Ergebnis gesendet
5. **Testnachricht senden**. Sie hat `"isTest": true`; dein Workflow kann sie daran
   erkennen und verwerfen.

Sprachnachrichten, die nicht automatisch rausgehen, lassen sich nach dem
Transkribieren einzeln mit **An Webhook senden** übergeben. Schlägt der Versand
fehl, steht der Grund unter dem Transkript, daneben **Erneut senden**.

URL und Token liegen im macOS-Schlüsselbund, nicht in der `settings.json`. Eine
n8n-Webhook-URL ist selbst ein Geheimnis: Wer sie kennt, kann in deinen Workflow
schreiben.

### n8n: Test-URL vs. Produktions-URL

n8n zeigt am Webhook-Knoten zwei URLs. Die **Test-URL** (`…/webhook-test/…`) nimmt
nur etwas an, solange im Editor „Listen for test event“ läuft. Für den Alltag die
**Produktions-URL** (`…/webhook/…`) eintragen und den Workflow **aktivieren**.
Blitztext warnt, wenn eine Test-URL eingetragen ist. Ein `404` heißt fast immer:
Der Workflow ist nicht aktiv.

## Nutzlast (`blitztext.transcript.v1`)

`POST` mit `Content-Type: application/json`. Felder ohne Wert werden weggelassen.

```json
{
  "schema": "blitztext.transcript.v1",
  "id": "A2A373D3-EE38-451C-8002-594C988C92C9",
  "source": "voiceMessage",
  "sourceLabel": "Sprachnachricht",
  "createdAt": "2026-10-16T18:22:53Z",
  "text": "Das vollständige Transkript …",
  "language": "de",
  "transcription": "local",
  "fileName": "Aufnahme 232.m4a",
  "recordedAt": "2026-10-16T18:22:37Z",
  "durationSeconds": 2.76,
  "segments": [
    { "start": 0, "end": 1.2, "text": "Das vollständige" }
  ],
  "app": { "name": "Blitztext", "version": "1.8.0" },
  "isTest": false
}
```

| Feld | Bedeutung |
|---|---|
| `schema` | Version des Formats. Felder kommen nur hinzu; ändert sich etwas, ändert sich auch die Version. |
| `id` | Eindeutig je Versand. Damit erkennt dein Workflow doppelte Zustellungen, z. B. nach „Erneut senden“. |
| `source` | `voiceMessage`, `dictation` oder `rewrite` |
| `workflow` | Nur bei Diktat/Umformung: `transcription`, `localTranscription`, `textImprover`, `dampfAblassen`, `emojiText` |
| `createdAt` | Zeitpunkt des Versands (ISO 8601, UTC) |
| `text` | Das fertige Transkript bzw. die Umformung. |
| `transcription` | `local` (auf dem Mac) oder `openai` |
| `fileName` | Nur bei Sprachnachrichten: Name der Originaldatei |
| `recordedAt` | Aufnahmezeitpunkt **aus den Audio-Metadaten**, nie aus dem Dateisystem. Bei Exporten ist der Dateizeitstempel das Exportdatum. Fehlt das Feld, ist der Zeitpunkt unbekannt. |
| `durationSeconds` | Länge der Aufnahme |
| `segments` | Nur im lokalen Modus: Abschnitte mit Zeitstempeln in Sekunden |
| `isTest` | `true` nur bei der Testnachricht aus den Einstellungen |

In n8n liegt das unter `{{ $json.body.text }}`, `{{ $json.body.recordedAt }}` usw.

## Datenschutz

Was du zum Senden auswählst, verlässt den Mac **als Klartext**. Das gilt auch im
**Sicheren Lokalen Modus**: Der schützt die Transkription, nicht die Weitergabe,
die du selbst einschaltest. Blitztext zeigt dazu in den Einstellungen einen
Hinweis.

Wenn dein Workflow in ein Git-Repository mit `git-crypt` schreibt: Ein Commit über
die GitHub-API umgeht die Verschlüsselung. Die Datei liegt dann im Klartext in der
Historie.
