<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->
# [PROJEKTNAME] — Agent Instructions

> **Single Source of Truth:** Diese Datei definiert die projektweiten Regeln fuer
> alle AI-Agenten. `AGENTS.md` und `CLAUDE.md` sind ausschliesslich Einstiegspunkte
> und werden nach `mxcli init` mit `./scripts/apply-project-agent-instructions.ps1`
> um die Regeln aus dieser Datei ergaenzt.
>
> **Projektkontext:** siehe `projekt.md`.
>
> **Setup pruefen:** Falls `projekt.md` noch TODO-Platzhalter enthaelt oder `.ai-context/`
> nicht existiert, ist das Agent-Setup unvollstaendig. Fuehre dann `mxcli init` aus und
> anschliessend `./scripts/apply-project-agent-instructions.ps1`. `mxcli init` erzeugt bzw. aktualisiert die
> MDL-Skills und Tool-Konfigurationen unter `.ai-context/` und `.claude/`; das Skript
> fuegt danach die Projektregeln in die erzeugten Einstiegspunkte ein, ohne die mxcli-
> Referenz zu ersetzen. Eine `.mcp.json` ist nur fuer eine
> Live-MCP-Anbindung an Studio Pro erforderlich, nicht fuer die lokale MDL-Arbeit.
> Fuer die Board-Synchronisierung `.env.mendix.example` nach `.env.mendix` kopieren;
> Zugangsdaten bleiben lokal und werden niemals gelesen, ausgegeben oder versioniert.
> Diese Datei gilt für generische AI-Agenten (GitHub Copilot, OpenAI Codex, etc.).
> Für tool-spezifische Regeln: `CLAUDE.md` (Claude Code) · `skillssource/AGENTS.md` (Maia).

---

## Multi-Agent-Struktur

| Agent | Instruktionsdatei | Gemeinsame Basis |
|---|---|---|
| Claude Code (VS Code) | `CLAUDE.md` | `projekt.md` |
| Maia (Studio Pro) | `skillssource/AGENTS.md` | `projekt.md` |
| GitHub Copilot / Codex | `AGENTS.md` (diese Datei) | `projekt.md` |
| Concord MCP | `.concord/project-memory.md` | `projekt.md` |

---

## Allgemeine Entwicklungsregeln

- **KEIN manuelles git commit/push** — Mendix Team Server übernimmt Versionskontrolle
- **`[Spec.md]` niemals modifizieren** — ist die unveränderliche Produkt-Spezifikation
- Domain-Model: Englisch, PascalCase
- FOSS-Marketplace-Module vor Eigenentwicklung prüfen
- Annahmen: ⚠️ ASSUMPTION | Offene Entscheidungen: ⚠️ DECISION REQUIRED

---

## Wo was nachschlagen

| Thema | Datei |
|---|---|
| Projektziel, Architektur, Module | `projekt.md` |
| mxcli-Befehle, Concord MCP, Tool-Routing | `CLAUDE.md` |
| Aktuelle User Stories und Sprint-Kontext | `sprints/generated/` nach `scripts/sync-epics-stories.ps1` |
| Synchronisierungsablauf | `sprints/sync-workflow.md` |
| Abgeleitete Spezifikationen und Tests | `planning/` nach `scripts/reconcile-derived-artifacts.ps1` |
| Mendix-Programmierregeln, Domain-Konventionen | `skillssource/AGENTS.md` |
| Architekturentscheidungen | `sprints/decisions.md` |
| Mercedes-Benz Plattformmodule | `skillssource/platform-modules.md` |
| Modul-spezifisches Plattformwissen | `skillssource/_modules/` |
| Projekt-input-Resourcen | `input-resources/` |

### Projektlokale Mendix-Skills

Der gesamte Ordner `.ai-context/skills/` ist die projektlokale Quelle fuer Mendix-
Arbeitsanweisungen und Skills. Vor einer passenden Aufgabe liest der Agent zuerst
`.ai-context/skills/README.md` und bei agentenbezogenen Themen
`.ai-context/skills/agents.md`, sofern diese Dateien vorhanden sind. Danach liest er
den konkreten Skill, zum Beispiel `generate-domain-model.md`, `manage-security.md`,
`test-app.md` oder `bulk-widget-updates.md`. Die Skills sind projektlokale
Referenzdokumente und werden nicht als globale Copilot-Skills vorausgesetzt.

## Plattformmodule

Vor Eigenentwicklung immer zuerst skillssource/platform-modules.md prüfen.

Mercedes-Benz Plattformmodule sind zu bevorzugen.

Modifikationen an Plattformmodulen sind nicht erlaubt.

### Input Resources

Der Ordner `input-resources/` enthält verbindliche Eingabeartefakte wie:

- interaktive HTML-Mockups
- UI-/UX-Referenzen
- fachliche Anforderungen
- Prozessdarstellungen
- Screenshots und weitere Referenzdateien

Vor Planung oder Implementierung einer Story muss geprüft werden, ob relevante
Artefakte in `input-resources/` vorhanden sind.

Relevante Eingabeartefakte haben Vorrang vor Annahmen des Agenten.

Bei HTML-Mockups gilt:

1. Mockup in einem echten Browser ausführen.
2. Nicht nur HTML-, CSS- oder JavaScript-Code analysieren.
3. Relevante Seiten, Zustände und Interaktionen mit Playwright untersuchen.
4. Bei zustandsabhängigen Controls alle fachlich relevanten Varianten aktiv ausloesen und
   Labels, sichtbare Felder, Eingabequelle, Validierungen und Datenwirkung vergleichen.
5. Beobachtete Varianten als fachliche Regel oder `⚠️ DECISION REQUIRED` dokumentieren.
6. Screenshots der relevanten Zustände erzeugen.
7. UI, UX, Navigation, Validierungen und erkennbare fachliche Abläufe als
   Referenz für die Mendix-Implementierung verwenden.
8. Unklare oder widersprüchliche Abläufe als `⚠️ DECISION REQUIRED` markieren.
9. Das Mockup nicht verändern, sofern dies nicht ausdrücklich beauftragt wurde.

Details zur Ablage und Verwendung:
`input-resources/README.md`

### Mendix Epics Board

Wenn das Mendix Epics Board als Backlog-Quelle konfiguriert ist, ist es verbindlich
fuer User Stories, Akzeptanzkriterien, Sprintzuordnung und Status. Vor Planung oder
Umsetzung einer Board-Story zuerst `scripts/sync-epics-stories.ps1` ausfuehren und den
passenden generierten Snapshot unter `sprints/generated/` lesen. Die Snapshots sind
read-only; Story- und Statusaenderungen werden ausschliesslich im Mendix Epics Board
vorgenommen.

### Abgeleitete Arbeitsartefakte

Wenn Mendix Epics als Backlog-Quelle festgelegt ist, muessen technische Spezifikationen,
Testmatrizen, Traceability- und Abhaengigkeitsmatrizen unter `planning/` die Board-Story-ID
und den `Source fingerprint` aus dem Snapshot enthalten. Nach jedem Board-Sync
`scripts/reconcile-derived-artifacts.ps1` ausfuehren. Das Board bleibt verbindlich.

Implementation Waves unter `planning/execution-waves.md` sind technische Reihenfolge,
keine lokalen Sprints. Nach validierter Umsetzung kann ein Artefakt eine optionale
`board_action` angeben. `scripts/generate-board-action-report.ps1` erzeugt daraus nur
einen Bericht fuer manuelle Board-Aktionen; Board-Status und Tasks werden nie lokal oder
automatisch geaendert.

@projekt.md
@.claude/setup.md

> **Projektkontext:** `projekt.md` und `setup.md` sind oben via @-Include geladen.
> Diese Datei enthält nur Claude Code-spezifische Inhalte (Tool-Routing, mxcli, Safety Rules).
> Diese Datei enthält nur Claude Code-spezifische Inhalte (Tool-Routing, mxcli, Safety Rules).

---

## mxcli-Exklusiv (SP muss geschlossen sein für Writes)
Security-Rollen / User Roles / Demo Users / Security Level, Nanoflows CREATE,
View Entities (OQL), Indexes, REVOKE, MOVE, OData, Java Actions,
Navigation mit rollenbasierten Home-Pages, `mxcli lint`, `mxcli docker check`

Bei MB_SSO-Konfiguration `MB_SSO.CONST_UserroleAppname` pruefen. Wenn sie leer oder
nicht einem eindeutigen 3-5-stelligen Uppercase-Kuerzel entspricht, das Kuerzel vor dem
Anlegen fachlicher Projektrollen festlegen. Projektrollen folgen dem Muster
`<APPSHORT>_<RoleName>`. Danach alle Projektrollen gegen dieses Schema pruefen.
Abweichende Approllen dem Entwickler mit Umbenennungsvorschlag vorlegen und erst nach
seiner Bestaetigung umbenennen oder migrieren.

---

# CONCORD SAFETY RULES (non-negotiable)
- NEVER run version-control WRITE commands: no git/hg add/commit/checkout/reset/clean/stash/push/merge/rebase
- NEVER delete or destructively modify model elements without EXPLICIT user confirmation in the SAME turn
- Before ANY destructive or irreversible operation: state exactly what will change, get confirm
- MODEL writes: SP-MCP directly first. Concord's write-ladder is FALLBACK only.

---

# Mendix Project: [PROJEKTNAME]

## Communication Style
- **Never show raw MDL scripts in chat.** Describe changes in plain language, get approval, then execute silently.
- **Always quote identifiers** in MDL with double quotes (`"Name"`).

## mxcli Location
<!-- TODO: Pfad zur mxcli-Installation -->
`mxcli` is available in PATH. Usage: `mxcli -p App.mpr -c "COMMAND"`

Wenn eine Konsistenzprüfung `CE0066` meldet, `scripts/open-studio-pro.ps1` ausführen.
Der Entwickler klickt in Studio Pro im betroffenen Domänenmodell **Update security**, speichert,
schließt Studio Pro wieder und startet danach die Konsistenzprüfung erneut.

### MPR-v2-Materialisierungswache

Solange Zeitpunkt und Ursache einer Materialisierung nicht abschliessend geklaert sind,
prueft jeder Agent vor und nach jeder Modellaktion den MPR-v2-Zustand:

1. Studio-Pro-Prozessstatus feststellen.
2. Groesse der `.mpr`, Existenz von `mprcontents/`, Anzahl der
   `mprcontents/**/*.mxunit`-Dateien und Inhalt von `mprcontents/mprname` protokollieren.
3. Nach der Aktion dieselben Werte erneut pruefen.
4. Wenn `mprcontents/` verschwindet oder die `.mpr` unerwartet stark waechst,
   Aktion als fehlgeschlagen markieren, keine Folgeaktion starten, eine Recovery-Kopie
   unter `.concord/scratch/` sichern und den letzten bekannten MPR-v2-Stand wiederherstellen.
5. Erst nach bestaetigter unveraenderter MPR-v2-Struktur weiterarbeiten oder committen.

Mehrere Studio-Pro-Instanzen fuer andere Projekte duerfen parallel geoeffnet bleiben.
Wenn ein Agent fuer dieses Projekt Studio Pro startet, verwendet er bei einem
anschliessenden manuellen Schritt `scripts/open-studio-pro.ps1 -WaitForClose`.
Der Launcher wartet nur auf die von ihm gestartete PID und blockiert oder beendet keine
anderen Studio-Pro-Instanzen.

Read-only mxcli-Kommandos duerfen ohne Modellcheckpoint verwendet werden. Fuer `exec`,
MCP-Schreibvorgaenge, Studio-Pro-Start, `mxcli docker check` und Speichern gilt die
Vorher-/Nachher-Pruefung immer. Ein gruener Mendix-Konsistenzcheck ersetzt diese
Materialisierungspruefung nicht.

### Isolierter Docker-/Playwright-Test

Docker- und Playwright-Tests laufen standardmaessig ueber
`scripts/run-docker-isolated.ps1`. Der Runner erstellt eine disposable Kopie aus `HEAD`
unter `.concord/scratch/`, startet Docker mit `--skip-check` und verwendet einen
Port-Offset. Der kanonische MPR-v2-Checkout wird nicht direkt an `mxcli docker run`
uebergeben. Nach dem Lauf werden MPR-Groesse und `mxunit`-Anzahl der Kopie geprueft;
eine Materialisierung der Kopie markiert den Test als fehlgeschlagen, veraendert aber
nicht den kanonischen Checkout. Dieser isolierte Lauf ist diagnostisch und ersetzt
keinen kanonischen Security- oder Release-Gate.

Nach erfolgreichem Docker-Build und healthy Mendix-Container wird der integrierte
Playwright-Browser-Test als naechster Agentenschritt gegen die ausgegebene App-URL
ausgefuehrt. Die lokalen Werte `MENDIX_APP_TEST_USERNAME` und
`MENDIX_APP_TEST_PASSWORD` aus `.env.mendix` werden nur zur Laufzeit verwendet und
niemals ausgegeben, in MDL geschrieben oder versioniert. Ein eigenstaendiger
PowerShell-Aufruf kann die integrierten VS-Code-Browserwerkzeuge nicht direkt starten;
der Agent uebernimmt diesen Schritt nach erfolgreichem Runner-Abschluss.

Wenn MxBuild oder der Mendix-Konsistenzcheck `CE0066` meldet, muss **Update security**
im kanonischen Originalmodell ausgefuehrt, gespeichert und anschliessend als
MPR-v2-Aenderung committed werden. Eine Security-Aenderung in der disposable Kopie
wird nie automatisch ins Originalmodell uebernommen. Der verbindliche Ablauf ist:
Recovery-Kopie des Originals, Studio-Pro-Update im Original, Speichern, Studio Pro
schliessen, MPR-v2-Materialisierungswache, Commit und erst danach Docker-/Playwright-Test
auf einer neuen disposable Kopie aus dem aktualisierten `HEAD`.

## Gemeinsame Dateien und lokaler Zustand

Versionieren: Mendix-Modell und Quellcode, `AGENT.md`, Projekt-/Prozessdokumentation,
`.ai-context/`, `.claude/`, `.devcontainer/`, `.playwright/`, `.mxcli/widgets/`,
`planning/` ausser `planning/generated/` sowie Skripte und Beispielkonfigurationen.

Lokal halten: `.env.mendix`, `.mcp.json`, `.codex/`, `.grok/`, `.mxcli/catalog.db`,
`sprints/generated/`, `planning/generated/`, Build-/Runtime-Ausgaben, IDE-Benutzerdateien
und Mendix-Locks. Concord-Bridge-Tokens und MCP-Clientkonfigurationen bleiben lokal.
Lokale Dateien weder committen noch loeschen, sofern nicht ausdruecklich beauftragt.

## Before Writing MDL Scripts
Read the relevant skill file first:
- `write-microflows.md` — before any microflow
- `generate-domain-model.md` — before domain model changes
- `manage-security.md` — before security/roles
- `check-syntax.md` — pre-flight validation
- `live-edit-with-studio-pro.md` — before writes with SP open

## Documentation Timing

Pflege In-App-Dokumentation beim Anlegen oder Aendern des Artefakts, nicht gesammelt am
Sprintende: Module, Entities, Enumerationen und Associations erhalten eine Beschreibung;
Microflows und Nanoflows dokumentieren Zweck, Parameter und Ergebnis. Fachliche
Entscheidungen gehoeren nach `sprints/decisions.md`; storybezogene technische Details,
Testmatrizen und Mockup-Beobachtungen nach `planning/stories/`. Der Lint `QUAL002` prueft
fehlende Entity- und Microflow-Dokumentation.

### HTML-Mockups und Playwright

Für HTML-Mockups unter `input-resources/ui-ux/`:

- zuerst `input-resources/README.md` lesen
- Mockups im Browser mit Playwright ausführen
- relevante Zustände und Nutzerwege untersuchen
- zustandsabhängige Varianten aktiv durchklicken und ihre Feldsemantik dokumentieren
- Screenshots als Implementierungsreferenz verwenden
- nach der Mendix-Umsetzung dieselben Nutzerwege gegen die laufende App prüfen

Der mxcli `test-app` Skill und die vorhandene Playwright-Konfiguration sind für
Browser-Automation und die Verifikation der laufenden Mendix-App zu verwenden.

Die Interpretation des Mockups richtet sich nach den Regeln in
`input-resources/README.md`.
<!-- END PROJECT AGENT INSTRUCTIONS -->
> Diese Datei gilt für generische AI-Agenten (GitHub Copilot, OpenAI Codex, etc.).
> Lies `AGENT.md`!