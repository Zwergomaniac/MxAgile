# Feature Specification: MxAgile Dev Board Redesign

**Feature Branch**: `001-board-redesign` (Spec-Verzeichnis; kein Git-Branch angelegt)

**Created**: 2026-11-05

**Status**: Draft — zur Freigabe; keine Implementierung vor ausdrücklicher Freigabe je Changeset

**Input**: User description: "MxAgile Dev Board Redesign: Translate the approved planning artifacts docs/board-redesign-plan.md, docs/board-redesign-findings.md and docs/board-redesign-implementation-contract.md into an implementation-ready specification. The Board stays a strictly read-only projection of canonical MxAgile state; incremental changesets CS-1 → CS-2 → CS-7 → CS-0 → CS-3 → CS-4 → CS-5 → CS-6; performance targets from reference project reality; Current Work derivation without invented lifecycle relationships; evidence-based timeline; separated human attention / projection health / framework diagnostics; Page Hub; bounded Doctor board smoke (<15 s, 60 s hard timeout, UNAVAILABLE when no browser). Short name: board-redesign."

**Autoritative Quellen** (Architektur- und Produktautorität; diese Spec übersetzt sie, sie ersetzt sie nicht):

- [docs/board-redesign-plan.md](../../docs/board-redesign-plan.md) — Architektur, IA, Timeline, Page Hub, OD-3-Klärung (Abschnitt K)
- [docs/board-redesign-findings.md](../../docs/board-redesign-findings.md) — Befunde BRD-F-01…36
- [docs/board-redesign-implementation-contract.md](../../docs/board-redesign-implementation-contract.md) — verbindliche Changeset-Grenzen

Bei Widerspruch gilt der Implementation Contract vor dem Plan und der Plan vor dieser Spec.

## Akteure

- **Project Owner / Entwickler (PO)**: liest das Board, um Stand, Historie, Vertrauen und Handlungsbedarf zu verstehen.
- **MxAgile-Agent**: führt den Lifecycle aus; nutzt Doctor und Lifecycle-Regeln (nicht das Board) als Autorität.
- **Framework-Maintainer**: liefert Core-Updates aus, betreibt Doctor und Board-Smoke, prüft Kompatibilität mit gewachsenen Projekten.

## User Scenarios & Testing *(mandatory)*

Reihenfolge = verbindliche Changeset-Sequenz **CS-1 → CS-2 → CS-7 → CS-0 → CS-3 → CS-4 → CS-5 → CS-6**.
Jede Story ist ein eigenständig prüfbarer, commit- und reviewbarer Schritt mit STOP danach.

### User Story 1 — Board zeigt nichts Falsches (Priority: P1, CS-1)

Als PO will ich, dass das Board keine irreführenden Werte anzeigt: keine „HEAD UNKNOWN / BASELINE REQUIRED", wenn Daten nur noch laden; keine erfundene „0"; keine ins Leere führenden Links; Pages korrekt gezählt; Parity-Reports öffnenbar.

**Why this priority**: Falsche Aussagen zerstören Vertrauen schneller als fehlende Funktionen; die Korrekturen sind klein und risikoarm.

**Independent Test**: Board gegen ein Fixture-Projekt und read-only gegen Referenzprojekt öffnen; die sieben bekannten Fehlbilder (BRD-F-01…08) treten nicht mehr auf.

**Acceptance Scenarios**:

1. **Given** ein Projekt mit Reconciliation-Watermark und noch nicht geladener Reconciliation, **When** der PO die Overview öffnet, **Then** zeigt der Drift-Bereich „lädt" sowie aktuellen HEAD und Branch, nie „BASELINE REQUIRED" oder „HEAD UNKNOWN".
2. **Given** ein Projekt ohne Watermark, **When** die Reconciliation geladen ist, **Then** wird der bekannte HEAD angezeigt.
3. **Given** ein terminales Finding in der Historie, **When** der PO dessen Link öffnet, **Then** erscheint die Finding-Detailansicht.
4. **Given** keine Mission-State-Quelle, **When** der PO ein Wave-Detail öffnet, **Then** wird kein Blocker-Zähler „0" angezeigt, sondern der Zustand „nicht erfasst".
5. **Given** ein Standalone-Interaction-Artefakt im UI-Inventory, **When** UI & Pages geladen ist, **Then** stimmt die Page-Anzahl mit der Status-Projektion überein (Referenzprojekt: 10, nicht 11).
6. **Given** ein Parity-Report unter `planning/parity/`, **When** der PO dessen Quelle öffnet, **Then** wird sie angezeigt (kein 404).
7. **Given** die Parity-Spalte in UI & Pages, **When** die Gallery noch nicht geladen ist, **Then** wird kein Paritätswert vorgetäuscht; nach Laden zeigen Server- und Client-Seite denselben „letzten Lauf".

---

### User Story 2 — Board reagiert wie ein lokales Dashboard (Priority: P1, CS-2)

Als PO will ich, dass Ansichten und Links sofort reagieren und das Board auch bei paralleler Projektarbeit nicht mit einem Fehler startet, statt bei jedem Klick das ganze Projekt neu zu scannen.

**Why this priority**: Heute 3–6,5 s pro Request, ~8,4 s pro Link, Reconciliation 280–373 s, Kaltstart-503 (Referenzprojekt). Ohne Performance-Basis sind alle späteren Sichten unbenutzbar.

**Independent Test**: Messlauf vorher/nachher gegen Referenzprojekt (read-only) und Fixture; Dateisystem-Diff des Projekts vor/nach Board-Nutzung ist leer.

**Acceptance Scenarios**:

1. **Given** ein bereits geladenes Board ohne Quelländerung, **When** der PO eine Ansicht wechselt oder einen Quell-/Mockup-Link öffnet, **Then** reagiert das Board innerhalb der Zielzeiten (SC-001, SC-002), ohne Gesamtscan.
2. **Given** ein Agent ändert während des Board-Aufbaus Projektdateien, **When** der PO das Board öffnet, **Then** sieht er den letzten gültigen Stand mit sichtbarer Altersangabe oder einen frischen Stand — nie einen Startfehler.
3. **Given** eine kanonische Datei wird geändert (auch bei gleichem Zeitstempel), **When** der PO aktualisiert, **Then** wird die Änderung erkannt.
4. **Given** 26 unreconcilierte Commits, **When** die Drift-Daten geladen werden, **Then** liegen sie innerhalb von SC-003 vor und stimmen inhaltlich mit dem bisherigen Ergebnis überein.

---

### User Story 3 — Maintainer kann Board-Funktion schnell prüfen (Priority: P1, CS-7)

Als Framework-Maintainer will ich nach einem Core-Update optional einen schnellen, begrenzten Board-Smoke ausführen, der eindeutig PASS, FAIL, UNAVAILABLE oder TIMEOUT meldet.

**Why this priority**: Regressionsnetz für alle folgenden Board-Changesets; nicht blockierend für den Default-Doctor.

**Independent Test**: Smoke gegen Fixture (PASS), mit injiziertem Fehler (FAIL + Screenshot), ohne Browser (UNAVAILABLE), mit erzwungener Verzögerung (TIMEOUT + Aufräumen).

**Acceptance Scenarios**:

1. **Given** ein gesundes Projekt, **When** der Maintainer den Smoke startet, **Then** ist das Ergebnis PASS in unter 15 s, ohne Mendix-Runtime, ohne Visual-Parity, ohne Crawling.
2. **Given** kein Browser verfügbar, **When** der Smoke läuft, **Then** ist das Ergebnis UNAVAILABLE für die Browserstufen (nie PASS); die übrigen Stufen laufen.
3. **Given** ein Darstellungsfehler in einer Route, **When** der Smoke läuft, **Then** ist das Ergebnis FAIL mit Route, Fehlerart und einem Fehler-Screenshot außerhalb des Projekts.
4. **Given** ein nicht-interaktiver Installer- oder CI-Lauf, **When** das Core-Update abschließt, **Then** startet kein Smoke automatisch.
5. **Given** ein hängender Board-Prozess, **When** 60 s überschritten sind, **Then** endet der Smoke mit TIMEOUT, und kein Board-Prozess oder belegter Port bleibt zurück.

---

### User Story 4 — Lifecycle sagt eindeutig, wohin Arbeit nach DONE gehört (Priority: P2, CS-0)

Als MxAgile-Agent und Maintainer will ich eindeutige Regeln: DONE bleibt DONE, spätere Arbeit kommt in eine neue Wave, geplante Waves sind maschinenlesbar registriert, und die DONE-Grundlage kann strukturiert erfasst werden.

**Why this priority**: Voraussetzung für korrektes Current Work und „Vertrauen in DONE" (CS-4). Ändert Agentenverhalten → eigene Freigabe.

**Independent Test**: Schema- und Doctor-Fixtures; read-only Doctor-Lauf gegen Referenzprojekt ergibt neue Hinweise (nur INFO/WARNING), keine neuen Blocker.

**Acceptance Scenarios**:

1. **Given** ein Projekt, dessen letzte Wave DONE ist, **When** neue oder nachgearbeitete Arbeit autorisiert wird, **Then** schreiben die Regeln eine neue Wave vor; die DONE-Wave wird nicht wiedereröffnet.
2. **Given** eine in der Wave-Planung autorisierte Wave, **When** sie autorisiert wird, **Then** ist sie im selben Schritt im Wave-Register registriert (noch ohne Fortschritt).
3. **Given** bestehende Prozesszustände ohne neue Gate-Felder, **When** sie validiert werden, **Then** bleiben sie gültig; neue Acceptance-/Testability-Gate-Einträge sind ebenfalls gültig.
4. **Given** Referenzprojekt (read-only), **When** Doctor läuft, **Then** erscheinen Hinweise zu schema-invaliden Change-Sets und zu DONE-Waves ohne erfasste DONE-Grundlage — nie als Blocker, nie mit Reparatur.
5. **Given** das Glossar, **When** ein Agent „Campaign", „GAP", „Change-Set" oder „Workpackage" nachschlägt, **Then** findet er die kanonische Rolle (Campaign = Acceptance-Lauf, GAP = Finding, Change-Set = Provenance, Workpackage = optionales Label).

---

### User Story 5 — Ich sehe, was meine Aufmerksamkeit braucht — getrennt von Systemdiagnose (Priority: P2, CS-3)

Als PO will ich Projekt-Aufmerksamkeit, Datenqualität der Projektion und Framework-Diagnostik getrennt sehen und jeden Unbekannt-Zustand eindeutig verstehen.

**Why this priority**: Referenzprojekt zeigt 184 Diagnosen (0 blockierend) über jeder Seite und acht verschiedene Bedeutungen von „UNKNOWN".

**Independent Test**: Fixture mit allen Beobachtungszuständen; Referenzprojekt read-only: Zustands-Mapping alt → neu.

**Acceptance Scenarios**:

1. **Given** nur nicht-blockierende Kompatibilitätshinweise, **When** der PO eine Fachansicht öffnet, **Then** erscheinen sie nicht als Inhalt, sondern über einen kompakten Gesundheitsindikator und eine eigene Diagnose-Ansicht.
2. **Given** ein fehlendes Findings-Verzeichnis, **When** der PO die Findings öffnet, **Then** lautet der Zustand „nicht erfasst" mit Erklärung, nicht „UNKNOWN".
3. **Given** strukturell nicht ermittelbare Werte (z. B. Modellfrische), **When** der PO das Board nutzt, **Then** werden sie einmal in der Gesundheitsansicht erklärt und nicht als Projekt-Aufmerksamkeit gezählt.
4. **Given** ein optionales, nicht gesetztes Feld (Workpackage), **When** Diagnosen angezeigt werden, **Then** sind sie als „optionale Metadaten" gruppiert, nicht als Defekte.

---

### User Story 6 — Ich verstehe aktuelle Arbeit, Fertigstellung und ihre Belege (Priority: P2, CS-4)

Als PO will ich sehen, woran gearbeitet wird (oder dass keine kanonische Arbeit aktiv ist), warum ein Requirement als fertig oder nicht fertig gilt, worauf DONE beruht, welche Decisions und Revisionen wirken und welche Parity-Berichte existieren.

**Why this priority**: Beantwortet die Kernfragen 1, 5–8, 11, 12 aus dem Plan (Abschnitt J).

**Independent Test**: Regel-Fixtures für Delivery Assessment und Current-Work-Kaskade; Referenzprojekt read-only Abgleich.

**Acceptance Scenarios**:

1. **Given** eine aktive Mission, **When** der PO die Overview öffnet, **Then** zeigt „Current Work" Mission, Ziel, aktive Wave, Fortschritt, Blocker (mit Reichweite und weiterführbarer Arbeit) und nächsten Schritt mit Quelle.
2. **Given** keine Mission, keine aktive und keine registrierte geplante Wave, aber Projekt-Commits nach dem letzten DONE, **When** der PO die Overview öffnet, **Then** steht dort „Keine aktive kanonische Arbeit" plus der Hinweis „Arbeit außerhalb des kanonischen Lifecycles beobachtet" — ohne Zuordnung zu einer Wave.
3. **Given** widersprüchliche Quellen (aktive Wave zeigt auf DONE-Wave), **When** Current Work abgeleitet wird, **Then** lautet der Zustand CONFLICT.
4. **Given** ein Requirement, **When** der PO dessen Detail öffnet, **Then** sieht er eine als „abgeleitet" gekennzeichnete Bewertung mit Regelversion, jede Stufe mit verlinkter kanonischer Evidenz bzw. Grund der Nichterfüllung.
5. **Given** eine DONE-Wave mit offenen Legacy-Tasks und erfasster Acceptance-Grundlage, **When** der PO „Vertrauen in DONE" öffnet, **Then** sind die Tasks als „durch Acceptance-Evidenz überholt" gekennzeichnet; ohne Grundlage lautet der Zustand „DONE-Grundlage nicht erfasst".
6. **Given** Parity-Reports ohne gebundene Captures (Referenzprojekt: 6 PASS, 5 PARTIAL), **When** der PO Pages oder Verification öffnet, **Then** erscheinen sie als „berichtet, nicht belegt", nie als verifiziert und nie unsichtbar.
7. **Given** eine aktive Revision im Revisions-Ledger (Referenzprojekt REV-037), **When** der PO Design Authority öffnet, **Then** ist sie mit gebundenen und nicht gebundenen Pages sichtbar.
8. **Given** eine Page mit auflösbarer HTML-Quelle bei Projektvorgabe „nicht HTML-first", **When** der PO die Page sieht, **Then** werden Absicht und Fakt getrennt gezeigt und die Abweichung als Gesundheitshinweis markiert.

---

### User Story 7 — Ich sehe, was zuletzt passiert ist und wie es zusammenhängt (Priority: P3, CS-5)

Als PO will ich eine Timeline und „Recent Activity" aus dauerhafter Projektgeschichte, mit nachvollziehbarer Herkunft jedes Eintrags und ehrlicher Spur für nicht zuordenbare Aktivität.

**Why this priority**: Beantwortet Fragen 2–4, 10 aus Plan J; baut auf Performance-Infrastruktur und Zustandsvokabular auf.

**Independent Test**: Fixture-Repository mit synthetischer Historie (Merge, Rebase, Shallow, Trailer, Change-Sets gültig/ungültig); zwei Läufe liefern identische Ereignis-IDs.

**Acceptance Scenarios**:

1. **Given** Commits, die kanonische Artefakte ändern, **When** der PO die Timeline öffnet, **Then** sieht er Ereignisse mit Zeit, betroffenen Entitäten, Autoritätsklasse und Beleg-Commit.
2. **Given** ein Commit ohne Artefaktbezug, Trailer oder Change-Set, **When** er in der Timeline erscheint, **Then** liegt er in der Spur „Nicht zugeordnet" — unabhängig von zeitlicher Nähe zu einer Wave.
3. **Given** eine Commit-Message erwähnt eine ID ohne Dateibezug, **When** angezeigt, **Then** ist der Bezug als „erwähnt" gekennzeichnet.
4. **Given** ein Change-Set mit Freitext-Missionsangabe, **When** angezeigt, **Then** wird diese als Label gezeigt und nur bei exakter ID-Gleichheit mit dem Mission-State verlinkt.
5. **Given** Filter (Zeitraum, Typ, Wave, Requirement, Page, Mission/Change-Set, Autoritätsklasse), **When** angewendet, **Then** ist die gefilterte Ansicht als Link teilbar.
6. **Given** OD-2, **When** Agenten aktuell arbeiten, **Then** zeigt das Board keine Live-Telemetrie.

---

### User Story 8 — Eine Page an einem Ort prüfen (Priority: P3, CS-6)

Als PO will ich pro Page Referenz-Mockup, HTML-Quelle, Design Preview, zuletzt erfasste Runtime, Soll/Ist-Captures, Parity-Bericht, Evidenz-Stand und Verlauf an einer Stelle — besonders für HTML-first Pages, die in Studio Pro kaum prüfbar sind — sowie eine Navigation, die nach menschlichen Fragen gegliedert ist.

**Why this priority**: Abschluss der IA; setzt alle vorherigen Projektionen voraus.

**Independent Test**: PO-Walkthrough entlang der 12 Fragen (Plan J) mit Referenzprojekt-Screenshots (read-only); Smoke mit neuer Routenliste.

**Acceptance Scenarios**:

1. **Given** eine HTML-first Page, **When** der PO den Page Hub öffnet, **Then** erreicht er Referenz, Design Preview, HTML-Quelle, Inventory-Quelle, Parity-Bericht und — falls erfasst — Runtime-URL „aus Evidenz vom …".
2. **Given** ein Parity-Bericht ohne Identität/Captures, **When** der Hub ihn zeigt, **Then** nennt er den Grund, warum die Parität nicht belegt ist, und gegen welche Referenz verglichen wurde.
3. **Given** alte Deep-Links, **When** sie geöffnet werden, **Then** führen sie zur neuen Route; die alte Navigation bleibt einen Release lang erreichbar.
4. **Given** die neue Navigation (NOW / DELIVERY / QUALITY / SYSTEM), **When** der PO die 12 Fragen aus Plan J beantwortet, **Then** ist jede ohne Rohdateien beantwortbar oder als „nicht erfasst" erklärt.

---

### Edge Cases

- Parallele Agentenarbeit während Board-Aufbau oder Smoke (Referenzprojekt: HEAD wanderte während der Inspektion) → letzter gültiger Stand mit Alter; nie Startfehler.
- Gleicher Zeitstempel bei Inhaltsänderung → Änderung muss trotzdem erkannt werden.
- Rebase/Force-Push, Shallow-Clone, Merge-Commits → Timeline-Index invalidiert bzw. First-Parent-Behandlung; keine falschen Zuordnungen.
- Fehlende Quellen (Mission, Context Epoch, Findings, Target-Mockups) → `NOT_RECORDED`, nicht Fehler und nicht „UNKNOWN".
- Legacy-Formen (leeres Legacy-Evidence-Manifest, Descriptive Filenames, Task-Inspect-Altform, Mojibake in Notizen) → sichtbar, klassifiziert, nicht normalisiert weg.
- Schema-invalide Change-Sets → als Ereignis mit Gesundheitshinweis, ohne Zuordnungswirkung.
- Kein Browser, belegter Port, hängender Prozess → Smoke UNAVAILABLE/FAIL/TIMEOUT mit Aufräumen.
- Sehr große Modellverzeichnisse (2.140 Dateien in Referenzprojekt) → werden für interaktive Nutzung nicht gescannt.
- Gelöschter Projektion-Cache → vollständiger, korrekter Neuaufbau ohne Projektwirkung.

## Requirements *(mandatory)*

### Functional Requirements

Kennung `[CS-n]` = verbindliches Changeset laut Implementation Contract. `[BRD-F-xx]` = Befund-Referenz.

**Übergreifend**

- **FR-001**: Das Board MUST strikt read-only bleiben: keine Schreibzugriffe auf das Projekt, keine Schreib-Endpunkte, keine Mutation kanonischer Artefakte.
- **FR-002**: Abgeleitete Zwischenstände MUST außerhalb des Projektverzeichnisses liegen, jederzeit löschbar und vollständig rekonstruierbar sein und nie als Autorität gelten.
- **FR-003**: Das Board MUST jeden angezeigten Wert auf eine kanonische Quelle, einen Beleg-Commit oder eine ausgewiesene Ableitungsregel zurückführen können.
- **FR-004**: Die Changesets MUST in der Reihenfolge CS-1 → CS-2 → CS-7 → CS-0 → CS-3 → CS-4 → CS-5 → CS-6 einzeln geliefert, geprüft und mit einem STOP abgeschlossen werden.
- **FR-005**: Vor CS-0 MUST der Eigentümer die vorbestehenden uncommitteten Framework-Änderungen committen; CS-0 MUST diese weder aufnehmen noch überschreiben noch zurücksetzen.

**CS-1 Korrektheit**

- **FR-010** [CS-1][BRD-F-01]: Nicht geladene Drift-Daten MUST als „lädt" erscheinen; aktueller HEAD und Branch MUST aus der Grundprojektion sichtbar sein.
- **FR-011** [CS-1][BRD-F-02]: Ein bekannter HEAD MUST auch ohne Watermark angezeigt werden.
- **FR-012** [CS-1][BRD-F-03]: Detailansichten MUST auch terminale Findings auflösen.
- **FR-013** [CS-1][BRD-F-04]: Das Board MUST keine Zähler ausgeben, deren Quelle nicht verfügbar ist.
- **FR-014** [CS-1][BRD-F-05]: Page-Anzahlen MUST in allen Ansichten übereinstimmen; Standalone-Interaction-Artefakte sind keine Pages.
- **FR-015** [CS-1][BRD-F-06, F-08]: Paritätsangaben MUST einer einzigen serverseitigen Regel für „letzter Lauf" folgen und dürfen ohne geladene Daten keinen Wert vortäuschen.
- **FR-016** [CS-1][BRD-F-07]: Parity-Reports MUST als Quelle öffnenbar sein.

**CS-2 Performance**

- **FR-020** [CS-2][BRD-F-10]: Interaktive Anfragen und Link-Aufrufe MUST ohne erneuten Gesamtscan des Projekts beantwortet werden; Änderungserkennung MUST gedrosselt im Hintergrund erfolgen und große Modellverzeichnisse nicht einzeln durchlaufen.
- **FR-021** [CS-2][BRD-F-11]: Bei Quelländerung während des Aufbaus MUST das Board den letzten gültigen Stand mit Altersangabe liefern oder erneut aufbauen; ein Startfehler ist nicht zulässig.
- **FR-022** [CS-2]: Inhaltsänderungen kanonischer Dateien MUST auch bei unverändertem Zeitstempel erkannt werden.
- **FR-023** [CS-2][BRD-F-24]: Die Drift-/Reconciliation-Analyse MUST mit konstant wenigen Prozessaufrufen je Commit-Bereich auskommen und inhaltlich gleichwertige Ergebnisse liefern.
- **FR-024** [CS-2]: Die Projektion MUST ihren Zustand und ihr Alter ausweisen.
- **FR-025** [CS-2]: Ein Rückfallmodus auf das bisherige Cache-Verhalten MUST für einen Release verfügbar sein.

**CS-7 Board-Smoke**

- **FR-030** [CS-7]: Ein optionaler Board-Smoke MUST die Stufen Vorprüfung, Start, Daten, Darstellung der Hauptansichten, je ein Drilldown (Wave, Requirement, Page), höchstens fünf repräsentative Links und sechs Konsistenzwerte prüfen.
- **FR-031** [CS-7]: Der Smoke MUST in der Regel unter 15 s abschließen und hart nach 60 s mit TIMEOUT enden, inklusive Prozess- und Port-Aufräumen.
- **FR-032** [CS-7]: Ohne Browser MUST das Ergebnis UNAVAILABLE lauten; fehlende Fähigkeit wird nie als PASS gewertet.
- **FR-033** [CS-7]: Der Smoke MUST weder Mendix-Runtime starten noch Visual-Parity ausführen, Entitäten crawlen, Regression-Suiten starten oder ins Projekt schreiben.
- **FR-034** [CS-7]: Screenshots MUST nur bei Fehlern und nur außerhalb des Projekts entstehen.
- **FR-035** [CS-7]: Das Ergebnis MUST maschinenlesbar sein und Exit-Codes PASS/FAIL/UNAVAILABLE/Betriebsfehler unterscheiden.
- **FR-036** [CS-7][OD-4]: Doctor und Core-Update dürfen den Smoke nur anbieten; Default-Doctor bleibt browserfrei; nicht-interaktive Läufe starten ihn nie automatisch.

**CS-0 Lifecycle-Klärung**

- **FR-040** [CS-0][R1]: Die Lifecycle-Regeln MUST festhalten, dass eine DONE-Wave nicht wiedereröffnet wird; widerlegte DONE-Aussagen werden scoped über bestehende Mechanismen erfasst.
- **FR-041** [CS-0][R2][BRD-F-32]: Die Regeln MUST spätere, neue und nachgearbeitete Arbeit nach DONE einer neuen Wave zuweisen; die Verknüpfung erfolgt über vorhandene Felder (Finding → Repair-Task → Wave).
- **FR-042** [CS-0][R3][BRD-F-33]: Die Regeln MUST verlangen, eine Wave bei Autorisierung im Wave-Register zu registrieren.
- **FR-043** [CS-0][R4][BRD-F-30]: Der Prozesszustand MUST optionale Acceptance- und Testability-Gate-Einträge zulassen (Acceptance mit Zustand „pending"); bestehende Zustände bleiben gültig.
- **FR-044** [CS-0][R5][BRD-F-31, F-35]: Glossar und Lifecycle-Beschreibung MUST die kanonischen Rollen von Mission, Workpackage, Acceptance Campaign, GAP, Repair Task und Change-Set definieren und den kanonischen Ort des Prozesszustands konsistent nennen.
- **FR-045** [CS-0][R6][BRD-F-34]: Doctor MUST schema-invalide Change-Sets, DONE-Waves ohne erfasste Grundlage und ungebundene aktive Revisionen als nicht blockierende Hinweise melden, ohne Reparatur und ohne Auswertung von Markdown-Planungsdateien.
- **FR-046** [CS-0]: CS-0 MUST keine neue kanonische Entität, keine automatische Projektmigration und keine Board-Änderung enthalten.

**CS-3 Zustände & Trennung**

- **FR-050** [CS-3]: Jeder projizierte Bereich MUST genau einen Beobachtungszustand aus dem geschlossenen Vokabular tragen: AVAILABLE, EMPTY, NOT_RECORDED, NOT_LOADED/LOADING, STALE, INVALID, UNSUPPORTED, NOT_OBSERVABLE, NOT_APPLICABLE, AMBIGUOUS, PROJECTION_ERROR.
- **FR-051** [CS-3][BRD-F-21]: Strukturell nicht ermittelbare Werte MUST als NOT_OBSERVABLE geführt und nicht als Projekt-Aufmerksamkeit gezählt werden.
- **FR-052** [CS-3][BRD-F-22]: Diagnosen MUST in Projekt-Aufmerksamkeit, Projektionsgesundheit, Framework-Kompatibilität und optionale Metadaten gruppiert werden.
- **FR-053** [CS-3][BRD-F-23]: Fehlende Quellen MUST als NOT_RECORDED mit Erklärung erscheinen; leere Quellen als EMPTY.
- **FR-054** [CS-3][G-01]: Projektkontext und Kompatibilitätsdiagnose MUST nur auf Overview bzw. Gesundheitsansicht erscheinen; global bleibt ein kompakter Gesundheitsindikator.
- **FR-055** [CS-3]: Bisherige Verfügbarkeitsfelder MUST einen Release lang parallel bestehen.

**CS-4 Projektionen**

- **FR-060** [CS-4]: Current Work MUST ausschließlich über die Kaskade Mission → registrierte aktive/blockierte Wave → nächste registrierte Wave → „keine aktive kanonische Arbeit" abgeleitet werden; Widersprüche ergeben CONFLICT.
- **FR-061** [CS-4][K.6]: Werden nach dem letzten DONE-Übergang Commits auf Projekt- oder Modellpfaden beobachtet, ohne aktive kanonische Arbeit, MUST das Board „Arbeit außerhalb des kanonischen Lifecycles beobachtet" melden, ohne diese einer Wave zuzuordnen.
- **FR-062** [CS-4][OD-1]: Das Requirement Delivery Assessment MUST als „abgeleitet" gekennzeichnet, regelversioniert und je Stufe mit kanonischer Evidenz oder Nichterfüllungsgrund versehen sein; es wird nie zurückgeschrieben.
- **FR-063** [CS-4][K.5][BRD-F-14]: „Vertrauen in DONE" MUST je Wave DONE-Grundlage, Legacy-Status, überholte offene Tasks, spätere Findings/Overrides und Änderungen nach DONE zeigen.
- **FR-064** [CS-4][BRD-F-19]: Decisions MUST Datum, Bestätigungsdatum, Begründungsauszug und betroffene Requirements, Screens und Revisionen zeigen.
- **FR-065** [CS-4][BRD-F-16]: Das Revisions-Ledger MUST als Design-Authority-Quelle projiziert werden.
- **FR-066** [CS-4][BRD-F-15]: Parity-Reports ohne gebundene Evidenz MUST als „berichtet, nicht belegt" erscheinen.
- **FR-067** [CS-4][BRD-F-17]: Implementierungsmodus MUST als Absicht und Fakt getrennt gezeigt werden.
- **FR-068** [CS-4][BRD-F-13]: Vorhandene, nicht kanonisierte Checklisten MUST als solche sichtbar sein.
- **FR-069** [CS-4]: Mission- und Context-Epoch-Felder (Ziel, Fortschritt, Blocker-Details, Checkpoint-Commits, Terminal-Guard-Ergebnis, nächster Schritt) MUST projiziert werden, wenn vorhanden.

**CS-5 Timeline**

- **FR-070** [CS-5]: Die Timeline MUST aus kanonischen Artefakten und Git-Historie rekonstruiert werden; rekonstruierbare Ereignisse werden nicht persistiert. Dauerhafte Ausführungshistorie (Delegation Results, Change-Sets, Mission-Checkpoints, Context-Epoch-Rollover, Gate-Auswertungen, Reconciliation, Framework-Update/Doctor) ist Teil der Timeline [BRD-F-27]; fehlende Übergangszeitstempel werden als NOT_RECORDED geführt, nicht erschlossen [BRD-F-28].
- **FR-071** [CS-5][K.6]: Zuordnungen MUST ausschließlich über die Autoritätsklassen kanonischer Eintrag, Git-abgeleitete Artefaktänderung, Commit-Trailer mit gültigem Change-Set oder gekennzeichnete Erwähnung erfolgen; sonst Spur „Nicht zugeordnet".
- **FR-072** [CS-5]: Ereignis-IDs MUST deterministisch und über Läufe stabil sein.
- **FR-073** [CS-5]: Merge, Rebase, Shallow-Historie MUST korrekt behandelt werden (First-Parent; Invalidierung bei Nicht-Vorfahr).
- **FR-074** [CS-5]: Filter nach Zeitraum, Typ, Wave, Requirement, Page, Mission/Change-Set und Autoritätsklasse MUST verfügbar und als Link teilbar sein.
- **FR-075** [CS-5][OD-2]: Live- oder Harness-Telemetrie MUST NOT angezeigt werden.
- **FR-076** [CS-5]: Overview MUST die fünf jüngsten Ereignisse als Recent Activity zeigen; Detailansichten zeigen entitätsbezogene Verläufe.

**CS-6 IA & Page Hub**

- **FR-080** [CS-6]: Die Navigation MUST nach NOW (Overview, Timeline), DELIVERY (Waves, Requirements, Tasks), QUALITY (Verification, Pages & Parity, Findings, Decisions) und SYSTEM (Health & Diagnostics, Portfolio) gegliedert sein.
- **FR-081** [CS-6]: Der Page Hub MUST Referenz, HTML-Quelle, Design Preview, zuletzt erfasste Runtime, Soll/Ist- und vorherige Captures, Parity-Bericht, Evidenz-Stand (Commit/Modell/Runtime, sofern erfasst), Page-Verlauf, Authority und Builder-Kit-Fähigkeit zeigen.
- **FR-082** [CS-6]: Screenshots allein MUST nie einen Paritätsstatus begründen; Overlays/Diffs nur aus referenzierten Artefakten.
- **FR-083** [CS-6]: Der Page Hub MUST nur die Daten der gewählten Page laden.
- **FR-084** [CS-6]: Alte Routen MUST umgeleitet werden; die bisherige Navigation bleibt einen Release lang erreichbar.

### Key Entities

- **Projektion (Snapshot)**: abgeleiteter, fingerprint-gebundener Gesamtstand kanonischer Quellen; Zustand und Alter; nie Autorität.
- **Beobachtungszustand**: geschlossenes Vokabular je Bereich (FR-050).
- **Diagnosegruppe**: Projekt-Aufmerksamkeit / Projektionsgesundheit / Framework-Kompatibilität / optionale Metadaten.
- **Current Work**: abgeleitete Sicht aus Mission, Wave-Register, Tasks/Checklisten; Zustände ACTIVE, BLOCKED, NOT_STARTED, NONE, CONFLICT, plus Hinweis auf nicht zugeordnete Aktivität.
- **Delivery Assessment**: abgeleitete, regelversionierte Bewertung je Requirement mit Stufen (Implementation, Verification, Freshness, Blocker), Evidenzverweisen und Gründen.
- **DONE-Grundlage**: Acceptance-Gate-Eintrag oder `NOT_RECORDED`; Legacy-Klassifikation.
- **Timeline-Ereignis**: deterministische ID, Typ, Autoritätsklasse, Zeitpunkt und Zeitbasis, Entitätsbezüge mit Ableitungsweg, Beleg-Commit, Quelle, optional Change-Set/Mission.
- **Page-Hub-Eintrag**: Page, Referenz/Revision, HTML-Quelle, Implementierungsabsicht/-fakt, Parity-Bericht (computed/reported/unbound), Captures, Evidenz-Stand, Verlauf.
- **Smoke-Ergebnis**: Gesamtresultat, Stufenresultate, Dauer, Browserverfügbarkeit, Fehler-Screenshots.
- **Kanonische Bestandsentitäten (unverändert)**: Mission, Wave (Register + Planung), Task (inkl. Repair), Requirement, Finding (= GAP), Decision, Revision, Page, Parity-Report, Evidence-Manifest, Change-Set (Provenance).

## Success Criteria *(mandatory)*

### Measurable Outcomes

Referenzprojekt für Messungen: Referenzprojekt (read-only), Ausgangswerte 2026-11-05.

- **SC-001**: Bei unverändertem Projekt erscheint eine angeforderte Ansicht in höchstens 0,3 s (heute 3–6,5 s).
- **SC-002**: Ein Quell-, Mockup- oder Screenshot-Link öffnet in höchstens 0,2 s (heute ~8,4 s bzw. ~19 s).
- **SC-003**: Drift-/Reconciliation-Daten für 26 Commits liegen in höchstens 10 s vor (heute 280–373 s) und stimmen inhaltlich mit dem bisherigen Ergebnis überein.
- **SC-004**: Erste Anzeige nach Board-Start in höchstens 3 s mit vorhandenem letzten Stand, höchstens 6 s ohne; unter paralleler Projektarbeit 0 Startfehler in 20 Wiederholungen.
- **SC-005**: Der Board-Smoke endet in höchstens 15 s (Ziel) und spätestens nach 60 s; in 100 % der Fälle ohne Browser lautet das Ergebnis UNAVAILABLE, nie PASS.
- **SC-006**: Nach Board-Nutzung und Smoke ist der Dateisystem- und Git-Zustand des Projekts unverändert (0 Abweichungen).
- **SC-007**: In Referenzprojekt erscheinen 0 nicht-blockierende Diagnosen als Projekt-Aufmerksamkeit (heute 184 über jeder Seite).
- **SC-008**: Jede der 12 Kernfragen aus Plan J ist in Referenzprojekt ohne Öffnen von Rohdateien beantwortbar oder ausdrücklich als „nicht erfasst" erklärt (heute: 0 von 12 vollständig).
- **SC-009**: 100 % der Timeline-Zuordnungen haben eine ausgewiesene Autoritätsklasse; 0 Zuordnungen beruhen auf zeitlicher Nähe (Negativtest-Fixture).
- **SC-010**: Zwei Timeline-Aufbauten derselben Historie liefern 100 % identische Ereignis-IDs; Erstaufbau für ~600 Commits höchstens 10 s, inkrementell höchstens 1 s.
- **SC-011**: Jede abgeleitete Bewertung (Delivery Assessment, Current Work, Vertrauen in DONE) ist als „abgeleitet" gekennzeichnet und verlinkt mindestens eine kanonische Quelle oder einen Nichterfüllungsgrund (100 %).
- **SC-012**: CS-0 erzeugt beim read-only Doctor-Lauf gegen Referenzprojekt 0 neue blockierende Diagnosen; Doctor-Laufzeit steigt um höchstens 10 %.
- **SC-013**: Projekt-Statusaufbau wird durch CS-3/CS-4 um höchstens 10 % langsamer.

### Referenzprojekt-Realitätsfälle (Abnahmefälle, read-only)

| RC | Situation (Stand 2026-11-05) | Erwartung nach Changeset |
|---|---|---|
| RC-01 | Watermark vorhanden, Board zeigt „BASELINE REQUIRED / HEAD UNKNOWN" | CS-1: „lädt" + HEAD/Branch |
| RC-02 | 11 statt 10 Pages in UI & Pages | CS-1: 10 |
| RC-03 | Parity-Report-Quelle → 404 | CS-1: öffenbar |
| RC-04 | 3–6,5 s pro Request, 8,4 s pro Link, 503 beim Kaltstart | CS-2: SC-001…004 |
| RC-05 | Reconciliation 280–373 s | CS-2: SC-003 |
| RC-06 | Change-Sets mit vom Schema nicht erlaubten Feldern (mind. 2 von 3); DONE-Waves ohne strukturierte Grundlage | CS-0: Doctor-Hinweise, keine Blocker |
| RC-07 | 184 Diagnosen (0 blockierend) über jeder Seite | CS-3: nur Gesundheitsindikator + Diagnoseansicht |
| RC-08 | „UNKNOWN" für Findings, Mission, Modellfrische | CS-3: NOT_RECORDED / NOT_OBSERVABLE mit Erklärung |
| RC-09 | 15/15 Waves DONE, Mission fehlt, REF2/Regionen-Arbeit aktiv | CS-4: „Keine aktive kanonische Arbeit" + „Arbeit außerhalb des Lifecycles beobachtet" |
| RC-10 | 13 pending + 1 blocked Task in DONE-Waves | CS-4: „Vertrauen in DONE" mit Grundlage/NOT_RECORDED |
| RC-11 | 6 PASS / 5 PARTIAL Parity-Reports unsichtbar | CS-4: „berichtet, nicht belegt" |
| RC-12 | REV-037 nur über 1 Page sichtbar | CS-4: Revisions-Ledger als Authority |
| RC-13 | PAGE-ABTEILUNGSVERWALTUNG als MENDIX_NATIVE trotz HTML-Quelle | CS-4: Absicht ≠ Fakt markiert |
| RC-14 | Jüngste Arbeit (05.11.) nirgends sichtbar | CS-5: Timeline mit belegten Ereignissen; REF2-Commits ohne Trailer in „Nicht zugeordnet" |
| RC-15 | HTML-first Page nur über verstreute Links prüfbar | CS-6: Page Hub |

## Scope-Grenzen

**Out of Scope (V1)**: Live-/Harness-Telemetrie (OD-2); Schreibfunktionen/Projekteditor; Board-seitige Bild-Diffs; Evidence-Erweiterung um Commit-/Modell-Fingerprint (CX-A, eigene Mission; BRD-F-20 bleibt bis dahin NOT_OBSERVABLE); Ursachenanalyse fehlender Mission-State (CX-C, BRD-F-12); Artifact-Index-Fingerprint (BRD-F-26); projektseitige Referenzprojekt-Nacharbeit (BRD-F-13, BRD-F-18, BRD-F-25, BRD-F-34, BRD-F-36); jede Änderung an Referenzprojekt; automatische Projektmigration.

**Querschnitt**: Server-seitige Teilprojektionen (Page Previews, Builder Kit) werden in CS-3/CS-6 unter den Status-Contract gebracht (BRD-F-09); die Overview-Target-Karte verliert Fingerprints und Authority-Listen (CS-6, BRD-F-29).

## Assumptions

- Der Implementation Contract ist verbindlich; diese Spec übernimmt seine Grenzen unverändert.
- Messungen erfolgen auf derselben Maschinenklasse wie die Referenzprojekt-Ausgangsmessung (Windows-Entwicklerrechner).
- Ein Browser für den Smoke wird über vorhandene Framework-Werkzeuge bereitgestellt oder fehlt; er wird nie automatisch installiert.
- Modellfrische bleibt bis CX-A strukturell NOT_OBSERVABLE; die Spec erfindet keine Freshness.
- Die Re-Sync-Statusregeln in den vorbestehenden, noch uncommitteten `lifecycle-resync.md`-Änderungen werden vom Eigentümer committet; Current Work spiegelt sie.
- Referenzprojekt wird nur read-only genutzt und kann sich während der Arbeit durch parallele Projektarbeit verändern; Realitätsfälle werden deshalb je Lauf mit HEAD dokumentiert.
