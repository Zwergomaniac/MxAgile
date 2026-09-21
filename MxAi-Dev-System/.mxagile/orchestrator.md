# MxAgile Orchestrator — Prozessfluss

Maschinenlesbare Lifecycle-Definition: `.mxagile/lifecycle.yaml` (schema_version: 1).
Dieses Dokument ist die narrative Erweiterung davon — detaillierte Vorbedingungen,
Artefakte, Agenten und Ablaufregeln pro Phase.

Der aktuelle Phasenstatus wird in `.concord/scratch/process-state.yaml` festgehalten
(lokal, gitignored). Gate-Skills pruefen Vorbedingungen vor Phasenwechseln.

Quellen-Vorrang: siehe `policies/source-priority.md` (D44).
Lifecycle Re-Sync & Interruption: siehe `policies/lifecycle-resync.md`.

---

## Startup Re-Sync

Beim Starten in einem bestehenden Projekt oder nach einer Session-Pause:
den Lifecycle-Zustand aus Repository-Artefakten rekonstruieren, BEVOR Lifecycle-Arbeit
fortgesetzt wird. Vollstaendiger Algorithmus: `policies/lifecycle-resync.md`.

Quellen in Autoritaetsreihenfolge:
1. Repository-Artefakte (Checkliste, Story-Specs, Decisions, Input-Resources)
2. `.concord/scratch/process-state.yaml`
3. `.mxagile/lifecycle.yaml`

Abgeschlossene Lifecycle-Phasen werden NICHT neu durchlaufen, nur weil eine neue
Agent-Session startet. Konversationsspeicher ist ergaenzend, nicht autoritativ.

---

## Interruption Handling

Ein Benutzer kann den Agent jederzeit unterbrechen. Die bevorzugte Reaktion:

    1. Legitime Anfrage ausfuehren
    2. Lifecycle-Wahrheit bewahren
    3. Danach re-synchronisieren

Unterbrechungsklassen (vollstaendige Definitionen in `policies/lifecycle-resync.md`):

| Klasse | Beispiel | Lifecycle-Konsequenz |
|---|---|---|
| OBSERVATION | "Start die App", "Zeig die Seite" | Phase UNVERAENDERT; vorherige Arbeit fortsetzen |
| CLARIFICATION | Entwickler liefert fehlende Entscheidung | Betroffene Artefakte aktualisieren; nur betroffenes Gate re-evaluieren |
| CHANGE | Mockup geaendert, neue Anforderung | Frueheste betroffene Phase bestimmen; nur betroffenen Scope re-eintreten |
| PAUSE | "Stopp hier" | Abgeschlossene Items bewahren; strukturierter Pause-Eintrag in process-state |
| EXPLORATORY | "Versuche dies ausser Reihenfolge" | Nur mit ausdruecklicher Freigabe; Gates NICHT als bestanden markieren |

**Kein uebertriebenes Ablehnen:** Kein Agent darf eine legitime Benutzeranfrage
lediglich deshalb ablehnen, weil sich das Projekt in einer bestimmten Lifecycle-Phase
befindet. Runtime starten, Seite zeigen, Logs pruefen — alles gueltige Anfragen in jeder Phase.

---

## Phase: Intake

- **Entry Gate:** keines
- **Skills:** (extern — Microsoft Copilot Agent / kundenseitiger Bot)
- **Agents:** Intake-Bot (laeuft AUSSERHALB des Entwickler-Kontexts)
- **Exit Gate:** Completeness-Check durch Intake-Bot
- **Pflichtartefakte:**
  - Mockup(s) unter `input-resources/ui-ux/` abgelegt (HTML, Figma-Export, Screenshot)
  - Spezifikationsdokument unter `input-resources/requirements/` abgelegt (Markdown)
  - Beide Artefakte durch Completeness-Check als `COMPLETE` oder `PARTIAL` markiert
- **Beschreibung:**
  Vorgelagerte Phase: Ein kundenseitiger Bot (z.B. Microsoft Copilot Agent) unterstuetzt
  Fachanwender bei der Erstellung von Mockups und Spezifikationsdokumenten. Der Bot
  fuehrt einen Completeness-Check durch:
  - **COMPLETE:** Artefakte werden in `input-resources/` abgelegt, Discovery beginnt.
  - **PARTIAL:** Bot meldet fehlende Informationen und gibt dem Kunden einen
    Klarifizierungslink (Agent-Link) zum Nachbessern. Schleife dreht sich bis COMPLETE.

  Diese Phase ist OPTIONAL — ein Projekt kann direkt mit Discovery starten, wenn die
  Input-Resources bereits vom Entwickler oder Projektleiter bereitgestellt wurden.

  > **Achtung:** Der Intake-Bot ist KEIN Entwickler-Agent. Er hat keinen Zugriff auf
  > das Mendix-Modell, keine MCP-Tools, und kein Git. Er produziert nur Input-Artefakte.

---

## Phase: Discovery

- **Entry Gate:** keines (oder Intake COMPLETE)
- **Skills:** mxagile-discovery
- **Agents:** mxagile-discovery-agent + **mxagile-ui-agent** (parallel, D41)
- **Exit Gate:** mxagile-gate-to-refinement
- **Pflichtartefakte:**
  - Relevante Input-Resources identifiziert (`input-resources/`)
  - Story-Spezifikation erstellt (`planning/stories/{STORYPREFIX}-*.md`, eine Datei je Requirement)
  - UI-Inventar erstellt (`planning/ui-inventory/`) — vom UI-Agent, wenn Mockups vorhanden
  - Mockup-Screenshots unter `.concord/screenshots/mockup/` — vom UI-Agent
  - Offene Entscheidungen als `DECISION REQUIRED` markiert
  - Board-Sync ausgefuehrt (wenn Board konfiguriert — optional, D52)
- **Beschreibung:**
  Zwei Agents arbeiten parallel:
  - **Discovery-Agent:** Analysiert Requirements-Dokument, bestehendes Modell, Board-Stories (optional).
  - **UI-Agent:** Je nach Ausgangslage in einem von zwei Modi:
    - **Generate-Modus:** Kein Mockup vorhanden, aber App-Beschreibung → Wireframe-HTML
      mit mocketeer-spec generieren, Entwickler-Freigabe einholen, dann Analyze-Modus.
    - **Analyze-Modus:** Mockup vorhanden → per Playwright analysieren, YAML-Feldinventar
      mit `suggested_mendix_type` und `standard_widget` Flag erzeugen (D49).

  Primaere Quellen sind Kunden-Mockup + Requirements (Rang 1). Generierte Mockups sind
  Rang 1.5 (unterhalb Requirements). Board-Stories sind Kontext (Rang 3).

---

## Phase: Refinement

- **Entry Gate:** mxagile-gate-to-refinement
- **Skills:** mxagile-refinement
- **Agents:** mxagile-refinement-agent
- **Exit Gate:** mxagile-gate-to-ready
- **Pflichtartefakte:**
  - Alle `DECISION REQUIRED` beantwortet oder als bewusste Annahme (`ASSUMPTION`) markiert
  - Entscheidungen in `sprints/decisions.md` dokumentiert
  - Widersprueche zwischen Quellen aufgeloest (gemaess `policies/source-priority.md`)
  - Akzeptanzkriterien in Story-Spezifikation vorhanden
  - Marketplace-Widgets identifiziert fuer `standard_widget: false` Items (D49)
- **Beschreibung:**
  Klaerung von Mehrdeutigkeiten, Widerspruechen und fehlenden Geschaeftsregeln.
  Strukturierte Rueckfragen an den Entwickler mit Kontext und Empfehlung.
  Marketplace-Recherche fuer nicht-Standard-Widgets (D49).
  Iterativ bis alle Blocker aufgeloest sind.

---

## Phase: Ready

- **Entry Gate:** mxagile-gate-to-ready
- **Skills:** (keine eigenen)
- **Agents:** (keine eigenen)
- **Exit Gate:** Entwicklerfreigabe zur Implementierung
- **Pflichtartefakte:**
  - Story-Spezifikation vollstaendig und widerspruchsfrei
  - `planning/checklists/W*-implementation-checklist.yaml` erzeugt vom Gate (D37)
  - Wave-Planung in `planning/execution-waves.md` aktualisiert
  - Alle Blocker aufgeloest
- **Beschreibung:**
  Zwischenzustand: alle Vorbedingungen fuer die Implementierung sind erfuellt.
  Das Gate hat die Checkliste aus UI-Inventar + Story-Specs erzeugt (D36). Eine Checkliste
  deckt eine ganze Wave ab und referenziert die enthaltenen Requirements je Item.
  Der Entwickler gibt die Implementierung explizit frei.

---

## Phase: Implementing

- **Entry Gate:** Entwicklerfreigabe
- **Skills:** mxcli-technische Skills (aus `.ai-context/skills/`)
- **Agents:** **mxagile-implementation-agent** (als Subagent, D35)
- **Exit Gate:** Alle Checklisten-Items abgearbeitet
- **Pflichtartefakte:**
  - Mendix-Mapping dokumentiert in der Checkliste
  - MDL-Scripts validiert (`mxcli check --references`) und ausgefuehrt (`mxcli exec`)
  - Wave-Schnitt eingehalten
  - Checklisten-Items als `done`/`blocked`/`deferred` markiert
- **Beschreibung:**
  Der Implementation-Agent arbeitet die `implementation-checklist.yaml` Zeile fuer Zeile ab.
  Er liest Mockup-Screenshots fuer Layout-Entscheidungen (D46).
  Jede Aenderung wird vor Ausfuehrung validiert und dem Entwickler in Klartext beschrieben.

### Development Runtime (Warm Local Loop)

Fuer runtime-relevante iterative Implementierung (Pages, Navigation, Microflow-Verhalten,
Validierungen, UI-Iteration) bevorzugt der Implementation-Agent den warmen lokalen
Entwicklungsloop:

```
mxcli run --local -p <project>.mpr --watch
```

Die Runtime wird gestartet wenn Runtime-Feedback nuetzlich wird — nicht pauschal zu Beginn.
`--watch` erkennt Modellaenderungen und wendet sie automatisch an, ohne volle Neustarts.

Vollstaendige Regeln: `.mxagile/policies/development-runtime.md`.

**Abgrenzung:** Runtime-Inspektion waehrend Implementing ist Entwicklungs-Feedback.
Sie ersetzt NICHT die formale Verifikation (Quality Gate, UI-Agent Verify, Acceptance-Agent)
in der Verifying-Phase. Siehe Invarianten unter Uebergaenge und Ausnahmen.

### Security-Timing (D48)

| Zeitpunkt | Aktion |
|---|---|---|
| Bei CREATE ENTITY | Entity Access Rules sofort setzen (erstmal `*` auf alle Module Roles) |
| Waehrend Page/MF-Bau | Keine Access Rules noetig — Development-Modus |
| Nach letztem Domain-Model-Item | Dedizierter Security-Pass: User Roles, Page/MF Access, Demo Users |

---

## Phase: Verifying

- **Entry Gate:** Implementierung abgeschlossen
- **Skills:** check-syntax, test-app, assess-quality (aus `.ai-context/skills/`), mxagile-quality-gate
- **Agents:** **mxagile-ui-agent** (Verifying-Modus) + **mxagile-acceptance-agent** (parallel, D40)
- **Exit Gate:** Alle Pruefungen bestanden
- **Ablauf (D40):**

### Schritt 1: Quality-Gate (sequenziell, Voraussetzung)

Technische Pruefung — muss bestehen bevor UI/Acceptance starten:
- `mxcli check --references` ohne Fehler
- `mxcli lint` ohne kritische Findings
- `mxcli docker check` ohne CE-Fehler
- Docker-Build und Container-Start erfolgreich
- Security Level mindestens Prototype (wenn Security-Pass ausgefuehrt)

### Schritt 2: UI-Agent + Acceptance-Agent (parallel)

Starten sobald Docker-App laeuft:

**UI-Agent (Verifying-Modus):**
- Checklisten-Abgleich: YAML-Felder gegen `.mx-name-*` Selektoren
- Soll-Ist-Report unter `planning/ui-inventory/`
- App-Screenshots unter `.concord/screenshots/app/`

**Acceptance-Agent:**
- Modell-Inspektion (mxcli DESCRIBE) fuer `inspect:` Items
- Playwright User Journeys fuer `test:` Items
- Acceptance-Report unter `planning/wave-reports/`

### Fehler-Ruecklauf (D50)

Bei Abweichungen:
1. Betroffene Items in `implementation-checklist.yaml` auf `status: failed` setzen
2. Konkreter `failure_reason` pro Item
3. Zurueck in Implementing-Phase — Implementation-Agent bearbeitet nur `failed`-Items
4. Neue Anforderungen die erst beim Testen auffallen → neues Ticket, nicht Checklisten-Ruecklauf

### Abschluss

- Wave-Report unter `planning/wave-reports/` erstellt
- Board-Sync als Reporting (wenn Board konfiguriert — optional, D52)

---

## Uebergaenge und Ausnahmen

- Ein Uebergang von Discovery oder Refinement direkt zu Implementing darf nur bei
  begruendeter Ausnahme mit ausdruecklicher Entwicklerfreigabe erfolgen.
- **Selbstpruefpflicht vor jedem Implementing-Einstieg:** Bevor ein Agent MDL schreibt
  oder ausfuehrt, prueft er `.concord/scratch/process-state.yaml` fuer die betroffene
  Wave. Fehlt Discovery (insbesondere `planning/ui-inventory/` vom UI-Agent) oder ist
  der Phasenstatus nicht `Ready`, implementiert er NICHT kommentarlos weiter. Er benennt
  dem Entwickler explizit, welches Artefakt fehlt und welche Konsequenz das hat (z. B.
  kein Mockup-Abgleich, Risiko unentdeckter UI-Abweichungen), und holt die Ausnahme-
  Freigabe **im selben Turn** ein. Eine spaeter nachgereichte Begruendung nach einer
  Rueckfrage des Entwicklers zaehlt nicht als Freigabe.
- **Verifying ist nicht optional und nicht ersetzbar.** Eine Wave gilt erst als
  abgeschlossen, wenn Quality-Gate UND UI-Agent UND Acceptance-Agent gelaufen sind
  (`planning/wave-reports/`). Ein Agent darf technische Gruenlaufergebnisse
  (`mxcli check`, `docker check`, Docker-Start) dem Entwickler nicht als vollstaendige
  Verifikation praesentieren, solange Schritt 2 (UI-/Acceptance-Agent) nicht gelaufen ist.
- Gate-Skills sind das primaere Qualitaetssicherungsinstrument. Die Zustandsdatei
  ist diagnostisches Tracking — nicht blockierend, aber verbindlich gefuehrt. Ein
  Agent, der eine Wave implementiert oder verifiziert, aktualisiert `process-state.yaml`
  im selben Arbeitsschritt; Drift zwischen Datei und Realitaet meldet er aktiv.
- **`gate_to_refinement` und `gate_to_ready` haben keinen eigenen Agenten** (siehe
  Phasentabellen oben) und werden deshalb nur ausgefuehrt, wenn der gerade aktive
  Agent sie selbst aufruft. Wer Discovery oder Refinement als inhaltlich abgeschlossen
  betrachtet, ruft im selben Arbeitsschritt den zugehoerigen Gate-Skill auf und traegt
  das Ergebnis (`passed`/`failed`, nicht `not_recorded`) unter `waves.<Wave>.gates` in
  `process-state.yaml` ein. `not_recorded` ist nur der Zustand vor dem ersten Durchlauf
  einer Wave zulaessig — nicht das Dauerergebnis fuer eine Wave, die faktisch bereits
  implementiert oder verifiziert wird.
- Wenn ein Gate-Skill fehlende Artefakte meldet, dokumentiert er was fehlt und
  blockiert den Phasenwechsel bis die Luecken geschlossen sind.
- Der Ruecklauf Verifying→Implementing ist Checklisten-basiert: nur `failed`-Items
  werden erneut bearbeitet, nicht die gesamte Implementierung.
- **Process-State kanonische Aktualisierung:** Beim Schreiben von `process-state.yaml`
  immer den GESAMTEN Wave-Block neu schreiben. Niemals einzelne Keys an einen
  bestehenden Block anhaengen — das erzeugt duplizierte YAML-Keys (z.B. zwei `phase:`
  Zeilen). Schema: `.mxagile/schemas/process-state.schema.json`.
  Vollstaendige Regeln: `policies/lifecycle-resync.md`.

### Verification-Invarianten (Development Runtime)

Folgende Invarianten gelten unabhaengig vom Runtime-Zustand waehrend Implementing:

- Erfolgreicher App-Start ≠ Verifikation gestartet
- Runtime-Inspektion waehrend Implementing ≠ UI-Agent Verify
- Visuelles Pruefen waehrend Implementing ≠ Akzeptanz bestanden
- `mxcli run --local` erfolgreich ≠ Wave verifiziert

Ein Agent darf Runtime-Ergebnisse waehrend Implementing dem Entwickler als
Entwicklungs-Feedback praesentieren, NICHT als Verifikationsnachweis.

Die Development-Runtime fuehrt eine zweite Zustandsdimension ein:
Lifecycle-Zustand (`implementing`) und Runtime-Zustand (`running_warm`, `stopped`, etc.)
sind unabhaengig. Runtime-Zustandsaenderungen loesen KEINEN Phasenwechsel aus.

Vollstaendige Regeln: `.mxagile/policies/development-runtime.md`.


