# Research: MxAgile Dev Board Redesign

Phase 0. Alle technischen Unbekannten aus plan.md sind hier entschieden. Grundlage: Code-Lektüre
(`serve_project_board.py`, `build_project_status.py`, `reconcile_external_changes.py`, `project_compatibility.py`,
`board.js`), Impact-Mapping (`run-impact-tests.py --list --paths …`) und CapTrack-Messungen (read-only, 2026-11-05).

## R-01 · Änderungserkennung ohne interaktiven Vollscan (CS-2)

- **Decision**: Ein Hintergrund-Thread prüft höchstens alle 2 s eine **billige Signatur**: Git `HEAD`, Index-Datei (`mtime_ns`, `size`), Branch-Ref; je kanonischer Collection ein Directory-Listing mit (Name, `mtime_ns`, `size`); `*.mpr`-Stat; Modellstand über `git rev-parse HEAD:mprcontents` (tracked) plus `git status --porcelain=v1 -z --untracked-files=no -- mprcontents *.mpr` für den Dirty-Zustand. Interaktive Requests lesen nur den aktuellen Snapshot.
- **Same-mtime-Problem** (Test P3b): Für kanonische YAML/JSON-Collections wird zusätzlich `size` geprüft; der vollständige Aufbau hasht die Inhalte ohnehin (`source_fingerprint`). Bleiben `size` und `mtime` gleich, erkennt Git über den Index-Stat bzw. `git status` die Änderung. Fällt Git aus oder liegt kein Repository vor, gibt es pro Hintergrundzyklus einen Content-Hash der kanonischen Collections (wenige hundert kleine Dateien, ≤ 300 ms in CapTrack).
- **Rationale**: Die heutige Signatur walkt sechs Wurzeln inkl. 2.140 Modelldateien mit `CreateFileW` je Datei, pro Request. Gemessen 2,9–6,5 s.
- **Alternatives**: Filesystem-Watcher (plattformabhängig, zusätzliche Abhängigkeit); mtime-only (verletzt P3b); weiterhin synchron pro Request (Ursache des Problems).

## R-02 · Ort der Cache-/Snapshot-Logik (CS-2)

- **Decision**: In `serve_project_board.py` belassen (Klasse `ProjectStatusCache` erweitern) statt eines neuen Moduls.
- **Rationale**: Ein neues, an Projekte verteiltes Modul erfordert eine Änderung an `install-core.ps1` und macht CS-2 zum Full-Gate-Changeset. Die Logik ist board-spezifisch.
- **Alternatives**: eigenes Modul `board_cache.py` (sauberer, aber Full Gate); Verlagerung in `build_project_status.py` (falsche Verantwortung).

## R-03 · Cache-Verzeichnis außerhalb des Projekts

- **Decision**: Windows `%LOCALAPPDATA%\mxagile\board-cache\`, sonst `${XDG_CACHE_HOME:-~/.cache}/mxagile/board-cache/`; Unterordner `<repository_identity>/<branch_key>/` (sha256-Identitäten wie in `reconcile_external_changes._branch_state_path`). Override per `MXAGILE_BOARD_CACHE_DIR` (für Tests). Schreiben atomar (temp + replace). Fehlt das Verzeichnis oder ist es nicht beschreibbar, arbeitet das Board nur im Speicher und meldet `projection_health: CACHE_UNAVAILABLE`.
- **Rationale**: Doctor „never create project files or caches"; Board LOCAL · READ ONLY.
- **Alternatives**: `.mxagile/state/` im Projekt (verletzt read-only); OS-Temp (wird ggf. aggressiv geleert, akzeptabel als Fallback).

## R-04 · Stale-while-revalidate und kein 503 (CS-2)

- **Decision**: `last-good.json` je Branch. Beim Start wird er sofort mit `projection.state=STALE` und `age_seconds` ausgeliefert. Ändern sich Quellen während des Aufbaus (`*_SOURCES_CHANGED_DURING_*`), folgen bis zu 3 Retries mit Backoff (0,5/1/2 s). Danach wird der letzte gültige Stand mit `STALE` und dem Grund `SOURCES_CHURNING` ausgeliefert. 503 nur, wenn weder ein letzter Stand noch ein erfolgreicher Aufbau existiert (`PROJECTION_ERROR`).
- **Rationale**: In CapTrack trat der 503 unter paralleler Agentenarbeit auf.

## R-05 · Reconciliation-Batching (CS-2)

- **Decision**: Ein Prozess `git log --raw -z --no-renames --format=<sep>%H%x00%P%x00%ct ...` für die Range; Blob-Inhalte per **einem** `git cat-file --batch`-Prozess; Pfadklassifikation unverändert (`classify_path`). Ergebnis-Cache key = (HEAD, Watermark-Commit, Worktree-Status-Hash). `build_report` erhält den vorhandenen Snapshot statt `build_status` erneut aufzurufen. Der mxcli-Capability-Probe wird pro mxcli-Binary-Stat gecacht.
- **Rationale**: Heute ~40 Prozesse/Commit, ~0,27 s je Prozess unter Windows.
- **Äquivalenzbeweis**: Fixture-Repo mit Commits jeder Klassifikation; altes und neues Ergebnis werden JSON-verglichen (gleiche Commits, Pfade, Klassifikationen, Spans).

## R-06 · Compatibility-Report-Cache (CS-2)

- **Decision**: Ergebnis je Dokument key = (Pfad, sha256, Schema-Fingerprint, Regelversion), im Speicher und im OS-Cache. Dateiübergreifende Prüfungen (Duplicate IDs, Referenzen) werden weiterhin vollständig, aber auf den gecachten Einzelergebnissen berechnet.

## R-07 · Browser für den Smoke (CS-7)

- **Decision**: Reihenfolge der Erkennung: (1) Python-`playwright`, falls importierbar und Chromium vorhanden; (2) vorhandenes Node-Playwright über das bestehende Framework-Werkzeug (`playwright-cli`), aufgerufen über ein Subprozess-Skript; (3) keines → S3/S4 = UNAVAILABLE. Keine Installation im Smoke- oder Doctor-Pfad.
- **Rationale**: Python-Playwright ist keine Framework-Abhängigkeit (requirements.txt); das Framework standardisiert Node-Playwright-CLI.
- **Alternatives**: Playwright zur Pflichtabhängigkeit machen (zu schwer für Doctor); nur HTTP-Prüfung (erkennt keine JS-Fehler).

## R-08 · Smoke-Prozessführung (CS-7)

- **Decision**: Server mit `--port 0` (neues optionales Argument; heute nur feste Ports) starten, die Ready-Zeile `MxAgile Board: http://127.0.0.1:<port>/` lesen, Python mit `-B` und `PYTHONDONTWRITEBYTECODE=1`. Unter Windows Start in einer eigenen Prozessgruppe (`CREATE_NEW_PROCESS_GROUP`), sonst `start_new_session`; Ende per Terminate, nach 2 s Kill; danach prüfen, dass der Port frei ist. Gesamt-Timeout 60 s über eine Monotonic-Deadline; jede Stufe mit eigenem Budget.
- **Konsistenzwerte (S6)**: Requirement-Gesamtzahl, Tasks done/total, Waves done, Decisions PROPOSED, Findings open (bzw. Leerzustandsklasse), Health-Chip-Zustand (ab CS-3; vorher entfällt der Wert und wird mit `NOT_APPLICABLE` berichtet).

## R-09 · Beobachtungszustände (CS-3)

- **Decision**: Neues Feld `observation_state` je Bereich neben dem bestehenden `availability`. Mapping: `available` → AVAILABLE; leere Collection → EMPTY; fehlende Datei/Verzeichnis → NOT_RECORDED; `partial` → AVAILABLE + Health-Hinweis; Parse/Schema → INVALID; Legacy ohne Regel → UNSUPPORTED; bedingungslose Gaps (`MODEL_FRESHNESS_`, `PROJECT_ID_`, `OPERATING_MODE_`, `CAPABILITY_SESSION_`, `CONTEXT_SESSION_`, `MULTI_SOURCE_UNAVAILABLE`) → NOT_OBSERVABLE; Reconciliation-Platzhalter → NOT_LOADED; Workpackage fehlt → NOT_APPLICABLE (optional_metadata); Authority-Konflikte → AMBIGUOUS; Server-Fehler → PROJECTION_ERROR.
- **Wichtig**: `read_collection` liefert heute `"unavailable"` sowohl für „Verzeichnis fehlt" als auch für „alle Dateien invalide". CS-3 trennt das (NOT_RECORDED vs. INVALID).

## R-10 · Current-Work-Kaskade und „letzter DONE-Übergang" (CS-4)

- **Decision**: Kaskade gemäß Plan C.3/K.6. Den Zeitpunkt „letzter DONE-Übergang" liefert ein einziger Aufruf `git log --format=%H%x00%ct -p --unified=0 -- planning/lifecycle/process-state.yaml` (begrenzt auf 200 Commits). Daraus wird der jüngste Commit bestimmt, in dem eine Wave auf `phase: done` wechselte (YAML-Blob-Vergleich, nicht Textsuche). Danach werden Commits seit diesem Commit gezählt, die Projekt-/Modellpfade berühren (`classify_path` ∈ {MODEL, APP_SOURCE, THEME, REFERENCE}). Ist die Zahl > 0 und gibt es keine aktive kanonische Arbeit, wird `UNATTRIBUTED_DELIVERY_ACTIVITY` gesetzt. Cache pro HEAD.
- **Rationale**: Deterministisch; keine Zuordnung, nur Existenzaussage.
- **Grenze**: Ohne Git oder bei Shallow-Historie ohne diesen Commit gilt NOT_OBSERVABLE.

## R-11 · Delivery Assessment Regel v1 (CS-4, OD-1)

- **Decision**: Stufen und Bedingungen (alle aus bestehenden Policies abgeleitet; Regeltext versioniert `delivery-assessment/v1`):
  - *Implementation*: alle Tasks mit `req ∋ REQ` in Terminalzustand `done`; `deferred/blocked` → Nichterfüllungsgrund.
  - *Verification*: alle Proof Points der Test Contracts mit `requirement_ids ∋ REQ` haben Evidenz mit berechnetem PASS (via `resolve_parity_status`/Evidence-Einträge); `REPORTED_UNBOUND` zählt **nicht**.
  - *Freshness*: Ziel-Frische aus Revision/Bundle-Hash; Modellfrische NOT_OBSERVABLE bis CX-A.
  - *Blocker*: keine blockierenden Findings mit `requirement_ids ∋ REQ`; keine PROPOSED Decisions mit `affected_requirements ∋ REQ`.
  - Gesamtlabel: `NOT_STARTED | IN_PROGRESS | IMPLEMENTED | VERIFIED | BLOCKED`, immer mit Badge „abgeleitet" und Liste `reasons[]` + `evidence_refs[]`.
- **Alternatives**: Gesamtlabel weglassen (OD-1 hat Anzeige freigegeben).

## R-12 · Timeline-Index (CS-5)

- **Decision**: `build_project_timeline.py` als CLI und Bibliothek. Einmaliges `git log --raw -z --first-parent` über `last_indexed..HEAD`; Feld-Diffs nur für Status-/Phase-/Authority-Felder via `git cat-file --batch`; Trailer per `%(trailers:key=MxAgile-Mission,key=MxAgile-Change-Set,valueonly)`. Ein Change-Set gilt nur als `COMMIT_TRAILER`-Beleg, wenn es schema-valide ist und der Commit in `parent_commits`/`paths` passt. Index-Datei `timeline-<branch_key>.jsonl` + `cursor.json` im OS-Cache; Invalidierung, wenn `last_indexed` kein Vorfahr von HEAD mehr ist. `event_id = "EV-" + sha256(type|source_path|commit|field|value)[:16]`.
- **Rationale**: Deterministisch, inkrementell, Prozessanzahl konstant.

## R-13 · Page Hub Datenzuschnitt (CS-6)

- **Decision**: `/api/page/<PAGE-ID>` liefert nur eine Page: Inventory-Felder, Settings (Absicht), HTML-Quelle (Fakt), Referenz/Revision, Parity-Berichte (computed/reported/unbound), Captures nur dieser Page (inkl. vorheriger Run), Page-Ereignisse aus der Timeline, Builder-Kit-Fähigkeit. Captures werden nicht mehr global vorab geladen.

## R-14 · Vorbedingung fremder Änderungen

- **Decision**: Task T001/T002 (tasks.md) erfassen vor jedem Changeset `git status --porcelain` und blockieren, wenn das Changeset Dateien mit fremden uncommitteten Änderungen berühren müsste. Für CS-0 gilt verpflichtend, dass `lifecycle-resync.md` und `implementation-control.md` vorher vom Eigentümer committet sind. Commits stagen nur explizit benannte Dateien (`git add -- <pfade>`), nie `-A`/`.`.
