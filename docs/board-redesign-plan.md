# MxAgile Dev Board — Architektur- & UX-Redesign (Planungsbericht)

> **Status:** PLANUNG — im Grundsatz akzeptiert (2026-11-05). OD-1, OD-2, OD-4 entschieden; OD-3 in
> Abschnitt K geklärt. Verbindlicher Umsetzungsrahmen: [board-redesign-implementation-contract.md](board-redesign-implementation-contract.md).
> Keine Implementierung vor expliziter Freigabe je Changeset.
> **Stand:** 2026-11-05 · Framework `main` @ `6b5091d` (+ uncommitted Policy-Änderungen in `lifecycle-resync.md`,
> `implementation-control.md` u. a. — für OD-3 relevant, siehe K.1)
> **Realitätsreferenz:** CapTrack (`D:\MTC\Mendix\Projekte\CapTrack\CapTrack-devrick`), Branch `dev/gb`,
> Core 1.10.0 / `6b5091d`, Inspektion read-only bei HEAD `257989f1` (HEAD wanderte während der Inspektion
> durch parallele Projektarbeit auf `6d8923dc` — siehe R-12).
> **Begleitdokument:** [board-redesign-findings.md](board-redesign-findings.md) — Findings-Register (BRD-F-xx)

---

## 0. Kurzfassung

Das Board ist eine solide, sicherheitsbewusste **read-only Projektion** mit guter kanonischer Disziplin
(keine LLM-Aufrufe, Fingerprints, allowlisted Serving, kein Fabrizieren von PASS). Es scheitert aber an der
Kernfrage eines Menschen — *„Was passiert gerade, was ist zuletzt passiert, und kann ich dem DONE trauen?"* —
aus vier Gründen, die CapTrack eindeutig belegt:

1. **Diagnostik dominiert jede Ansicht.** Kopfbereich (Design Authority mit Fingerprints, Git-Drift,
   Attention, Metrics) und das Compatibility-Panel werden auf *jedem* Tab gerendert. In CapTrack: 184
   Diagnostics, **0 blockierend** (123× `UNASSIGNED` = fehlendes *optionales* `workpackage_id`,
   38× Task-Inspect-Migration) — erscheint als „183 diagnostics" über jeder Seite.
2. **Unbekannt-Zustände sind nicht unterscheidbar.** `UNKNOWN` steht gleichzeitig für „strukturell nie
   beobachtbar" (Model Freshness ist *hart kodiert* `unknown`), „noch nicht geladen" (Reconciliation-Platzhalter
   → „HEAD UNKNOWN / BASELINE REQUIRED", obwohl HEAD und Watermark existieren), „nie erfasst"
   (kein `planning/findings/`) und echte Mehrdeutigkeit.
3. **Es gibt keine Zeitachse und kein „Current Work".** Das Board liest nur Zustandssnapshots. CapTrack zeigt
   „alle 15 Waves DONE, Mission unavailable", während die echte Arbeit (Regionen-A/B HTML-first, REV-037,
   Department HTML-first, CAP2-Integration) nur in Git, Change-Sets und Decisions sichtbar ist.
4. **Performance-Architektur skaliert nicht.** Jede Anfrage (auch jedes Mockup-/Quell-Asset) walkt
   `requirements/ specs/ scripts/ planning/ input-resources/ui-ux/ mprcontents/ …` mit Windows-`CreateFileW`
   pro Datei plus `git status --untracked-files=all`: **3–6,5 s pro Request**, **~8,4 s pro Link-Klick**,
   Reconciliation **280–373 s** (~1.100 git-Prozesse).

Der Redesign-Vorschlag behält das Prinzip *„Board = read-only Projektion"* strikt bei und führt ein:

- eine **dreistufige Datenarchitektur**: kanonische Artefakte → abgeleiteter, verwerfbarer **Projection Index**
  (außerhalb des Projekts, fingerprint-gebunden) → UI; Session-Telemetrie nur als explizit flüchtige Schicht,
- ein **geschlossenes Beobachtungszustands-Vokabular** (`AVAILABLE · EMPTY · NOT_RECORDED · NOT_LOADED ·
  STALE · INVALID · UNSUPPORTED · NOT_OBSERVABLE · NOT_APPLICABLE · AMBIGUOUS · PROJECTION_ERROR`),
- eine **deterministisch rekonstruierte Timeline** (Git-Commits × Pfad→Artefakt-Mapping × Artefakt-Zeitstempel
  × Change-Sets), ohne neuen Event-Store für rekonstruierbare Ereignisse,
- **Current Work** als *abgeleitete* Sicht mit expliziter Quellenkaskade (Mission → Context Epoch → aktive Wave →
  „zuletzt beobachtet"), nie als neuer mutabler Zustand,
- Trennung **Project Attention / Projection Health / Framework Diagnostics**,
- **Page Hub** (Mockup → Page → HTML-Source → Runtime → Capture → Parity → Evidence) statt gefilterter Gallery,
- **Doctor `--board-smoke`** (Ziel < 15 s, harter Timeout 60 s),
- **7 inkrementelle Changesets**, beginnend mit risikoarmen Bugfixes und Performance.

---

## A. Ist-Architektur

### A.1 Komponenten und Datenfluss

```
Browser (board.js, Hash-Router, Vanilla DOM)
   │  GET /api/status            → Summary-Projektion (ohne Gallery, Reconciliation = Platzhalter)
   │  GET /api/reconciliation    → lazy, nach /api/status automatisch angestoßen
   │  GET /api/page-previews     → lazy, nur Tab "UI & Pages"
   │  GET /api/gallery[?screen]  → lazy, nur "Parity Gallery" / page/<id>
   │  GET /source/* /reference/* /capture/* /design-preview*/ /diagnostic-source/*
   ▼
serve_project_board.py  (ThreadingHTTPServer, 127.0.0.1, CSP, allowlist)
   │  ProjectStatusCache: In-Memory, key = source_metadata_signature()
   │    source_metadata_signature(): os.walk über STATUS_ROOTS
   │       (requirements, specs, scripts, planning, input-resources/ui-ux, mprcontents,
   │        .mxagile/schemas|tools|state) + *.mpr + STATUS_FILES
   │       + Windows ChangeTime (CreateFileW je Datei/Verzeichnis)
   │       + git rev-parse HEAD, symbolic-ref, index-Stat, git status --porcelain --untracked-files=all
   │    → pro Request erneut berechnet (auch bei Cache-Hit, auch für Assets)
   ▼
build_project_status.py  (_build_status, ~2.300 Zeilen)
   │  liest: mxagile-project.yaml, .mxagile/version.yaml, planning/lifecycle/process-state.yaml,
   │         planning/mission/mission-state.yaml, planning/lifecycle/context-epoch.yaml,
   │         requirements/*.yml, specs/*.yml, planning/tasks/*.yml, planning/decisions/*.yml,
   │         planning/findings/*.yml, planning/test-contracts/TC-*.yaml,
   │         planning/verification-plans/*.yaml, planning/ui-inventory/*.yaml,
   │         planning/evidence/manifests/*-evidence-manifest.yaml, planning/parity/*.yaml (nur Hash),
   │         planning/target-mockups/*/_history/REV-*/revision.yaml, planning/checklists/W*-…yaml
   │  + project_compatibility.compatibility_report(): Schema-Validierung + deepcopy aller Dokumente
   │  + visual_evidence_projection() (nur Gallery): Bild-Bytes lesen + hashen
   ▼
reconcile_external_changes.build_report()  (nur /api/reconciliation)
      git-Snapshot, Watermark (.mxagile/state/reconciliation/…), analyze_commit_range()
      → reconciliation_git._classify_commit: ~40 git-Prozesse pro Commit
      + resolve_impact._compute_current_fingerprint, mxcli --version/--help Probe
```

### A.2 Kanonische Quellen und was das Board davon nutzt

| Quelle | Board nutzt | Board ignoriert (aber vorhanden & relevant) |
|---|---|---|
| `mission-state.yaml` | `mission_id`, `progress.mission`, `blockers[].type` | `objective`, `progress.implementation/verification/acceptance`, `blockers[].description/blast_radius/work_that_can_continue`, `checkpoint_commits[]`, `terminal_guard_result`, `waves_in_scope` |
| `context-epoch.yaml` | `epoch_id`, `current_phase`, `pressure` | `mission.objective/status`, `lifecycle.last_completed_checkpoint`, **`next_action`**, `repository.commit`, `verified[]/failed[]/unverified[]`, `open_gates`, `artifacts[]` |
| `process-state.yaml` | `phase`, `gate_*.result` | `gate_*.evaluated` (Datum!), `paused_at`, `pause_reason`, `next_script`, `resume_from`, `build_status` |
| Decisions | `ID,title,status,affected_requirements` | `created_at`, `confirmed_at`, `rationale`, `affected_screens`, `affected_mockup_revisions`, `superseded_by`, `gap_ref` |
| Findings | sehr vollständig | — |
| Parity-Reports `planning/parity/*.yaml` | **nur über Evidence-Manifest-Entries** | `verified_at`, `overall_result`, `page_id`, `target_revision`, `app_url` — ohne Manifest-Bindung unsichtbar |
| `planning/revisions/REV-*.yaml` | **gar nicht** | `active_target`, `accepted_at`, `acceptance_decisions`, `screens` |
| Change-Sets `planning/reconciliation/change-sets/*.json` | **gar nicht** | `mission_id`, `context_epoch`, `parent_commits`, `paths`, `created_at`, `final_result` |
| Git-Historie | nur Reconciliation-Range (teuer) | Commit-Zeit, Autor, Message-Referenzen, Pfad→Artefakt |
| Delegation Results (`delegation-result.schema.json`) | gar nicht | `mission_id`, `completed_at`, `scope`, `conclusion`, `affected_ids` |

### A.3 Routing / Views

Hash-Router: `#portfolio`, `#overview`, `#waves`, `#requirements`, `#verification`, `#gallery`, `#ui-pages`,
`#findings`, `#decisions` sowie Details `#wave/<id>`, `#workpackage/<wave>/<wp>`, `#requirement/<id>`,
`#decision/<id>`, `#finding/<id>`, `#page/<PAGE-ID>` (= gefilterte Gallery). Projekt-Kontextblock
(Heading, Active Mockup, Project Drift, Human Attention, Metrics) + Compatibility-Panel auf **jedem** Tab außer Portfolio.

### A.4 Stärken, die erhalten bleiben müssen

- Read-only, Loopback, CSP, Allowlist-Serving, Symlink-/Traversal-Schutz, „DESIGN PREVIEW · NOT MENDIX RUNTIME EVIDENCE".
- Kein PASS-Fabrizieren: `resolve_parity_status` rechnet Aggregat neu, `promotion_allowed`, Identity-Binding.
- Fingerprint-gebundene Projektion (`source_fingerprint`), Single-Flight-Cache, Build-Validierung gegen Quelländerung.
- Traceability-Drilldowns Wave → Requirements/Tasks/Findings/Decisions/Evidence; Requirement → Tasks/TC/Evidence/Findings/Decisions.
- Findings-Modell (Disposition, Reconciliation-Fingerprint, Framework-Followup) — das reifste Teilmodell.
- UI & Pages: Settings-Herkunft (`requested/effective/source/scope`), Builder-Kit-Capability, Design Preview + HTML-Source.
- Reference-Authority-Modell (ACTIVE_TARGET, Revision, Bundle-Hash, Drift).
- Bestehende Tests: `test_board_http.py`, `test_board_performance.py` (Invalidierung, Single-Flight), `test-board-authority.ps1`.

### A.5 Zentrale technische Grenzen

1. Monolithische Projektion (270 KB JSON für CapTrack) wird pro Ansicht vollständig geladen und clientseitig gefiltert.
2. Invalidierung = vollständiger Metadaten-Walk pro Request (statt Ereignis-/Grenzen-basiert).
3. Kein Zeitbezug außer Fingerprint; keine Historie.
4. „Verfügbarkeit" (`available/partial/unavailable/unknown/not_loaded`) ist pro Feld ad hoc, ohne geschlossene Semantik.
5. Server baut abgeleitete Teilprojektionen (Page Previews, Builder Kit) außerhalb des Status-Contracts → Inkonsistenzen (11 vs. 10 Pages, BRD-F-09).
6. Frontend enthält Logik-Duplikate (z. B. `updatePageEvidence` wählt „latest run" anders als der Server).

---

## B. Gap-Analyse

Legende Klassifikation: **UX** = UX/Präsentation · **PROJ** = fehlende Projektion · **CAN** = fehlende kanonische Daten ·
**LEG** = Legacy-Kompatibilität · **BUG** = Implementierungsfehler · **OBS** = Observability · **PERF** = Performance · **ARCH** = Architektur.
IDs verweisen auf das Findings-Register.

| # | Befund | Klasse | Beleg (CapTrack/Code) |
|---|---|---|---|
| G-01 | Diagnostik-/Kontextblock und Compatibility-Panel auf jedem Tab | UX | `renderView()` → `renderCompatibility()`; Playwright: jede Route beginnt mit „183 diagnostics" |
| G-02 | 123 INFO-Diagnostics `UNASSIGNED` für optionales `workpackage_id` wirken wie Defekte | UX/LEG | 184 Diagnostics, 0 blocking |
| G-03 | `model_freshness` hart `unknown`, Gap `MODEL_FRESHNESS_UNAVAILABLE` bedingungslos → Recorded PASS kann *nie* VERIFIED werden | CAN/ARCH | `build_project_status.py:1939,1989` |
| G-04 | Weitere bedingungslose Gaps (`PROJECT_ID_`, `OPERATING_MODE_`, `CAPABILITY_SESSION_`, `CONTEXT_SESSION_`, `MULTI_SOURCE_UNAVAILABLE`) | UX/ARCH | `build_project_status.py:1691,1940-1943` |
| G-05 | Reconciliation-Platzhalter rendert „HEAD UNKNOWN / BASELINE REQUIRED" statt LOADING; Watermark existiert | BUG | BRD-F-01, CapTrack FINDING-018 |
| G-06 | Ohne Watermark wird bekannter HEAD nicht in `commit_range` übernommen | BUG | `reconcile_external_changes.py:350` |
| G-07 | Finding-Detail findet terminale Findings (History) nicht → Link führt ins Leere | BUG | `board.js:864` |
| G-08 | Wave-Detail „MISSION BLOCKERS 0" obwohl Mission unavailable (fabrizierte 0) | BUG | `board.js:791`; CapTrack W4a |
| G-09 | Page Previews zählen Standalone-Interaction-Artefakt als Page (11 vs. 10) | BUG | `build_page_previews` ohne `is_standalone_interaction_artifact` |
| G-10 | Page-Parität in „UI & Pages" dauerhaft `NOT_LOADED` (Gallery nie geladen) | BUG/UX | alle 11 CapTrack-Pages |
| G-11 | `implementation_mode` nur aus Konfiguration, nicht aus Page-Fakt (`html_source`) → HTML-first-Page als MENDIX_NATIVE | PROJ/CAN | PAGE-ABTEILUNGSVERWALTUNG |
| G-12 | Parity-Reports ohne Manifest-Bindung unsichtbar; keine Unterscheidung „nicht verifiziert" vs. „nicht projizierbar" | PROJ/LEG | 11 Reports (6 PASS, 5 PARTIAL) → Gallery 0 Runs |
| G-13 | Parity-Reports nicht als Quelle verlinkbar (404) | PROJ | `/source/planning/parity/…` |
| G-14 | `planning/revisions/` (Ledger mit `active_target`) nicht gelesen → REV-037 nur via 1 Page sichtbar, rev5 für 9 Pages | PROJ/LEG | CapTrack FINDING-019 |
| G-15 | Decisions: `affected_screens/mockup_revisions`, Daten, Rationale nicht projiziert; Decision-Detail ohne Inhalt | PROJ | DEC-053 Detail: nur „No explicitly linked Findings" |
| G-16 | Keine Timeline / Recent Activity | PROJ/ARCH | — |
| G-17 | Kein Current Work; Mission/Context-Epoch-Felder (`objective`, `next_action`, `checkpoint_commits`) ungenutzt | PROJ | A.2 |
| G-18 | CapTrack: keine `mission-state.yaml`/`context-epoch.yaml`, obwohl Change-Sets Missionen benennen | CAN | BRD-F-12 |
| G-19 | Neueste Waves W9a–W10c ohne kanonische Tasks; Arbeit läuft als „Kampagnen/GAP-IDs" außerhalb des Task-Modells | CAN | Waves mit 0 Tasks, Commits „Regionen parity Wave 3/4" |
| G-20 | DONE-Waves mit offenen Tasks (13 pending + 1 blocked in W1a–W7) werden nicht als Vertrauensproblem sichtbar | PROJ/UX | Legacy-Completion |
| G-21 | Requirement hat keinen Delivery-Status (Enum: draft/accepted/…); „Warum fertig?" nicht beantwortbar | PROJ/ARCH | `REQUIREMENT_STATUSES` |
| G-22 | Evidence besitzt keinen Commit-/Modell-Fingerprint → „zu welchem Stand gehört diese Evidenz?" unbeantwortbar | CAN | Schema `evidence-manifest` |
| G-23 | Findings-Verzeichnis fehlt → „UNKNOWN open/blocking…" statt „keine Findings erfasst" | UX/ARCH | CapTrack Findings-Tab |
| G-24 | Signatur-Walk pro Request inkl. `mprcontents/` (2.140 Dateien) + `git status -uall` | PERF | 3–6,5 s/Request, 8,4 s/Link |
| G-25 | Reconciliation: ~1.100 git-Subprozesse für 26 Commits | PERF | 280–373 s |
| G-26 | Kaltstart-503, wenn Quellen sich während Build ändern (parallele Agentenarbeit) — kein „last good snapshot" | ARCH/BUG | BRD-F-11 |
| G-27 | Keine Agent-/Delegations-Sicht; Delegation Results und Change-Sets nicht projiziert | OBS | — |
| G-28 | Kein automatisierter Board-Smoke im Doctor | OBS | — |
| G-29 | Mojibake in `process-state.yaml` (`\xE2\u20AC"`) wird ungefiltert angezeigt | LEG (Projektdaten) | CapTrack W1a-Notes |
| G-30 | Frontend-Duplikatlogik (latest-run-Auswahl) weicht vom Server ab | BUG | `updatePageEvidence` vs. `build_page_previews` |

---

## C. Ziel-Informationsarchitektur

### C.1 Leitprinzipien

1. **Frage zuerst, Diagnose auf Abruf.** Jede Ansicht beantwortet eine menschliche Frage; Datenqualität erscheint
   als kompakter Indikator, nicht als Inhalt.
2. **Jeder Wert trägt Herkunft.** Hover/Detail zeigt Quelle (Artefakt/Commit), Beobachtungszustand und Fingerprint.
3. **Abgeleitet ≠ kanonisch** ist visuell erkennbar (Icon/Label „abgeleitet", „zuletzt beobachtet", „live · flüchtig").
4. **Kein Zustand wird ausgeblendet** — nur richtig klassifiziert und richtig platziert.
5. **Read-only bleibt read-only.** Keine Schreib-Endpunkte; „Aktionen" sind Kopier-Hinweise (z. B. der nächste
   Skill-Aufruf), nie Mutationen.

### C.2 Navigation

```
┌ MxAgile · CapTrack ────────────────────────── [● Projection OK · 4s alt] [LOCAL · READ ONLY] ↻ ┐
│ NOW        Overview  ·  Timeline                                                              │
│ DELIVERY   Waves  ·  Requirements  ·  Tasks                                                   │
│ QUALITY    Verification  ·  Pages & Parity  ·  Findings  ·  Decisions                         │
│ SYSTEM     Health & Diagnostics  ·  Portfolio                                                 │
└───────────────────────────────────────────────────────────────────────────────────────────────┘
```

- „Parity Gallery" + „UI & Pages" verschmelzen zu **Pages & Parity** (Liste) mit **Page Hub** (Detail).
- **Tasks** wird eigene Liste (heute nur in Waves versteckt, inkl. „UNASSIGNED"-Sektion).
- **Health & Diagnostics** nimmt Compatibility-Panel, Gaps, Coverage, Projection-Timings, Builder-Kit, Settings-Herkunft auf.
- Projekt-Kontextblock verschwindet von allen Tabs außer Overview; global bleibt nur die Statuszeile (Health-Chip).

### C.3 Overview (Wireframe)

```
┌ CURRENT WORK ───────────────────────────────────────────── Quelle: mission-state.yaml ┐
│ Mission  MISSION-2026-11-CAP2 · "CAP2 Save/Undo-Integration"           ACTIVE        │
│ Phase    implementing   · Wave W10c · TASK-240 (in_progress)                          │
│ Page     PAGE-ZIELEMANAGEMENT-REGIONPLANTYP · HTML-first · Authority REV-037          │
│ Stand    Impl ● in_progress · Verify ○ not_started · Accept ○                         │
│ Commit   6d8923dc · vor 12 min · "feat(cap2): apply WP1/WP2 …"                         │
│ Weiter   next_action: "Visual parity Regionen gegen REV-037" (safe_to_run: nein)      │
└──────────────────────────────────────────────────────────────────────────────────────┘
   Fallback ohne Mission/Epoch (CapTrack heute):
┌ CURRENT WORK ─────────────────────────────────────────── abgeleitet · zuletzt beobachtet ┐
│ Keine aktive Mission erfasst (planning/mission/mission-state.yaml nicht vorhanden).     │
│ Alle 15 Waves: done.  Zuletzt beobachtete Arbeit (Git/Change-Sets):                     │
│   18:47 Change-Set CS-2026-11-05-cap2-integration · 32 Pfade · Ergebnis offen           │
│   15:43 Core-Update auf 6b5091d                                                          │
│   12:56 Department_Overview_HTML (REV-037) — PAGE-ABTEILUNGSVERWALTUNG                   │
│ ⚠ Arbeit findet außerhalb kanonischer Waves/Tasks statt (W9a–W10c: 0 Tasks)            │
└────────────────────────────────────────────────────────────────────────────────────────┘

┌ BRAUCHT DICH (Project Attention) ─────────┐ ┌ VERTRAUEN IN "DONE" ───────────────────────┐
│ 5 Decisions PROPOSED  (DEC-054, DEC-055 …)│ │ Waves done          15/15                   │
│ 1 Task blocked  TASK-231 (W7)             │ │  davon mit offenen Tasks   5  ⚠ (Legacy)   │
│ 1 Page-Identity unklar (Regionen-B)       │ │ Requirements accepted  61 · mit Evidence 0 │
│ 23 externe Commits unreconciled           │ │ Parity recorded PASS   6 · current 0        │
└───────────────────────────────────────────┘ │ Modellfrische: nicht ermittelbar (→ Health) │
                                              └─────────────────────────────────────────────┘
┌ RECENT ACTIVITY ─────────────────────────────────────────────── alle → Timeline ┐
│ 18:47 ◆ Change-Set  CAP2 Interaction/Save/Undo Integration      32 Pfade         │
│ 12:56 ● Page        Department_Overview_HTML ersetzt Navigation  REV-037 · 74b5d482│
│ 11:15 ◇ Decision    DEC-054, DEC-055 vorgeschlagen · REQ-093..095 (draft)         │
│ 07:43 ★ Authority   REV-037 → ACTIVE_TARGET (REV-020 superseded) · DEC-053        │
└──────────────────────────────────────────────────────────────────────────────────┘
┌ DESIGN AUTHORITY (kompakt) ───────────────┐ ┌ DELIVERY ──────────────────────────────────┐
│ REV-037 · 1 Page gebunden · aktiv         │ │ Waves (Phase-Streifen) · Tasks 109/123 done │
│ rev5 · 9 Pages noch gebunden  ⚠ veraltet? │ │ Requirements 61 accepted · 24 draft         │
└───────────────────────────────────────────┘ └────────────────────────────────────────────┘
```

(Die Mission-Variante ist illustrativ; die Fallback-Variante entspricht den realen CapTrack-Daten.)

**Ableitungskaskade Current Work** (spiegelt die Re-Sync-Statusregeln aus `lifecycle-resync.md`; Details K.5):

1. `mission-state.yaml` mit `progress.mission: active|blocked` → Mission, `active_wave`, Blocker.
2. Sonst: registrierte Waves in `process-state.yaml` mit nichtterminaler Phase, bestätigt durch Checkliste/Tasks
   → `ACTIVE` bzw. `BLOCKED`.
3. Sonst: registrierte Waves ohne Fortschritt → „Nächste geplante Wave" (`NOT_STARTED`).
4. Sonst: „Keine aktive kanonische Arbeit". Zeigt die Timeline nach dem letzten DONE-Übergang Commits auf
   Projekt-/Modellpfaden, erscheint zusätzlich der Health-Hinweis `UNATTRIBUTED_DELIVERY_ACTIVITY`
   („Arbeit außerhalb des kanonischen Lifecycles beobachtet") — ohne Zuordnung zu einer Wave.
5. Widersprechen sich die Quellen (z. B. `active_wave` zeigt auf eine `done`-Wave) → `CONFLICT`, nichts wird geraten.

### C.4 Weitere Ansichten (Kurzspezifikation)

| Ansicht | Inhalt | Drilldown |
|---|---|---|
| **Timeline** | Ereignisliste (D), Filter: Zeitraum, Typ, Wave, Requirement, Page, Mission/Change-Set, Autor/Quelle | jedes Ereignis → Entität / Commit-Detail |
| **Waves** | Phasenstreifen, Gate-Daten, Task-Fortschritt, „done mit offenen Tasks"-Flag, Pausen | Wave-Detail inkl. Wave-Timeline |
| **Requirements** | Tabelle + **Delivery Assessment** (C.5) + Trust-Spalte | Requirement-Detail mit Traceability-Kette und „Warum (nicht) fertig" |
| **Tasks** | Liste, Filter Status/Wave/Requirement; `UNASSIGNED` = optionaler Hinweis | Task-Detail (Inspect-Target, depends_on, Commits) |
| **Verification** | Test Contracts → Proof Points → Evidence → Parity; Freshness-Achsen getrennt | Proof-Point-/Evidence-Detail |
| **Pages & Parity** | Page-Karten: Modus, Authority, Parität, letzte Verifikation, Hub-Links | **Page Hub** (E) |
| **Findings** | aktiv/terminal, Disposition; Leerzustand nach Taxonomie | Finding-Detail (auch terminal) |
| **Decisions** | Status, Datum, Rationale-Auszug, betroffene REQ/Screens/Revisions | Decision-Detail mit Wirkungen + Timeline |
| **Health & Diagnostics** | Projection Health, Framework-Diagnostics (gruppiert), Coverage, Timings, Builder Kit | Diagnose-Gruppen → Einzelquelle |
| **Portfolio** | unverändert, aber mit Health-Chip und Current-Work-Einzeiler | — |

### C.5 Traceability & „Warum ist das fertig?"

Abgeleitete, **regelversionierte** Bewertung pro Requirement (nie zurückgeschrieben), Stufen spiegeln die
Completion-Level aus `mission-completion.md`/`mission-state.progress`:

```
REQ-018  "…"                                          Delivery Assessment (rule v1)
  Implementation   ● 4/4 Tasks done              ← TASK-061, -062, -063, -070
  Verification     ◐ 1/2 Proof Points mit PASS   ← TC-004/PP-01 PASS (SCN-CAP-SEED, 2026-11-02)
                                                    TC-004/PP-02 keine Evidenz
  Freshness        ○ Evidenz-Commit unbekannt    ← Manifest ohne captured_at_commit (G-22)
  Blocker          — keine blockierenden Findings · Decisions: DEC-012 CONFIRMED
  → Ergebnis: IMPLEMENTED · NOT VERIFIED   (Grund: PP-02 ohne Evidenz; Freshness nicht ermittelbar)
```

Fehlende kanonische Links (Review-Ergebnis):

| Link | Status heute | Vorschlag |
|---|---|---|
| Evidence-Entry → Commit/Modellstand | fehlt | `captured_at_commit`, `model_tree_oid`, `worktree_model_dirty` je Capture-Group (CAN) |
| Parity-Report → Requirement/Task | nur via Manifest | Projektion über `page_id` → Page → Requirements (`requirement.screens`) als *abgeleitet* markieren |
| Decision → Page/Revision | Schema vorhanden, nicht projiziert | projizieren (`affected_screens`, `affected_mockup_revisions`) |
| Task → Commit | fehlt | Timeline-Ableitung (Commit berührt Task-Datei / Message nennt TASK-ID; zwei Vertrauensstufen) |
| Revision-Ledger → Page | `planning/revisions` ungelesen | projizieren + Doctor-Hinweis bei ungebundenem `active_target` |
| Wave → GAP-Arbeit | vorhanden: GAP = Finding, Behebung = Repair-Task mit `wave_id` (K.2) | projizieren; Lifecycle-Klarstellung R2 (CS-0) |

---

## D. Timeline-Architektur

### D.1 Prinzip

> **Rekonstruieren statt duplizieren.** Ein Ereignis wird nur dann explizit persistiert, wenn es
> deterministisch nicht aus Artefakten + Git rekonstruierbar ist **und** dauerhafte Projektrelevanz hat.

Drei Autoritätsklassen, im UI unterscheidbar:

| Klasse | Bedeutung | Beispiel | Darstellung |
|---|---|---|---|
| `CANONICAL_RECORD` | Ereignis steht explizit in einem kanonischen Artefakt (mit Zeitstempel) | Decision `created_at`, Parity `verified_at`, Gate `evaluated`, Revision `accepted_at`, Change-Set `created_at`, Finding `updated_at`, Delegation `completed_at` | ● voll |
| `GIT_DERIVED` | Ereignis = Commit berührt kanonisches Artefakt; Inhalt per Blob-Diff deterministisch (z. B. Task-Status `pending→done`) | „TASK-231 → blocked" | ◐ mit Commit-Hash |
| `COMMIT_TRAILER` | Commit trägt `MxAgile-Mission`/`MxAgile-Change-Set`-Trailer, durch ein schema-valides Change-Set belegt (`external-change-reconciliation.md`) | Commit → CS-2026-11-02-… | ● mit Change-Set-Link |
| `GIT_MENTION` | Commit-Message nennt ID, ohne die Datei zu berühren | „feat(regions): … (REV-037)" | ○ „erwähnt in" |

Zuordnungsregel (OD-3, K.6): Ein Ereignis wird einer Wave/Mission/Requirement nur über diese Klassen zugeordnet.
Commits ohne solche Belege erscheinen in der Spur **„Nicht zugeordnet"**; zeitliche Nähe zu einer Wave ist nie ein Zuordnungsgrund.

Session-Telemetrie ist **keine** Timeline-Klasse (siehe D.6).

### D.2 Ereignistypen (v1)

| Typ | Quelle(n) | Klasse |
|---|---|---|
| `mission.started/completed/blocked` | mission-state (`created_at`, `progress.mission`-Diff), Change-Set `mission_id` | CANONICAL / GIT_DERIVED |
| `mission.checkpoint` | `mission-state.checkpoint_commits[]` | CANONICAL |
| `epoch.rollover / resume` | context-epoch (`active_context_epoch`-Diff, `last_completed_checkpoint`) | GIT_DERIVED |
| `wave.phase_changed` | process-state Blob-Diff `phase` | GIT_DERIVED |
| `wave.gate_evaluated` | `gates.*.evaluated` + `result` | CANONICAL |
| `wave.paused` | `paused_at`, `pause_reason` | CANONICAL |
| `requirement.created/changed/status_changed` | `created_at`; Blob-Diff `status` | CANONICAL / GIT_DERIVED |
| `task.status_changed` | Blob-Diff `status` | GIT_DERIVED |
| `finding.created/transitioned` | `created_at/updated_at`; Diff `lifecycle_status` | CANONICAL / GIT_DERIVED |
| `decision.proposed/confirmed/superseded` | `created_at`, `confirmed_at`; Diff `status` | CANONICAL / GIT_DERIVED |
| `authority.revision_accepted / active_target_changed` | revision `accepted_at`; Diff `active_target` / UI-Inventory `target_mockup` | CANONICAL / GIT_DERIVED |
| `page.changed` | Commit berührt `planning/ui-inventory/PAGE-*.yaml` oder `html_source`-Pfad | GIT_DERIVED |
| `model.changed` | Commit berührt `*.mpr`/`mprcontents/` (nur Zähler, keine Semantik) | GIT_DERIVED |
| `parity.verified` | parity `verified_at`, `overall_result` | CANONICAL |
| `evidence.recorded` | Manifest `created_at` / Capture `captured_at` | CANONICAL |
| `changeset.recorded` | Change-Set `created_at/updated_at/final_result` | CANONICAL |
| `delegation.completed` | delegation-result `completed_at`, `scope`, `conclusion` | CANONICAL |
| `reconciliation.performed / baseline_adopted` | Watermark `updated_at`, `reconciliation_references` | CANONICAL |
| `framework.updated / doctor_run` | `.mxagile/state/last-update-result.json`, `core-provenance.json`, Commit-Diff `version.yaml` | CANONICAL / GIT_DERIVED |
| `commit.external` | Reconciliation-Klassifikation `EXTERNAL_CHANGE/AMBIGUOUS` | GIT_DERIVED |
| `commit` (generisch) | jeder Commit mit ≥1 kanonischem/Projekt-Pfad, gruppiert | GIT_DERIVED |

### D.3 Datenmodell (abgeleitet, nicht kanonisch)

```yaml
event_id: "EV-<sha256(type|source_path|commit|field|value)[:16]>"   # deterministisch, stabil
type: task.status_changed
authority_class: GIT_DERIVED            # CANONICAL_RECORD | GIT_DERIVED | GIT_MENTION
occurred_at: "2026-11-05T12:56:10+01:00"
time_basis: commit_time                 # artifact_field | commit_time | file_record
title: "TASK-231 → blocked"
entities: [{type: task, id: TASK-231}, {type: wave, id: W7}, {type: requirement, id: REQ-071}]
links_derivation: {wave: task.wave_id, requirement: task.req}   # wie die Verknüpfung entstand
commit: {hash: 74b5d482, parents: [...], author: "…", subject: "…"}
source: {path: planning/tasks/TASK-231.yml, blob_before: …, blob_after: …}
change_set_id: CS-2026-11-05-cap2-integration     # falls Commit in change_set.parent_commits/paths
mission_id: null
```

### D.4 Rekonstruktionsstrategie

1. **Commit-Scan einmalig + inkrementell:** `git log --raw -z --no-renames --format=…` *eines* Prozesses über
   die Range `last_indexed_commit..HEAD` (statt Prozess pro Commit). Pfade → Artefaktklasse via bestehendes
   `classify_path`/Contract-Mapping.
2. **Feld-Diffs nur für relevante Artefakte:** Blob-Paare per **einem** `git cat-file --batch`-Prozess lesen,
   YAML parsen, nur Status-/Phase-/Authority-Felder vergleichen.
3. **Artefakt-Zeitstempel** (Decisions, Parity, Revisions, Gates, Change-Sets, Delegations) direkt aus aktuellem Snapshot.
4. **Merge-Regel:** CANONICAL-Zeitstempel hat Vorrang vor Commit-Zeit; Dubletten per `event_id` zusammengeführt;
   Commit bleibt als Beleg verlinkt.
5. **Index** (abgeleitet, verwerfbar, außerhalb des Projekts — G.3): Key = (repository_identity, branch, HEAD);
   Rebuild vollständig möglich. Erstaufbau CapTrack (597 Commits) geschätzt < 10 s mit Batch-Git; inkrementell < 1 s.
6. **Merge-Commits** (z. B. `6832c480`): als ein Ereignis mit First-Parent-Diff; zweiter Elternteil nur Hinweis.
7. **Shallow/Rebased History:** Index invalidiert, wenn `last_indexed_commit` nicht mehr Vorfahr von HEAD ist.

### D.5 Verhältnis zu Git, Missionen, Sessions

- **Git ist Zeitachse und Beleg, nicht Inhalt.** Die Timeline zeigt nur Commits, die kanonische oder
  projektrelevante Pfade berühren; reine Code-/Modell-Commits erscheinen gruppiert („Modell geändert · 214 Dateien").
- **Missionen:** Zuordnung über `mission-state.checkpoint_commits`, Change-Set `parent_commits`/`paths` und
  Zeitfenster `created_at…updated_at`. Ohne diese Daten keine Mission-Zuordnung (kein Raten über Zeitnähe).
- **Sessions:** nicht dauerhaft modelliert. Context-Epoch-Rollover/Resume sind die dauerhaften Session-Grenzen.

### D.6 Agent-Aktivität — Grenzziehung

| Schicht | Inhalt | Speicher | Autorität | Board-Darstellung |
|---|---|---|---|---|
| **Durable History** | Delegation Results, Change-Sets, Checkpoints, Epoch-Rollover, Gate-Ergebnisse | kanonische Artefakte (existieren) | ja | Timeline |
| **Derived State** | Current Work, Delivery Assessment, Trust | Projection Index | nein (abgeleitet) | Overview/Details |
| **Live Telemetry** | „Main Agent arbeitet", „Subagent delegiert", „Parity läuft", „Doctor läuft" | optional `…/board-cache/<repo>/live.jsonl` (außerhalb Projekt, TTL) | **nein** | eigener „LIVE · flüchtig"-Streifen, verschwindet nach TTL |

Empfehlung: Live-Telemetrie **nicht** in v1. Erst wenn ein Harness-Adapter sie standardisiert schreiben kann
(Hook), und dann ausschließlich als TTL-Datei außerhalb des Repos. Kein Agent darf daraus Zustand ableiten.

### D.7 Retention & Filter

- Kanonisch: unbegrenzt (Git). Index: Komplettwiederaufbau jederzeit; UI paginiert (50 Ereignisse/Seite).
- Filter: Zeitraum, Typ-Gruppe (Delivery/Quality/Authority/Framework/Git), Wave, Requirement, Page,
  Mission/Change-Set, Autoritätsklasse (z. B. „nur kanonisch"). Filter sind URL-Parameter (deep-linkbar).

### D.8 CapTrack-Validierung der Timeline-Annahme

| Frage | Heute beantwortbar? | Mit Timeline |
|---|---|---|
| Was wurde zuletzt bearbeitet? | Nein | Ja (Commits 05.11, Change-Set CAP2) |
| Zu welcher Wave/REQ/Task/Page? | Nein | Teilweise: Page/REV/DEC ja; Wave/Task **nein**, weil die Arbeit keine kanonischen Tasks hat (G-19) |
| Welche Decisions? | Teilweise (Liste ohne Datum) | Ja (51/55 mit `created_at`; DEC-053 → REV-037) |
| Welche Commits? | Nein | Ja (GIT_DERIVED/GIT_MENTION) |
| Deterministisch rekonstruierbar? | — | **Ja für Artefakt-Änderungen**; **nein** für Task-Übergänge vor Canonicalization (alle 123 Tasks haben `migration_date` = Einführungscommit) und für Arbeit ohne Artefakte |

→ Die Annahme „Timeline aus Artefakten + Git" trägt; sie deckt aber die **Datenlücke** (G-18/G-19) auf statt sie zu verdecken. Das ist erwünscht.

---

## E. Page- / Parity-Artefakt-Architektur

### E.1 Beziehungsmodell

```
Decision (DEC-053) ──accepts──► Revision (REV-037, active_target, artifact_hash)
                                    │ screens / affected_screens
                                    ▼
                    Page (planning/ui-inventory/PAGE-X.yaml)
                     ├─ target_mockup / target_revision ──► Reference-Datei (/reference/…)
                     ├─ html_source ──► themesource/…/X.html  (Design Preview / HTML Source)
                     ├─ mendix_page_name (page_bindings)
                     ├─ implementation_mode  = Config-Intent ⊕ Page-Fakt (E.3)
                     └─ requirements (requirement.screens ∋ PAGE-X)  [abgeleitet]
                                    │
                                    ▼
             Parity Report (planning/parity/SCN-*.yaml)
                     ├─ comparison_identity {target_page, canonical_mockup_path, revision, fingerprint}
                     ├─ verified_at · overall_result (reported) · evidence_matrix
                     └─ capture_ids ──► Evidence Manifest Entry ──► capture_groups
                                                         ├─ mockup capture  (Soll)
                                                         ├─ application capture (Ist, runtime_url)
                                                         └─ [NEU] captured_at_commit · model_tree_oid
                                    │
                                    ▼
             Board: resolve_parity_status() → computed_result + Gründe
                    + Freshness: target (Revision/Hash) · model (Tree-OID) · runtime (recorded readiness)
```

### E.2 Page Hub (Wireframe)

```
PAGE-ABTEILUNGSVERWALTUNG · Abteilungsverwaltung                 HTML-FIRST (Page-Fakt) ⚠ Config: false
Mendix: CAP_Core.Department_Overview_HTML · Requirements: REQ-0xx, REQ-0yy · Wave: —
┌ ANSEHEN ───────────────────────────────────────────────────────────────────────────────────────┐
│ [Reference REV-037 ↗]  [Design Preview ↗]  [HTML Source ↗]  [Runtime (zuletzt erfasst) ↗]       │
│ [Page-Inventory ↗]     [Parity Report SCN-CAP-DEPARTMENTS-HTMLFIRST ↗]                          │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
┌ PARITÄT ──────────────────────────────────────────────────────────────────────────────────────┐
│ Reported PARTIAL (verified_at 2026-11-05) · Computed: NICHT PROJIZIERBAR                       │
│ Grund: Report ohne comparison_identity; keine Manifest-Captures gebunden → kein Gallery-Run    │
│ Gegen: Reference input-resources/ui-ux/…rev37….html · Revision ? · Fingerprint sha256:5154…    │
│ Stand: Commit ? · Modell ? · Runtime ?                                                          │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
┌ CAPTURES ─────────── Soll | Ist | (vorheriges Ist) | [Overlay/Diff falls Artefakt vorhanden] ──┐
└────────────────────────────────────────────────────────────────────────────────────────────────┘
┌ VERLAUF (Page-Timeline) ── 12:56 Page geändert (74b5d482) · 07:43 Authority REV-037 · … ──────┐
└────────────────────────────────────────────────────────────────────────────────────────────────┘
┌ AUTHORITY & BUILD ── Builder Kit 1.4.0 (project) · Mockup-Modus guided · Konflikte: keine ─────┐
└────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### E.3 Regeln

1. **Implementation Mode** wird zweiachsig dargestellt: *Intent* (Config `ui.implementation.html_first` +
   Page-Override) und *Fakt* (Page hat auflösbare `html_source`). Abweichung = Projection-Health-Hinweis, kein Fehler.
2. **Parity-Zustände** (geschlossen): `PASS · PARTIAL · FAIL` (computed) · `NOT_VERIFIED` (kein Report) ·
   `REPORTED_UNBOUND` (Report existiert, Identity/Captures fehlen → *nicht* als verifiziert, aber sichtbar) ·
   `STALE` (Target/Modell weicht ab) · `NOT_LOADED` (nur transient).
3. Screenshots allein erzeugen nie einen Paritätsstatus (bestehende Regel bleibt).
4. Overlay/Diff wird nur angezeigt, wenn ein Diff-Artefakt im Manifest referenziert ist; das Board rechnet keine Diffs.
5. „Vorheriges Ist" = letzter historischer Run derselben Page mit anderem `run_id` (nur Anzeige).
6. Runtime-Link = zuletzt *erfasste* `runtime_url`, beschriftet „aus Evidenz vom …", nie als Live-Status.
7. Page Hub lädt nur die Daten **einer** Page (`/api/page/<id>`), nicht die ganze Gallery.

---

## F. Doctor-/Playwright-Board-Smoke

### F.1 Einordnung

- Aufruf: `python .mxagile/tools/project_compatibility.py doctor --board-smoke [--format json]`
  oder eigenständig `python .mxagile/tools/board_smoke.py --project-root .`.
- **Nicht** im Default-Doctor (Doctor bleibt reiner Datei-/Schema-Check und läuft auch ohne Browser).
  Begründung: Doctor ist Teil des Update-Completion-Pfads (`update-contract.md`) und muss schnell und
  abhängigkeitsarm bleiben; ein Browser-Start würde ihn verlangsamen und von Node/Chromium abhängig machen.
- Opt-in-Integration: `install-core.ps1` darf `--board-smoke` nach erfolgreichem Doctor *anbieten*,
  Ergebnis wird separat berichtet („Board Smoke: PASS/FAIL/UNAVAILABLE").

### F.2 Ablauf und Budget

| Stufe | Inhalt | Budget |
|---|---|---|
| S0 Preflight | Payload vorhanden (`.mxagile/board/*`), freier Loopback-Port, Python-Deps | < 0,5 s |
| S1 Server | Start mit `--port 0`, Ready-Zeile lesen; Timeout 15 s | 1–3 s (Ziel nach CS-2 Performance) |
| S2 API | `/api/status` (200, Schema-valide gegen `project-status.schema.json`), `/api/page-previews`, `/api/gallery?screen_id=<erste Page>` — **nicht** `/api/reconciliation` (S2b nur mit `--include-reconciliation`) | 2–5 s |
| S3 Browser | Chromium headless: Routen `portfolio, overview, waves, requirements, verification, pages, findings, decisions, health`; je Route: Root-Selector sichtbar, kein „Project status unavailable", kein Uncaught Error/`pageerror`, keine Console-Errors | 3–6 s |
| S4 Drilldowns | genau **eine** Wave, **ein** Requirement, **eine** Page (deterministisch: erste nach ID) | 1–2 s |
| S5 Links | max. **5** repräsentative Links per HEAD/GET: 1 Source, 1 Reference, 1 Design Preview (falls vorhanden), 1 Capture (falls vorhanden), 1 Parity-Report-Source | < 2 s |
| S6 Konsistenz | 6 Werte UI vs. API: Requirement-Gesamtzahl, Tasks done/total, Waves done, Decisions PROPOSED, Findings open (oder Leerzustand-Klasse), Health-Chip-Zustand | < 0,5 s |
| Cleanup | Browser schließen, Server terminieren (Prozessgruppe), Port-Freigabe prüfen | < 1 s |

**Zielgesamtlaufzeit:** < 15 s (nach CS-2), **harter Timeout:** 60 s gesamt, je Stufe eigener Timeout.
Vor CS-2 realistisch 30–45 s auf CapTrack (Signaturkosten).

### F.3 Fehlerverhalten & Ergebnis

```json
{
  "check": "board_smoke", "schema_version": 1, "result": "PASS|FAIL|UNAVAILABLE|TIMEOUT",
  "duration_seconds": 11.8, "core_version": "1.10.0", "project_fingerprint": "sha256:…",
  "stages": [{"id": "S3", "result": "FAIL", "seconds": 4.1,
              "failures": [{"route": "findings", "kind": "pageerror", "message": "…"}]}],
  "browser": {"available": true, "engine": "chromium", "source": "playwright-cli"},
  "artifacts": {"failure_screenshots": ["<os-temp>/mxagile-board-smoke/<run>/findings.png"]}
}
```

- Screenshots **nur bei Fehlern**, in OS-Temp (nicht im Projekt).
- Kein Browser verfügbar → `UNAVAILABLE` für S3/S4 (nicht PASS); S0–S2/S5/S6 laufen trotzdem.
- Exit-Codes: 0 PASS, 1 FAIL, 2 UNAVAILABLE (teilweise), 3 Betriebsfehler/TIMEOUT.
- Startet **nie** Mendix-Runtime, keine Parity-/Visual-Checks, kein Crawling, keine Framework-Testsuite,
  keine Projektschreibzugriffe (Python mit `-B`, Git mit `--no-optional-locks`).
- Browser-Quelle: bevorzugt vorhandene Framework-Tooling (`ensure-playwright-cli`); Python-Playwright nur, wenn
  installiert. Keine automatische Installation im Doctor-Pfad.

---

## G. Performance-Strategie

### G.1 Messungen (CapTrack, 2026-11-05)

| Vorgang | heute |
|---|---|
| Signatur pro Request (auch Cache-Hit) | 2,9–6,5 s |
| `/api/status` kalt | 8–17 s (einmal 503) |
| `build_project_status` selbst | 1,8–4,5 s (davon Compatibility 0,5–2,2 s) |
| Link-Klick Source/Reference | ~8,4 s |
| Capture-Link | ~19 s |
| `/api/reconciliation` | 280–373 s (in 3 min Sitzung nicht fertig) |
| Projektion JSON | 270 KB |

### G.2 Ursachen

1. Invalidierung per vollständigem Metadaten-Walk (inkl. `mprcontents/`, `scripts/`) und `git status -uall` **pro Request**.
2. Asset-Requests (`/reference/`, `/source/`, `/capture/`) laufen durch `_status()` → Signatur.
3. Reconciliation: Prozess-pro-Commit-Muster; zusätzlich vollständiger `build_status` innerhalb.
4. Compatibility-Report validiert & deep-copied alle Dokumente bei jedem Build.
5. Monolithische Antwort; Client lädt alles für jede Ansicht.

### G.3 Zielarchitektur

```
              ┌────────── Invalidation Sources (billig) ──────────┐
              │ git: HEAD, index-mtime+size, branch                │
              │ fs: mtime/size NUR der kanonischen Collections     │
              │     (Directory-Listing, keine CreateFileW je Datei)│
              │ Modell: *.mpr mtime/size + git tree-OID mprcontents│
              └──────────────┬─────────────────────────────────────┘
                             ▼  (max. 1×/2 s, gedrosselt; nicht pro Request)
Projection Index (abgeleitet, außerhalb des Projekts):
  %LOCALAPPDATA%/mxagile/board-cache/<repo-id>/<branch-key>/
     status-<fingerprint>.json        ← Summary-Projektion
     pages-<fingerprint>.json         ← Page/Parity-Projektion
     timeline-<head>.jsonl + cursor   ← inkrementell (D.4)
     reconciliation-<head>-<wm>-<wt>.json
     last-good.json                   ← letzter vollständiger Snapshot
                             ▼
Server: Snapshot-Serving (Assets prüfen nur Allowlist des aktuellen Snapshots, keine Neuberechnung)
```

Maßnahmen:

1. **Gedrosselte Invalidierung:** Signatur in Hintergrund-Thread, höchstens alle N Sekunden; Requests lesen den
   aktuellen Snapshot. `mprcontents/` wird nicht gewalkt — stattdessen `git rev-parse HEAD:mprcontents` +
   `git diff --quiet -- mprcontents *.mpr` (ein Prozess) bzw. `*.mpr`-Stat.
2. **Asset-Requests** nutzen den aktuellen Snapshot (Allowlist), nie eine Neuberechnung.
3. **Stale-while-revalidate:** Liegt ein `last-good`-Snapshot vor, wird er sofort mit Zustand `STALE (n s)`
   ausgeliefert, während neu gebaut wird; Quelländerung während Build → Retry mit Backoff statt 503 (behebt G-26).
4. **Reconciliation:** ein `git log --raw`, ein `git cat-file --batch`; Ergebnis-Cache pro (HEAD, Watermark,
   Worktree-Hash); kein `build_status` erneut, sondern Snapshot übergeben. Ziel < 5 s für 26 Commits.
5. **Compatibility-Report** cachen pro Dokument-Hash (Ergebnis je Datei wiederverwenden).
6. **Geteilte Endpunkte:** `/api/overview`, `/api/timeline?…`, `/api/page/<id>`, `/api/requirement/<id>`,
   `/api/health` — jeweils Ausschnitte aus demselben Snapshot.
7. **Lifecycle-Grenzen** (Gate, Commit-Checkpoint, Doctor, Update) *dürfen* den Index vorwärmen
   (z. B. Doctor schreibt nichts ins Projekt, kann aber den OS-Cache füllen). Pflicht ist das nicht —
   das Board muss ohne Vorwärmen korrekt sein.
8. **Was live bleibt:** HEAD/Branch/Worktree-dirty (billig), Health-Chip-Alter. Alles andere aus Snapshot.

Cache-Ort-Begründung: Doctor/Dry-Run „never create project files or caches" (`project-compatibility.md`) und das
Board ist LOCAL · READ ONLY → Cache außerhalb des Projekt-Worktrees; jederzeit löschbar; nie Autorität.

Zielwerte (CapTrack): erster Paint < 3 s mit last-good, kalt < 6 s; Link-Klick < 200 ms; Timeline inkrementell < 1 s;
Reconciliation < 10 s.

---

## H. Migrationsstrategie — Changesets

> Verbindliche Fassung mit Scope-Grenzen, Gates, Performance-Zielen und STOP-Punkten:
> [board-redesign-implementation-contract.md](board-redesign-implementation-contract.md). Die folgende Übersicht ist
> die Planungsbegründung; bei Abweichung gilt der Contract. Neu hinzugekommen ist **CS-0** (Lifecycle-Klärung aus OD-3).

Reihenfolge: zuerst Korrektheit & Performance ohne neue Semantik, dann Taxonomie, dann neue Sichten.
Jedes Changeset ist einzeln reviewbar, einzeln rückrollbar und ändert **keine** kanonischen Projektdaten.

### CS-1 · Board-Korrektheitsfixes (klein, sofort)
- **Zweck:** G-05, G-06, G-07, G-08, G-09, G-10, G-13, G-30.
- **Komponenten:** `board.js` (Drift-Rendering LOADING statt BASELINE/UNKNOWN; Finding-Detail sucht `history`;
  Wave-Detail ohne fabrizierte 0), `serve_project_board.py` (`build_page_previews` filtert Standalone-Interaction;
  Parity-Reports in Source-Allowlist), `reconcile_external_changes.py` (HEAD auch ohne Watermark),
  `build_project_status.build_source_references` (Typ `parity_report`).
- **Schema:** `project-status.schema.json` ggf. `source_type: parity_report` (bereits als Typ im Frontend referenziert prüfen).
- **Risiko:** niedrig. **Validierung:** `test_board_http.py` + neue Fälle (terminales Finding, Platzhalter-Rendering, 10≠11 Pages), Tier 0/1.
- **Rollback:** Revert des Commits.

### CS-2 · Performance-Grundlage
- **Zweck:** G-24, G-25, G-26.
- **Komponenten:** `serve_project_board.py` (gedrosselte Hintergrund-Signatur, Snapshot-Serving für Assets,
  stale-while-revalidate, Retry statt 503, OS-Cache-Verzeichnis), `reconciliation_git.py` (Batch-Git),
  `project_compatibility.py` (Per-Dokument-Cache).
- **Schema:** keine kanonische; neuer Projection-Contract-Hinweis `projection.age_seconds`, `projection.state`.
- **Risiko:** mittel (Invalidierungskorrektheit). **Validierung:** `test_board_performance.py` erweitern
  (P3b same-mtime-Edit muss weiterhin invalidieren; Asset-Request ohne Signatur; Quelländerung während Build → kein 503),
  Reconciliation-Äquivalenztest alt vs. neu auf Fixture-Repo; Messlauf CapTrack read-only.
- **Rollback:** Feature-Flag `MXAGILE_BOARD_LEGACY_CACHE=1` für einen Release, danach Revert möglich.

### CS-3 · Beobachtungszustands-Taxonomie & Health-Trennung
- **Zweck:** G-01–G-04, G-23, Abschnitt 5 (siehe I.1/Anhang T).
- **Komponenten:** `build_project_status.py` (strukturelle Gaps als `NOT_OBSERVABLE`-Klasse, Collections
  `EMPTY` vs. `NOT_RECORDED` vs. `INVALID`), `project_compatibility.py` (Diagnose-Gruppen: `project_attention`,
  `projection_health`, `framework_compat`; `UNASSIGNED` für optionale Felder → Gruppe „optional metadata"),
  `board.js` (Health-Chip, Health-&-Diagnostics-Ansicht, Kontextblock nur auf Overview).
- **Schema:** `project-status.schema.json` v3 (additive Felder `observation_state`, `diagnostic_group`);
  v2-Felder bleiben ein Release lang parallel.
- **Risiko:** mittel (Konsumenten von `availability`). **Validierung:** Schema-Snapshot-Test, Fixture mit allen
  Zuständen, `test-board-authority.ps1`.
- **Rollback:** Frontend fällt auf v2-Felder zurück (Feature-Detection).

### CS-4 · Fehlende Projektionen bestehender kanonischer Daten
- **Zweck:** G-11, G-12, G-14, G-15, G-17, G-20, G-21 (ohne neue kanonische Daten; Current-Work-Kaskade und
  DONE-Grundlage nutzen die CS-0-Regeln R3/R4, siehe K).
- **Komponenten:** Projektion von Mission-/Epoch-Feldern (`objective`, `next_action`, `checkpoint_commits`,
  `progress.*`), Decisions (`created_at`, `confirmed_at`, `rationale`-Auszug, `affected_screens/revisions`),
  `planning/revisions/` Ledger, Parity-Reports als `REPORTED_UNBOUND`, Implementation Mode Intent/Fakt,
  „Wave done mit offenen Tasks", Requirement **Delivery Assessment v1** (regelversioniert).
- **Schema:** Status-Contract additive Felder; keine Projektschemas.
- **Risiko:** mittel (Regeldefinition Delivery Assessment). **Validierung:** Regel-Fixtures je Stufe; CapTrack-Readonly-Abgleich.
- **Rollback:** Feld-Flags im Frontend; Projektion additiv.

### CS-5 · Timeline & Recent Activity
- **Zweck:** G-16, G-27 (durable Teil), D komplett.
- **Komponenten:** neues `build_project_timeline.py` (Batch-Git, Index im OS-Cache), `/api/timeline`,
  Overview-Recent-Activity, Timeline-Ansicht, Entity-Timelines in Details.
- **Schema:** neuer Projection-Contract `project-timeline.schema.json` (abgeleitet, nicht kanonisch).
- **Risiko:** mittel (Git-Edge-Cases: Merge, Rebase, Shallow). **Validierung:** Fixture-Repo mit synthetischer
  Historie inkl. Merge/Rebase; Determinismus-Test (zwei Läufe → identische `event_id`s); CapTrack read-only.
- **Rollback:** Endpoint + Ansicht entfernen; keine Datenfolgen.

### CS-6 · Pages & Parity Hub + IA-Umbau
- **Zweck:** E komplett, C.2/C.4 Navigation, Current Work (C.3).
- **Komponenten:** `board.js` (Navigation, Page Hub, Requirements/Tasks-Listen), `/api/page/<id>`,
  `/api/requirement/<id>`, CSS.
- **Schema:** keine kanonische.
- **Risiko:** mittel (UX-Umbau). **Validierung:** Board-Smoke (CS-7) + HTTP-Tests; Review mit PO anhand CapTrack-Screenshots.
- **Rollback:** alter Router hinter `#legacy/…` ein Release lang.

### CS-7 · Doctor `--board-smoke`
- **Zweck:** F komplett, G-28.
- **Komponenten:** `board_smoke.py`, Doctor-Flag, `install-core.ps1`-Opt-in-Report, Impact-Mapping in `tests/`.
- **Risiko:** niedrig. **Validierung:** Smoke gegen Fixture-Projekt (Tier 2), Timeout-/Cleanup-Test, „Browser fehlt" → UNAVAILABLE.
- **Rollback:** Flag entfernen.
- Hinweis: CS-7 kann **vor** CS-6 als Regressionsnetz eingeführt werden (dann Routen-Liste versioniert).

### Separate, nicht Teil des Redesigns (kanonische Datenerweiterungen — eigene Missionen)
- **CX-A** Evidence-Capture `captured_at_commit` / `model_tree_oid` / `worktree_model_dirty` (behebt G-03/G-22 an der Wurzel).
- **CX-B** entfällt als offene Entscheidung; durch OD-3/CS-0 geklärt (K). Projektseitige Nacharbeit in CapTrack bleibt Projektsache.
- **CX-C** Mission-State-Disziplin: Warum fehlt `mission-state.yaml` in CapTrack trotz Missionen? (BRD-F-12)

---

## I. Architekturentscheidungen (PO-Entscheid 2026-11-05)

| ID | Entscheidung | Auflage |
|---|---|---|
| **OD-1** | **APPROVED** — abgeleitete Requirement-/Delivery-Bewertung darf angezeigt werden | explizit als „abgeleitet" gekennzeichnet; kanonische Evidenz und Regel-Trace offenlegen |
| **OD-2** | **APPROVED (Empfehlung)** — keine Live-Agent-Telemetrie in Board V1 | dauerhafte/rekonstruierbare Vergangenheit ja; flüchtige Harness-Telemetrie out of scope |
| **OD-3** | **GEKLÄRT** in Abschnitt K — kein neues kanonisches Konzept; kleine Lifecycle-Klarstellung (CS-0) | Board zeigt nur belegte Zuordnungen |
| **OD-4** | **APPROVED (Empfehlung)** — Doctor/Core-Update dürfen den schnellen Board-Smoke *anbieten* | nie automatisch teurer Pfad; non-interaktiv/CI-sicher |

*Nicht* als offene Entscheidung geführt (aus bestehender Autorität ableitbar): Read-only bleibt; Cache außerhalb
des Projekts; Screenshots begründen keine Parität; Timeline-Ereignisse werden nicht persistiert, wenn rekonstruierbar;
Doctor-Default bleibt browserfrei.

---

## J. End-State-Walkthrough (Project Owner, CapTrack)

1. **Was macht MxAgile gerade?** Overview → *Current Work*. Mit Mission: Mission, Phase, Wave, Task, Page, Fortschritt.
   CapTrack heute: „Keine aktive Mission erfasst" + zuletzt beobachtete Change-Sets/Commits + Hinweis
   „Arbeit außerhalb kanonischer Waves" — ehrlich statt „DONE".
2. **Was ist zuletzt passiert?** *Recent Activity* (5 Einträge) → Timeline mit Filter „heute".
3. **Zu welcher Wave/REQ/Page gehört es?** Jedes Ereignis zeigt Entitätschips mit Ableitungsweg
   (z. B. „Page via geänderte PAGE-Datei", „REQ via Commit-Erwähnung").
4. **Was hat sich geändert?** Ereignis-Detail: geänderte Felder (Blob-Diff, z. B. `status: pending → done`),
   berührte Artefakte, Commit-Link.
5. **Welche Decisions wirkten?** Decision-Chips auf Page/Requirement/Revision; Decision-Detail mit Datum, Rationale,
   Wirkungen (DEC-053 → REV-037 → PAGE-ABTEILUNGSVERWALTUNG).
6. **Was ist blockiert und warum?** *Braucht dich* → TASK-231 blocked; Mission-Blocker mit `blast_radius` und
   `work_that_can_continue`; blockierende Findings mit Disposition.
7. **Was erfordert meine Aktion?** Nur Project Attention: PROPOSED Decisions, Authority-Konflikte, offene
   Page-Identity, unreconciled externe Commits. Framework-Diagnostik nur als Health-Chip.
8. **Wurde das Ergebnis verifiziert?** Requirement-/Page-Detail: computed Parity, Proof-Point-Abdeckung,
   `REPORTED_UNBOUND` klar als „berichtet, nicht belegt".
9. **Wo ist die Evidenz?** Page Hub: Soll/Ist-Captures, Parity-Report-Source, Manifest-Link.
10. **Zu welchem Commit/Runtime/Modellstand gehört sie?** Evidenz-Karte: Commit/Modell-Tree-OID (nach CX-A),
    Runtime-URL „aus Evidenz vom …"; bis dahin explizit `NOT_RECORDED` mit Erklärung.
11. **Was passiert als Nächstes?** `context-epoch.next_action` (inkl. `safe_to_run`, Prerequisites); ohne Epoch:
    „Kein nächster Schritt erfasst".
12. **Kann ich dem DONE trauen?** *Vertrauen in DONE*: Waves done mit offenen Tasks, Requirements ohne Evidenz,
    recorded vs. computed Parität, Freshness-Achsen — jeweils mit Drilldown zur Ursache.

---

## K. OD-3 — Campaign- und GAP-Arbeit im MxAgile-Lifecycle

### K.1 Autoritätsbasis (geprüft)

`lifecycle.yaml`; `policies/mission-completion.md`, `gap-verification-repair.md`,
`legacy-completion-reconciliation.md`, `project-release-checkpoint.md`, `external-change-reconciliation.md`;
Schemas `process-state`, `mission-state`, `task`, `finding`, `change-set`; `GLOSSARY.yaml`. Dazu die vor dieser Mission
**uncommitteten** Änderungen in `lifecycle-resync.md` (Re-Sync-Statusmodell) und `implementation-control.md`
(„Mission Decomposition and Wave Execution"). Auf sie stützt sich K. **Sie müssen vom Eigentümer committet sein,
bevor CS-0 beginnt.**

### K.2 Kanonische Rollen der Begriffe

| Begriff | Kanonische Rolle (Framework) | Arbeitscontainer? | Beleg |
|---|---|---|---|
| **Mission** | Autorisierter Nutzerauftrag mit `completion_boundary`; wird in Waves zerlegt; `mission-state.yaml` hält `active_wave`, `waves_in_scope`, Blocker, Checkpoints | ja (Auftrag) | mission-completion.md; implementation-control.md (neu) |
| **Wave** | Lieferungseinheit mit Lifecycle-Phasen und Gates; Phase in `process-state.yaml`, Plan/Scope in `execution-waves.md` | ja (Lieferung) | lifecycle.yaml; lifecycle-resync.md |
| **Workpackage** | Optionales, projektdefiniertes Gruppierungslabel an Task/Finding (`workpackage_id`); keine Phase, keine Gates, keine Datei | nein (Label) | task/finding-Schema; project-compatibility.md („never invented") |
| **Requirement** | Fachliche Anforderung; wird vor Ready genau einer Wave im Missionsumfang zugeordnet | nein | implementation-control.md (neu) |
| **Task / Checkliste** | Trägt die Arbeit einer Wave; `type: repair` für GAP-Behebung (`repair.gap_ids`, Bezüge zu REQ/DEC/PAGE/REV) | Arbeitseinheit | task-Schema; repair-tasks-Template |
| **GAP** | Verifizierte Abweichung vom bestätigten Soll; **kanonisch als Finding** (`planning/findings/`, `gap_type`, Lifecycle DETECTED…VERIFIED) | nein (Befund) | gap-verification-repair.md § Canonical GAP Record |
| **Campaign** | **Acceptance-Verifikationslauf** (REQUIREMENT/ROLE/RISK_CHANGE_IMPACT) als Teilschritt von `verifying`; Ergebnisse unter `planning/acceptance-campaigns/<wave>/` | **nein** | lifecycle.yaml verifying.sub_steps |
| **Change-Set** | Commit-Provenance (Pfade, Blob-IDs, Eltern), referenziert über Commit-Trailer | nein (Beleg) | change-set-Schema; external-change-reconciliation.md |

Beziehungen: `Mission 1─n Wave 1─n Task (Checkliste)`, `Task n─m Requirement`, `Finding(GAP) ─repair_task_id→ Task(repair)`,
`Finding.wave_id` = Wave, deren Ergebnis betroffen ist, `Task.wave_id` = ausführende Wave, `Campaign` ⊂ `Wave.verifying`,
`Commit ─Trailer→ Change-Set ─mission_id→ Mission`.

### K.3 Diagnose: Welche der vier Ursachen?

| Ursache | Befund | Gewicht |
|---|---|---|
| **3 · Falsche Nutzung bestehender Konzepte (CapTrack)** | „Campaign" als Arbeitsbündel statt Acceptance-Lauf; GAP-IDs (GAP-R02…) ohne Findings (`planning/findings/` fehlt) und ohne Repair-Tasks; Missionen ohne `mission-state.yaml` (nur Freitext in Change-Sets); Change-Sets mit nicht erlaubten Feldern (`gap_classification`, `final_result`, `updated_at`) als Kampagnen-Log; REV-020/REV-037-Umsetzung ohne Wave, obwohl das Projekt für REV-014/REV-017 selbst W9/W10 angelegt hat; W8 und W11 („In Arbeit") in `execution-waves.md`, aber nicht in `process-state.yaml`; W9/W10-Checklisten nicht zu Tasks kanonisiert | **Hauptursache** |
| **2 · Lifecycle-Semantik unklar (Framework)** | (a) Die Regel „GAP-Repair erzeugt keine neue Wave, gehört zum Verifikationszyklus der aktuellen Wave" deckt den Fall *keine aktuelle Wave* nicht ab. (b) Nicht festgelegt, ab wann eine geplante Wave in `process-state` registriert wird; das Board kann geplante Waves nur so erkennen. (c) `lifecycle.yaml` verweist für den State noch auf `.concord/scratch/process-state.yaml` (gitignored), alle anderen Quellen auf `planning/lifecycle/process-state.yaml`. (d) Das Glossar definiert Campaign/GAP/Change-Set/Workpackage nicht; das begünstigt die Begriffsüberladung | klein, real |
| **1 · Fehlende kanonische Beziehung (Framework)** | `lifecycle.yaml` verlangt `testability_gate` und `acceptance_gate` je Wave, `process-state.schema.json` erlaubt sie nicht (`additionalProperties: false`). Die DONE-Grundlage ist dadurch nicht strukturiert erfassbar; sie liegt nur in frei benannten Markdown-Wave-Reports (vgl. CapTrack FINDING-013) | klein, real |
| **4 · Neuer Arbeitscontainer nötig?** | **Nein.** Jede beobachtete CapTrack-Arbeit lässt sich in Mission → Wave → Task (repair) → Finding → Change-Set abbilden. Ein „Campaign"-Container würde Wave-Semantik duplizieren und gegen „keine parallele Wave-Spezifikation" (implementation-control.md) verstoßen | verworfen |

Fazit: **Hauptsächlich (3), ergänzt durch kleine Klarstellungen (2) und eine fehlende Schema-Beziehung (1).** Kein neues
kanonisches Konzept.

### K.4 Kleinstes kohärentes Lifecycle-Modell (Inhalt von CS-0)

**R1 · DONE ist unveränderlich.** `phase: done` = `ACCEPTANCE_COMPLETE` (oder `VERIFIED_LEGACY_STATE`) für den damals
autorisierten Wave-Scope. Eine `done`-Wave wird **nicht** wiedereröffnet (konsistent mit
legacy-completion-reconciliation.md „Do NOT reopen the entire Wave").

**R2 · Arbeit nach DONE geht in eine neue Wave.** Neu autorisierter Scope (neue Revision, neue/geänderte Requirements,
Remediation nach DONE) wird als neue Wave geplant, auch klein (`Significance: LOCAL` erlaubt). Die bestehende Regel
„GAP-Repair erzeugt keine neue Wave" gilt weiter, solange die betroffene Wave noch nicht `done` ist. Widerlegt neue
Evidenz eine DONE-Aussage, wird das scoped per `completion_override`/Finding erfasst (bestehender Mechanismus), und die
Behebung läuft als Repair-Task in der neuen Wave. Die Verknüpfung entsteht über vorhandene Felder:
`Finding.wave_id` = betroffene alte Wave, `Finding.repair_task_id` → Task mit `wave_id` = neue Wave.

**R3 · Wave-Registrierung bei Autorisierung.** Wird eine Wave in `execution-waves.md` autorisiert, wird im selben
Schritt ihr `process-state`-Block geschrieben (`phase: discovery`, Gates `not_recorded`). `process-state.yaml` ist damit das
vollständige maschinenlesbare Wave-Register; `execution-waves.md` bleibt die menschliche Planung. Ein registrierter Block
ohne Gate/Checkliste/Tasks erfüllt `NOT_STARTED` nach lifecycle-resync.md. Keine Schemaänderung nötig.

**R4 · Gate-Vollständigkeit.** `process-state.schema.json` erhält die von `lifecycle.yaml` bereits verlangten optionalen
Gates `testability_gate` und `acceptance_gate`. `acceptance_gate.result` umfasst zusätzlich `pending`
(lifecycle.yaml; autonomous-remediation.md schreibt `pending_decisions`), `evidence` referenziert den Wave-Report bzw. die
Campaign-Ergebnisse. Additiv und optional; Altprojekte bleiben valide.

**R5 · Begriffsklärung.** GLOSSARY erhält Mission, Workpackage, Acceptance Campaign, GAP, Repair Task und Change-Set mit
den Rollen aus K.2. `lifecycle.yaml` state_tracking wird auf `planning/lifecycle/process-state.yaml` korrigiert.

**R6 · Doctor-Sichtbarkeit (nur INFO/WARNING, nie blockierend, nie Reparatur).** Neue Diagnosen:
Change-Set verletzt Schema; Wave `done` ohne erfasste DONE-Grundlage (`acceptance_gate` fehlt, als Legacy-INFO);
`active_target`-Revision ohne Page-Bindung (CT-FINDING-019). **Kein** Markdown-Parsing von `execution-waves.md`.

Ausdrücklich **nicht** Teil von CS-0: automatische Migration von Projekten. CapTrack (oder jedes Projekt) holt R2/R3 durch
seinen eigenen Agenten über reguläre Lifecycle-Arbeit nach (W8/W11 registrieren, Mission-State anlegen, GAPs als Findings).

### K.5 Was DONE garantiert — und was nicht

| DONE garantiert | DONE garantiert nicht |
|---|---|
| Acceptance-Gate für den damaligen Wave-Scope bestanden (alle Campaigns PASS, kein offenes DECISION_REQUIRED, CRITICAL/MATERIAL GAPs VERIFIED/DEFERRED, Wave-Report) bzw. legacy-reconciled | dass alle Tasks/Checklist-Items `done` sind („acceptance evidence outranks checklist entry") |
| | dass spätere Änderungen nichts regressiert haben (dafür Overrides/Findings/Reconciliation) |
| | FEATURE_SCOPE_COMPLETE oder USER_MISSION_COMPLETE |
| | dass Evidenz zum aktuellen Modellstand gehört (Freshness, CX-A) |

Board-Folge (CS-4): „Vertrauen in DONE" zeigt je Wave die DONE-Grundlage (`acceptance_gate.evidence` oder `NOT_RECORDED`),
den Legacy-Status, offene Tasks als „durch Acceptance-Evidenz überholt" (nicht als Widerspruch, wenn eine Grundlage
existiert), spätere Overrides/Findings gegen die Wave und Commits nach DONE, die Wave-Artefakte berühren.

### K.6 Current Work und Timeline ohne erfundene Beziehungen

- **Current Work** folgt der Kaskade in C.3: Mission → registrierte aktive/blockierte Wave → nächste registrierte Wave →
  „keine aktive kanonische Arbeit" + `UNATTRIBUTED_DELIVERY_ACTIVITY`. Sie wird nie aus Commit-Messages, Branch-Namen,
  Change-Set-Freitext oder zeitlicher Nähe abgeleitet.
- **Timeline:** Zuordnung nur über `CANONICAL_RECORD`, `GIT_DERIVED` (berührte Artefaktdatei), `COMMIT_TRAILER`
  (schema-valides Change-Set) oder als `GIT_MENTION` gekennzeichnete Erwähnung. Alles andere landet in der Spur
  „Nicht zugeordnet". Ein Freitext-`mission_id` im Change-Set wird als Label angezeigt und nur bei exakter ID-Gleichheit mit
  `mission-state.mission_id` verlinkt. Schema-invalide Change-Sets erscheinen als Ereignis mit Health-Hinweis, ohne
  Zuordnungswirkung.

### K.7 CapTrack-Einordnung

CapTrack **nutzt bestehende Semantik falsch bzw. unvollständig** (K.3 Zeile 3) **und** legt zwei kleine Framework-Lücken
offen (fehlende Gates im Schema, ungeregelter Fall „Arbeit nach letztem DONE"). Nach CS-0 würde das Board für CapTrack
ohne Projektänderung korrekt zeigen: „Keine aktive kanonische Arbeit · Arbeit außerhalb des Lifecycles beobachtet
(Commits seit letztem DONE, Change-Set CAP2) · W8/W11 nicht registriert (Quelle: execution-waves.md, nur als Link)". Nach
regulärer Lifecycle-Nacharbeit durch das Projekt erscheinen W11 als ACTIVE und W8 als NOT_STARTED.

---

## Anhang T · Beobachtungszustände (Abschnitt 5 der Mission)

| Zustand | Semantik | Quelle | Projekt-Issue? | Darstellung |
|---|---|---|---|---|
| `AVAILABLE` | Wert bekannt, Quelle valide | Artefakt | — | Wert |
| `EMPTY` | Quelle existiert, 0 Datensätze | Collection vorhanden, leer | nein | „Keine X" |
| `NOT_RECORDED` | Framework kennt Quelle, Projekt hat sie nicht angelegt | Datei/Dir fehlt (z. B. `planning/findings/`, `mission-state.yaml`) | evtl. (Prozesslücke) | „Nicht erfasst" + Erklärung, Health-Hinweis |
| `NOT_LOADED` / `LOADING` | Lazy-Projektion noch nicht da | Board-intern | nie | Skeleton/Spinner, **nie als Wert** |
| `STALE` | Wert bekannt, aber an älteren Fingerprint/Target/Modell gebunden | Vergleich | ja (Verifikation) | Wert + Alters-/Grund-Badge |
| `INVALID` | Quelle existiert, Parse/Schema-Fehler | Doctor | ja (Datenqualität) | Health + betroffene Ansicht markiert |
| `UNSUPPORTED` | Quelle in Legacy-/Fremdform ohne Projektionsregel | Compatibility | nein (Framework) | Diagnostics |
| `NOT_OBSERVABLE` | Strukturell nicht ermittelbar (Modellfrische heute, Operating Mode, Session) | Framework-Grenze | nein | einmal in Health erklärt, nicht in Attention |
| `NOT_APPLICABLE` | Konzept trifft nicht zu (Checklist für Wave ohne Checklist; Workpackage optional) | Regel | nein | ausgeblendet oder „—" |
| `AMBIGUOUS` | Ermittlung versucht, widersprüchliche Quellen | Authority-Konflikte | ja | Attention |
| `PROJECTION_ERROR` | Board konnte nicht bauen | Server | nein (Tooling) | Banner + last-good |

`UNKNOWN` entfällt als Sammelbegriff; Bestandswerte werden gemappt (z. B. `model_freshness: unknown` →
`NOT_OBSERVABLE`; Reconciliation-Platzhalter → `NOT_LOADED`; Findings-Dir fehlt → `NOT_RECORDED`;
`UNASSIGNED workpackage` → `NOT_APPLICABLE`/optional).

## Anhang R · CapTrack-Realitätsabgleich der Missionsfragen

| # | Frage | heute | Ursache |
|---|---|---|---|
| R-1 | Zuletzt bearbeitet? | nein | keine Timeline (G-16) |
| R-2 | Wave/REQ/Task/Page? | nein | keine Timeline; Arbeit ohne Tasks (G-19) |
| R-3 | Welche Decisions? | teilweise | Liste ohne Datum/Wirkung (G-15) |
| R-4 | Welche Commits? | nein | nur Reconciliation-Range, 5 min |
| R-5 | Was ist DONE, warum? | irreführend | 15/15 Waves done trotz 14 offener Tasks; kein Requirement-Delivery-Status (G-20/G-21) |
| R-6 | Evidenz für DONE? | nein | 0 Evidence-Entries; Parity-Reports unsichtbar (G-12) |
| R-7 | Autoritatives Mockup je Page? | teilweise/falsch | REV-037 nur 1 Page, rev5 für 9 (G-14, CapTrack FINDING-019) |
| R-8 | Wo sind Parity-Screenshots? | nein | 58 Screenshots, Gallery 0 Runs |
| R-9 | HTML-first ohne Studio Pro? | teilweise | Design Preview/Source funktionieren (200, < 0,2 s), aber Page als MENDIX_NATIVE (G-11); RegionOverview.html ungebunden |
| R-10 | UNKNOWN echt vs. unvollständig? | nein | keine Taxonomie; s. Anhang T |
| R-11 | Aktion vs. Diagnose? | nein | 184 INFO-Diagnostics über jeder Seite (G-01/G-02) |
| R-12 | Aktivität deterministisch rekonstruierbar? | — | ja für Artefakt-Änderungen; nein für Arbeit ohne Artefakte. Live-Beleg: HEAD wanderte während der Inspektion `257989f1 → 6d8923dc` (Merge + CAP2), neues Change-Set — das Board hätte davon nichts gezeigt |

## Anhang M · Methodik & Nachweise

- Framework-Code gelesen: `serve_project_board.py`, `build_project_status.py` (Kernabschnitte), `board.js`,
  `index.html`, `reconcile_external_changes.py`, `project_compatibility.py` (Report), Schemas.
- CapTrack read-only: Artefaktzählung, Status-/Page-Preview-/Gallery-API, Playwright-Rundgang (13 Routen, 0 Console-
  /Page-Errors), Link-Checks, `git log` read-only. Python mit `-B`/`PYTHONDONTWRITEBYTECODE=1`, Git mit
  `--no-optional-locks`, Server nur Loopback, beendet. CapTrack-`git status` vor/nach unverändert durch diese Inspektion
  (die HEAD-Bewegung stammt aus paralleler Projektarbeit). `/api/reconciliation` wurde durch das Board-Frontend
  automatisch angestoßen, lief read-only und wurde mit dem Server beendet (nicht fertig).
- Temporäre Inspektionsdateien ausschließlich außerhalb beider Repositories (OS-Temp).
- Keine Tests ausgeführt außer `run-impact-tests.py --list` (Planungsmission; nur Doku geändert).
