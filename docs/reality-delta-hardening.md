# CAPTRACK Reality: begrenzter Delta-Hardening-Pass

Stand: 2026-11-15. Ausgangs-HEAD: `371f9d6`; Core-Hardening: `d1d5b6e`.
Kein erneuter Sweep der 80 Findings. Der bestehende Bericht bleibt historisch unverändert.
CAPTRACK wurde nicht geändert, kein Runtime-Start, Benutzerwechsel oder Modellwrite ausgeführt.
Die vom Nutzer gelieferte Pilotbeschreibung ist Reality-Evidence, keine neue Live-Verifikation.
Fremde Änderungen an `.gitignore` und `.vscode/mcp.json` sind ausdrücklich nicht Teil des Scopes.

## Status und Grenzen

FIXED bezeichnet hier den begrenzten Frameworkvertrag mit Regression, nicht einen CAPTRACK-App-PASS.
PARTIAL trennt abgesicherte Caller-Verträge von nicht verifizierten externen Implementierungen.
HISTORICAL_ONLY bedeutet, dass die alte Abwesenheitsbehauptung nicht als aktueller Defekt fortgeführt wird.

| Finding / Ergebnis | HEAD-Befund und Delta | Status / Evidence-Grenze |
|---|---|---|
| FINDING-029 / RUNTIME_START_DIAGNOSTICS | Evidence-first schon vorhanden; Studio-Pro/Concord Build-/Run-Logs, aktuelles `m2ee_log.txt`, Attempt-/Instanzbindung, bounded redacted Diagnose ergänzt. | PARTIAL: Vertrag präzisiert; kein neuer Startfehler oder upstream Log-API-Test. |
| FINDING-030 / CAPABILITY_REGISTRY | MCP `enabled` las fälschlich Framework-YAML statt `config_location`; Browser-PASSED autorisierte ohne aktuelle Run-/Generation-/Target-Evidence. | FIXED: korrekte MCP-Deklaration, keine statische ACTIVE-/Execution-Behauptung; scoped DECLARED/DISCOVERED/CURRENTLY_AVAILABLE/EXECUTABLE/LAST_VERIFIED. |
| FINDING-031 / PROVIDER_SELECTION | Operation-Routing vorhanden, aber kein kleines nachvollziehbares Provider-Selection-Ergebnis. | FIXED: eine Capability, explizite Präferenzbegründung, aktuelle Executability und Instanzbindung, Ablehnungsgründe und geprüfte Fallbacks; kein Delivery Planning. |
| FINDING-032 / REFERENCE_SAFETY | Frische kanonische Impact-Kandidaten bereits abgesichert; kein negativer Referenzbeweis für dynamische Modellreferenzen. | PARTIAL: read-only Safety-Auswertung und zwingender destructive Preflight-Vertrag ergänzt; tatsächliche Concord-Segmentierung/Fortsetzung bleibt TOOL_LIMITATION bzw. NOT_OBSERVABLE. |
| FINDING-033 / PAGE_IDENTITY_BINDING | Selektives Rebinding vorhanden, BOUND aber durch einzelnes `target_revision` erreichbar. | FIXED: fingerprinted beobachtete Screen/Page/Mendix-/Backup-Identität vor BOUND; aktuelle Input-Hashes; vorige/aktuelle Revision und Delta/Evidence nachvollziehbar. |
| FINDING-034 / CLAIM_PROVENANCE | Observation/Interpretation getrennt, Taxonomie nicht persistiert. | FIXED: optionaler Legacy-kompatibler Schema-Vertrag; INFERRED/PROPOSED kein Defekt/Rule; kanonische akzeptierte Authority vor Promotion. Semantischer Quellencheck bleibt erforderlich. |
| FINDING-035 / ROLE_VERIFICATION | AUTHORIZATION, DISCOVERABILITY und BEHAVIOR bereits unabhängig. | FIXED: bestehenden Vertrag beibehalten und gezielte Role-Regression wiederverwendet; fehlende Behavior-Evidence bleibt PARTIAL/NOT_OBSERVABLE, kein Live-Rollen-PASS. |
| FINDING-036 / AUXILIARY_RESUME_SIGNAL | Guard sperrte korrekt; resync-preflight zeigte nur READY_FOR_RESYNC. | FIXED: konkreter Reason Code, delivery_resume_allowed=false, primary_recovery und next_action; Dry Run/Planhash/Human/APPLIED/diagnostic-only unverändert. |
| FINDING-037 / MODEL_PROFILE_EVIDENCE | requested/actual bereits getrennt; resolved profile/provider/spawn request fehlten im neutralen Telemetrierecord. | FIXED für Telemetrie; tatsächliches historisches Child-Modell NOT_OBSERVABLE. Kein Schluss auf Opus/Sonnet aus Parent, MID oder Adapter. |
| FINDING-038 / CONTEXT_MODE_ROUTING | Task-Tool-Evidence vorhanden; Hook-alternative konnte allgemeiner Discovery verborgen bleiben. | PARTIAL: Loopback/external unterscheiden, exact-name discovery/schema-load und klare Missing-Alternative-Recovery dokumentiert; externer Hook unverändert, keine HTTP-Freigabe. |
| FINDING-039 / SNAPSHOT_REF_LIFETIME | Scroll-/Capture-Vertrag vorhanden, Ref-Lifetime nicht explizit. | PARTIAL: Generation/Page-State-Bindung, invalidation und fresh-snapshot recovery ergänzt; upstream stale-ref Erkennung nicht behauptet. |
| FINDING-040 / DEMO_SWITCHER | Geschlossenes Disclosure erklärt outside-of-viewport; kein belegter Core-/Tooldefekt. | PROJECT_SPECIFIC: generisches UI_INTERACTION_REQUIREMENT; normal öffnen, neue State-Evidence, sichtbare Option wählen. Kein Switcher-Sondervertrag. |
| CANONICAL_WRITE_PREVALIDATION | DEC-058-artige Kandidaten-/Resulting-Artifact-/Schema-/Contract-Checks bereits in d1d5b6e vorhanden. | FIXED: bestehende Regression erneut prüfen; kein unnötiger Writer-Umbau. |
| FINDING-026 / CONCORD_READINESS | PROGRESS/READY/BLOCKED/TIMEOUT/UNKNOWN bereits explizit, normaler Build kein Blocker. | PARTIAL: Caller-Vertrag vorhanden; aktuelle upstream `run_and_await_ready`-Implementierung ohne autorisierten Runtime-Start nicht reproduziert oder geschlossen. |
| FINDING-027 / PLAYWRIGHT_CAPABILITY | Alte Abwesenheitsbehauptung überholt. | HISTORICAL_ONLY: aktuelle read-only Handler-Discovery zeigt konkrete `mcp_studio-pro-playwright_browser_*` Handler; DISCOVERED, nicht frisch EXECUTABLE. |

## Konkrete Regressionsevidence

- [test_reality_tooling.py](../tests/test_reality_tooling.py): vor Änderung reproduzierte
  Run-/Generation-/Target-Drift weiterhin route_allowed=true; danach fail-closed.
  MCP-declaration vs Executability, provider-scoped Auswahl/Fallback (kein erneuter Versuch
  beim bereits ausgewählten Provider auch bei doppelter Präferenz) und Reference-Scan-Abbruch,
  stale Index, dynamische Referenzen und unvollständige Abdeckung.
- [test_lifecycle_reality_contracts.py](../tests/test_lifecycle_reality_contracts.py): vor Änderung
  kosmetisches target_revision ergab BOUND; danach fehlende/widersprüchliche/stale Identity,
  aktuelle Modellinput-Änderung und Active/Backup-Konflikt verhindern BOUND.
  P-09-artige Hypothese bleibt Hypothese; PROPOSED Authority erlaubt keine Defekt-Promotion.
  Der positive Fall bestätigt die konkrete Reihenfolgeregel, nicht bloß generische Mockup-Akzeptanz.
- [test_project_status.py](../tests/test_project_status.py): der Doctor darf seine
  ACTIVE_REVISION_UNBOUND-Diagnose nicht durch ein kosmetisches Revision-Feld verlieren;
  erst eine belegte aktuelle Page-Identität liefert den positiven Kontrollfall.
- [test_control_plane_phase1b.py](../tests/test_control_plane_phase1b.py): konkrete Auxiliary-
  Resume-Signallücke reproduziert; bestehende DEC-058 Candidate-/Schema-/Guard-Regressionen.
- [test_context_architecture_telemetry.py](../tests/test_context_architecture_telemetry.py):
  Opus-Parent/MID-Plan ohne Modellrequest/-Attestation beweist kein Child-Modell.
- [test-role-access-semantics.ps1](../tests/test-role-access-semantics.ps1): Rollen-Dimensionen
  und read-only Behavior getrennt, technische Page-Grants ersetzen kein Rollen-PASS.

Alle Ausführungstests sind synthetische/disposable Framework-Fixtures. Die einzige aktuelle
Host-Observation ist die read-only Studio-Pro Handler-Liste, ohne Handlerausführung.
Die Visual-Skill-Projektionen wurden ausschließlich mit dem kanonischen Generator erzeugt
(`PROJECTIONS_VALIDATED outputs=80`); keine generierte Datei manuell editiert.

## Scope, Gates und Commit

- DEVELOPMENT_GATE = PASS (expliziter Delta-Scope).
- FAST_GATE = PASS (Diff-Hygiene, Python/PowerShell-Parser, JSON/Schemas).
- IMPACT_REGRESSION = PASS, zusammengesetzte Evidence für alle 42 gemappten Consumer-Suites:
  18 Python-Suites / 431 Fälle im initialen Lauf, davon 430 PASS und eine veraltete Erwartung,
  dass ein einzelnes Revision-Feld die Diagnose beseitigen dürfe. Dieser Lauf blieb FAILED;
  die erforderliche Consumer-Anpassung wurde mit der vollständigen Diagnostic-Klasse
  erneut geprüft (14/14 PASS). Die abschließend konkretisierten Delta-Cases wurden separat
  frisch geprüft: Lifecycle/Identity/P-09 29/29 PASS, Tooling/Provider/Reference 12/12 PASS.
  Alle 24 gemappten PowerShell-Suites PASS, einschließlich disposable Installer-/Upgrade-,
  Injection-, Projection-, Role- und Runtime-Contract-Fixtures. Unveränderte Passing Evidence
  wurde wiederverwendet; kein erneuter 431-Fälle-Lauf nur zur Beruhigung.
- UNMAPPED = 0 (22 explizite Delta-Pfade; fremde lokale Änderungen ausgenommen).
- FULL_REGRESSION = NOT_RUN_BY_DESIGN.
- FULL_RELEASE_GATE = NOT_RUN_BY_DESIGN.
- COMMITS = ein kohärenter lokaler Delta-Hardening-Commit, der diesen Bericht enthält.
- PUSH_READY = YES, gate-seitig für den Experiment-Branch; kein Merge-/Release-PASS.
  Kein Push ausgeführt; eine spätere ausdrückliche Push-Freigabe bleibt erforderlich.

Auswahl vor Regression: `python tests\run-impact-tests.py --list --paths <Delta-Scope>`.
Development/Fast: `python tests\run-impact-tests.py --tier fast --paths <Delta-Scope>`.
Die aus dem Impact Plan gewählten PowerShell-Consumer wurden nach dem initialen Python-
Befund separat mit ihren bestehenden Test-Entry-Points ausgeführt. Fehlgeschlagene alte
Assertions wurden nicht als PASS umetikettiert: aktualisierte bzw. geänderte Cases erhielten
neue Evidence; unveränderte Cases behielten ihre Passing Evidence. Die kleine abschließende
Provider-Deduplikation betrifft ausschließlich die neue Operation-Evidence-Auswahl;
deren vollständige Tooling-Suite wurde danach erneut ausgeführt.

Commit-Identität und fremde Änderungen werden unmittelbar vor Commit erneut geprüft.
Großes Capability-aware Delivery Planning, Harness-/Model-Matrix, OpenCode Compaction,
Work IQ/Orca, TaskStop/Ownership ohne neue Evidence und DevBoard-Neugestaltung bleiben PARKED.
