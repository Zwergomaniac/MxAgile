# Implementation Plan: MxAgile Dev Board Redesign

**Branch**: `001-board-redesign` (Spec-Verzeichnis; Arbeit auf `main` gemäß Repository-Regeln, kein Branch angelegt) | **Date**: 2026-11-05 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-board-redesign/spec.md`

**Autorität**: [docs/board-redesign-implementation-contract.md](../../docs/board-redesign-implementation-contract.md) ist verbindlich für Changeset-Grenzen; dieser Plan präzisiert ihn technisch und dokumentiert, wo die Repository-Prüfung ihn verfeinert (Abschnitt „Contract-Abgleich").

## Summary

Das read-only Dev Board wird in acht einzeln freigegebenen Changesets überarbeitet: zuerst Korrektheit (CS-1), Performance-Architektur ohne interaktive Vollscans (CS-2) und ein begrenzter Board-Smoke als Regressionsnetz (CS-7); dann die Lifecycle-Klärung aus OD-3 (CS-0), ein geschlossenes Beobachtungszustands-Vokabular mit Trennung von Aufmerksamkeit/Gesundheit/Diagnose (CS-3), Projektionen vorhandener kanonischer Daten inkl. Current Work und abgeleitetem Delivery Assessment (CS-4), eine evidenzbasierte Timeline (CS-5) und schließlich die neue Informationsarchitektur mit Page Hub (CS-6). Kanonische Semantik ändert sich ausschließlich in CS-0.

## Technical Context

**Language/Version**: Python 3 (lokal 3.14.7 gemessen; Code bleibt mit der in Projekten genutzten Python-3-Version kompatibel — keine neuen Sprachfeatures einführen, die über den bisherigen Stand von `build_project_status.py` hinausgehen); Vanilla JavaScript (kein Build-Schritt) für `.mxagile/board/`; PowerShell 5.1+/7 für `scripts/install-core.ps1`.

**Primary Dependencies**: Bestehend: `PyYAML`, `jsonschema>=4.18,<5`, `beautifulsoup4` (requirements.txt); Git-CLI; Standardbibliothek (`http.server`, `threading`, `subprocess`). Neu: **keine Pflichtabhängigkeit**. Browser für CS-7 optional über vorhandene Werkzeuge (`scripts/ensure-playwright-cli.ps1`/Node-Playwright) oder installiertes Python-Playwright; fehlend → UNAVAILABLE.

**Storage**: Kanonische Artefakte im Projekt (nur lesend). Abgeleiteter Cache außerhalb des Projekts: `%LOCALAPPDATA%\mxagile\board-cache\<repository_identity>\<branch_key>\` (Windows) bzw. `${XDG_CACHE_HOME:-~/.cache}/mxagile/board-cache/…`; JSON/JSONL-Dateien, jederzeit löschbar.

**Testing**: `python tests/run-impact-tests.py` (Fast Gate → Impact → Integration/Release); bestehende Suiten `tests/test_board_http.py`, `tests/test_board_performance.py`, `tests/test_project_status.py`, `tests/test_parity_gallery.py`, `tests/test-board-authority.ps1`, `tests/test_external_change_reconciliation.py`, `tests/test-negative-schema.ps1`, `tests/test-injection-contract.ps1`; neue Fixture-Repos unter `tests/fixtures/`.

**Target Platform**: Lokaler Entwicklerrechner (Windows primär, Linux/macOS sekundär); Loopback-HTTP; Chromium headless (optional) für den Smoke.

**Project Type**: Framework-Werkzeug — lokaler read-only Webserver + statisches Frontend + CLI-Werkzeuge (Doctor, Smoke, Timeline-Builder) + JSON-Schemas + Policy-Dokumente.

**Performance Goals** (CapTrack-Referenz, read-only gemessen): warme Ansicht ≤ 300 ms; Link ≤ 200 ms; erster Paint ≤ 3 s mit letztem Stand / ≤ 6 s kalt; Reconciliation (26 Commits) ≤ 10 s; Timeline-Erstaufbau (~600 Commits) ≤ 10 s, inkrementell ≤ 1 s; Smoke ≤ 15 s (hart 60 s); Doctor +≤ 10 %; Statusaufbau durch CS-3/CS-4 +≤ 10 %.

**Constraints**: strikt read-only; keine Schreibzugriffe im Projekt (auch kein `__pycache__`: Server-/Smoke-Starts mit `-B`); Git nur mit `--no-optional-locks`; keine Zuordnung über zeitliche Nähe; keine Live-Telemetrie; Default-Doctor browserfrei; nicht-interaktive Läufe starten keinen Smoke.

**Scale/Scope**: CapTrack: ~6.300 getrackte Dateien, 2.140 Modelldateien, 597 Commits, 90 Requirements, 123 Tasks, 55 Decisions, 11 Parity-Reports, 58 Screenshots, 10 Pages, 15 registrierte Waves. Ziel: unverändertes Verhalten bis ~5× dieser Größe.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` ist ein **unausgefülltes Template** und enthält keine prüfbaren Prinzipien. Als geltende Prinzipien dienen die Repository-Regeln aus `CLAUDE.md` und die MxAgile-Policies. (Hinweis: Das Ausfüllen der Konstitution wäre eine eigene Entscheidung, `/speckit-constitution`; nicht Teil dieser Mission.)

| # | Prinzip (Quelle) | Prüfung | Ergebnis |
|---|---|---|---|
| P1 | Board ist read-only Projektion, keine zweite Wahrheit (Plan, Contract §0.1) | Keine Schreib-Endpunkte; Cache außerhalb Projekt; SC-006 als Test | PASS |
| P2 | `.mxagile/` ist kanonische Quelle; generierte Projektionen nicht manuell editieren (CLAUDE.md) | CS-0 berührt ggf. Skills/Agents → Generatorlauf als Task | PASS |
| P3 | Installation nur über `install-core.ps1`; öffentliche Bootstrap-Skripte unverändert (CLAUDE.md) | Neue verteilte Skripte (CS-5, CS-7) nur in `install-core.ps1` | PASS |
| P4 | Testing-Strategie: `--list` zuerst, Fast/Impact/Full getrennt, Full bei unmapped/Installer/Runner (CLAUDE.md) | Je Changeset Gate-Tabelle (unten) | PASS |
| P5 | Unavailable ≠ passed (CLAUDE.md External Skills) | Smoke UNAVAILABLE; Gates berichten NOT RUN separat | PASS |
| P6 | Keine Subagents/Worktrees/Branches ohne Mission-Erlaubnis (CLAUDE.md) | Spec Kit ohne Branch; Implementierung ohne Subagents geplant | PASS |
| P7 | Commit-Identität `Zwergomaniac <Keeperdeluxe@web.de>` (CLAUDE.md) | Pre-Commit-Task je Changeset | PASS |
| P8 | Fremde Arbeit nicht absorbieren (Mission) | Vorbedingungs-Task T001/T002; selektives Staging | PASS (mit Vorbedingung) |
| P9 | Keine kanonische Semantik fürs UI ändern (Contract §0.2) | Kanonische Änderungen nur CS-0 | PASS |

Post-Design-Recheck: unverändert PASS (siehe Ende).

## Contract-Abgleich (Repository-Prüfung 2026-11-05)

Die Sequenz **CS-1 → CS-2 → CS-7 → CS-0 → CS-3 → CS-4 → CS-5 → CS-6** bleibt unverändert. Die Prüfung ergab keine falsche Abhängigkeit, aber fünf Präzisierungen:

| # | Befund (Evidenz) | Kleinste Korrektur |
|---|---|---|
| A1 | CS-1/BRD-F-02 ändert `scripts/reconcile_external_changes.py`; Impact-Mapping wählt dafür **Tier 3** (`test_external_change_reconciliation.py`, `test-core-provenance.ps1`, `test-injection-contract.ps1`). Der Contract nannte für CS-1 nur Board-Suiten. | CS-1-Gate um diese Tier-3-Suiten ergänzen; keine Scope-Änderung. |
| A2 | `project-status.schema.json` hat `additionalProperties: false` auf Root-Ebene; `test_combined_server_snapshot_matches_status_schema` validiert jede Server-Projektion. | Jedes Changeset, das Projektionsfelder ergänzt (CS-2 `projection`, CS-3 `observation_state`/`diagnostic_group`, CS-4 `current_work`/`delivery_assessment`/`done_basis`), ändert das Schema im selben Commit (Tier 2). Schemas sind verteilt. |
| A3 | `scripts/board_smoke.py` und `scripts/build_project_timeline.py` sind **unmapped**; Mapping-Ergänzung ist eine Test-Runner-Änderung. | Bestätigt Full Release Gate für CS-7 und CS-5 (Contract bereits so). Mapping-Ergänzung im selben Changeset. |
| A4 | Die Vorbedingungsliste im Contract (§0.8) ist unvollständig: Seitdem kamen weitere fremde uncommittete Änderungen hinzu (`CLAUDE.md`, `scripts/apply-project-agent-instructions.ps1`, `tests/test-runtime-orchestration.ps1`, `tests/test-startup-priority.ps1`, `.vscode/tasks.json`). | Vorbedingung als Regel statt Liste: **Vor jedem Changeset** wird `git status` erfasst; Dateien, die das Changeset berühren will und die fremde uncommittete Änderungen tragen, sind blockierend bis zur Klärung durch den Eigentümer. Für CS-0 verpflichtend: `lifecycle-resync.md`, `implementation-control.md` committet. |
| A5 | Plan F.2 nennt Smoke-Routen `pages`/`health`, die erst mit CS-3/CS-6 existieren. | CS-7 startet mit der aktuellen Routenliste (`portfolio, overview, waves, requirements, verification, gallery, ui-pages, findings, decisions`); Routenliste versioniert; Anpassung als Folge-Task in CS-3 (health) und CS-6 (neue IA). |

Weitere Bestätigungen: `parity_report` ist bereits als `source_type` im Status-Schema vorhanden (CS-1 braucht dafür keine Schemaänderung). `reconciliation_git.py` ist gemappt (Tier 3) und verteilt; CS-2 benötigt dadurch Impact Tier 3, aber kein Full Gate, solange `install-core.ps1` unverändert bleibt.

## Changeset-Architektur (technische Präzisierung)

Für jedes Changeset gilt: eigener Commit (oder kleine Commit-Serie) nur mit den eigenen Dateien, selektives Staging, Identitätsprüfung, STOP mit Bericht. Vollständige Vertragsfelder: [contracts/changeset-gates.md](contracts/changeset-gates.md).

| CS | Zweck | Hauptkomponenten | Kanon/Schema | Gate (Mindestumfang) | Perf-Ziel | Rollback | Unabhängig? |
|---|---|---|---|---|---|---|---|
| **CS-1** | Falsche Anzeigen beseitigen (BRD-F-01…08) | `board.js`, `serve_project_board.py`, `reconcile_external_changes.py`, `build_project_status.build_source_references` | keine | Fast + Impact Tier 3 (A1) | ±10 % | Revert | ja |
| **CS-2** | Keine interaktiven Vollscans; kein 503 | `serve_project_board.py` (Snapshot-Manager, Hintergrund-Invalidierung, Asset-Allowlist, SWR, Retry), `reconciliation_git.py` (Batch-Git), `project_compatibility.py` (Per-Dokument-Cache), Cache-Pfad-Logik in `serve_project_board.py` (R-02), Schema `projection.*` | Status-Schema additiv | Fast + Impact Tier 3 + CapTrack-Messlauf | SC-001…004 | Flag `MXAGILE_BOARD_LEGACY_CACHE=1`, dann Revert | ja |
| **CS-7** | Begrenzter Board-Smoke, OD-4 | neues `board_smoke.py`, Doctor-Flag `--board-smoke`, `install-core.ps1` (Angebot nur interaktiv + Verteilung), Impact-Mapping | keine | **Full Release Gate** (A3, Installer) | ≤ 15 s / 60 s | Flag+Angebot entfernen | ja |
| **CS-0** | Lifecycle-Klärung R1–R6 | Policies, `lifecycle.yaml`, `GLOSSARY.yaml`, `process-state.schema.json`, `project_compatibility.py`, ggf. Skills via Generator | **kanonisch** (additiv) | Fast + Impact Tier 2 + Projektionstests; CapTrack-Doctor read-only | Doctor +≤ 10 % | Revert vor Distribution | ja (nach Vorbedingung) |
| **CS-3** | Zustandsvokabular, Trennung | `build_project_status.py`, `project_compatibility.py`, `board.js`, `styles.css`, Status-Schema v3 additiv | Status-Schema | Fast + Impact Tier 2 | Build +≤ 10 % | v2-Fallback, Revert | nach CS-1 |
| **CS-4** | Projektionen, Current Work, Delivery Assessment, Vertrauen in DONE | `build_project_status.py` (neue Projektoren), `board.js`, Status-Schema; kleine Git-Abfrage „Commits seit letztem DONE" | Status-Schema | Fast + Impact Tier 2 | ≤ 300 ms warm; Git ≤ 500 ms | Feld-Flags, Revert | nach CS-3, CS-0 |
| **CS-5** | Evidenzbasierte Timeline | neues `build_project_timeline.py`, `serve_project_board.py` (`/api/timeline`), `board.js`, neues `project-timeline.schema.json` (abgeleitet), `install-core.ps1`, Mapping | abgeleitetes Schema | **Full Release Gate** (A3, Installer) | SC-010 | Endpoint/Ansicht entfernen | nach CS-2, CS-3 |
| **CS-6** | IA, Page Hub | `board.js`, `index.html`, `styles.css`, `serve_project_board.py` (`/api/page/<id>`, `/api/requirement/<id>`), Smoke-Routenliste | keine kanonische | Fast + Impact Tier 1–2 + Smoke | Route ≤ 500 ms; Hub ≤ 1 s | `#legacy/…`-Router | nein |

## Project Structure

### Documentation (this feature)

```text
specs/001-board-redesign/
├── plan.md              # dieser Plan
├── research.md          # Phase 0: technische Entscheidungen
├── data-model.md        # Phase 1: abgeleitete Entitäten, Zustände, Schemaergänzungen
├── quickstart.md        # Phase 1: Validierungs-/Messläufe je Changeset
├── contracts/
│   ├── board-http-api.md        # Endpunkte (bestehend + neu), read-only, Fehlerverhalten
│   ├── status-projection.md     # additive Felder im Status-Contract je Changeset
│   ├── timeline-event.md        # abgeleiteter Timeline-Contract (CS-5)
│   ├── board-smoke-result.md    # Smoke-Ergebnis + Exit-Codes (CS-7)
│   ├── lifecycle-rules-cs0.md   # R1–R6, Schema-Diff process-state, Doctor-Diagnosen
│   └── changeset-gates.md       # verbindliche Gate-/STOP-Tabelle je CS
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
.mxagile/
├── board/               # index.html, board.js, styles.css  (CS-1, CS-3, CS-4, CS-5, CS-6)
├── schemas/
│   ├── project-status.schema.json     # CS-2, CS-3, CS-4 (additiv)
│   ├── process-state.schema.json      # CS-0 (additiv, kanonisch)
│   └── project-timeline.schema.json   # CS-5 (neu, abgeleitet)
├── policies/            # CS-0: gap-verification-repair.md, lifecycle-resync.md*, implementation-control.md*
├── lifecycle.yaml       # CS-0 (state_tracking-Pfad)
└── GLOSSARY.yaml        # CS-0
scripts/
├── serve_project_board.py          # CS-1, CS-2, CS-5, CS-6
├── build_project_status.py         # CS-1, CS-3, CS-4
├── project_compatibility.py        # CS-2, CS-0, CS-3, CS-7 (Flag)
├── reconcile_external_changes.py   # CS-1, CS-2
├── reconciliation_git.py           # CS-2
├── build_project_timeline.py       # CS-5 (neu, verteilt)
├── board_smoke.py                  # CS-7 (neu, verteilt)
└── install-core.ps1                # CS-7, CS-5 (Verteilung)
tests/
├── test_board_http.py, test_board_performance.py, test_project_status.py, test_parity_gallery.py
├── test_board_smoke.py             # CS-7 (neu)
├── test_project_timeline.py        # CS-5 (neu)
├── test_board_states.py            # CS-3 (neu)
├── test_board_projections.py       # CS-4 (neu)
├── fixtures/board-redesign/        # Fixture-Projekt + synthetisches Git-Repo
└── run-impact-tests.py             # Mapping-Ergänzungen (CS-7, CS-5)
```
`*` = Datei trägt vorbestehende fremde Änderungen → Vorbedingung A4.

**Structure Decision**: Bestehende Struktur beibehalten; neue Logik in zwei neuen Modulen (`build_project_timeline.py`, `board_smoke.py`), damit `build_project_status.py` (2.300 Zeilen) nicht weiter wächst als für CS-3/CS-4 nötig. **Entscheidung CS-2:** Cache-/Snapshot-Logik bleibt in `serve_project_board.py`; ein eigenes verteiltes Modul würde `install-core.ps1` ändern und CS-2 zum Full-Gate-Changeset machen (research.md R-02).

## Complexity Tracking

| Abweichung | Warum nötig | Einfachere Alternative verworfen, weil |
|---|---|---|
| Hintergrund-Thread für Invalidierung (CS-2) | Request-Pfad darf keinen Scan ausführen (SC-001/002) | Synchrones Prüfen pro Request ist genau die Ursache von 3–6,5 s |
| Cache außerhalb des Projekts (CS-2, CS-5) | read-only + Neustart-Performance (SC-004) | Reiner In-Memory-Cache verliert `last-good` bei jedem Start; Cache im Projekt verletzt Doctor/Board-Read-only |
| Neues abgeleitetes Schema für Timeline (CS-5) | Determinismus und Testbarkeit des Ereignisformats | Freies JSON ohne Contract wäre nicht regressionsfest |

## Post-Design Constitution Re-Check

Nach Phase 1 (research.md, data-model.md, contracts/, quickstart.md): alle Prinzipien P1–P9 weiterhin PASS. Neue Erkenntnisse A1–A5 sind dokumentiert und ändern weder Sequenz noch Scope.
