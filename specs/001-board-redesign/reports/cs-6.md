# CS-6 Report - Informationsarchitektur und Page Hub

Commit: `a928211` (Autor/Committer Zwergomaniac). 7 Dateien, +900/-29. Voraussetzungen: CS-5 `bc86540`, UX-Verfeinerung `66bf93b`.

## Informationsarchitektur
Navigation NOW (Overview, Timeline) / DELIVERY (Waves, Requirements, Tasks) / QUALITY (Verification, Pages & Parity, Findings, Decisions) / SYSTEM (Health & Diagnostics, Portfolio). "UI & Pages" und "Parity Gallery" sind zu **Pages & Parity** zusammengefuehrt: Katalog (Zum Hinschauen / Ohne auffaellige Signale) und Parity-Uebersicht (Gesamtsicht aller Reports). Der Page Hub liegt unter `#pages/<PAGE-ID>`. Die frueheren Ansichten bleiben einen Release unter `#legacy/gallery|ui-pages|page/<id>` erreichbar; `#gallery`, `#ui-pages`, `#page/<id>` werden umgeleitet. Overview: kompakte Design Authority ohne Fingerprints (Hover).

## Page Hub
Kopf (Titel, Einstellung vs. HTML-Quelle, Zweck, Hinweise), SOLL (Referenz, skalierte Vorschau), UMSETZUNG (HTML-Quelle, Design Preview, Fragment-Hinweis), IST (Captures als Thumbnails, Laufzeit-URL), Parity & Evidenz (je Report: Prueziel, Nachweisstufe, Evidenz-Bindung, Commit des Reports, Dimensionen mit Ergebnis/Notiz), Kontext (Decisions, Requirements ueber Decisions, Findings, Tasks=NOT_OBSERVABLE, Design Authority), Verlauf (CS-5-Timeline `entity=page:<ID>`), Technische Quellen.

## Semantik
Screenshots/Reports belegen nie Paritaet (FR-082). Captures, die ein Report nur im Kommentar nennt, sind `bound: false` und als Erwaehnung gekennzeichnet. Evidenz-Bindung nur ueber Evidence-Manifest (`BOUND`), sonst `NOT_RECORDED`; Modell-/Commit-Stand der Pruefung `NOT_RECORDED` (der Commit, der den Report erfasste, wird getrennt gezeigt).

## Abweichungen von der Spezifikation
- Parity Gallery (`#gallery`) ist in "Pages & Parity" aufgegangen (Parity-Uebersicht); die alte Gallery bleibt nur als Legacy-Route.
- Page-Hub-Daten: Requirements nur ueber Decisions, Tasks nicht verknuepfbar (BRD-F-67); keine Overlays/Diffs (keine referenzierten Artefakte vorhanden).
- Overview-Layout (T123) beschraenkt auf kompakte Design Authority; "Braucht dich"/Vertrauen in DONE wie in CS-4 umgesetzt, keine weitere Umordnung.
- Reference-CSP `frame-ancestors 'self'` (BRD-F-68).
- Neuer Endpunkt `/page-artifact/<PAGE>/<pfad>` (Allowlist je Page) zusaetzlich zu den im Contract genannten.

## Performance (CapTrack, 10 Pages)
Routenwechsel warm 15-40 ms; Pages-Katalog 105 ms; Page Hub warm 210-330 ms (ein Ausreisser 852 ms, erste Seite mit 65 Bildern); Ziel Routenwechsel <= 500 ms, Hub <= 1 s erreicht. Kalter erster Hub-Aufruf nach Serverstart bis 17 s (BRD-F-69).

## Validierung
Fast Gate PASS (0,38 s); Impact Tier 2 PASS (567 s; unmapped: keine, Full Release Gate nicht erforderlich); test_board_http 23/23 (neu: Hub nur eigene Page, Allowlist/404, Requirement-Slice); test_board_smoke 20/20 mit Routenliste v3, Hub-Drilldown und Legacy-Redirect.

## Status
STOP CS-6. Entfernen des Legacy-Routers braucht eine separate Freigabe. PO-Abnahme steht aus.
