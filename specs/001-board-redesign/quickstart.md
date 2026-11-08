# Quickstart: Validierung je Changeset

Validierungs- und Messleitfaden. Implementierungsdetails stehen in `tasks.md`, Gates in
[contracts/changeset-gates.md](contracts/changeset-gates.md).

## Voraussetzungen

- Python 3 mit `requirements.txt`; Git; optional Chromium über Python-Playwright oder `playwright-cli`.
- Fixture-Projekt `tests/fixtures/board-redesign/` (wird in Phase 2 der Tasks angelegt).
- Referenzprojekt **nur read-only**: `<reference-project>`.

## Read-only-Board gegen ein Projekt starten

```bash
cd <projekt>
PYTHONDONTWRITEBYTECODE=1 MXAGILE_BOARD_PROFILE=1 python -B .mxagile/tools/serve_project_board.py --project-root . --port 0
# Framework-Arbeitskopie gegen reference project: python -B <repo>/scripts/serve_project_board.py --project-root <reference-project>
```

Danach ist `git -C <projekt> --no-optional-locks status --porcelain` vor und nach dem Lauf identisch (fremde Parallelarbeit ausgenommen und gesondert notiert).

## Messlauf (CS-2, CS-4, CS-5, CS-6)

```bash
for ep in api/status api/status api/page-previews "api/gallery" "source/planning/decisions/DEC-053.yml"; do
  curl -s -o /dev/null -w "$ep %{http_code} %{time_total}s\n" "http://127.0.0.1:<port>/$ep"; done
```

Erwartung nach CS-2: zweiter `api/status` ≤ 0,3 s; `source/…` ≤ 0,2 s; keine 503 bei 20 Neustarts unter paralleler Dateiänderung (Fixture-Skript ändert während des Aufbaus eine Requirement-Datei).

## Gates

```bash
python tests/run-impact-tests.py --list --paths <geänderte Pfade>
python tests/run-impact-tests.py --tier fast
python tests/run-impact-tests.py --paths <geänderte Pfade>            # Impact Regression
python tests/run-impact-tests.py --tier release                       # nur CS-7, CS-5 (bzw. unmapped)
```

## Realitätsfälle (spec.md RC-01…RC-15)

| Nach | Prüfen | Erwartung |
|---|---|---|
| CS-1 | Overview-Drift, UI & Pages-Anzahl, `/source/planning/parity/SCN-CAP-DEPARTMENTS-HTMLFIRST.yaml` | RC-01…03 |
| CS-2 | Messlauf oben; Reconciliation-Zeit | RC-04, RC-05 |
| CS-7 | `python -B scripts/board_smoke.py --project-root <reference-project> --format json` | PASS oder UNAVAILABLE ≤ 15 s; `project_unchanged: true` |
| CS-0 | `python -B scripts/project_compatibility.py doctor --project-root <reference-project> --format json` | RC-06; 0 neue blockierende Diagnosen |
| CS-3 | `/api/health`; Fachansichten ohne Diagnosepanel | RC-07, RC-08 |
| CS-4 | Overview Current Work; Requirement-Detail; Vertrauen in DONE; Pages | RC-09…13 |
| CS-5 | `/api/timeline?from=2026-11-05` | RC-14; REF2-Commits ohne Trailer `lane=unattributed` |
| CS-6 | Page Hub `PAGE-ABTEILUNGSVERWALTUNG`; Walkthrough 12 Fragen | RC-15; SC-008 |

## Smoke-Negativfälle (CS-7)

- Browser deaktivieren (`MXAGILE_BOARD_SMOKE_BROWSER=none`) → `result: UNAVAILABLE`, Exit 2.
- Fixture mit injiziertem JS-Fehler → `FAIL`, Screenshot unter OS-Temp, Exit 1.
- Fixture-Server mit künstlicher Verzögerung → `TIMEOUT` ≤ 60 s, kein Prozess/Port übrig, Exit 3.
- `install-core.ps1` non-interaktiv → kein Smoke, Bericht `NOT RUN (non-interactive)`.
