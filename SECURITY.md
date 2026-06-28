# Sicherheit & Datenschutz

Kontor ist eine **local-first**-Buchhaltungs-App: deine Finanzdaten bleiben auf deinem Gerät.

## Datenhaltung

Alle Daten liegen im **sandboxed App-Container**:

```
~/Library/Containers/de.wiredframe.Kontor/Data/Library/Application Support/
├── default.store      # SwiftData-Datenbank (deine Buchhaltung)
├── Belege/<Jahr>/      # angehängte PDFs/Bilder
├── Backups/            # tägliche Auto-Backups (JSON, letzte 14 Tage)
└── KI-Backups/         # Backup vor dem ersten MCP-Schreibzugriff je Sitzung
```

- **Keine Telemetrie, kein Tracking, keine Analytics.**
- **Kein Netzwerkverkehr** – mit einer einzigen, optionalen Ausnahme: dem lokalen MCP-Server
  (siehe unten), der ausschließlich auf `127.0.0.1` (Loopback) lauscht.
- Backups werden **lokal** geschrieben; der manuelle Export landet dort, wohin du ihn speicherst.

## Optionaler MCP-Server (KI-Zugriff)

Unter *Einstellungen → KI-Zugriff (MCP)* lässt sich ein lokaler Server für externe KI-Clients
(z. B. Claude Code) **einschalten**. Er ist **standardmäßig aus**. Wenn aktiv:

- bindet **nur an Loopback** (`127.0.0.1`); Verbindungen von anderen Hosts werden abgewiesen;
- erfordert ein **Bearer-Token**, das in der **Keychain** gespeichert wird (nicht im Klartext);
  der Token-Vergleich ist konstantzeitig;
- begrenzt Anfragegröße (25 MB) und Verbindungsdauer (Timeout) gegen hängende/übergroße Requests;
- legt **vor dem ersten Schreibzugriff je Sitzung** automatisch ein Backup an (`KI-Backups/`).

Der Kontoauszug-Import läuft **nicht** über das MCP, sondern ausschließlich in-App.

## Entitlements (und warum)

| Entitlement | Zweck |
|-------------|-------|
| `com.apple.security.app-sandbox` | Standard-Sandboxing – die App läuft eingeschränkt. |
| `com.apple.security.files.user-selected.read-write` | Zugriff **nur** auf vom Nutzer per Dialog gewählte Dateien (Beleg-Import, CSV-Kontoauszug, Backup-Export/-Import). |
| `com.apple.security.network.server` | **Nur** für den optionalen lokalen MCP-Server (Loopback). Ohne aktivierten MCP wird nichts geöffnet. |

Hardened Runtime ist aktiv; Release-Builds werden mit *Developer ID* signiert und notarisiert.

## Eine Schwachstelle melden

Bitte **keine** öffentlichen Issues für Sicherheitslücken. Nutze stattdessen die
**GitHub Security Advisories** dieses Repositories („Report a vulnerability"). Wir bemühen uns
um eine zeitnahe Rückmeldung.
