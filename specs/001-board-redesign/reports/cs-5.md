# CS-5 Report - Evidenzbasierte Project Timeline

Commit: `bc86540` (Autor/Committer Zwergomaniac). 16 Dateien, +2027/-6. Voraussetzungen: CS-4 `8cf7013`.

## Architektur
`scripts/build_project_timeline.py` (Bibliothek + CLI): ein `git log --first-parent -m --raw`, ein `git cat-file --batch`, Trailer-/Change-Set-Verifikation ohne Prozess pro Commit. Index (nur Git-abgeleitete Ereignisse + Commit-Zusammenfassungen) im OS-Cache ausserhalb des Projekts, inkrementell ueber `last..HEAD`, invalidiert wenn der zuletzt indizierte Commit kein Vorfahr von HEAD ist. Kanonische Eintraege (Change-Sets, Delegationsergebnisse) werden aus dem Snapshot ergaenzt. `/api/timeline` filtert nur den In-Memory-Index; Aufbau laeuft im Hintergrund (`BUILDING` wird sichtbar gemacht).
Darstellung: Tagesgruppen, je Commit ein Moment; Kopfereignis nach Bedeutung, Kennzeichnung der Beleg-Klasse, Details und Beleg auf Abruf, teilbare Filter (`#timeline?...`), Recent Activity auf der Overview, Verlauf in Wave-/Requirement-/Decision-Details.

## Evidenzklassen und Regeln
CANONICAL_RECORD (Eintrag mit eigenem Zeitstempel), GIT_DERIVED (Aenderung eines Projektartefakts), COMMIT_TRAILER (Trailer + schema-valides Change-Set, inline verifiziert), GIT_MENTION (nur Commit-Nachricht). Lane `unattributed` ohne belegte Entitaet. Verboten und getestet: Zuordnung ueber Zeitnaehe, Branch, Dateinamen, Freitext-`mission_id`.

## Per-Wave-DONE (BRD-F-56)
DONE-Uebergang je Wave aus der process-state-Historie; `changes_after_done` = verknuepfte Artefakt-Commits (explizite Evidenz) + projektweite Delivery-Commits (nicht zugeordnet). Waves ohne beobachteten Uebergang: NOT_RECORDED (BRD-F-28). Spaetere Aenderungen oeffnen oder entwerten DONE nie.

## Abweichungen von der Spezifikation
- Kein `tests/fixtures/board-redesign/make_fixture_repo.py`; synthetische Git-Repos im Testmodul selbst (`Repo`-Helfer).
- Date-only-Felder (Decision/Requirement/Parity) erzeugen keine eigenen Ereignisse; Zeit = Commit-Zeit (`time_basis: commit_time`), keine erschlossenen Zeitpunkte.
- `mission.checkpoint`, `reconciliation.performed` und `wave.gate_evaluated` aus kanonischen Zeitstempeln sind nicht als eigene kanonische Ereignisse umgesetzt (gate/reconciliation nur Git-abgeleitet bzw. nicht vorhanden); Delegationsergebnisse und Change-Sets sind kanonisch.
- Zusaetzliche Health-Werte `COMMIT_TRAILER_UNVERIFIED`, `COMMIT_TRAILER_UNVERIFIABLE` neben `CHANGE_SET_SCHEMA_INVALID`.
- `significance` (1-3) je Ereignis fuer die Auswahl in Recent Activity; Filterangebot gegenueber FR-074: Zeitraum, Bereich, Wave/Requirement/Page/Decision/Entity, Zuordnung, Beleg, Detailgrad (Mission/Change-Set nur per URL-Parameter).

## Performance (reference project, 390 First-Parent-Commits, 39k Pfade)
Kalt (Dateisystem-Cache kalt): 12,4 s; kalt mit warmem Cache: 2,4 s; Ziel <= 10 s nur mit warmem Cache sicher erreicht. Von der Platte: 0,18-0,5 s. Inkrementell (3 Commits): 0,9 s. Warm im Speicher (TTL): 1 ms; `/api/timeline` warm: 13-37 ms (Ziel <= 300 ms). Erster Board-Start ohne Index: Status-Bau und Index-Aufbau konkurrieren (Status 17,8 s kalt).

## Validierung
Fast Gate PASS; test_project_timeline 18/18 PASS; test_project_status + test_board_http + test_project_timeline 176/176 PASS; Full Release Gate PASS (Tier 0/1/2, ohne Agent-Umgebungsvariablen, mit MXCLI_TEST_BINARY): FULL REGRESSION: PASS.

## Status
STOP CS-5. CS-6 nicht gestartet; PO-Sichtpruefung und Freigabe ausstehend.
