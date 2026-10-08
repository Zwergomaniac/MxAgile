# MxAgile Orchestrator — Prozessfluss

Maschinenlesbare Lifecycle-Definition: `.mxagile/lifecycle.yaml` (schema_version: 1).
Dieses Dokument ist die narrative Erweiterung davon — detaillierte Vorbedingungen,
Artefakte, Agenten und Ablaufregeln pro Phase.

Der aktuelle Phasenstatus wird in `planning/lifecycle/process-state.yaml` (Git-tracked,
kanonisch) festgehalten. `.concord/scratch/process-state.yaml` ist nur lokaler Session-Cache.
Gate-Skills pruefen Vorbedingungen vor Phasenwechseln.

Quellen-Vorrang: siehe `policies/source-priority.md` (D44).
Lifecycle Re-Sync & Interruption: siehe `policies/lifecycle-resync.md`.
Ownership-Guard: siehe `policies/ownership-guard.md`.

---

## Board Authority Guard

The external Mendix Epics Board is an **optional organizational status projection**.
Full contract: `policies/backlog-sync.md` § Board Authority Contract.

Board content MUST NOT create scope, extend missions, authorize implementation,
create/reopen Waves, or become the default continuation for "Continue with the project."

After Feature Scope completion and Project/Release Checkpoint evaluation:
- Existing authorized work may be reflected back to the Board as status.
- New scope requires explicit developer/product-authority selection.
- Absence of new authorized scope → product prioritization, NOT Board story selection.
- Projects without Board integration experience no Board-related behavior or prompts.

---

## ORIENTATION Check (vor FRAMEWORK_CHANGE)

**Vor dem FRAMEWORK_CHANGE-Check** den User-Request auf Orientierungsanfragen pruefen.

Erkennt die Anfrage ein Orientierungs-Intent? Beispiel-Patterns:
"wie funktioniert MxAgile", "mxagile help", "was kann ich mit MxAgile machen",
"wie soll ich weitermachen", "what can I do with MxAgile", "how does this work", "help"

**JA → ORIENTATION**
Kurze Orientierung ausgeben (EXPLICIT_HELP-Template aus `policies/user-orientation.md`).
Vollstaendiger Vertrag: `policies/user-orientation.md`.

Orientierung blockiert NIEMALS den eigentlichen Request. Kein Bestaetigunsgate.

- Nur Orientierung angefragt: Orientierung ausgeben, dann auf Benutzerinput warten.
- Orientierung + weitere Aufgabe: Orientierung ausgeben, dann FRAMEWORK_CHANGE-Check und
  normale Lifecycle-Arbeit fortfahren.

**NEIN → weiter mit FRAMEWORK_CHANGE-Check.**

---

## FRAMEWORK_CHANGE Detection

**Vor jeder anderen Lifecycle-Aktion** den User-Request klassifizieren:

Aendert die Anfrage:
- MxAgile Core-Verhalten, Policies, Schemas?
- Agents, Skills, Lifecycle-Architektur?
- Installer/Update-Verhalten?
- Generierte Framework-Projektionen?
- Beliebige Datei unter `.mxagile/` die aus der Framework-Distribution stammt?

**JA → FRAMEWORK_CHANGE**

Dann pruefen: Ist dies der kanonische MxAgile-Framework-Entwicklungs-Workspace?
(`.mxagile/` ist Source-of-Truth UND kein Mendix-Consumer-Projekt)

- **NEIN (Consumer-Projekt):** Installierte `.mxagile/`-Kopie NICHT veraendern.
  Klassifikation melden, Finding dokumentieren, Consumer-Projekt bewahren.
  Vollstaendiger Vertrag: `policies/ownership-guard.md`

- **JA (Framework-Dev-Workspace):** Normale Framework-Entwicklungsregeln gelten.

**NEIN → normales Projekt-Lifecycle-Arbeit; mit Startup Re-Sync fortfahren.**

---

## Startup Re-Sync

Beim Starten in einem bestehenden Projekt oder nach einer Session-Pause:
den Lifecycle-Zustand aus Repository-Artefakten rekonstruieren, BEVOR Lifecycle-Arbeit
fortgesetzt wird. Vollstaendiger Algorithmus: `policies/lifecycle-resync.md`.

### Schritt 1 — Betriebsmodus ermitteln (PFLICHT, vor Lifecycle-Arbeit)

Der Betriebsmodus MUSS deterministisch erkannt werden, BEVOR nach ihm gefragt wird.
Vollstaendiger Erkennungsalgorithmus: `policies/operating-mode.md`.

```
1. Projektroot und .mpr-Pfad bestimmen (lifecycle-resync.md § Projektroot)
2. Plattform pruefen — Linux/headless → CLOSED-AUTONOM sofort
3. scripts/check-studio-pro-status.ps1 -ProjectPath <mpr> -Json ausfuehren
4. Ergebnis klassifizieren:
     isOpen = true                     → LIVE-SP-CURRENT
     isOpen = false, anyStudioProRunning = false → CLOSED-AUTONOM
     isOpen = false, anyStudioProRunning = true  → LIVE-SP-OTHER
     exit 2 / anyStudioProRunning = null         → AMBIGUOUS-SP-STATE
5. Modus in .concord/scratch/process-state.yaml festhalten
6. Bei CLOSED-AUTONOM oder LIVE-SP-OTHER: autonom fortfahren — KEINE Rueckfrage
7. Bei LIVE-SP-CURRENT: sicherer Koexistenz-Modus (policies/consistency-check.md)
8. Bei AMBIGUOUS-SP-STATE: sichere Arbeit fortsetzen;
   Frage nur wenn Ambiguitaet eine Mendix-Modell-Mutation blockiert
```

**Verboten:** Den Benutzer nach dem Betriebsmodus fragen, bevor Schritt 3 ausgefuehrt wurde.
Vollstaendige Regeln fuer erlaubte Rueckfragen: `policies/operating-mode.md § User Question Policy`.

### Schritt 2 — Lifecycle-Zustand rekonstruieren

Quellen in Autoritaetsreihenfolge:
1. Repository-Artefakte (Checkliste, Story-Specs, Decisions, Input-Resources)
2. `planning/lifecycle/process-state.yaml` (kanonisch, Git-tracked — primaere Quelle)
3. `.concord/scratch/process-state.yaml` (lokaler Session-Cache — Fallback wenn (2) fehlt)
4. `.mxagile/lifecycle.yaml`

Abgeschlossene Lifecycle-Phasen werden NICHT neu durchlaufen, nur weil eine neue
Agent-Session startet. Konversationsspeicher ist ergaenzend, nicht autoritativ.

**Kanonischer Zustand gewinnt bei Konflikt mit Session-Cache:**
Wenn `planning/lifecycle/process-state.yaml` eine Wave als `done` zeigt, aber
`.concord/scratch/process-state.yaml` als `verifying` — gewinnt der kanonische Zustand.
Session-Cache wird aus dem kanonischen Zustand rekonstruiert, nie umgekehrt.

**Legacy-Completion-Reconciliation bei historischen Waves:**
Zeigt eine Wave im kanonischen Zustand eine Phase !== `done`, bedeutet das NICHT
automatisch ausstehende Arbeit. Vor jeder Schlussfolgerung ueber historische Waves:
Legacy-Completion-Reconciliation anwenden (`policies/legacy-completion-reconciliation.md`).
Eine Wave kann `VERIFIED_LEGACY_STATE` sein und als abgeschlossen gelten, ohne dass
Implementierung oder Verifikation unter dem aktuellen Protokoll wiederholt wird.

**Orientierung bei frisch initialisiertem oder adoptiertem Projekt:**
Falls nach Startup Re-Sync kein Lifecycle-Zustand vorhanden ist (kein
`planning/lifecycle/process-state.yaml` und kein `.concord/scratch/process-state.yaml`):
kurze PROJECT_INITIALIZED- oder PROJECT_ADOPTED-Orientierung ausgeben.
Vollstaendiger Vertrag: `policies/user-orientation.md`.
Orientierung blockiert niemals den eigentlichen User-Request.

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

## Credential Bootstrap and Prerequisite Discovery

Wenn `development.ui_driven = true` oder wenn ein Runtime-relevanter Lifecycle-Schritt
bevorsteht, MUSS vor dem Versuch den Runtime zu starten die vollstaendige Prerequisite-
und Credential-Discovery ausgefuehrt werden.

Vollstaendiger Contract: `policies/credential-discovery.md`

Kurzfassung des pflichtmaessigen Ablaufs:

```
prerequisite benoetigt
    ->
automatisch entdecken (`.env.mendix`, mxcli config, Projekteinstellungen, ...)
    ->
kann autonom aufgeloest werden?
    |
    +-- JA -> ausfuehren, validieren, fortfahren
    |
    +-- NEIN
          ->
    Genuinen User-Input benoetigt?
          |
          +-- JA
          |     ->
          | Bootstrap-Datei vorbereiten (key-Namen, Platzhalter, nicht-geheime Defaults)
          | Nur fehlende Keys anfordern
          | `prerequisite_state` in process-state aktualisieren
          | Auto-Resume nach User-Input
          |
          +-- NEIN
                ->
          Technischen Fehler klassifizieren (CONFIG_NOT_DISCOVERED, RUNTIME_START_FAILED, etc.)
```

**NIEMALS:**
- Default-Credential-Fehler als Beweis behandeln, dass `.env.mendix` fehlt oder falsch ist
- `ALTER USER`, Passwort-Reset oder Credential-Mutation als Reaktion auf Auth-Fehler
- Secret-Werte ausgeben, in Reports schreiben oder in process-state persistieren

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
  - Mockup-Screenshots unter `.concord/screenshots/mockup/` — vom UI-Agent (evidence: static)
  - Offene Entscheidungen als `DECISION REQUIRED` markiert
  - **Evidenz-Level** fuer alle Befunde klassifiziert (`evidence: static/model/runtime/browser`)
  - Board-Sync ausgefuehrt (wenn Board konfiguriert — optional, D52)
  - Wenn `ui_driven = true`: UI-Driven Runtime Readiness Gate ausgefuehrt (siehe unten)
- **Beschreibung:**
  Zwei Agents arbeiten parallel:
  - **Discovery-Agent:** Analysiert Requirements-Dokument, bestehendes Modell, Board-Stories als
    Rang-3-Kontext (optional — Board autorisiert keinen Scope, siehe Board Authority Guard).
    Fuehrt bei `ui_driven = true` das UI-Driven Runtime Readiness Gate aus.
  - **UI-Agent:** Je nach Ausgangslage in einem von zwei Modi:
    - **Generate-Modus:** Kein Mockup vorhanden, aber App-Beschreibung → Wireframe-HTML
      mit mocketeer-spec generieren, Entwickler-Freigabe einholen, dann Analyze-Modus.
    - **Analyze-Modus:** Mockup vorhanden → per Playwright analysieren, YAML-Feldinventar
      mit `suggested_mendix_type` und `standard_widget` Flag erzeugen (D49).
      **Evidenz-Level: STATIC** — Playwright oeffnet lokale `file://` HTML-Mockups.

  Primaere Quellen sind Kunden-Mockup + Requirements (Rang 1). Generierte Mockups sind
  Rang 1.5 (unterhalb Requirements). Board-Stories sind Kontext (Rang 3).

### UI-Driven Runtime Readiness Gate (Discovery)

Wenn `development.ui_driven = true`, ist FULL UI DISCOVERY PASS nur moeglich wenn:

1. Credential-Discovery ausgefuehrt (`.env.mendix` geprueft)
2. Lokaler Runtime gestartet und erreichbar
3. Repraesentativer Daten-Zustand hergestellt
4. Test-Identitaeten verfuegbar
5. Browser-Evidenz (BROWSER-Level) fuer runtime-testbaren Scope erzeugt

Ohne Browser-Evidenz muss das Discovery-Gate-Ergebnis als eine der folgenden
Zwischenzustaende dokumentiert werden:

| Zustand | Bedeutung |
|---|---|
| `FULL_UI_DISCOVERY_PASS` | Alle 5 Voraussetzungen erfuellt; Browser-Evidenz vorhanden |
| `PARTIAL_DISCOVERY` | Modell/Static-Analyse vollstaendig; Browser-Evidence ausstehend |
| `MODEL_ONLY_DISCOVERY` | Nur STATIC/MODEL-Evidenz; Runtime nicht gestartet |
| `RUNTIME_BLOCKED` | Runtime-Start fehlgeschlagen nach korrekter Credential-Discovery |

**FULL_UI_DISCOVERY_PASS darf NICHT deklariert werden ohne Browser-Evidenz.**

Vollstaendige Evidenz-Level-Definitionen: `policies/evidence-levels.md`

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

### Phase-Boundary Continuation after Implementing (Mandatory)

When ALL checklist items reach terminal state (`done | blocked | deferred`):

```
WAVE_IMPLEMENTATION_COMPLETE
→ persist checklist final state
→ update planning/lifecycle/process-state.yaml
→ checkpoint commit (if authorized — policies/commit-authority.md)
→ lifecycle re-sync (policies/lifecycle-resync.md § Phase-Boundary Continuation)
→ ENTER Verifying automatically
→ DO NOT stop, DO NOT ask user for phase-transition confirmation
```

**lifecycle.yaml prescribes: implementing.next = [verifying]. This transition is
deterministic and requires no user confirmation.**

An empty implementation checklist is NOT mission complete. It is a re-sync trigger.
Run the Terminal-State Guard (policies/mission-completion.md) before any "done" claim.

### Betriebsmodus-Recheck vor erster Mendix-Modell-Mutation

Unmittelbar vor dem ERSTEN `mxcli exec` Aufruf einer Session: Betriebsmodus erneut
pruefen (scripts/check-studio-pro-status.ps1 -Json ausfuehren). Vollstaendige Regeln:
`policies/operating-mode.md § Mutation Recheck`.

Bei CLOSED-AUTONOM oder LIVE-SP-OTHER: sofort fortfahren.
Bei LIVE-SP-CURRENT: Koexistenz-Vertrag anwenden (policies/consistency-check.md).
Bei AMBIGUOUS-SP-STATE: eine Rueckfrage stellen (policies/operating-mode.md § User Question Policy).

### Development Runtime (Warm Local Loop)

Fuer runtime-relevante iterative Implementierung (Pages, Navigation, Microflow-Verhalten,
Validierungen, UI-Iteration) bevorzugt der Implementation-Agent den warmen lokalen
Entwicklungsloop.

Basis-Befehl (Profil-Aufloesung per `policies/development-runtime.md` vor Ausfuehrung — DB-Identitaet muss bekannt sein):

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
- `mxcli docker check` ohne CE-Fehler (Konsistenzpruefung, kein Docker-Build)
- Applikation laeuft und ist erreichbar — bevorzugt `mxcli run --local` im autonomen Modus
  (ohne `--watch`, Level 3); `--watch` wird im Verifying nicht benoetigt
  (vollstaendige Modi: `policies/development-runtime.md` § Runtime Modes;
  Eskalationsregeln: `policies/runtime-strategy.md`)
- Readiness Gate: APPLICATION_REACHABLE per HTTP-Poll bestaetigt bevor
  UI-Agent und Acceptance-Agent starten
- Runtime-Startup-Fehler → TEST_INFRASTRUCTURE_GAP, nicht APPLICATION_DEFECT
- Security Level mindestens Prototype (wenn Security-Pass ausgefuehrt)

### Schritt 2: UI-Agent + Acceptance-Agent (parallel)

Starten sobald Applikation laeuft (lokal oder Docker per Runtime-Strategie):

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
- Board-Sync als organisatorische Status-Reflektion (wenn Board konfiguriert — optional, D52).
  Board-Sync in Verifying ist Reporting, nicht Scope-Import. Neue Board-Stories die beim
  Sync sichtbar werden, autorisieren KEINEN neuen Scope und erweitern KEINE Mission.
- **Terminal-State Guard PFLICHT:** Bevor der Agent "fertig" oder "abgeschlossen" meldet,
  muss die Terminal-State Guard-Pruefung aus `policies/mission-completion.md` ausgefuehrt werden.
  Ein Wave-Report alleine schliesst NICHT die Mission.
  Naechste Aktion: lifecycle re-sync → Mission-Evaluation → weiter oder stoppen.

---

## Feature-Scope Completion & Project/Release Checkpoint

Vollstaendiger Vertrag: `policies/project-release-checkpoint.md`.
Lifecycle-Definition: `.mxagile/lifecycle.yaml` § `feature_scope_completion`.
Terminal-State Guard: `policies/mission-completion.md` (Guard Check 8).

Nachdem eine Wave `done` erreicht, prueft der Terminal-State Guard ob alle autorisierten
Feature-Waves abgeschlossen sind.

```
LETZTE AUTORISIERTE WAVE DONE (oder alle Waves klassifiziert)
→ Legacy-Completion-Reconciliation (policies/legacy-completion-reconciliation.md)
    → historische Waves mit phase != done klassifizieren:
        VERIFIED_LEGACY_STATE            → als done zaehlen; keine Implementierungswiederholung
        CURRENT_REQUIRED_SCOPE           → genuine Restarbeit; weiter mit Completeness Check
        DEFERRED_OUTSIDE_FEATURE_SCOPE   → von Completeness Check ausschliessen
        SUPERSEDED                       → ausschliessen; Nachfolger-Artefakt referenzieren
        GENUINE_DECISION_BLOCKER         → an Entwickler melden; blockiert bis geloest
        UNKNOWN_REQUIRES_RECONCILIATION  → an Entwickler melden; blockiert bis klassifiziert
→ Feature-Scope Completeness Check (project-release-checkpoint.md § Completeness Check)
    → unvollstaendig:
        betroffenen Scope erneut eroeffnen (scoped return routing — policies/lifecycle-resync.md)
        unbetroffene Wave-Ergebnisse erhalten
        deterministisch fortfahren
    → vollstaendig: FEATURE_SCOPE_COMPLETE
        → Project/Release Completion Checkpoint auswerten (Guard Check 8)
            → mission schließt Checkpoint aus (implementation-only scope):
                Hinweis ausgeben: "Project/Release Review verfuegbar wenn bereit"
                MISSION_COMPLETE wenn alle anderen Kriterien erfuellt
            → Checkpoint noch nicht angeboten:
                Concise Offer ausgeben (siehe Nutzer-Interaktion unten)
                Auf Benutzer-Entscheidung warten
                Entscheidung in mission-state.yaml persistieren
            → Checkpoint bereits abgelehnt (status: declined):
                Gespeicherte Entscheidung respektieren
                MISSION_COMPLETE wenn alle anderen Kriterien erfuellt
            → Review ausgewaehlt (QUICK_HEALTH_CHECK / INTEGRATED_PRODUCT_REVIEW / RELEASE_READINESS_REVIEW):
                Review-Profil ausfuehren (policies/project-release-checkpoint.md § Review Profiles)
                Gap-Repair bei autorisierten Gaps (scoped lifecycle return)
                Readiness-Result produzieren
                PROJECT_RELEASE_REVIEW_COMPLETE
                Terminal-State Guard neu ausfuehren
                → MISSION_COMPLETE wenn alle Kriterien erfuellt
```

### Nutzer-Interaktion (Non-Technical)

Der Agent fragt NICHT nach VPL, Verification Economics, Campaign-Taxonomie oder anderen
Framework-Interna. Die Frage an den Entwickler lautet:

```
"Der geplante Feature-Scope ist vollstaendig.

Soll ich eine projektweite Abschluss-Review durchfuehren?

Optionen:
1. Quick Health Check — Erreichbarkeit, Kernpfade, bestehende Tests, offene Gaps
2. Integrated Product Review — vollstaendige UI/UX-Paritaet, Funktionsparitaet,
   Cross-Wave-Regression, Rollenkontrolle
3. Release Readiness Review — alles aus (2) plus NFR/Deployment-Evidence
4. Ueberspringen"
```

### Betriebsmodus fuer Integrated Review

Vor Browser-basierter Evidenz im Rahmen der Review: Betriebsmodus erneut pruefen.
CLOSED-AUTONOM: vollstaendig autonom. LIVE-SP-CURRENT: keine Mendix-Modell-Mutationen;
Browser-Inspektion und Reporting weiter moeglich.

### Non-Trigger Conditions

Der Checkpoint wird NICHT ausgeloest wenn:

- Eine einzelne Wave `done` ist, waehrend noch weitere autorisierte Waves offen sind
- Die aktuelle Mission explizit implementation-only begrenzt ist
- Der Entwickler den Checkpoint in dieser Mission bereits abgelehnt hat

### False Completion Prevention

Folgende Situation MUSS die Feature-Scope Completeness Check ausloesen, NICHT FEATURE_SCOPE_COMPLETE
direkt deklarieren:

- Backend-Logik existiert
- Checkliste sagt `done`
- Acceptance Criteria beschreiben User-sichtbares Verhalten
- Keine erreichbare UI-Oberflaeche konsumiert die Backend-Logik

Dieser Fall fuehrt zu einem gezielten Ruecklauf in `implementing` fuer betroffene Items.

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
  (`mxcli check`, `docker check`, App-Start) dem Entwickler nicht als vollstaendige
  Verifikation praesentieren, solange Schritt 2 (UI-/Acceptance-Agent) nicht gelaufen ist.
- **Implementierungsgates sind Pflichtbedingungen fuer Implementation-Completion — kein
  Gesamtmissions-Abschluss.** Das Bestehen von `mxcli check`, `docker check` oder
  Lint-Gates ist die Definition von IMPLEMENTATION_CHANGE_COMPLETE. Es beendet NICHT
  die Verifying-Phase, die Acceptance-Phase oder die User-Mission. Vollstaendige
  Completion-Level-Definitionen: `policies/mission-completion.md`.
- **Terminal-State Guard vor jedem "fertig"-Statement:** Bevor ein Agent dem Entwickler
  mitteilt, dass die Arbeit abgeschlossen ist, muss der Terminal-State Guard aus
  `policies/mission-completion.md` positiv ausgefuehrt sein (Ergebnis: MISSION_COMPLETE).
  Nur MISSION_COMPLETE erlaubt einen uneingeschraenkten Abschluss-Report.
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


