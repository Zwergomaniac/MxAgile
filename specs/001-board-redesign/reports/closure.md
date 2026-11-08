# Board Redesign Closure Report

Stand: 2026-11-07. Referenz: aktuelles CapTrack (HEAD `983e9e83`), read-only. Letzter Commit `54fd499`.

## 1. Produktziele
Das Board soll ein schreibgeschuetzter, ehrlicher Einstieg in den kanonischen Projektzustand sein: korrekter Zustand statt falscher Nullen, schnell wie ein lokales Dashboard, Unsicherheit explizit, Verlauf und Beleg auf Abruf, Page/HTML-first inspizierbar, ohne Verzeichnisse zu durchsuchen.

## 2. Umgesetzter Endzustand
CS-1 Korrektheit (BRD-F-01..08) | CS-2 Snapshot-Serving, Hintergrund-Revalidierung, Last-Good | CS-7 Board-Smoke / Doctor `--board-smoke` | CS-0 Lifecycle-Klaerung (DONE, Wave-Registrierung, Acceptance-Gate-Schema) | BRD-F-48 Policy-Angleichung | CS-3 Beobachtungszustaende, Attention/Health/Diagnostik, BRD-F-45 | CS-4 Current Work, Delivery Assessment (abgeleitet), Vertrauen in DONE | CS-5 evidenzbasierte Timeline (+UX-Verfeinerung) | CS-6 Navigation NOW/DELIVERY/QUALITY/SYSTEM, Pages & Parity, Page Hub | Closure-Absicherung `54fd499`.

## 3. Product-Owner-Walkthrough (CapTrack)
1 kanonischer Zustand: 18 Waves done, keine Mission, Zustaende explizit (NOT_RECORDED/NOT_OBSERVABLE). 2 aktuell: keine aktive kanonische Arbeit. 3 zuletzt: W13 (4/4 Tasks). 4 Verlauf: Timeline/Recent Activity. 5 beteiligt: Waves/Requirements/Tasks/Decisions in Detailansichten und Verlauf; Findings: nicht erfasst. 6 DONE-Grund: Vertrauen in DONE (8 ohne erfasste Grundlage, 10 Legacy). 7 verifiziert vs. berichtet: 0 VERIFIED, 13 Parity-Reports berichtet, nicht belegt. 8 Aufmerksamkeit: Project attention (0 Eintraege), Decisions PROPOSED (4). 9 Framework: eigene Gruppe (57 + 147). 10 Health: BLOCKED (5, Projektdaten-Defekte). 11-12 Page: Hub (Referenz, HTML-Quelle, Captures). 13 Capture: Thumbnails, skalierte Vorschau. 14-15 Parity: Reports mit Dimensionen, Evidenz-Bindung `keine`. 16 Stand: Report-Commit sichtbar, geprueftes Modell `NOT_RECORDED`. 17 HTML-first: Design Preview (Fragment = nur Struktur) + Captures. 18 Page-Historie: Verlauf je Page. 19 Provenienz: Details & Beleg, Hover, Quellen. 20 Unterscheidung: 12-Werte-Vokabular (unbekannt/fehlend/veraltet/ungueltig/nicht verfuegbar/nicht beobachtbar).

Cross-View-Konsistenz: 28 von 29 automatisierten Pruefungen identisch (Overview, Header, Current Work, Waves, Requirements, Tasks, Decisions, Findings, Pages, Parity-Uebersicht, Page Hubs, Health, Timeline); der eine Treffer war ein Pruefskript-Artefakt (Untertitel ohne Zahl; Tabellenzeilen 90 = Status 90).

## 4. Verbleibende Einschraenkungen
Keine Task-Page-Beziehung; Requirements nur ueber Decisions; Parity-Captures nur als Erwaehnung; kein Modell-/Commit-Stand der Pruefung; historische DONE-Uebergaenge nur, wo Git sie zeigt (13 von 18); 599/1166 Timeline-Ereignisse ohne belegte Zuordnung; Sprach-/Wortmix (BRD-F-71).

## 5. Performance
Warm: Status 0,1 s; Timeline 0,01-0,02 s; Page Hub 0,11-0,21 s; Page-Previews 0,06-0,08 s; Routenwechsel 15-40 ms; Katalog 105 ms. Kalt (leerer Cache): Server 1,2 s; erster Status 17,3 s; Timeline-Index parallel 3,7 s (12,4 s bei kaltem Dateisystem-Cache); Folgestart mit Last-Good 0,4 s; erster Hub nach Status 0,14 s.

## 6. Security
Loopback, nur GET, nie Schreiben ins Projekt, Cache ausserhalb des Projekts, Allowlists (Quellen, Captures, Page-Artefakte), Sandbox-Frames. CSP-Matrix: Board-Antworten `frame-ancestors 'none'`; Referenzen und Design Preview `'self'` (BRD-F-68, bewusst akzeptiert, dokumentiert in `docs/board-security-decisions.md`, Regressionstest `test_reference_csp_allows_only_the_board_itself_to_frame`). Artefakt-Skriptfehler sind keine Board-Fehler (BRD-F-70).

## 7. Triage
BLOCKING: keine. SHOULD FIX soon: BRD-F-44 (API-/Schema-Overlay), BRD-F-73/69 (erster Statusbau 17 s), BRD-F-64 (Capture-Bindung im Daten-Contract, Framework-Frage). NORMAL follow-up: BRD-F-46, 60, 61, 62, 67, 71, 72, Legacy-Routen-Entfernung (separate Freigabe), BRD-F-66 (Framework-Frage). CapTrack-Bereinigung (projektspezifisch): BRD-F-47/54 (Core-Update/UI), 49, 55, 58, 65, 66. Obsolet/behoben: 45, 48, 50, 51, 52, 53, 56, 57, 59, 63, 68 (akzeptiert), 70.

## 8. Kompatibilitaet / Legacy
Status v2/v3 parallel (Frontend per Feature-Detection, Last-Good akzeptiert 2 und 3); Legacy-Routen `#legacy/gallery|ui-pages|page/<id>` fuer einen Release, alte Hashes umgeleitet; Installer verteilt Timeline-Bibliothek und Schema; kein Projekt musste migriert werden; CapTrack zeigt bis zum Core-Update seine alte UI.

## 9. Empfehlung
CLOSE with follow-ups.
