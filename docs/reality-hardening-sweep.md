# Reality-Hardening-Sweep: Umsetzung und Evidence

Stand: 2026-11-15. Repository: MxAgile, Branch `experiment/control-plane-sak-principles`.
Ausgangscommit: `8ac37a7ac74476c417d0f562ccaf6444f5c8bfa0`.

## Auftrag und Grenzen

Dieser Sweep setzt bestätigte Frameworklücken um; ein Handoff gilt nicht als Umsetzung.
Inventar: 52 Einträge des Originalauftrags A1–O und 28 source-qualified CAP-FW-Aliasse.
Die acht Admin_CenterYear-Ergänzungen gehören zu denselben Findings, nicht zu einer neuen Architektur.
Die Aliasse sind keine 28 zusätzlichen unabhängigen Defekte.
Konsolidierte 80 Source-Einträge: **58 FIXED, 10 PARTIAL, 4 NOT_OBSERVABLE, 8 PARKED**.
Die acht Pilot-Ergänzungen werden zugeordnet, nicht zusätzlich als Dubletten gezählt.

CAPTRACK blieb read-only. Es wurden dort weder Modell, Runtime-State, Benutzerkontext, Jahre,
Rollen, Pages noch Planungsartefakte geändert. Die Anwendung selbst wurde durch diesen Sweep
nicht repariert und nicht erneut interaktiv bedient. Fremde Änderungen an `.gitignore` und
`.vscode/mcp.json` gehören nicht zum Paket. Kein Push und kein Full Release Gate.

**Statusdefinitionen:**

- **FIXED:** der bezeichnete Frameworkvertrag beziehungsweise reproduzierte Core-Defekt ist
  durch Code/Policy und passende Regression abgesichert. Kein impliziter CAPTRACK-App-PASS.
- **PARTIAL:** Core-Vertrag abgesichert, aber die konkrete externe Host-/Provider-Ausführung
  ist nicht bewiesen. Fehlende Live-Evidence ist ausdrücklich kein PASS.
- **NOT_OBSERVABLE:** historische Ursache, verlorene Source-Evidence oder aktuelle Ausführung
  lässt sich mit der vorhandenen Evidence nicht feststellen.
- **PARKED:** Research oder eine projekt-/source-owned fachliche Zuordnung ohne belegten Core-Fix.
  Keine stillschweigende Erfindung kanonischer Anforderungen, Wave-Zuordnungen oder Authorities.

## Umgesetzte Workstreams

### 1. Canonical Write, Recovery und Delivery

[project_compatibility.py](../scripts/project_compatibility.py),
[enforcement.py](../experiments/control-plane/enforcement.py) und
[guard.py](../experiments/control-plane/guard.py): Kandidaten vor Mutation prüfen;
Schemas, Identität, Parent- und Referenzinventare prüfen; Windows-Case-Aliasse berücksichtigen;
opaque Shell-Writes nicht durch Diagnose-/Verification-Keywords freigeben.

Bounded Repair bindet Run, Root, Target und exakt autorisiertes invalides Ergebnis an einen
Fingerprint. Geschützte Before-Felder bleiben erhalten; Snapshot/Base64/SHA werden geprüft.
Ein Journal allein autorisiert keinen TaskStop. Human Resolution und Auxiliary-Writes bleiben
an konkrete Scope-/Evidence-Verträge gebunden; kein genereller User-/Shell-Bypass.

Offene scope-relevante PROPOSED Decisions blockieren teure Umsetzung. Nichtterminale Tasks und
fehlende erforderliche Security-Evidence verhindern einen unberechtigten Wave-Abschluss.
Git-Unbeobachtbarkeit wird nicht als clean gemeldet; registrierte Capability ist keine frische
Execution-Probe. Checkpoint-Commitzahlen sind deklarierte Missiondaten, nicht Git-verifizierte Evidence.

### 2. Lifecycle, historische Anforderungen und Revisionen

[create_revision.py](../scripts/create_revision.py) verlangt eine schema-valide kanonische
CONFIRMED Decision, validiert den vollständigen Snapshot-Kandidaten vor Copy und erstellt
ACCEPTED, aber **inaktive** Revisionen. Erstellung aktiviert nichts und bindet keine Pages um.
Bundle-Namen dürfen die sichere Verzeichnisgrenze nicht verlassen.

Candidate-Prevalidation verhindert konkurrierende aktive Targets innerhalb derselben
Bundle-Namespace; eine andere Namespace bleibt unabhängig. ACCEPTED/ACTIVE braucht nichtleere
kanonische Bestätigungsreferenzen. Das Manifest-Schema ist **nicht** das Legacy-Ledger-Schema;
keine erfundenen Bundlefelder werden Legacy-Ledgern aufgezwungen.

Upstream `mockup.id` und Source-Revision sind unabhängig von Bundle-Verzeichnis und lokalem
Snapshot-Zähler. Ein Source-REV-38 kann in Snapshot REV-001 erhalten sein. Die archivierte,
fingerprinted HTML-Entrypoint-Evidence liefert die Source-Identität; Namen/Gleichzahlen allein
beweisen keine Identität. Pages dürfen `mockup_id` und einen anderen `mockup_name` besitzen.

Delivery-Preflight projiziert Page-Bindings pro aktiver Namespace/Revision. Gemeinsame
Source-/Target-Pfade sind kein Revision-Binding. Betroffene Pages werden als stale/reverify
klassifiziert; unveränderte Pages werden nicht pauschal umgebunden. Retention ist nur
**Eignung zur Wiederverwendung bereits gültiger Evidence**, niemals ein neuer Evidence-PASS.
Die Projektion ist read-only und vor Implementierung nicht automatisch blockierend.

Historische Requirement-Lifecycle-Zustände, Split/Merge/Supersession und Traceability werden
bewahrt. Scope-Ausschluss ist keine automatische Löschung bestehender Implementierung.
Ein Snapshot-Writer oder ein einzelner Schema-PASS beweist keine atomare Multi-Datei-Aktivierung;
dafür wird hier kein neuer Aktivierungsautomat eingeführt oder eine Host-Garantie behauptet.

### 3. Tooling, Runtime und Rollen

[Get-MxAgileCapabilities.ps1](../scripts/Get-MxAgileCapabilities.ps1) trennt deklarierte,
aufgefundene und ausgeführte Capability nach Provider/Host/Zeit/Evidence. Der generische
Artifact-Invariant-Evaluator prüft Nanoflow-Rollen, Replacement/Backup, JS-Identifier und
HTML-Ressourcen. Fehlende/stale Beobachtung ergibt NOT_OBSERVABLE, nicht PASS.

[Write-MxAgileEpochCheckpoint.ps1](../scripts/Write-MxAgileEpochCheckpoint.ps1) vermeidet leere
native Argumente und lehnt unstrukturierte Preflight-Ausgabe fail-closed ab.
[Save-MxAgileRoutingDecision.ps1](../scripts/Save-MxAgileRoutingDecision.ps1) lehnt Typ-Coercion,
falsche Enum-Schreibung und nichtkanonische ROUTE-/DELEGATION-Identitäten vor Persistenz ab.
Ein vollständiges minimales Writer-Input-Beispiel ist im kanonischen Delegation-Vertrag enthalten.

Runtime-Smoke bleibt scope-aware. Sichtbare Navigation/erreichbare Route, Entity-/Page-Zugriff
und sinnvolles Verhalten sind drei unabhängige Dimensionen. Model-/Schema-Clean ersetzt keine
Runtime-Evidence, keine fachliche Berechnungsbaseline und kein Security-Gate.

### 4. Update und Installation

[install-core.ps1](../scripts/install-core.ps1) und
[update-transaction.ps1](../scripts/update-transaction.ps1): Ownership-Preflight vor Mutation,
eindeutige aktuelle Update-Ergebnisse, Generation-/Attempt-Bindung, fail-closed Persistenz,
Recovery/Resume und Restart-Barriere. Keine universelle Restart-Pflicht für normale Updates.
Installer-Completion persistiert Contract-Reconciliation mit `--contract-only`: bestehende
lossless Decision-Alias-/typed-inspect-Normalisierung bleibt erhalten, gewöhnliche Project-Source-
Reparaturen und abgeleitete Task/Wave-Zuordnungen werden nicht still angewandt.
`--record-only` ist separat vollständig ohne Source-Änderungen verfügbar. Doctor invocation bleibt von validierter
Compatibility getrennt. Auch der historische `version=/commit=`-Logfilter erhält den Re-Sync-Hinweis.
Bootstrap-Logik bleibt im Core; kein impliziter lokaler Company-Layer-Fallback.

Ein echter PS5-Aufruf reproduzierte einen ANSI-/UTF8-Parserfehler vor dem vorgesehenen Guard.
UTF8 BOM plus früh platzierter Guard ergeben nun die beabsichtigte klare Ablehnung.
**PS5-Installation wird weiterhin nicht unterstützt.** Die drei Entry Points wurden in eigenen
Fixtures tatsächlich mit Windows PowerShell 5.1 aufgerufen, nicht nur statisch gemustert.

### 5. Observability, Fingerprints und Test-Gates

[build_project_status.py](../scripts/build_project_status.py),
[wave_ids.py](../scripts/wave_ids.py), [run_events.py](../scripts/run_events.py) und Board:
Plan-/Commit-Evidence ist keine Lifecycle-Authority; zusammengesetzte Wave-IDs bleiben erhalten;
Legacy-Unklarheit wird nicht als DONE normalisiert. Run/Child/Orphan und Restart/Resync bleiben
getrennt; Sequenzierung über Resume und Clock-Skew ist abgesichert.

Builder, Resolver und KnowledgeGraph verwenden dieselbe Sourceauswahl und Fingerprint-Berechnung.
Standalone Interaction-/Impact-Analysen werden nicht als Pages/TCs fehlklassifiziert. Der Builder
wird neben den Consumern installiert. Board-Cache berücksichtigt Context Epoch und Migration State;
Contract-Lookups bleiben bounded/cached. NOT_LOADED ist nicht MISSING.

[run-impact-tests.py](../tests/run-impact-tests.py) verweigert auch einen Fast-PASS bei unmapped
Pfaden. Native Windows-Pfade werden vor Matching/Deduplikation normalisiert; zentrale
Compatibility-Änderungen selektieren auch Canonical-/Preflight-/Guard-Consumer.
Diff-Check bleibt auf den angegebenen Scope begrenzt. Mapping ist eine Auswahlhilfe,
keine Behauptung eines Full Regression PASS.

## Findings-Inventar A1–O

Evidence-Kürzel (konkrete Testdateien unterhalb verlinkt):
**CW** CanonicalWriteReality/Recovery/Auxiliary; **PH** PhasePreflight/Guard;
**LC** LifecycleReality/Revision/SPA-CLI; **TO** RealityTooling;
**UP** FrameworkUpdateRecovery/Install-/Bootstrap-Fixtures;
**OB** ProjectStatus/BoardPerformance/RunEvents/WaveIds;
**RO** ResourceOwnership/Child/Phase1b/Phase2;
**IM** TestImpact/Fast-Gate.

| ID | Status | Zuordnung / Ergebnis / Evidence-Grenze |
|---|---|---|
| A1 | FIXED | Candidate-, Schema-, Identity-, Parent-/Referenzprüfung, native Aliasse; CW |
| A2 | FIXED | Integrity-/Run-bound Repair und exact-result Rollback; CW |
| A3 | FIXED | Evidence-bound Human Resolution, kein Recovery-Generalbypass; CW |
| A4 | FIXED | Scoped Auxiliary create/replace/delete/interrupt; CW |
| A5 | FIXED | Blocked-Delivery-Matrix trennt Canonical/Product/Auxiliary; CW/RO |
| B1 | FIXED | Scoped PROPOSED Decisions vor teurer Arbeit; PH |
| B2 | FIXED | Preflight/Checkpoint-Observability, unknown Git nicht clean; PH |
| C1 | FIXED | Compound Wave IDs; OB |
| C2 | FIXED | Plan/Git nicht Lifecycle-Authority; OB/LC |
| C3 | FIXED | Legacy UNKNOWN braucht Reconciliation, kein Auto-DONE; OB/LC |
| D1 | FIXED | Historische Requirements, Split/Merge/Supersession; LC |
| D2 | FIXED | Retirement entfernt nicht automatisch Implementierung; LC/Policy |
| D3 | FIXED | Source-/Canonical-Identitäten und Lifecycle getrennt; LC |
| E1 | FIXED | Neue Source löst Reconciliation aus, Pfadgleichheit reicht nicht; LC |
| E2 | FIXED | Embedded Contract als Source-Evidence, Fingerprint-/Identity-Abgleich; LC |
| E3 | FIXED | Readiness, Acceptance und ACTIVE_TARGET unabhängig; LC; kein Atomic-Host-PASS |
| E4 | FIXED | Namespace-/Scope-selektives Binding, stale vs reuse eligibility; LC |
| F1 | FIXED | PS5 native args/Output-Recovery; früher UTF8-Guard separat; TO/UP |
| F2 | PARTIAL | Start-/Progress-Vertrag abgesichert; konkrete Concord-Host-Start-/Progress-Ausführung nicht bewiesen |
| F3 | PARTIAL | Capability-Trennung implementiert; aktueller SP-MCP erklärt available, browser_* nicht entdeckt |
| F4 | PARTIAL | Sync-Barrier-/Merge-Vertrag abgesichert; kein echter cross-tool Sync/MPR-Write im readonly Pilot |
| F5 | PARTIAL | Lossless-Write-/Fidelity-Vertrag; reale Concord-Serialisierung nicht roundtrip-verifiziert |
| F6 | FIXED | Capability-first Routing, missing Probe kein declared PASS; TO/PH |
| G1 | FIXED | Generische Nanoflow-Rollen-Invariante; TO; kein neuer CAP-Model-PASS |
| G2 | FIXED | Replacement/Backup-Exclusion, Rollen und Navigation; TO |
| G3 | FIXED | Exakte generierte JS-Identifier, nicht Display Names; TO |
| G4 | FIXED | HTML-Bridge-Ressourcen nur materialisiert/explicit geladen; TO |
| G5 | FIXED | Scope-aware Runtime-Smoke, Source-Claim kein Runtime-PASS; TO/RO |
| H1 | FIXED | Discoverability/Authorization/Behavior getrennt; TO/Policy |
| H2 | FIXED | Erforderliche eigene fingerprinted Security-Evidence; PH |
| H3 | FIXED | Deklarierte Berechnungsbaseline plus Build/Model-Evidence; LC/Merge-Preflight |
| I1 | FIXED | Writer/Schema/Policy-Drift, identity, Enum-/Typ-Coercion, vollständiges Input; TO |
| I2 | PARTIAL | Name-only Child-Allow geschlossen; echte Host-ReadOnly-Enforcement nicht bewiesen; RO |
| I3 | PARTIAL | Trusted inner-operation Boundary verlangt; Live-Dispatcher-Interception nicht bewiesen; RO |
| I4 | PARTIAL | Profile-/Actual-Resolution getrennt; tatsächliches Child-Modell nicht host-verifiziert |
| J1 | FIXED | Recovery-Update in blocked state bleibt scope-bound; UP/CW |
| J2 | FIXED | Projection Ownership vor Mutation; UP |
| J3 | FIXED | Partial Update/Resume generation-bound; UP |
| J4 | FIXED | Ein aktuelles persisted Result, kein gemischter Attempt-PASS; UP |
| J5 | FIXED | Provenance/Attempt/Fingerprint, Persistenz fail-closed; UP |
| J6 | FIXED | Human Resolution ohne fremde Ownership zu überschreiben; UP/CW |
| J7 | FIXED | Restart/Resync nur für tatsächlich erforderliche Recovery; UP |
| K1 | FIXED | Run-/Event-Sequenz, Resume/Clock-Skew; OB |
| K2 | FIXED | Control-Plane-Projektion mit klarer Observability; OB |
| K3 | FIXED | Current/Previous Run und Orphans getrennt, kein falsches Completed; OB/RO |
| K4 | FIXED | Scoped Finding-/Diagnostic-Writes ohne Lifecycle-Authority; CW |
| L1 | NOT_OBSERVABLE | Historische konkrete TaskStop-Ursache unbekannt; nicht nachträglich PID-/Journal-Evidence erfinden |
| L2 | FIXED | Journal/PID allein kein TaskStop-Allow; trusted current host ownership nötig; RO |
| M1 | PARTIAL | Fingerprinted Result Reuse abgesichert; reale Host-Compaction-/Causality nicht beobachtet |
| M2 | FIXED | Bounded Input-/Output-Vertrag, kompakte Ergebnisse; TO/Policy; keine erfundenen Cost-Zahlen |
| N | FIXED | Scope-aware angemessene Dev-/Impact-Auswahl, unmapped fail-closed; IM |
| O | PARKED | Capability-aware Delivery Planning ist Research; keine belastbare taktische Operations-/Fidelity-/Cost-Matrix |

## Historischer CAP-Crosswalk und Dubletten

Quelle: readonly CAPTRACK `.mxagile/state/framework-findings.md`; Zeilen beziehen sich auf den
inspizierten Source-Snapshot. FIXED schließt die genannte Core-Regression, nicht offene fachliche
Datenkorrekturen des Consumerprojekts.

| Alias | Source-Zeile | Status | Zusammenführung / konkrete Grenze |
|---|---:|---|---|
| CAP-FW-001 | 11 | FIXED | F1/J: UTF8/PS5 früher Guard; echte PS5-Fixtures |
| CAP-FW-002 | 38 | NOT_OBSERVABLE | F6: historisches mxcli v0.24/migrate-contract; aktuelle Operation nicht ausgeführt |
| CAP-FW-003 | 62 | PARKED | H1: fehlende deklarierte DC-Rollenintention; kein belegter Core-Defekt, keine Rollen erfinden |
| CAP-FW-004 | 82 | FIXED | C/D: kanonische Reader grenzen Story-MD aus; physische Projektmigration separat |
| CAP-FW-005 | 104 | PARKED | D/E: HTML-abgeleitete States ohne vollständige Source-Deklaration; keine automatische AC-Erfindung |
| CAP-FW-006 | 123 | NOT_OBSERVABLE | G5: historische expand/collapse Runtime-Evidence; kein neuer interaktiver CAP-Test |
| CAP-FW-007 | 139 | FIXED | E1/E4: shared path kein Binding; namespaces/Source-Counter getrennt; LC |
| CAP-FW-008 | 158 | NOT_OBSERVABLE | D1/E: historische Rev6–8 HTML/Hashes fehlen; Snapshot-Creator rekonstruiert sie nicht |
| CAP-FW-009 | 180 | FIXED | D3/E2: Source-/Canonical-Namespace getrennt, exact identity statt Nummerngleichheit |
| CAP-FW-010 | 209 | FIXED | D3/E2: ID-Collision kein semantischer Mapping-PASS |
| CAP-FW-011 | 227 | FIXED | C/K: typed inspect projections; fehlende Expectation bleibt fehlend |
| CAP-FW-012 | 259 | PARKED | Discovery-Legacy-Payload ohne Wave: keine lossless scenarios→entries Zuordnung belegbar |
| CAP-FW-013 | 289 | PARKED | Fremde process-state Authorities: erkannt/bewahrt, fachlicher Owner-Split nicht deklariert |
| CAP-FW-014 | 326 | PARKED | Impact-Analyse nicht als TC lesen ist korrigiert; eigene neue Artifact-Authority nicht belegt |
| CAP-FW-015 | 363 | PARKED | Interaction nicht als Page lesen ist korrigiert; eigene Metadata-Authority nicht erfunden |
| CAP-FW-016 | 380 | FIXED | K2: kompakte Overview/Source-Tooltip-Projektion; Board-Evidence |
| CAP-FW-017 | 397 | FIXED | K2/N: request-window Cache und bounded Contract-Lookup; Backend-Regressionsprobe, kein CAP-UX-Latenz-PASS |
| CAP-FW-018 | 418 | FIXED | K2: NOT_LOADED vs MISSING, HTTP-/Board-Evidence |
| CAP-FW-019 | 435 | FIXED | E/K: Ledger oder Diagnostic sichtbar, shared path nicht gebunden |
| CAP-FW-020 | 454 | FIXED | E/N: Builder/Resolver/Graph gleiche Fingerprints; Builder installiert |
| CAP-FW-021 | 490 | PARKED | Projekt-owned Page-Mapping; keine readonly Consumerkorrektur und kein bestätigter Core-Defekt |
| CAP-FW-022 | 497 | FIXED | J3/J4/J5: Update-Generationen/Attempts/Results getrennt |
| CAP-FW-023 | 519 | FIXED | A1/A2: Prevalidation/Bounded Repair statt invalid-write Selflock |
| CAP-FW-024 | 540 | FIXED | F1: keine leeren native args, malformed Preflight-JSON blockiert |
| CAP-FW-025 | 550 | FIXED | I1: Routing Input/Enums/Typen/IDs/Identity-Schema konsistent |
| CAP-FW-026 | 560 | PARTIAL | F2: externer Concord Progress-Handler im Host nicht ausgeführt |
| CAP-FW-027 | 566 | PARTIAL | F3: Node-Playwright Pilot funktioniert historisch, SP-MCP browser_* aktuell nicht entdeckt |
| CAP-FW-028 | 571 | FIXED | B/I: fresh validated Handoff vor Spawn, kein name-only Allow; Live-Host-Grenze siehe I2/I3 |

## Die acht Admin_CenterYear-Ergänzungen

Readonly Pilot-Evidence: `findings-w18a.txt:4–21`; Browserpfad aus `cya-verify.js` nur zur
Provider-/Binary-Identifikation gelesen. Keine Zugangsdaten werden übernommen.

| Nr. | Zuordnung | Erhaltene Regression / Bedeutung |
|---|---|---|
| 1 | G5/H1/E4 | Globaler Header vs lokales betrachtetes Jahr: fachlichen State-Owner und Synchronisation deklarieren/verifizieren, keine Page-Sonderregel |
| 2 | H1/G5 | AppAdmin sieht Navigation, Ziel liefert keinen sinnvollen Inhalt: Discoverability reicht nicht für Authorization/Behavior |
| 3 | G2 | Original excluded, BAK runnable ohne Rollen: generische Replacement-/Backup-Invariante |
| 4 | F3/O | Erfolgreicher Node-Browserpfad vs widersprüchliche SP-MCP-Declaration: host-/zeitbezogen, nicht permanent unavailable |
| 5 | G5/H3 | Header, Rename, Dialogtexte und AppAdmin-Inhalt: Runtime-Smoke findet echte Gaps trotz Model-Clean |
| 6 | D3/H3/B1 | P-09 earliest-open-year/hint-statt-button sind INFERRED/PROPOSED, nicht still DECLARED |
| 7 | E1/E3/E4 | REV-038 ACTIVE_TARGET mit alten Bindings: betroffener Scope stale/unbound; unveränderte Pages nicht pauschal rebind |
| 8 | B1/H2/K3 | DEC-058 PROPOSED, TASK-259 offen, Security nicht belegt, funktionale Gaps: Runtime Partial PASS ist nicht Acceptance Complete/Wave DONE |

## Capability-aware Delivery Planning: Research, keine Implementierung

Aktuelle readonly Probe am 2026-11-15, Host-Zeit `14:19:17+01:00`:
SP-MCP listet `playwright_status`, liefert nach schema-konformer Abfrage
„Playwright is available; use the browser_* handlers to check the UI.“; browser_* waren in der
Handler-Discovery nicht vorhanden. Declaration AVAILABLE, ausführbarer SP-MCP-Browserpfad
NOT_OBSERVABLE. VS-Code-Browsertools sind separat deklariert, hier nicht ausgeführt.
`mxcli` wurde auf PATH nicht gefunden: nur **PATH-NOT_OBSERVABLE**, kein Beweis globaler Abwesenheit.

| Provider | Declaration/Discovery | Ausführung / Host-/Versionsgrenze |
|---|---|---|
| mxcli | erforderliches Engineering-Tool; PATH-Probe ohne Application | keine aktuelle Modelloperation/Version-Probe; kein global absent Claim |
| Concord | Start-/Progress-/Fidelity-Verträge vorhanden | keine aktuelle externe Host-Ausführung/Serialisierungsprobe |
| Studio-Pro-MCP | playwright_status AVAILABLE, keine browser_* gefunden | hostbezogene deklarierte/entdeckte Diskrepanz; keine Browseroperation ausgeführt |
| Studio-Pro Runtime | historische Model-Clean-Evidence im Pilot | kein aktueller Scope-Smoke durch diesen Sweep |
| Playwright | historische Node-Ausführung über playwright-core/@playwright/cli, headless shell 1243 | localhost:8180 Pilot ausführbar; damaliger Agenthost/Provider nicht vollständig bekannt; kein SP-MCP-PASS |
| Highcode | Framework-Routen/Verträge, generische Browsertools separat deklariert | keine aktuelle taktische Edit-/Roundtrip-/Cost-Evidence |

Die Operations-/Domain-Matrix wird nicht mit Capability-Declarations gefüllt. `?` bedeutet
**NOT_OBSERVABLE für einen aktuellen providerbezogenen Operationsnachweis**, nicht unsupported.

| Domain | READ | CREATE | PATCH | REPLACE | DELETE | DIFF | VALIDATE | SYNC |
|---|---|---|---|---|---|---|---|---|
| Pages | ? | ? | ? | ? | ? | ? | ? | ? |
| Microflows | ? | ? | ? | ? | ? | ? | ? | ? |
| Nanoflows | ? | ? | ? | ? | ? | ? | ? | ? |
| Navigation | ? | ? | ? | ? | ? | ? | ? | ? |
| Domain Model | ? | ? | ? | ? | ? | ? | ? | ? |
| Security | ? | ? | ? | ? | ? | ? | ? | ? |
| JS Actions | ? | ? | ? | ? | ? | ? | ? | ? |
| HTML | ? | ? | ? | ? | ? | ? | ? | ? |
| Runtime | ? | ? | ? | ? | ? | ? | ? | ? |
| Visual | ? | ? | ? | ? | ? | ? | ? | ? |

Diese 80 Zellen gelten je Provider; die Faktorisierung erfindet keine 480 Messwerte.
Historischer Runtime-/Visual-Smoke ist positive Behavior-Evidence, keine aktuelle CRUD-/SYNC-Matrix.
Für Fidelity, Setup/Roundtrip, Bulk vs Small Edit und Context-/Tokenkosten fehlen vergleichbare
Messungen. Ergebnis O: **INSUFFICIENT_EVIDENCE**. Keine automatische Toolwahl-/Planungsstrategie.

## Verifikation und Fehlerhistorie

**Implementierbarer Core-Scope umgesetzt und gezielt verifiziert. Development/Fast Gate: PASS.
Impact Regression: gezielte/deltaabhängige Consumer bestanden; gesamter gemappter Lauf bleibt
INCOMPLETE wegen einer Host-Ressourcenunterbrechung des Baseline-Upgrade-E2E. Kein Gesamt-/Full-PASS.**

- Erster gemappter Lauf: 54 deduplizierte Suites, unmapped = 0, kein Full Release.
  Python-Anteil: 546 Tests / 2568.925s, `failures=5, errors=1`.
  Ursache: versehentlich entfallener Contract-Lookup-Cache, zwei Routing-Fixtures ohne neue
  Identity-Felder (drei abhängige Tests), alte Page-Path-Binding-Erwartung (zwei Subcases).
- Korrekturen: bounded Cache wiederhergestellt; Routing-Identity ausdrücklich in der
  Routing-Fixture, nicht als unzulässiges Handoff-Schemafeld; alte Erwartungen auf explicit
  target_revision umgestellt. Alle fünf betroffenen Testmethoden danach: 5 PASS / 61.660s.
- Während des ersten Laufs änderten sich zuletzt Revision-/Preflight-/Routing-Quellen.
  Er ist deshalb **kein einheitlicher final-source PASS**. Unveränderte passing Evidence wird
  wiederverwendet; geänderte Consumer erhalten einen frischen Delta-Lauf.
- Frische gezielte Läufe: Lifecycle einschließlich Source-/Snapshot-Counter und tatsächlicher
  Preflight-Binding-Projektion: 24 PASS / 4.474s; Canonical/Preflight/Resource: 19 PASS / 23.843s;
  Human/Auxiliary/Child: 12 PASS / 297.641s; Resource Ownership: 5 PASS / 0.035s;
  Routing/PS-Preflight: 2 PASS / 52.831s; PS5-Entry-Points: 16 PASS;
  SPA-CLI: 10 Szenarien PASS. TestImpact: 44 PASS / 5.173s.
- Red/Green separat erhalten: Creator-Confirmation/Manifest; PS5 UTF8-Guard; Builder-Fingerprint;
  shared-path Doctor-Binding; malformed Epoch Output; Routing-ID/Typ-/Enum-Coercion;
  unmapped Fast-PASS; duplicate active target; Source-/Bundle-Namespace und Source-/Snapshot-Zähler.
- Zusätzlicher frischer Consumer-Lauf: **271 PASS / 804.714s**. Nach record-only-Updatefix:
  Recovery/Canonical/Preflight/Lifecycle/Update: **62 PASS / 733.168s**;
  vollständige Capability-/Update-Routing-PS-Suite: **148 PASS, 0 FAIL**.
- Impact-Auswahl für den finalen Scope: **58 Dateien, 55 deduplizierte Suites, unmapped = 0**.
  Native-Pfad-/Consumer-Mapping-Regressionssuite: **45 PASS / 6.099s**.
- Die serielle Fortsetzung enthält noch ausstehende PS-Suites. Ein Start scheiterte mit
  CoreCLR-Out-of-Memory (Host-Ressource, kein PASS); danach liefen Context Operational/Rollover.
  Die Baseline-Upgrade-Fixture brach bei `git add` ab. Isolierte git-add-Probe: exit 0;
  der Upgrade-Retry erreichte 93 PASS / 4 FAIL. Er zeigte, dass vollständiges record-only auch
  die bisher validierte verlustfreie Decision-Normalisierung unterdrückte. Das ist kein Host-Limit:
  Installer nutzt nun contract-only mit zwei versionierten Normalisierungen, ohne ADD_WAVE_ID oder
  generische Text-/Agent-Reparatur. Neue Scope-/Idempotenztests: 2 PASS / 13.995s;
  exakte Hook-/Lifecycle-Tests: 25 PASS / 22.906s. Contract-only-Retry: PS-148 PASS,
  Upgrade 95 PASS / 2 FAIL. Beide Restfehler betrafen Projection-Resume des gepinnten alten
  Producers, der den neueren CLI-Schalter nicht kennt. Resume wählt nun den tatsächlich
  installierten CLI-Vertrag; es ersetzt keine alte Core-Payload und behauptet nicht, dass diese
  bereits die aktuelle engere Repair-Semantik besitzt. Aktuelle und gepinnte Resume-Suites laufen
  erneut seriell geprüft: aktuelle PS-Suite 148 PASS; Upgrade erreichte 73 PASS einschließlich
  tatsächlich gepinnter Migration und blocked Doctor. Repeat-Resume startete nicht: CoreCLR
  HRESULT 0x800705AF (Host-Commit-Speicher); anschließend war kein Guard-verdict verfügbar.
  Dieser Lauf ist **INCOMPLETE / HOST_RESOURCE_UNAVAILABLE**, kein vollständiger Upgrade-PASS
  und keine weitere bestätigte Frameworklücke. Die 24 verbleibenden PS-Suites sind inzwischen
  alle mit exit 0 durchgelaufen. Zusammen mit neun wiederverwendbaren passing Suites und der
  aktuellen 148-PASS-Routing-Suite sind **34 von 35 ausgewählten PS-Suites bestanden**;
  Baseline-Upgrade bleibt INCOMPLETE/HOST_RESOURCE_UNAVAILABLE. Die einzige SKIP-Meldung im
  24-Suite-Lauf betrifft bereits initialisierte `mxcli init --all-tools`, keinen ausgelassenen
  Testfall; keine UNAVAILABLE-/INCOMPLETE-Ergebnis-Marker dort.
  Finale gezielte Migration-/Repair-/Hook-/Impact-Prüfung: **51 PASS / 67.004s**.
  Keine fremden Prozesse wurden beendet, keine OS-/Pagefile-Konfiguration geändert.
  Fehlende Evidence wird nicht grün gerechnet.
- **Full Regression / Full Release Gate: NICHT AUSGEFÜHRT.**

Regressionsdateien:
[Lifecycle](../tests/test_lifecycle_reality_contracts.py),
[Tooling](../tests/test_reality_tooling.py),
[Resource Ownership](../tests/test_reality_resource_ownership.py),
[Canonical/Child/Recovery](../tests/test_control_plane_phase1b.py),
[Guard](../tests/test_control_plane_guard.py),
[Update Recovery](../tests/test_framework_update_recovery.py),
[PS5 Preflight](../tests/test-hardening-rf005-ps-preflight.ps1),
[SPA CLI](../tests/test-spa-bundle-revision.ps1),
[Project Status](../tests/test_project_status.py),
[Board Performance](../tests/test_board_performance.py),
[Run Activity](../tests/test_run_activity_board.py),
[Run Events](../tests/test_run_events.py),
[Wave IDs](../tests/test_wave_ids.py),
[Impact Runner](../tests/test_test_impact.py).

## Exakt geänderte Dateien

56 Code-/Policy-/Schema-/Test-Dateien plus Installationsdokumentation und diesem Bericht = **58 Sweep-Dateien**.
Die sieben schon beim Start vorhandenen Framework-Deltas wurden integriert, nicht als neue
Eigenimplementierung ausgegeben: project-status-/requirement-Schema, enforcement, guard,
build_project_status, project_compatibility und wave_ids. Der Ausgangsdiff wurde separat gesichert.

### Policies und Board (15)

- [board.js](../.mxagile/board/board.js)
- [agent-delegation.md](../.mxagile/policies/agent-delegation.md)
- [capability-discovery.md](../.mxagile/policies/capability-discovery.md)
- [design-contract-intake.md](../.mxagile/policies/design-contract-intake.md)
- [development-runtime.md](../.mxagile/policies/development-runtime.md)
- [impact-resolution.md](../.mxagile/policies/impact-resolution.md)
- [implementation-control.md](../.mxagile/policies/implementation-control.md)
- [legacy-completion-reconciliation.md](../.mxagile/policies/legacy-completion-reconciliation.md)
- [mockup-lifecycle.md](../.mxagile/policies/mockup-lifecycle.md)
- [project-compatibility.md](../.mxagile/policies/project-compatibility.md)
- [spa-mockup-bundle.md](../.mxagile/policies/spa-mockup-bundle.md)
- [test-contract-derivation.md](../.mxagile/policies/test-contract-derivation.md)
- [test-workflow.md](../.mxagile/policies/test-workflow.md)
- [ui-parity.md](../.mxagile/policies/ui-parity.md)
- [update-contract.md](../.mxagile/policies/update-contract.md)

### Schemas (7)

- [framework-config.schema.json](../.mxagile/schemas/framework-config.schema.json) — neu
- [implementation-checklist.schema.json](../.mxagile/schemas/implementation-checklist.schema.json) — neu
- [process-state.schema.json](../.mxagile/schemas/process-state.schema.json)
- [project-status.schema.json](../.mxagile/schemas/project-status.schema.json)
- [requirement.schema.json](../.mxagile/schemas/requirement.schema.json)
- [revision.schema.json](../.mxagile/schemas/revision.schema.json)
- [routing-decision.schema.json](../.mxagile/schemas/routing-decision.schema.json)

### Code / Installer (17)

- [enforcement.py](../experiments/control-plane/enforcement.py)
- [guard.py](../experiments/control-plane/guard.py)
- [mxagile-setup-company-layer.ps1](../mxagile-setup-company-layer.ps1)
- [Get-MxAgileCapabilities.ps1](../scripts/Get-MxAgileCapabilities.ps1)
- [Save-MxAgileRoutingDecision.ps1](../scripts/Save-MxAgileRoutingDecision.ps1)
- [Write-MxAgileEpochCheckpoint.ps1](../scripts/Write-MxAgileEpochCheckpoint.ps1)
- [build_artifact_index.py](../scripts/build_artifact_index.py)
- [build_project_status.py](../scripts/build_project_status.py)
- [create_revision.py](../scripts/create_revision.py)
- [graph_capability.py](../scripts/graph_capability.py)
- [install-core.ps1](../scripts/install-core.ps1)
- [project_compatibility.py](../scripts/project_compatibility.py)
- [resolve_impact.py](../scripts/resolve_impact.py)
- [run_events.py](../scripts/run_events.py)
- [serve_project_board.py](../scripts/serve_project_board.py)
- [update-transaction.ps1](../scripts/update-transaction.ps1)
- [wave_ids.py](../scripts/wave_ids.py)

### Tests / Mapping (17)

- [test-capability-discovery-routing.ps1](../tests/test-capability-discovery-routing.ps1)
- [run-impact-tests.py](../tests/run-impact-tests.py)
- [test-inventory.json](../tests/test-inventory.json)
- [test-hardening-rf005-ps-preflight.ps1](../tests/test-hardening-rf005-ps-preflight.ps1)
- [test-spa-bundle-revision.ps1](../tests/test-spa-bundle-revision.ps1)
- [test_board_performance.py](../tests/test_board_performance.py)
- [test_control_plane_guard.py](../tests/test_control_plane_guard.py)
- [test_control_plane_phase1b.py](../tests/test_control_plane_phase1b.py)
- [test_framework_update_recovery.py](../tests/test_framework_update_recovery.py)
- [test_lifecycle_reality_contracts.py](../tests/test_lifecycle_reality_contracts.py) — neu
- [test_project_status.py](../tests/test_project_status.py)
- [test_reality_resource_ownership.py](../tests/test_reality_resource_ownership.py) — neu
- [test_reality_tooling.py](../tests/test_reality_tooling.py) — neu
- [test_run_activity_board.py](../tests/test_run_activity_board.py)
- [test_run_events.py](../tests/test_run_events.py)
- [test_test_impact.py](../tests/test_test_impact.py)
- [test_wave_ids.py](../tests/test_wave_ids.py)

### Dokumentation (2)

- [installation.md](./installation.md)
- [reality-hardening-sweep.md](./reality-hardening-sweep.md) — neu

Keine Agent-/Skill-Source wurde verändert; deshalb kein manuelles Projection-Edit und kein
zusätzlicher Projection-Generatorlauf. Kanonische Policies/Schemas und ihre Installer-Distribution
sind Bestandteil des gemappten Pakets.

## Commit- und Git-Transparenz

Core-/Regression-/Installationsdokumentations-Paket:
`d1d5b6eee7359eff442d41d9a4a7c90a7dd11c2c`
— **Harden reality contracts across delivery, revisions, tooling and updates**, 57 Dateien.

Dieser Bericht ist ein separates Evidence-Paket. Seine Commit-ID wird im Session-Abschluss
angegeben und ist dauerhaft über `git log -- docs/reality-hardening-sweep.md` bestimmbar;
der Bericht kann seine eigene Commit-ID nicht ohne erneuten Commit enthalten.

Die gemeinsame project_compatibility-/Guard-/Installer-API erlaubt kein ungetestetes künstliches
Aufteilen nach Agenten oder einzelnen Findings. Deshalb ein kohärent gemeinsam verifiziertes
Corepaket und ein getrenntes Evidence-Paket, statt scheinbar unabhängiger Teilcommits.
Staging erfolgte ausschließlich per Sweep-Allowlist. Vor jedem Commit werden Author und
Committer frisch gegen `Zwergomaniac <Keeperdeluxe@web.de>` geprüft; keine globale
Identity-Änderung und kein History-Rewrite. Co-authored-by-Trailer enthalten.

Abschließender erwarteter Dirty-Scope ist ausschließlich die zwei vorher vorhandenen fremden
Deltas `.gitignore` und `.vscode/mcp.json`; beide wurden mit dem Ausgangsdiff verglichen und
blieben unverändert, unstaged/uncommitted. Alle 58 Sweep-Dateien sind in den beiden Paketen
enthalten. Kein Push und kein Full Release Gate.

## Abschluss und verbleibende Grenzen

Der vollständig implementierbare, bestätigte Findings-Scope ist umgesetzt, gezielt verifiziert
und im Repository persistiert. Kein Handoff wird als Implementierung gewertet. Die verbleibenden
PARTIAL-Einträge betreffen echte externe Host-/Provider-/Execution-Evidence; NOT_OBSERVABLE
bezeichnet konkrete fehlende historische/aktuelle Beobachtung. PARKED umfasst Research oder
undeclared source-/project-owned Zuordnung, nicht liegengebliebene bestätigte Core-Fixes.

Letzte Development/Fast-Prüfung des persistierten Gesamt-Scopes: PASS / 2.66s,
Mapping 58 Dateien / 55 Suites / unmapped=0.
Letzte Dokumentationsprüfung: 63 PASS / 0 FAIL. Gezielte finale Codeprüfung: 51 PASS / 67.004s.
Gesamter Impact-Lauf bleibt **INCOMPLETE**: Baseline-Upgrade wegen Host-Speicher nicht vollständig
beendet. Keine Behauptung eines Full Regression-, Full Release- oder CAPTRACK-App-PASS.
Die benötigte Ergänzung ist ein gezielter Baseline-Upgrade-Lauf auf einem Host mit ausreichendem
Commit-Speicher, kein neuer Framework-Architekturstrang und kein Full Release Gate.
