# Mx Project Template — Setup-Anleitung

Dieses Template enthält die Multi-Agent-Wissensarchitektur für neue Mendix-Projekte.

---

## Voraussetzungen (einmalig pro Entwicklermaschine)

Folgende Tools müssen installiert sein bevor du mit einem neuen Projekt startest:

### 1. mxcli installieren
mxcli ist das CLI-Tool für AI-gestützte Mendix-Entwicklung (MDL-Sprache, Lint, Check).

**Download:** [github.com/mxcli/releases](https://github.com/mxcli/releases) → `mxcli-windows-amd64.exe`

**PATH einrichten (einmalig, PowerShell als Admin):**
```powershell
# Dauerhaft in User-PATH eintragen (Terminal-Neustart nötig)
[Environment]::SetEnvironmentVariable(
  "PATH",
  [Environment]::GetEnvironmentVariable("PATH","User") + ";D:\Mendix\MxTools\Mx-CLI",
  "User"
)
```

**Für Git Bash** — in `~/.bashrc` ergänzen:
```bash
export PATH="$PATH:/c/Users/<USERNAME>/AppData/Roaming/npm"
# oder den Ordner wo mxcli liegt, z.B.:
export PATH="$PATH:/d/Mendix/MxTools/Mx-CLI"
```

**Testen:**
```bash
mxcli --version
```

---

### 2. Concord installieren (Mendix Marketplace)

Concord ist das MCP-Bridge-Tool zwischen Claude Code und Studio Pro. Es stellt:
- Mendix-Wissensfragen via `mx.ask` (grounded, versionskorrekt)
- IDE-Steuerung (App starten, Logs lesen, Editor-Tabs schließen)
- Lerngedächtnis für projektspezifische Best Practices

**Installation:**
1. Mendix Marketplace öffnen: `https://marketplace.mendix.com/` → suche **"Concord"**
2. Modul in Studio Pro importieren (wie jedes Marketplace-Modul)
3. Studio Pro einmal neu starten

**Was Concord nach der Installation tut:**
Concord schreibt automatisch eine `.mcp.json` im Projektstamm mit den projektspezifischen
Verbindungsparametern (Runtime-Fingerprint, Bridge-Token, SP-Version). Diese Datei
**nicht manuell bearbeiten** — Concord aktualisiert sie selbst.

Beispiel wie `.mcp.json` aussieht (wird von Concord generiert):
```json
{
  "mcpServers": {
    "concord-v2-mcp": {
      "command": "C:\\Users\\<USER>\\AppData\\Local\\Concord\\mcp-runtime\\<FINGERPRINT>\\win-x64\\Concord.Mcp.exe",
      "args": ["--stdio", "--runtime-fingerprint", "<FINGERPRINT>"],
      "env": {
        "CONCORD_SP_VERSION": "11.12.1",
        "CONCORD_PROJECT_ROOT": "<PROJEKTPFAD>",
        "CONCORD_BRIDGE_TOKEN": "<TOKEN>",
        "CONCORD_MCP_RUNTIME_FINGERPRINT": "<FINGERPRINT>"
      }
    }
  }
}
```

---

### 3. Studio Pro MCP (built-in, kein Install nötig)

Ab Studio Pro 11.11 ist ein MCP-Server eingebaut, der auf `localhost:7782` lauscht.
Er ermöglicht Live-Schreiboperationen ins geöffnete Projekt.

**Zugang von Claude Code:** Nicht direkt möglich (Streamable HTTP, kein `.mcp.json`-Support).
**Zugang über mxcli:**
```bash
mxcli --mcp http://localhost/mcp --mcp-dial localhost:7782 -p App.mpr -c "MDL-Befehl"
```
→ Vollständige Anleitung: `.ai-context/skills/live-edit-with-studio-pro.md`

---

### 4. Claude Code (VS Code Extension)

Download über VS Code Marketplace: **"Claude Code"** von Anthropic.

Nach Installation: VS Code neu starten. Claude Code lädt automatisch `.mcp.json` aus dem Projektordner.

---

## Setup-Reihenfolge für ein neues Projekt

### Schritt 1 — Template kopieren
```bash
cp -r .claude/templates/mx-project/. /pfad/zum/neuen/projekt/
```

### Schritt 2 — `projekt.md` ausfüllen
Pflichtabschnitte (alle mit `TODO` markiert):
- `## Projektziel` — Was soll das System leisten? Für wen?
- `## Tech Stack` — Mendix-Version, Deployment, Integrationen
- `## Module` — Alle Module mit Einzeiler-Beschreibung
- `## Sprint-Struktur` — Phasen und MVP-Definition
- `## Schlüsseldateien` — Wo liegt die Spezifikation?

### Schritt 3 — mxcli init ausführen (mit Projekt geöffnet in Studio Pro)
```bash
mxcli init /pfad/zum/projekt --tool claude
```
Legt an: `.ai-context/skills/`, `skillssource/_modules/` (je Modul), `AGENTS.md`.

> **Achtung:** Falls bereits eine `CLAUDE.md` existiert, sichert mxcli sie als `.bak`.
> Die Template-`CLAUDE.md` danach wiederherstellen und zusammenführen.

### Schritt 4 — Concord in Studio Pro installieren
1. Marketplace-Modul "Concord" importieren (falls noch nicht geschehen)
2. Studio Pro neu starten → Concord schreibt `.mcp.json`
3. Claude Code (VS Code) neu starten → MCP-Server `concord-v2-mcp` erscheint in der Liste

**Test in Claude Code:**
```
/mcp   ← sollte concord-v2-mcp als "connected" zeigen
```

### Schritt 5 — Maia-Skills synchronisieren
In Claude Code (VS Code Terminal oder Chat):
```
concord_discover → maia.sync-skills → concord_invoke
```
Schreibt Concord-Projektwissen nach `skillssource/` damit Maia das Projekt kennt.

### Schritt 6 — .claude/settings.json anlegen (optional aber empfohlen)
```json
{
  "permissions": {
    "allow": [
      "Bash(mxcli:*)",
      "Bash(mxcli *)"
    ]
  },
  "env": {
    "MXCLI_QUIET": "1"
  }
}
```
Erspart Genehmigungsabfragen für Standard-mxcli-Befehle.

### Schritt 7 — Validator ausführen
```
/validate-agent-setup
```
Prüft ob alle 7 Pflichtpunkte der Multi-Agent-Architektur erfüllt sind.

### Schritt 8 — `skillssource/_modules/` befüllen
Für jedes Modul eine `conventions.md` anlegen:
```
skillssource/_modules/core/conventions.md
skillssource/_modules/childmanagement/conventions.md
...
```
Inhalt je Datei: modul-spezifische Entity-Regeln, Microflow-Muster, bekannte Fallstricke.

---

## Dateien in diesem Template

| Datei | Empfänger | Nach Setup: Aktion |
|---|---|---|
| `projekt.md` | Alle Agenten | **Pflicht:** Mit Projektdaten befüllen |
| `CLAUDE.md` | Claude Code | mxcli-Pfad in `## mxcli Location` anpassen |
| `AGENTS.md` | GitHub Copilot / Codex | Fertig — Projektname ersetzen |
| `skillssource/AGENTS.md` | Maia (Studio Pro) | Mendix-Rollen und Konventionen anpassen |
| `skillssource/_modules/.keep` | — | Nach mxcli init: je Modul eine conventions.md |

---

## Architektur-Prinzip

```
projekt.md            ← Alle Agenten (Ziel, Kontext, Module, Stack)
├── CLAUDE.md         ← Claude Code (mxcli, Concord, Tool-Routing, Safety Rules)
├── AGENTS.md         ← Generische Agenten (GitHub Copilot, Codex)
└── skillssource/
    ├── AGENTS.md     ← Maia (Mendix-Programmierregeln, Domain-Konventionen)
    └── _modules/     ← Modul-spezifische Konventionen
```

Jede Agent-Datei enthält nur ihre eigene Domäne + einen Verweis auf `projekt.md`.