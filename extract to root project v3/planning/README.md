# Abgeleitete Arbeitsartefakte

`planning/` enthaelt versionierte technische Ableitungen aus Mendix-Board-Stories:
Spezifikationen, Testmatrizen, Traceability- und Abhaengigkeitsmatrizen. Es ist kein
zweites Backlog und kein zweiter Sprintplan.

## Struktur

```text
planning/
	stories/       Storybezogene technische Spezifikationen und Testmatrizen
	generated/     Lokale Reconciliation- und Board-Aktionsberichte
	*.md           Portfolio-Dokumente fuer das gesamte Backlog
```

## Pflicht-Frontmatter fuer storybezogene Dateien

```markdown
---
board_story: CAP-123
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
`feat: implement foundation [CAP-123] [CAP-124]`. Die IDs sind technische Traceability
und haken keine Board-Story automatisch ab. Das manuelle Abhaken erfolgt erst nach
Pruefung des Wave-Berichts und ueber `scripts/generate-board-action-report.ps1`.

## Portfolio-Dokumente

- `traceability.md`: Mockup und Fachgrundlage auf Board-Storys abbilden.
- `backlog-review.md`: Entwickelbarkeit, Risiken und erforderliche Klaerungen bewerten.
- `dependency-matrix.md`: Kritischen Pfad und technische Reihenfolge festhalten.

Diese Dokumente beschreiben den aktuellen Board-Snapshot, enthalten aber keine lokale
Statusfuehrung und brauchen kein storybezogenes Frontmatter.