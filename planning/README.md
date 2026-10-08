# Abgeleitete Arbeitsartefakte

`planning/` enthaelt versionierte technische Ableitungen aus MxAgile-autorisierten
Requirements und Mockups (Rang-1-Quellen). Wenn ein Mendix Epics Board konfiguriert
ist, koennen Artefakte optional Board-Story-IDs fuer organisatorische Traceability
enthalten. Es ist kein zweites Backlog und kein zweiter Sprintplan.

## Struktur

```text
planning/
	stories/       Eine Spezifikation je Requirement (siehe stories/README.md)
	checklists/    Eine Implementierungscheckliste je Wave (siehe checklists/README.md)
	ui-inventory/  YAML-Feldinventar je Mockup-Screen (siehe ui-inventory/README.md)
	generated/     Lokale Reconciliation- und Board-Aktionsberichte
	*.md           Portfolio-Dokumente fuer das gesamte Backlog
```

## Spec-Namenskonvention (`stories/`)

Eine Story-Spezifikation je Requirement, benannt nach der Requirement-ID.

| Muster | Beispiel | Verwendung |
|---|---|---|
| `{STORYPREFIX}-{Nr}.md` | `{STORYPREFIX}-001.md` | Einzelne Requirement-Spec |
| `INFRA-{slug}.md` | `INFRA-appui.md` | Infrastruktur-/Querschnitts-Spec |

`{STORYPREFIX}` ist beim Projekt-Setup festzulegen (siehe `SETUP.md`). Nummer fortlaufend.

## Standard-Planungsdokumente

| Dokument | Zweck |
|---|---|
| `sprint-roadmap.md` | Alle Specs nach Sprint und Feature-/Abo-Tier |
| `execution-waves.md` | Technische Reihenfolge innerhalb MxAgile-Lifecycle; fuer FEATURE+ Waves auch Capability/Domain/Module-Ownership; optional Board-Traceability |
| `traceability.md` | Mockup und Specs auf Requirements abbilden (optional Board-Story-IDs) |
| `backlog-review.md` | Entwickelbarkeit, Risiken, Klaerungsbedarf |
| `dependency-matrix.md` | **OPTIONAL** — kreuztabellarische Abhaengigkeiten; Wave-Ownership in execution-waves.md ist primaer |
| `mockup-gesamtplan.md` | Mockup-Strategie: Screens, Rollen, Detailstufen |
| `mockup-validation-report.md` | Abgleich Mockup gegen Story-Specs |
| `story-spec.schema.json` | JSON Schema fuer Story-Specs (Validierung + Extraktion) |

## Frontmatter fuer storybezogene Dateien

Pflichtfelder:

```markdown
---
state: Current
---
```

Zulaessige `state`-Werte: `Current`, `Review required`, `Blocked`, `Superseded`.

Optionale Board-Traceability-Felder (nur wenn Board konfiguriert):

```markdown
---
board_story: {STORYPREFIX}-123
source_fingerprint: <Wert aus epics-snapshot.json>
last_reconciled: 2026-08-20
board_action: None
board_action_evidence: Optional summary or test result
---
```

`board_action` ist optional. Zulaessig sind `None`, `Move to Testing`, `Mark Done`,
`Update Tasks`, `Add Comment` oder eine konkrete manuelle Aktion.

Projekte ohne Board-Integration benoetigen keine Board-Traceability-Felder.

## Ablauf

1. `scripts/sync-epics-stories.ps1` ausfuehren.
2. `scripts/reconcile-derived-artifacts.ps1` ausfuehren.
3. Bei einem Report-Fund das Artefakt gegen das Board pruefen und bei Bedarf anpassen.
4. `scripts/generate-board-action-report.ps1` ausfuehren und nur die gemeldeten
	Aktionen manuell im Board vornehmen.
5. Board-Story, Akzeptanzkriterien, Sprint und Status niemals lokal ueberschreiben.

`planning/generated/` enthaelt nur generierte Reconciliation-Berichte und wird nicht
versioniert.

## Versionskontrolle

Die storybezogenen Artefakte unter `planning/` werden versioniert. Nur
`planning/generated/` bleibt lokal. Der lokale Board-Snapshot unter `sprints/generated/`
und die Zugangsdaten in `.env.mendix` werden ebenfalls nicht versioniert.

## Implementation Waves

`execution-waves.md` ordnet technische Arbeit innerhalb des MxAgile-Lifecycle. Waves
sind MxAgile-Konstrukte und kein zweiter Sprintplan.

## Wave Completion And Commits

Jede abgeschlossene Wave erhaelt einen versionierten Bericht unter
`planning/wave-reports/`. Der Bericht nennt den umgesetzten Umfang, Requirement-IDs,
Testnachweise, offene Gates und — wenn Board konfiguriert — Board-Story-IDs und
manuell auszufuehrende Board-Aktionen.

Wave-relevante Commits nennen die betroffenen Requirement-IDs (und optional Board-Story-IDs)
explizit, zum Beispiel:
`feat: implement foundation [{STORYPREFIX}-123] [{STORYPREFIX}-124]`. Die IDs sind technische Traceability
und haken keine Board-Story automatisch ab. Wenn ein Board konfiguriert ist, erfolgt
das manuelle Abhaken erst nach Pruefung des Wave-Berichts und ueber
`scripts/generate-board-action-report.ps1`.

## Portfolio-Dokumente

- `traceability.md`: Mockup und Fachgrundlage auf Requirements abbilden (optional Board-Traceability).
- `backlog-review.md`: Entwickelbarkeit, Risiken und erforderliche Klaerungen bewerten.
- `dependency-matrix.md`: Optionale kreuztabellarische Abhaengigkeitsmatrix. Wave-uebergreifende
  Abhaengigkeiten und Modul-Ownership werden primaer in `execution-waves.md` festgehalten.

Diese Dokumente beschreiben den aktuellen Scope-Stand, enthalten keine lokale
Statusfuehrung und brauchen kein storybezogenes Frontmatter.