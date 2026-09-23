# .mxagile/ — Agentenagnostisches Mendix Delivery System

Dieses Verzeichnis ist die **plattformneutrale Prozessschicht** fuer AI-gestuetzte
Mendix-Entwicklung. Es definiert *was* in welcher Reihenfolge passiert — unabhaengig
davon, *welcher* AI-Agent (Claude Code, GitHub Copilot, OpenAI Codex, Grok, Maia,
OpenCode, Hermes) die Arbeit ausfuehrt.

## Kernidee

Jede AI-Plattform hat ein eigenes Format fuer Skills, Agenten und Instruktionen.
Statt denselben Inhalt manuell in 4-5 Formaten zu pflegen, liegt die **neutrale
Fachlogik** hier in `.mxagile/`. Ein Generierungsskript erzeugt daraus physische
Plattform-Kopien mit dem jeweils passenden Frontmatter.

```
.mxagile/ (neutral, template-owned)
    |
    v  scripts/generate-mxagile-platform-skills.ps1
    |
    +---> .claude/skills/mxagile-*/    (Claude Code)
    +---> .claude/agents/mxagile-*     (Claude Code)
    +---> .github/skills/mxagile-*/    (GitHub Copilot)
    +---> .agents/skills/mxagile/      (Codex / Generic)
    +---> .grok/skills/mxagile/        (Grok)
    +---> .opencode/skills/mxagile/    (OpenCode)
    +---> .hermes/skills/mxagile/      (Hermes)
```

## Verzeichnisstruktur

```
.mxagile/
├── README.md               <- Diese Datei
├── version.yaml            <- Template-Version und Kompatibilitaet
├── GLOSSARY.yaml           <- Interne Begriffe und Plattform-Routing
├── lifecycle.yaml          <- Maschinenlesbare Lifecycle-Definition (schema_version: 1)
├── orchestrator.md         <- Narrative Erweiterung der Lifecycle-Definition
├── skills/                 <- Neutrale Prozess-Skills (Markdown, kein Frontmatter)
│   ├── discovery.md
│   ├── refinement.md
│   ├── quality-gate.md
│   ├── gate-to-refinement.md
│   └── gate-to-ready.md
├── agents/                 <- Neutrale Agent-Bodies (Markdown, kein Frontmatter)
│   ├── discovery-agent.md
│   ├── refinement-agent.md
│   ├── ui-agent.md
│   ├── implementation-agent.md
│   ├── acceptance-agent.md
│   └── maintainer.md           <- Legacy-DFC Erkennungs- und Migrations-Agent
├── policies/               <- Wiederverwendbare Prozessregeln
│   ├── safety-rules.md
│   ├── source-priority.md
│   ├── backlog-sync.md
│   ├── implementation-control.md
│   ├── development-runtime.md
│   ├── runtime-strategy.md        <- Local First, Docker By Verification Need
│   ├── credential-discovery.md    <- Credential Bootstrap: Discover before blocking
│   ├── evidence-levels.md         <- STATIC/MODEL/RUNTIME/BROWSER evidence classification
│   ├── test-workflow.md
│   ├── consistency-check.md
│   ├── mockup-analysis.md
│   └── intake-completeness.md
├── layers/                 <- Installed Company Layers (populated by installer, not distributed from Core)
│   └── {layer-id}/         <- One subdirectory per installed Company Layer
│       ├── layer.json      <- Layer manifest (id, name, version)
│       ├── platform-modules.yml  <- Company platform module catalog (optional)
│       ├── glossary.yml    <- Company-specific terminology (optional)
│       └── modules/        <- Module detail documentation (optional)
└── adapters/               <- Plattformspezifisches Frontmatter
    ├── claude/
    │   ├── skills.yaml
    │   └── agents.yaml
    ├── copilot/
    │   └── skills.yaml
    ├── codex/
    │   └── skills.yaml
    ├── grok/
    │   └── skills.yaml
    ├── opencode/
    │   └── skills.yaml
    └── hermes/
        └── skills.yaml
```

## Agenten (6)

| Agent | Phase(n) | Kernaufgabe |
|---|---|---|
| **Discovery-Agent** | Discovery | Requirements-Analyse + Modell + Board (optional) analysieren |
| **UI-Agent** | Discovery + Verifying | Mockup generieren (Generate) oder analysieren (Analyze); Soll-Ist-Vergleich (Verify) |
| **Refinement-Agent** | Refinement | Klaerungen, Entscheidungen, Marketplace-Recherche |
| **Implementation-Agent** | Implementing | Checkliste abarbeiten, MDL ausfuehren (Subagent) |
| **Acceptance-Agent** | Verifying | Modell-Inspektion + Playwright User Journeys |
| **MxAgile-Maintainer** | Wartung / Migration | Erkennt und migriert Legacy-DFC-Installationen; erzeugt NIEMALS neue DFC-Ausgaben |

## Prozessfluss

```
Requirements + Mockup (Rang-1-Quellen)
    |
    v
Intake (optional, externer Kundenbot)
    |
    v
Discovery:  Discovery-Agent  <--parallel-->  UI-Agent (Generate oder Analyze)
    | gate-to-refinement
    v
Refinement: Refinement-Agent (+ Marketplace bei non-standard Widgets)
    | gate-to-ready (erzeugt implementation-checklist.yaml)
    v
Ready:      Entwicklerfreigabe
    |
    v
Implementing: Implementation-Agent (Subagent, Checkliste Zeile fuer Zeile)
              Security: Entity Access sofort, Rollen am Ende
    |
    v
Verifying:  1. Quality-Gate (Technik)
            2. UI-Agent (Soll-Ist) + Acceptance-Agent (Fachlich) parallel
            -> Bei Fehler: failed-Items zurueck in Implementing
```

## Quellen-Vorrang (policies/source-priority.md)

| Rang | Quelle |
|---|---|
| 1 | Kunden-Mockup + Requirements-Dokument (gleichrangig) |
| 1.5 | Generiertes Mockup (vom UI-Agent, nach Entwicklerfreigabe) |
| 2 | Bestehendes Mendix-Modell |
| 3 | Board-Stories (optional) |
| 4 | Klaerungen aus Refinement |

## Vier Skill-Quellen im Projekt

| Quelle | Verzeichnis | Eigentuemer | Update |
|---|---|---|---|
| **MxAgile** (Prozess) | `.mxagile/` | Template | Template-Versionierung |
| **mxcli** (Technik) | `.ai-context/skills/` | mxcli | `mxcli init` |
| **Concord** (Wissen) | Concord MCP | Concord Runtime | Automatisch |
| **Mendix MPR** (Modell) | Agent Documents | Studio Pro | Modellaenderung |

Strikt getrennte Namensraeume — kein Verzeichnis gehoert zwei Eigentuemern.

## Eigentum und Aenderungsregeln

- `.mxagile/` ist **read-only aus dem Template**. Projektspezifische Regeln
  gehoeren in `AGENT.md`, nicht hierher.
- Generierte Plattform-Kopien tragen einen `# GENERATED` Header und werden
  nicht manuell editiert.
- **Alle generierten Artefakte tragen den Prefix `mxagile-`** im Dateinamen.

## Adapter und Generierung

Jeder Adapter enthaelt ein **Default-Template** und optionale **pro-Skill-Overrides**.
Overrides sind noetig weil z.B. Claude-Agents `model:` und `tools:` brauchen,
Copilot-Agents ein anderes Format verwenden.

## Skripte

| Skript | Zweck |
|---|---|
| `scripts/setup-agent-system.ps1` | **Single Entry Point** — ruft beide Einzelskripte |
| `scripts/apply-project-agent-instructions.ps1` | AGENT.md → Plattform-Einstiegspunkte |
| `scripts/generate-mxagile-platform-skills.ps1` | `.mxagile/` → Plattform-Skills und -Agents |

## Versionierung

`version.yaml` mit `version` + `min_compatible`. Session-Start-Hook warnt bei Drift.

## Modusabhaengiges Routing

| Modus | Concord/SP-MCP | mxcli | Dateien |
|---|---|---|---|
| **CLOSED-AUTONOM** (SP geschlossen) | Nicht verfuegbar | Vollzugriff | Vollzugriff |
| **LIVE-SP** (SP offen) | Verfuegbar | Vollzugriff | Vollzugriff |

## Unterstuetzte Plattformen

| Plattform | Skill-Verzeichnis | Agent-Verzeichnis | Status |
|---|---|---|---|
| Claude Code | `.claude/skills/mxagile-*/` | `.claude/agents/mxagile-*` | Vollstaendig |
| GitHub Copilot | `.github/skills/mxagile-*/` | — | Vollstaendig |
| OpenAI Codex | `.agents/skills/mxagile/` | — | Vollstaendig |
| Grok | `.grok/skills/mxagile/` | — | Vollstaendig |
| OpenCode | `.opencode/skills/mxagile/` | — | Stub |
| Hermes | `.hermes/skills/mxagile/` | — | Stub |
| Maia | (via Concord CDP) | — | Manuell |

## Planungsdokument

52 bestaetigte Entscheidungen (D1-D52) und der vollstaendige Umsetzungsplan:

`.concord/plans/MxAgile-restructuring-plan.md`



