# Projekt-Setup Checklist

> Diese Datei wird von Claude Code bei jedem Session-Start automatisch geladen (@-include).
> Der SessionStart-Hook prüft den Status aktiv und gibt Warnungen aus wenn etwas fehlt.

## Wenn dieses Projekt noch nicht eingerichtet ist

Prüfe beim Session-Start folgende Punkte. Falls ein Check fehlschlägt, leite den Nutzer
durch den entsprechenden Schritt bevor du mit anderen Aufgaben beginnst.

### Setup-Status-Checks

1. **`.mcp.json` vorhanden?**
   - Nein → Concord nicht installiert
   - Nutzer-Anweisung: Mendix Marketplace → "Concord" installieren → Studio Pro neu starten
   - Danach erscheint `.mcp.json` automatisch im Projektstamm

2. **`projekt.md` hat keine TODOs mehr?**
   - Noch TODOs vorhanden → Projektkontext unvollständig
   - Nutzer-Anweisung: `projekt.md` öffnen und alle `<!-- TODO: ... -->` Abschnitte ausfüllen

3. **`.ai-context/` Verzeichnis vorhanden?**
   - Fehlt → `mxcli init` noch nicht ausgeführt
   - Nutzer-Anweisung:
     ```bash
     mxcli init . --tool claude
     ```

4. **`mxcli` im PATH?**
   - Test: `mxcli --version` in Terminal
   - Fehlt → PATH-Setup nötig (siehe `.claude/templates/mx-project/README.md`)

5. **Concord MCP verbunden?**
   - Test: `concord_discover` aufrufen — antwortet ohne Fehler?
   - Fehlt → `/mcp` in Claude Code prüfen, ob `concord-v2-mcp` als "connected" erscheint

### Vollständige Setup-Anleitung

→ `.claude/templates/mx-project/README.md`

## Wenn das Projekt bereits eingerichtet ist

Ignoriere diese Datei und fahre normal fort.
Der SessionStart-Hook gibt nur dann Warnungen aus wenn Checks fehlschlagen.