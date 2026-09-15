# DFC-AI Orchestrator — Prozessfluss

Dieses Dokument definiert die verbindliche Phasenfolge fuer AI-gestuetzte
Mendix-Entwicklung. Jeder Agent liest dieses Dokument und folgt der aktuellen Phase.

Der aktuelle Phasenstatus wird in `.concord/scratch/process-state.yaml` festgehalten
(lokal, gitignored). Gate-Skills pruefen Vorbedingungen vor Phasenwechseln.

Quellen-Vorrang: siehe `policies/source-priority.md` (D44).

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
- **Skills:** dfc-discovery
- **Agents:** dfc-discovery-agent + **dfc-ui-agent** (parallel, D41)
- **Exit Gate:** dfc-gate-to-refinement
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

- **Entry Gate:** dfc-gate-to-refinement
- **Skills:** dfc-refinement
- **Agents:** dfc-refinement-agent
- **Exit Gate:** dfc-gate-to-ready
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

- **Entry Gate:** dfc-gate-to-ready
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
- **Agents:** **dfc-implementation-agent** (als Subagent, D35)
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

### Security-Timing (D48)

| Zeitpunkt | Aktion |
|---|---|---|
| Bei CREATE ENTITY | Entity Access Rules sofort setzen (erstmal `*` auf alle Module Roles) |
| Waehrend Page/MF-Bau | Keine Access Rules noetig — Development-Modus |
| Nach letztem Domain-Model-Item | Dedizierter Security-Pass: User Roles, Page/MF Access, Demo Users |

---

## Phase: Verifying

- **Entry Gate:** Implementierung abgeschlossen
- **Skills:** check-syntax, test-app, assess-quality (aus `.ai-context/skills/`), dfc-quality-gate
- **Agents:** **dfc-ui-agent** (Verifying-Modus) + **dfc-acceptance-agent** (parallel, D40)
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
- Gate-Skills sind das primaere Qualitaetssicherungsinstrument. Die Zustandsdatei
  ist diagnostisches Tracking — nicht blockierend, aber verbindlich gefuehrt.
- Wenn ein Gate-Skill fehlende Artefakte meldet, dokumentiert er was fehlt und
  blockiert den Phasenwechsel bis die Luecken geschlossen sind.
- Der Ruecklauf Verifying→Implementing ist Checklisten-basiert: nur `failed`-Items
  werden erneut bearbeitet, nicht die gesamte Implementierung.
