# Abgeleitete Arbeitsartefakte

`planning/` enthaelt versionierte technische Ableitungen aus Mendix-Board-Stories:
Spezifikationen, Testmatrizen, Traceability- und Abhaengigkeitsmatrizen. Es ist kein
zweites Backlog und kein zweiter Sprintplan.

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
| `execution-waves.md` | Technische Reihenfolge innerhalb Board-Sprints |
| `traceability.md` | Mockup und Specs auf Board-Storys abbilden |
| `backlog-review.md` | Entwickelbarkeit, Risiken, Klaerungsbedarf |
| `dependency-matrix.md` | Kritischer Pfad, technische Reihenfolge |
| `mockup-gesamtplan.md` | Mockup-Strategie: Screens, Rollen, Detailstufen |
| `mockup-validation-report.md` | Abgleich Mockup gegen Story-Specs |
| `story-spec.schema.json` | JSON Schema fuer Story-Specs (Validierung + Extraktion) |

## Pflicht-Frontmatter fuer storybezogene Dateien

```markdown
---
board_story: {STORYPREFIX}-123
source_fingerprint: <Wert aus epics-snapshot.json>
last_reconciled: 2026-08-20
state: Current
board_action: None
board_action_evidence: Optional summary or test result
---
```

Zulaessige `state`-Werte: `Current`, `Review required`, `Blocked`, `Superseded`.
`board_action` ist optional. Zulaessig sind `None`, `Move to Testing`, `Mark Done`,
`Update Tasks`, `Add Comment` oder eine konkrete manuelle Aktion.

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

`execution-waves.md` ordnet technische Arbeit innerhalb offizieller Board-Sprints. Waves
sind kein zweiter Sprintplan und aendern keine Board-Sprintzuordnung.

## Wave Completion And Commits

Jede abgeschlossene Wave erhaelt einen versionierten Bericht unter
`planning/wave-reports/`. Der Bericht nennt die Board-Story-IDs, den umgesetzten Umfang,
Testnachweise, offene Gates und die manuell auszufuehrenden Board-Aktionen.

Wave-relevante Commits nennen die betroffenen Board-Story-IDs explizit, zum Beispiel:
`feat: implement foundation [{STORYPREFIX}-123] [{STORYPREFIX}-124]`. Die IDs sind technische Traceability
und haken keine Board-Story automatisch ab. Das manuelle Abhaken erfolgt erst nach
Pruefung des Wave-Berichts und ueber `scripts/generate-board-action-report.ps1`.

## Portfolio-Dokumente

- `traceability.md`: Mockup und Fachgrundlage auf Board-Storys abbilden.
- `backlog-review.md`: Entwickelbarkeit, Risiken und erforderliche Klaerungen bewerten.
- `dependency-matrix.md`: Kritischen Pfad und technische Reihenfolge festhalten.

Diese Dokumente beschreiben den aktuellen Board-Snapshot, enthalten aber keine lokale
Statusfuehrung und brauchen kein storybezogenes Frontmatter.