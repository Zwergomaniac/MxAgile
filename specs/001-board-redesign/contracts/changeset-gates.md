# Contract: Changeset-Gates, Rollback, Commit-Grenze, STOP

Übernimmt [docs/board-redesign-implementation-contract.md](../../../docs/board-redesign-implementation-contract.md) und ergänzt die Repository-Prüfung (plan.md A1–A5). Sequenz: **CS-1 → CS-2 → CS-7 → CS-0 → CS-3 → CS-4 → CS-5 → CS-6**.

## Gemeinsamer Ablauf je Changeset

1. **Pre-Flight**: `git status --porcelain` erfassen; Dateien des Changesets auf fremde uncommittete Änderungen prüfen → bei Treffer STOP und Eigentümer fragen.
2. `python tests/run-impact-tests.py --list --paths <geplante Pfade>` → Gate-Umfang festhalten.
3. Implementieren (erst nach ausdrücklicher Freigabe dieses Changesets).
4. Gates in Reihenfolge: **Fast Gate** → **Impact Regression** (Tier laut Liste) → **Full Release Gate**, nur wo unten verlangt. Ergebnisse getrennt berichten; NOT RUN ≠ PASS.
5. Referenzprojekt-Realitätsfälle read-only (Python `-B`, Git `--no-optional-locks`, Server danach beendet, `git status` vorher und nachher identisch bis auf fremde Aktivität).
6. Commit: Identität prüfen (`git var GIT_AUTHOR_IDENT`/`GIT_COMMITTER_IDENT` = `Zwergomaniac <Keeperdeluxe@web.de>`), nur eigene Pfade explizit stagen.
7. **STOP**: Bericht (Diff-Übersicht, Gates, Messwerte, RC-Ergebnisse); auf Freigabe des nächsten Changesets warten.

## Tabelle

| CS | Gate (Minimum) | Full Release Gate? | Performance-Abnahme | Rollback-Grenze | Commit/Review | STOP-Artefakt |
|---|---|---|---|---|---|---|
| CS-1 | Fast; Impact: `test_board_http.py`, `test_board_performance.py`, `test_project_status.py`, `test_parity_gallery.py`, `test-board-authority.ps1`, `test-reconciliation-board.ps1`, **Tier 3** `test_external_change_reconciliation.py`, `test-core-provenance.ps1`, `test-injection-contract.ps1` (A1) | nein | Profil ±10 % | 1 Commit, Revert | unabhängig | Vorher/Nachher-Screenshots RC-01…03 |
| CS-2 | Fast; Impact Tier 3 (Board-Suiten + Reconciliation-Suiten + Schema-Suiten); Äquivalenztest Reconciliation; Projekt-Unverändert-Test | nein (solange `install-core.ps1` unverändert, R-02) | SC-001…004 auf Referenzprojekt | Flag `MXAGILE_BOARD_LEGACY_CACHE=1` (1 Release), danach Revert; Cache löschbar | unabhängig; nach CS-1 mergen | Messprotokoll vorher/nachher, Äquivalenznachweis |
| CS-7 | Fast; Tier 2 Smoke-Fixture (PASS/FAIL/UNAVAILABLE/TIMEOUT/Cleanup); non-interaktiver Installer-Lauf | **ja** (Installer + unmapped neue Datei, A3) | SC-005 | Flag + Installer-Angebot entfernen | unabhängig | Laufprotokolle Fixture + Referenzprojekt, Full-Gate-Bericht |
| CS-0 | Fast; Impact Tier 2 (`test-injection-contract.ps1`, `test-negative-schema.ps1`, `test_project_status.py`, `test-documentation-consistency.ps1`, `test-ui-parity.ps1`, `test-verification-lifecycle.ps1`, `test-lifecycle-resync.ps1`, `test-architecture-drift-prevention.ps1`); Projektionstests nach Generatorlauf (falls Skills/Agents berührt) | nur falls Impact `unmapped` meldet | SC-012 (Doctor +≤ 10 %, 0 neue Blocker in Referenzprojekt) | Revert vor Distribution; danach Vorwärtskorrektur | unabhängig (nach Vorbedingung) | Policy-Diff + Referenzprojekt-Doctor-JSON → **ausdrückliche Freigabe (Agentenverhalten)** |
| CS-3 | Fast; Impact Tier 2 (Board- + Schema-Suiten); neues `test_board_states.py`; Smoke-Routenliste v2 (`health`) | nein | SC-013 | v2-Felder-Fallback; Revert | nach CS-1 | Zustands-Mapping alt → neu (Referenzprojekt) |
| CS-4 | Fast; Impact Tier 2; neues `test_board_projections.py` (Kaskade, Assessment, Trust, REPORTED_UNBOUND, Revision Ledger, Intent/Fakt) | nein | `/api/status` warm ≤ 300 ms; Git-Abfrage ≤ 500 ms | Feld-Flags; Revert | nach CS-3 und CS-0 | Regeltext `delivery-assessment/v1` + Referenzprojekt-Beispiele zur PO-Abnahme |
| CS-5 | Fast; neues `test_project_timeline.py` (Fixture-Git: Merge, Rebase, Shallow, Trailer, CS gültig/ungültig, Determinismus, Zeitnähe-Negativtest); Impact | **ja** (Installer + unmapped neue Datei, A3) | SC-010; `/api/timeline` ≤ 300 ms | Endpoint/Ansicht entfernen; Cache löschen | nach CS-2 und CS-3; unabhängig von CS-4 | Timeline-Auszug Referenzprojekt mit Autoritätsklassen |
| CS-6 | Fast; Impact Tier 1–2; Smoke mit Routenliste v3; HTTP-Tests neue Endpunkte | nein | Route ≤ 500 ms; Page Hub ≤ 1 s | `#legacy/…`-Router (1 Release) | nach CS-3, CS-4, CS-5 | PO-Walkthrough Plan J (12 Fragen) |

## Verbote (alle Changesets)

Keine Full Regression nach jedem Changeset, sofern die Tabelle sie nicht verlangt. Keine Änderungen an Referenzprojekt. Keine Live-Telemetrie. Keine kanonischen Änderungen außerhalb von CS-0. Kein `git add -A`.
