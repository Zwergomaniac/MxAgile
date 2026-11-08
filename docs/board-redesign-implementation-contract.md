# Board-Redesign — Implementation Contract

> **Status:** ENTWURF zur Freigabe, nicht implementiert. Grundlage: [board-redesign-plan.md](board-redesign-plan.md)
> (PO-Entscheide OD-1/2/4, OD-3-Klärung in Abschnitt K), Findings: [board-redesign-findings.md](board-redesign-findings.md).
> **Freigabe erfolgt pro Changeset.** Nach jedem Changeset gilt ein STOP: Ergebnis berichten, auf ausdrückliche
> Freigabe des nächsten Changesets warten. Schweigen ist keine Freigabe.

## 0. Gemeinsame Regeln für alle Changesets

1. **Read-only-Prinzip:** Das Board schreibt nie ins Projekt. Abgeleitete Caches liegen ausschließlich außerhalb des
   Projekt-Worktrees (`%LOCALAPPDATA%/mxagile/board-cache/<repo-id>/…` bzw. XDG-Äquivalent).
2. **Keine kanonische Semantik fürs UI ändern.** Kanonische Schema- oder Policy-Änderungen gibt es nur in **CS-0**.
3. **Projektionen:** Werden kanonische Skill-/Agent-Quellen berührt, nur über `generate-mxagile-platform-skills.ps1`
   regenerieren; generierte Projektionen nie manuell bearbeiten.
4. **Verifikation (CLAUDE.md):** Vor jedem Changeset `python tests/run-impact-tests.py --list`. Fast Gate, Impact Regression
   und Full Regression werden getrennt berichtet. Unmapped Pfade und Änderungen an `install-core.ps1` bzw. am Test-Runner
   erfordern das Full Release Gate. Ein Impact-PASS ist kein Full-PASS. Fehlend, fehlgeschlagen und unvollständig bleiben
   von PASS unterschieden.
5. **Realitätsprüfung Referenzprojekt:** nur read-only (Python `-B`, Git `--no-optional-locks`, Server nur auf Loopback und
   danach beendet). Keine Projektänderung, kein Doctor-Repair.
6. **Commit-Identität:** Vor jedem Commit `git var GIT_AUTHOR_IDENT`/`GIT_COMMITTER_IDENT` = `Zwergomaniac <Keeperdeluxe@web.de>`.
   Bei Abweichung stoppen.
7. **Distribution:** Neue, an Projekte verteilte Skripte werden im kanonischen Installer-Payload ergänzt (`install-core.ps1`
   project_distributed). Das macht das Changeset zu einem Full-Gate-Changeset.
8. **Vorbedingung:** Die vor dieser Mission uncommitteten Policy-Änderungen (`lifecycle-resync.md`,
   `implementation-control.md`, `agent-delegation.md`, `test-workflow.md`, `gate-to-ready.md`, Tests) committet ihr Eigentümer
   **vor CS-0**. CS-0 baut auf ihnen auf und darf sie nicht unbemerkt mitcommitten.

## 1. Abhängigkeiten und Reihenfolge

```
CS-1 Korrektheit ──┬──────────────► CS-3 Taxonomie ──┬──► CS-4 Projektionen ──┐
                   │                                  │         ▲              ├──► CS-6 IA / Page Hub
CS-2 Performance ──┼──────────────────────────────────┴──► CS-5 Timeline ─────┘
                   │                                            ▲
CS-0 Lifecycle ────┴────────────────────────────────────────────┘ (R2/R3/R4 für CS-4; Trailer-/Zuordnungsregeln für CS-5)
CS-7 Smoke  ── unabhängig; empfohlen direkt nach CS-1/CS-2 als Regressionsnetz, Routenliste nach CS-6 aktualisieren
```

Empfohlene Reihenfolge: **CS-1 → CS-2 → CS-7 → CS-0 → CS-3 → CS-4 → CS-5 → CS-6.**

### Unabhängig commit- und reviewbar

| Changeset | Unabhängig? | Bedingung |
|---|---|---|
| CS-0 | **ja** | nach Commit der vorbestehenden Policy-Änderungen (Regel 0.8) |
| CS-1 | **ja** | — |
| CS-2 | **ja** | logisch unabhängig von CS-1; beide berühren `serve_project_board.py` → nacheinander mergen, kein gemeinsamer Commit |
| CS-7 | **ja** | Routenliste ist versioniert; nach CS-6 als Folge-Commit anpassen |
| CS-3 | bedingt | setzt CS-1 voraus (Drift-/Leerzustands-Rendering) |
| CS-4 | bedingt | setzt CS-3 und CS-0 voraus |
| CS-5 | bedingt | setzt CS-2 (Cache-/Batch-Git-Infrastruktur) und CS-3 voraus; unabhängig von CS-4 |
| CS-6 | nein | setzt CS-3, CS-4, CS-5 voraus |

---

## CS-0 · Lifecycle-Klärung (OD-3)

| Aspekt | Vertrag |
|---|---|
| **Abhängigkeit** | Regel 0.8 erfüllt. Keine Board-Abhängigkeit. |
| **Scope — enthalten** | R1–R6 aus Plan K.4: Policy-Text in `gap-verification-repair.md` (Fall „keine aktuelle Wave", R2), `lifecycle-resync.md`/`implementation-control.md` (Wave-Registrierung bei Autorisierung, R3; DONE unveränderlich, R1), `lifecycle.yaml` (state_tracking-Pfad, R5), `GLOSSARY.yaml` (Mission, Workpackage, Acceptance Campaign, GAP, Repair Task, Change-Set; R5), `process-state.schema.json` (R4), `project_compatibility.py` Doctor-Diagnosen (R6), betroffene kanonische Skills/Agents per Generator. |
| **Scope — ausgeschlossen** | Kein neues Entity und keine neue Datei-Art; kein Markdown-Parsing von `execution-waves.md`; keine automatische Projektmigration; keine Board-Änderung; keine blockierenden Doctor-Diagnosen; kein Repair. |
| **Kanon/Schema** | `process-state.schema.json`: optionale `gates.testability_gate` (gate_result) und `gates.acceptance_gate` (`result: not_recorded\|passed\|failed\|pending`, `evaluated`, `evidence`, optional `pending_decisions`). Additiv. Change-Set wird als Contract in die Doctor-Coverage aufgenommen (nur Validierung). |
| **Migration** | Keine. Bestehende Projekte bleiben schema-valide. Neue Doctor-Diagnosen sind INFO/WARNING mit `repairability: DECISION_REQUIRED` bzw. `UNSUPPORTED`. Nacharbeit (Waves registrieren, Mission-State, GAPs als Findings) ist reguläre Projekt-Lifecycle-Arbeit. |
| **Validierung** | Fast Gate; Schema-Fixtures (Alt-Block ohne neue Gates valide, neuer Block valide, `pending` nur bei acceptance_gate); Doctor-Fixtures je neuer Diagnose (INFO, nicht blockierend, Exit-Code-Vertrag 0/1/2 unverändert); `test-lifecycle-resync.ps1`, `test-architecture-drift-prevention.ps1`, Projektions-Tests nach Generatorlauf; Impact Regression. Schemas sind verteilt: falls Impact unmapped → Full Release Gate. Referenzprojekt read-only Doctor-Lauf (`doctor --format json`): erwartete neue INFO-Diagnosen (Change-Sets, DONE ohne Grundlage), **0 neue blockierende**. |
| **Performance** | Doctor-Laufzeit Referenzprojekt +≤ 10 %. |
| **Rollback** | Ein Commit; Revert stellt Schema, Policies und Doctor wieder her. Projekte, die neue Gate-Felder bereits schreiben, würden nach Revert ungültig → Revert nur vor Distribution an Projekte unkritisch; danach Vorwärtskorrektur. |
| **STOP** | Nach CS-0: Policy-Diff und Doctor-Ergebnis (Referenzprojekt read-only) vorlegen. **Agentenverhalten ändert sich** → ausdrückliche Freigabe vor Distribution und vor CS-4. |

## CS-1 · Board-Korrektheitsfixes

| Aspekt | Vertrag |
|---|---|
| **Abhängigkeit** | keine |
| **Scope — enthalten** | BRD-F-01 (Reconciliation NOT_LOADED → LOADING, nie BASELINE/HEAD UNKNOWN; günstige HEAD/Branch-Fakten aus Summary), F-02 (HEAD ohne Watermark übernehmen), F-03 (Finding-Detail inkl. `history`), F-04 (keine fabrizierte 0 im Wave-Detail), F-05 (Standalone-Interaction aus Page Previews filtern), F-06 (Page-Parität: Gallery je Page nachladen oder explizit „nicht geladen" ohne Wertanmutung), F-07 (Parity-Reports als `source_type: parity_report` verlinkbar), F-08 (eine einzige Latest-Run-Regel, serverseitig). |
| **Scope — ausgeschlossen** | Neue Ansichten, Taxonomie, Performance-Umbau, Layoutänderungen. |
| **Kanon/Schema** | keine kanonische. `project-status.schema.json` ggf. additiv `parity_report` im `source_type`-Enum. |
| **Migration** | keine |
| **Validierung** | Fast Gate; `test_board_http.py` + neue Fälle (terminales Finding, Platzhalter-Rendering, 10 statt 11 Pages, Parity-Report-Source 200, HEAD ohne Watermark); `test-reconciliation-board.ps1`; Impact Regression. Referenzprojekt read-only: die betroffenen Routen zeigen keine der alten Fehlbilder mehr. |
| **Performance** | keine Verschlechterung (Messung `MXAGILE_BOARD_PROFILE=1`, ±10 %). |
| **Rollback** | Revert eines Commits. |
| **STOP** | Nach CS-1: Testbericht und Vorher/Nachher-Screenshots (Referenzprojekt read-only). |

## CS-2 · Performance-Grundlage

| Aspekt | Vertrag |
|---|---|
| **Abhängigkeit** | keine (nach CS-1 mergen) |
| **Scope — enthalten** | Gedrosselte Hintergrund-Invalidierung (keine Signatur pro Request); kein Walk von `mprcontents/` (stattdessen Git-Tree-OID + `*.mpr`-Stat); Asset-Requests (`/source`, `/reference`, `/capture`, `/design-preview*`) gegen die Allowlist des aktuellen Snapshots; Stale-while-revalidate mit `last-good`; Retry/Backoff statt 503 bei Quelländerung während des Builds; OS-Cache-Verzeichnis; Reconciliation mit einem `git log --raw` und einem `git cat-file --batch`, Ergebnis-Cache pro (HEAD, Watermark, Worktree-Hash); Compatibility-Ergebnis-Cache pro Dokument-Hash; `projection.state`/`projection.age_seconds` im Status. |
| **Scope — ausgeschlossen** | Neue Endpunkte für Teilansichten (CS-6), Timeline (CS-5), UI-Änderungen außer Health-Alter. |
| **Kanon/Schema** | keine kanonische; Status-Contract additiv `projection.*`. |
| **Migration** | Cache-Verzeichnis entsteht beim ersten Start; jederzeit löschbar. |
| **Validierung** | Fast Gate; `test_board_performance.py` erweitert: P3b (same-mtime-Edit invalidiert weiterhin), Asset-Request ohne Signatur, Quelländerung während Build → kein 503, `last-good` korrekt als STALE markiert, kein Schreibzugriff im Projekt (Dateisystem-Diff vor/nach); Reconciliation-Äquivalenz alt vs. neu auf Fixture-Repo (identische Klassifikation); Impact Regression. `reconciliation_git.py` ist verteilt → Full Release Gate, falls unmapped. Referenzprojekt-Messlauf read-only. |
| **Performance (Referenzprojekt)** | warmes `/api/status` ≤ 300 ms; Link-Klick ≤ 200 ms; erster Paint mit `last-good` ≤ 3 s; kalt ohne Cache ≤ 6 s; Invalidierungsprüfung ≤ 1 s im Hintergrund, höchstens alle 2 s; Reconciliation (26 Commits) ≤ 10 s. |
| **Rollback** | `MXAGILE_BOARD_LEGACY_CACHE=1` für einen Release; danach Revert möglich. Cache-Verzeichnis ist folgenlos löschbar. |
| **STOP** | Nach CS-2: Messprotokoll vorher/nachher (Referenzprojekt) und Äquivalenznachweis Reconciliation. |

## CS-7 · Doctor `--board-smoke` (OD-4)

| Aspekt | Vertrag |
|---|---|
| **Abhängigkeit** | keine; Ziele erst nach CS-2 erreichbar |
| **Scope — enthalten** | `board_smoke.py` mit Stufen S0–S6 (Plan F.2); Doctor-Flag `--board-smoke`; `install-core.ps1` **bietet** den Smoke nach erfolgreichem Doctor nur interaktiv an; non-interaktiv/CI: nie automatisch, nur mit explizitem Flag; separates Ergebnis „Board Smoke"; Impact-Mapping in `tests/`. |
| **Scope — ausgeschlossen** | Default-Doctor bleibt browserfrei; `/api/reconciliation` nur mit `--include-reconciliation`; kein Mendix-Runtime-Start, keine Parity-/Visual-Prüfung, kein Crawling (max. 1 Wave, 1 Requirement, 1 Page, 5 Links), keine Framework-Testsuite, keine automatische Browser-Installation. |
| **Kanon/Schema** | keine kanonische; maschinenlesbares Ergebnisformat (`board_smoke` v1, Plan F.3). |
| **Migration** | neues verteiltes Skript → Installer-Payload. |
| **Validierung** | Fast Gate; Tier 2: Smoke gegen Fixture-Projekt (PASS); Negativfälle: JS-Fehler injiziert → FAIL mit Screenshot in OS-Temp; Browser fehlt → `UNAVAILABLE` (nicht PASS); Timeout → `TIMEOUT` + Prozess-/Port-Cleanup; non-interaktiver Installer-Lauf startet keinen Smoke. `install-core.ps1` geändert → **Full Release Gate**. |
| **Performance** | ≤ 15 s gesamt (nach CS-2), harter Timeout 60 s, Stufen-Timeouts gemäß Plan F.2. |
| **Rollback** | Flag und Installer-Angebot entfernen (ein Commit). |
| **STOP** | Nach CS-7: Laufprotokolle (Fixture + Referenzprojekt read-only), Full-Gate-Bericht. |

## CS-3 · Beobachtungszustände & Health-Trennung

| Aspekt | Vertrag |
|---|---|
| **Abhängigkeit** | CS-1 |
| **Scope — enthalten** | Geschlossenes Vokabular (Plan Anhang T) als `observation_state` je projiziertem Bereich; strukturell bedingungslose Gaps → `NOT_OBSERVABLE`; Collections `EMPTY` vs. `NOT_RECORDED` vs. `INVALID`; Diagnose-Gruppen `project_attention` / `projection_health` / `framework_compat` / `optional_metadata`; Health-Chip global; Health-&-Diagnostics-Ansicht; Kontextblock und Compatibility-Panel nur noch auf Overview bzw. Health. |
| **Scope — ausgeschlossen** | Neue Datenquellen, Timeline, Navigationsumbau (außer Health-Ansicht). Kein Zustand wird ausgeblendet, nur klassifiziert und verortet. |
| **Kanon/Schema** | keine kanonische. `project-status.schema.json` v3 additiv (`observation_state`, `diagnostic_group`); v2-Felder bleiben einen Release parallel. |
| **Migration** | Frontend erkennt v2/v3 per Feature-Detection. |
| **Validierung** | Fast Gate; Schema-Snapshot-Test; Fixture-Projekt mit jedem Zustand; `test-board-authority.ps1`; `test_board_http.py`; Impact Regression. Referenzprojekt read-only: 0 blockierende Diagnosen erscheinen nicht mehr als Projekt-Attention; `MODEL_FRESHNESS` nur einmal in Health. |
| **Performance** | `build_project_status` +≤ 10 %. |
| **Rollback** | Frontend fällt auf v2 zurück; Revert ohne Datenfolgen. |
| **STOP** | Nach CS-3: Zustands-Mapping-Tabelle (alt → neu) für Referenzprojekt zur PO-Sichtprüfung. |

## CS-4 · Projektionen vorhandener kanonischer Daten + Delivery Assessment (OD-1)

| Aspekt | Vertrag |
|---|---|
| **Abhängigkeit** | CS-3, CS-0 |
| **Scope — enthalten** | Mission/Epoch-Felder (`objective`, `progress.*`, `blockers[].description/blast_radius/work_that_can_continue`, `checkpoint_commits`, `terminal_guard_result`, `next_action`); Decisions (`created_at`, `confirmed_at`, Rationale-Auszug, `affected_screens`, `affected_mockup_revisions`); `planning/revisions/`-Ledger; Parity-Reports als `REPORTED_UNBOUND`; Implementation Mode Intent/Fakt; nicht kanonisierte Checklisten sichtbar; **Current-Work-Kaskade** (Plan C.3/K.6) inkl. `UNATTRIBUTED_DELIVERY_ACTIVITY` (nutzt eine minimale Git-Abfrage „Commits seit letztem DONE-Übergang auf Projektpfaden", ohne Timeline-Index); **Vertrauen in DONE** (Plan K.5); **Requirement Delivery Assessment v1**: regelversioniert, als „abgeleitet" gekennzeichnet, jede Stufe mit verlinkter kanonischer Evidenz und Grund bei Nichterfüllung. |
| **Scope — ausgeschlossen** | Timeline-Ansicht, Navigationsumbau, Page Hub, Zuordnung über Message-/Zeit-Heuristik, Rückschreiben jeglicher Bewertung. |
| **Kanon/Schema** | keine kanonische; Status-Contract additiv (`current_work`, `delivery_assessment{rule_version, levels[], evidence_refs[], reasons[]}`, `done_basis`). |
| **Migration** | keine |
| **Validierung** | Fast Gate; Regel-Fixtures je Assessment-Stufe inkl. Negativfälle (keine Evidenz, STALE, blockierendes Finding, Legacy-DONE ohne Grundlage); Current-Work-Fixtures für alle Kaskadenstufen inkl. `CONFLICT`; Schema-Snapshot; Impact Regression. Referenzprojekt read-only: erwartet „keine aktive kanonische Arbeit + UNATTRIBUTED_DELIVERY_ACTIVITY", REV-037 sichtbar, 6 PASS/5 PARTIAL als `REPORTED_UNBOUND`. |
| **Performance** | `/api/status` warm unverändert ≤ 300 ms; Zusatz-Git-Abfrage ≤ 500 ms, gecacht pro HEAD. |
| **Rollback** | Additive Felder; Frontend-Flags; Revert ohne Datenfolgen. |
| **STOP** | Nach CS-4: Delivery-Assessment-Regeltext v1 und Referenzprojekt-Beispiele zur PO-Abnahme (OD-1-Auflage). |

## CS-5 · Timeline & Recent Activity (OD-2: nur dauerhafte Historie)

| Aspekt | Vertrag |
|---|---|
| **Abhängigkeit** | CS-2, CS-3 (CS-0-Zuordnungsregeln gelten) |
| **Scope — enthalten** | `build_project_timeline.py` (Batch-Git, inkrementeller Index im OS-Cache, Key repository/branch/HEAD, Invalidierung bei Nicht-Vorfahr); Ereignistypen Plan D.2; Autoritätsklassen `CANONICAL_RECORD`, `GIT_DERIVED`, `COMMIT_TRAILER`, `GIT_MENTION`; Spur „Nicht zugeordnet"; `/api/timeline` mit Filtern (Zeitraum, Typ, Wave, Requirement, Page, Mission/Change-Set, Autoritätsklasse) und Paginierung; Recent Activity (5) auf Overview; Entity-Timelines in Details. |
| **Scope — ausgeschlossen** | Live-/Harness-Telemetrie (OD-2), persistierte Ereignisse im Projekt, Zuordnung über Zeitnähe/Branch-Namen/Freitext, semantische Modell-Diffs. |
| **Kanon/Schema** | keine kanonische; neuer abgeleiteter Contract `project-timeline.schema.json` (nicht kanonisch). |
| **Migration** | neues verteiltes Skript → Installer-Payload. |
| **Validierung** | Fast Gate; Fixture-Repo mit synthetischer Historie (Merge, Rebase/Force-Push, Shallow, Change-Set mit/ohne Schema-Validität, Trailer, Task-Status-Übergänge); Determinismus (zwei Läufe → identische `event_id`s); Zuordnungs-Negativtests (kein Zeitnähe-Match); Impact Regression; Installer-Payload → **Full Release Gate**. Referenzprojekt read-only: Ereignisse vom 2026-11-05 erscheinen; REF2-Commits ohne Trailer in „Nicht zugeordnet". |
| **Performance (Referenzprojekt, 597 Commits)** | Erstaufbau ≤ 10 s; inkrementell ≤ 1 s; `/api/timeline`-Seite ≤ 300 ms. |
| **Rollback** | Endpoint/Ansicht entfernen; Cache löschen; keine Datenfolgen. |
| **STOP** | Nach CS-5: Timeline-Auszug Referenzprojekt mit Autoritätsklassen zur PO-Sichtprüfung. |

## CS-6 · Informationsarchitektur & Pages-&-Parity-Hub

| Aspekt | Vertrag |
|---|---|
| **Abhängigkeit** | CS-3, CS-4, CS-5 |
| **Scope — enthalten** | Navigation NOW/DELIVERY/QUALITY/SYSTEM (Plan C.2); Overview gemäß C.3; Tasks-Liste; Page Hub (Plan E.2/E.3) mit `/api/page/<id>`; `/api/requirement/<id>`; Gallery und UI & Pages zusammengeführt; Legacy-Router `#legacy/…` einen Release lang; CS-7-Routenliste aktualisieren (Folge-Commit). |
| **Scope — ausgeschlossen** | Schreibfunktionen, Live-Telemetrie, Board-seitige Diff-Berechnung, neue kanonische Daten. |
| **Kanon/Schema** | keine kanonische; Teil-Endpunkte als Ausschnitte desselben Snapshots (Status-Contract-Unterschemata). |
| **Migration** | Deep-Links alter Routen leiten auf neue Routen um. |
| **Validierung** | Fast Gate; `test_board_http.py`; Board-Smoke (CS-7) mit neuer Routenliste; Impact Regression; PO-Review anhand Referenzprojekt-Screenshots (read-only) entlang Plan J (12 Fragen). |
| **Performance** | Routenwechsel ≤ 500 ms bei warmem Snapshot; Page Hub ≤ 1 s inkl. Captures-Metadaten. |
| **Rollback** | `#legacy/…`-Router aktivieren; Revert ohne Datenfolgen. |
| **STOP** | Nach CS-6: PO-Abnahme-Walkthrough (Plan J); danach Entfernung des Legacy-Routers nur mit eigener Freigabe. |

---

## 2. Nicht Bestandteil dieses Contracts (eigene Missionen)

- **CX-A:** Evidence-Capture `captured_at_commit` / `model_tree_oid` / `worktree_model_dirty` (kanonische
  Evidence-Schema-Erweiterung; behebt die strukturelle Modellfrische-Lücke BRD-F-20).
- **CX-C:** Ursachenanalyse fehlender `mission-state.yaml` in Projekten mit Mehrsitzungsmissionen (BRD-F-12).
- Artifact-Index-Fingerprint-Divergenz (BRD-F-26 / CT-FINDING-020).
- Projektseitige Referenzprojekt-Nacharbeit (BRD-F-13, -18, -25, -34, -36). Dafür ist das Projekt selbst zuständig, nicht diese Mission.
