# Projekt-Setup nach Kopieren des Templates

Dieses Template in den Projektstamm kopieren und anschliessend die Platzhalter ersetzen.
Nicht alle Werte stehen beim Anlegen sofort fest — die Tabelle zeigt wann sie typischerweise bekannt sind.

## Platzhalter

| Platzhalter | Beispiel (CapTrack) | Bekannt ab | Beschreibung |
|---|---|---|---|
| `{Projektname}` | `CapTrack` | Projektanlage | Anzeigename der App (z.B. in MB_UI.AppName) |
| `{App}` | `Cap` | MB-Governance-Onboarding | Wert von `MB_SSO.CONST_UserroleAppname` — bestimmt das Rollen-Praefix |
| `{APP}_` | `CAP_` | MB-Governance-Onboarding | Rollen-Praefix (`{App}` in Grossbuchstaben + Unterstrich) |
| `{Projektbeschreibung}` | _optional_ | Projektanlage | Kurzbeschreibung fuer `projekt.md`, falls verwendet |

## Betroffene Dateien

### Sofort ersetzbar (`{Projektname}`)

| Datei | Stelle |
|---|---|
| `.dfc-ai/modules/MB_UI.md` | `MB_UI.AppName` Default-Wert |

### Nach Governance-Onboarding (`{App}`, `{APP}_`)

| Datei | Stelle |
|---|---|
| `.dfc-ai/modules/MB_SSO.md` | `CONST_UserroleAppname`, Rollen-Schema, Agent-Regeln |
| `.dfc-ai/modules/MB_NoAccess.md` | Rollen-Referenzen (3 Stellen) |
| `.dfc-ai/modules/MB_Feedback.md` | Role-Mapping-Anweisung |
| `.dfc-ai/agents/discovery-agent.md` | Rollen-Abgleich-Schritt |

## Vorgehen

1. **Template kopieren** — Gesamten Ordnerinhalt in den Mendix-Projektstamm kopieren
2. **`projekt.md` befuellen** — Projektziel, Module, Stack, Sprint-Struktur eintragen
3. **`{Projektname}` ersetzen** — Suche-und-Ersetze ueber die betroffene Datei
4. **`mxcli init` ausfuehren** — Legt `.ai-context/skills/` und `AGENTS.md` an
5. **CLAUDE.md reparieren** — siehe Abschnitt "Nach mxcli init" unten
6. **Nach Governance-Onboarding:** `{App}` und `{APP}_` in den 4 betroffenen Dateien ersetzen
7. **Diese Datei loeschen** — `SETUP.md` wird im Projekt nicht mehr gebraucht

## Nach `mxcli init` — CLAUDE.md und settings.json

`mxcli init` ueberschreibt `CLAUDE.md` und `.claude/settings.json` mit eigenen Versionen.
Das ist ein bekanntes Verhalten. Die mxcli-Versionen enthalten MDL-Syntax, Skills und
mxcli-Befehle — aber NICHT die DFC-AI-Sektionen aus dem Template.

### Was verloren geht

| Sektion | Zweck | Risiko wenn fehlend |
|---|---|---|
| `CONCORD SAFETY RULES` | Version-Control-Verbot, Destructive-Ops-Schutz | Agent koennte versehentlich git commit/push ausfuehren |
| Tool-Routing-Order | SP-MCP → Concord → Maia → mx → manual | Agent nutzt suboptimale Wege zum Modell |
| `.dfc-ai/` Referenzen | Orchestrator, Policies, Module | Agent kennt den DFC-AI-Prozess nicht |
| IDE-Control via Concord | run, build-errors, save-all, sync-files | Agent behauptet Studio-Pro-Steuerung sei unmoeglich |

### Reparaturschritte

**Option A — Template-CLAUDE.md wiederherstellen und mxcli-Teil anhaengen:**
1. `CLAUDE.md` aus diesem Template erneut kopieren (sie liegt als Backup hier)
2. Den mxcli-generierten Teil (alles ab `## Quick Start` oder `## MDL Commands`) aus der
   ueberschriebenen Version herausnehmen und UNTEN an die Template-Version anhaengen
3. MPR-Name und mxcli-Pfad im oberen Teil anpassen

**Option B — DFC-AI-Block in die mxcli-Version einfuegen:**
1. Aus der Template-`CLAUDE.md` den Block von Zeilenanfang bis einschliesslich
   `== CONCORD SAFETY RULES ==` kopieren
2. Diesen Block OBEN in die mxcli-generierte `CLAUDE.md` einfuegen

Option A ist sicherer — nichts geht verloren. Option B ist schneller.

**`.claude/settings.json`** ist unkritisch — mxcli generiert sinnvolle Permissions.
Pruefen ob `Bash(mxcli:*)` und `Bash(mxcli *)` enthalten sind, mehr ist nicht noetig.

### Praevention

Vor `mxcli init` eine Sicherungskopie anlegen:
```
cp CLAUDE.md CLAUDE.md.template-backup
```
Nach `mxcli init` den DFC-AI-Block aus dem Backup zurueckkopieren.

## Tipp

Suche-und-Ersetze im gesamten `.dfc-ai/` Ordner reicht — die Platzhalter kommen nur dort vor.
Fuer `{APP}_` auf Gross-/Kleinschreibung achten: `{APP}_` (gross) ist das Rollen-Praefix,
`{App}` (mixed) ist der `CONST_UserroleAppname`-Wert.
