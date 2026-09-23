# Policy: Lifecycle Re-Sync & Interrupt/Resume

Definiert, wie MxAgile-Agents nach Unterbrechungen und beim Session-Start den Lifecycle-Zustand
rekonstruieren und Benutzeranweisungen korrekt klassifizieren.

Schema fuer `process-state.yaml`: `.mxagile/schemas/process-state.schema.json`
Maschinenlesbare Lifecycle-Definition: `.mxagile/lifecycle.yaml`

---

## Grundprinzip

Der USER hat die Kontrolle ueber die Session.

Der MxAgile Lifecycle ist das autoritative Register des Lieferfortschritts.

Eine Benutzeranweisung impliziert KEINEN automatischen Lifecycle-Uebergang.

Bevorzugte Reaktion auf eine Unterbrechungsanfrage:

    1. Legitime Anfrage ausfuehren
    2. Lifecycle-Wahrheit bewahren
    3. Danach re-synchronisieren

Nur ablehnen oder zurueckstellen, wenn die Ausfuehrung eine Safety-Regel verletzt
oder Lifecycle-Evidenz faelschlicherweise als valide erscheinen lassen wuerde.

---

## Autoritaetsreihenfolge

Bei Widerspruechen zwischen Quellen gilt:

1. Repository-Artefakte (Checklist, Story-Specs, Decisions, Input-Resources) — autoritativ
2. `planning/lifecycle/process-state.yaml` — **kanonischer** Wave-Laufzustand (Git-tracked, durable)
3. `.concord/scratch/process-state.yaml` — lokaler Session-Cache; nur ergaenzend wenn
   `planning/lifecycle/process-state.yaml` fehlt oder juenger ist. NICHT die autoritative Quelle.
4. `.mxagile/lifecycle.yaml` — kanonische Phasen- und Gate-Definitionen
5. Konversationsspeicher — ergaenzend; NICHT ausreichend als alleinige Grundlage

Ein frischer Agent ohne Konversationsgeschichte MUSS den Zustand aus (1)-(2) und (4) allein
rekonstruieren koennen. Das Loeschen von `.concord/scratch/` darf keine kanonische
Lifecycle-Information zerstoeren.

---

## Projektroot-Bestimmung

**Lifecycle Re-Sync operiert ausschliesslich vom aktuellen MxAgile-Projektroot.**

Die erste Aufgabe der Re-Sync ist die Bestimmung dieses Roots.
Danach wird der Lifecycle-Zustand NUR aus Artefakten innerhalb dieses Roots rekonstruiert.

### Marker-Erkennung

Ein Verzeichnis ist der MxAgile-Projektroot wenn es mindestens eines der folgenden
kanonischen Marker enthaelt:

| Marker | Bedeutung |
|---|---|
| `mxagile-project.yaml` | Explizite MxAgile-Projektkonfiguration |
| `.mxagile/` | Installiertes MxAgile-Framework |
| `.concord/` | Laufzeit-/Artefakt-Verzeichnis von MxAgile |
| `planning/checklists/` | Vorhandene Implementierungspflichten |
| `*.mpr` | Mendix-Projektdatei |

### Bestimmungsalgorithmus

1. Aktuelles Arbeitsverzeichnis (CWD) pruefen — Marker vorhanden? → Das ist der Projektroot.
2. Falls CWD keinen Marker hat: ein Verzeichnis nach oben gehen, erneut pruefen.
3. Sobald ein Marker gefunden: Projektroot festgelegt — weiteres Traversieren stoppen.
4. Falls eine `.git`-Grenze ueberschritten wird ohne Marker: Traversieren sofort stoppen.
   Das CWD oder das naechste Verzeichnis mit Markern ist der Root.

Maximal 1-2 Verzeichnisebenen nach oben traversieren. Kein Suchen ueber das ganze Dateisystem.

### Eindeutigkeit

Sobald der Projektroot bestimmt ist, gilt er fuer die gesamte Session.
Re-Sync liest KEINE Artefakte ausserhalb dieses Roots.

---

## Scope-Grenzen (Boundary Rules)

Waehrend normaler Lifecycle Re-Sync gilt:

**NICHT traversieren:**
- Eltern-Repositories (z.B. framework dev-tree ausserhalb des Projektroot)
- Geschwister-Projekte oder Geschwister-Testprojekte
- `project-templates/` Verzeichnisse ausserhalb des Projektroot
- Verschachtelte Repositories die kein MxAgile-Marker des aktuellen Projekts enthalten
- Unverwandte `.git`-Verzeichnisse

**NICHT modifizieren:**
- Eltern-Repositories
- Geschwister-Projekte
- Framework-Repositories ausserhalb des Projektroot
- `.gitignore` von Eltern- oder Geschwister-Repos

**Boundary-Beispiel (Reality-Test-Regression):**

    CWD = MxAi-Dev-System/.testing-greenfield-rt4/

    Korrekt:
      Projektroot = .testing-greenfield-rt4/
      Re-Sync liest: .testing-greenfield-rt4/.mxagile/lifecycle.yaml
      Re-Sync liest: .testing-greenfield-rt4/.concord/scratch/process-state.yaml
      Re-Sync liest: .testing-greenfield-rt4/planning/checklists/W01-implementation-checklist.yaml

    Falsch (verboten):
      Traversieren in MxAi-Dev-System/ (Eltern-Framework)
      Lesen von MxAi-Dev-System/.mxagile/ als Lifecycle-Quelle
      Lesen von MxAi-Dev-System/project-templates/ oder Geschwister-Testprojekten
      Aendern von MxAi-Dev-System/.gitignore
      Erstellen eines Commits im Eltern-Repository

---

## Git-History

Git-History ist KEIN kanonischer Lifecycle-Zustand.

**Normaler Startup Re-Sync darf Git-History NICHT verwenden**, wenn die kanonischen
Projekt-Artefakte die benoetigte Evidenz liefern:

    Primaere Evidenz:
    lifecycle.yaml -> process-state.yaml -> implementation-checklist
        -> decisions.md -> story specs -> input-resources

Git-History darf NUR inspiziert werden wenn:
- Der Benutzer eine explizite Repository-History-Aufgabe stellt, ODER
- Die kanonischen Projekt-Artefakte fehlen UND der Benutzer ausdruecklich genehmigt

Das Fehlen von `process-state.yaml` bedeutet: Lifecycle-Phase aus vorhandenen
Artefakten ableiten (Checkliste, Story-Specs, Gate-Artefakte) — NICHT: Git-Log lesen.

---

## Git-Mutationen verboten waehrend Orientation/Re-Sync

Orientierung und Lifecycle Re-Sync sind KEINE Erlaubnis fuer:

- `git add`
- `git commit`
- `git push`
- Aendern von `.gitignore` (in keinem Repository)
- Bereinigen oder Reparieren von Eltern-/Geschwister-Repositories

Solche Aktionen sind nur erlaubt wenn sie:
1. Teil der aktuellen Liefer-Aufgabe sind, ODER
2. Ausdruecklich vom Benutzer in derselben Session angefordert wurden

Das Finden eines `.git`-Verzeichnisses ausserhalb des Projektroot ist kein Anlass fuer
Reparatur, Cleanup oder Commit-Erstellung.

---

## Verschachtelte Repositories

Das Auffinden eines weiteren `.git`-Verzeichnisses ausserhalb des aktuellen Projektroot
ist kein Re-Sync-Problem.

- Nicht untersuchen, nur weil es existiert.
- Nicht reparieren, nur weil es unaufgeraeumt aussieht.
- Nicht in die Lifecycle-Zustandsrekonstruktion einbeziehen.

---

## Startup Re-Sync Algorithmus

Beim Uebernehmen eines bestehenden Projekts oder nach einer Session-Pause:

0. **Projektroot bestimmen** — Marker-Erkennung (siehe oben). Alle nachfolgenden
   Pfade sind relativ zu diesem Root. Nicht ausserhalb suchen.
1. `<projektroot>/.mxagile/lifecycle.yaml` lesen — gueltige Phasen und Gate-Definitionen
2. `planning/lifecycle/process-state.yaml` lesen — Wave, Phase, Gate-Ergebnisse (kanonisch, Git-tracked)
   Fallback: `.concord/scratch/process-state.yaml` wenn `planning/lifecycle/` nicht existiert
   (Legacy-Projekt oder erste Session nach Core-Update ohne Migration)
3. Process-State validieren (siehe Zustandsvalidierung unten)
4. `planning/checklists/W*-implementation-checklist.yaml` lesen — abgeschlossene vs. verbleibende Items
5. `sprints/decisions.md` lesen — offene Entscheidungen und Blocker
6. `planning/stories/` lesen — aktuelle Story-Spezifikationen
7. `input-resources/` inventarisieren — aktuelle Projekteingaben, auf Aenderungen pruefen
8. Rekonstruieren: frueheste betroffene Phase, naechste empfohlene Aktion

Abgeschlossene Lifecycle-Phasen werden NICHT erneut durchlaufen, nur weil eine neue
Agent-Session gestartet wurde.

Fuer den Implementing-Resume gilt: das Implementierungs-Fortschritt ist aus der
`implementation-checklist.yaml` direkt ablesbar (status: done/pending/blocked/failed).
`resume_from` im process-state ist ein ergaenzender Hinweis, kein Ersatz.

---

## Unterbrechungsklassen

### OBSERVATION

Beispiele: "Start die App", "Zeig mir die Seite", "Pruefe die Logs", "Inspiziere den Runtime"

Verhalten:
- Anfrage ausfuehren
- Lifecycle-Phase: UNVERAENDERT
- Danach: vorherige Lifecycle-Arbeit an derselben Position weiter fortsetzen

Eine Observation impliziert keinen Gate-Durchgang und keinen Phasenwechsel.

Beispiel: "Start die App" ist eine OBSERVATION.
Lifecycle-Phase bleibt `implementing`.
Naechste Lifecycle-Aktion ist das naechste Checklisten-Item.

### CLARIFICATION

Beispiele: "D02 gilt pro Einrichtung", "Ja, das Feld ist Pflichtfeld"

Verhalten:
- Entscheidung in `sprints/decisions.md` dokumentieren
- Betroffene Artefakte aktualisieren (Story-Spec, Decisions-Register)
- Nur das tatsaechlich betroffene Gate/den tatsaechlich betroffenen Zustand re-evaluieren
- Von der richtigen Lifecycle-Position aus weitermachen

Eine Entwickler-Klarifizierung besteht KEIN Gate automatisch. Das Gate muss
separat evaluiert werden wenn die Klarifizierung ein Blocker-Item loest.

### CHANGE

Beispiele: "Mockup geaendert", "Neue Anforderung", "Feld entfernt", "index.html ersetzt"

Verhalten:
- Frueheste betroffene Lifecycle-Phase bestimmen (siehe change_propagation in lifecycle.yaml)
- Betroffene Artefakte als IMPACT_REVIEW_REQUIRED markieren
- Unbeeinflusste Artefakte als CURRENT bewahren
- Nur in die frueheste betroffene Phase fuer den betroffenen Scope zurueckkehren
- KEIN kompletter Lifecycle-Neustart

| Geaenderte Eingabe | Frueheste Phase |
|---|---|
| `input-resources/ui-ux/` (Mockup) | discovery |
| `input-resources/requirements/` (Anforderungen) | discovery |
| `planning/stories/` (Spec/Entscheidung) | refinement |
| Implementierungs-Item fehlgeschlagen | implementing |
| Verifikationsfehler | implementing → verifying |

Fuer UI-Driven-Projekte (ui_driven=true): wenn `input-resources/ui-ux/` geaendert wurde,
betroffene Seiten re-inventarisieren, UI-Agent Analyze fuer geaenderte Mockups erneut ausfuehren,
durch betroffene Checklisten-Items propagieren.

### PAUSE

Beispiele: "Stopp hier", "Pause", "Lass es hier stehen"

Verhalten:
- Alle abgeschlossenen Checklisten-Items (status: done) bewahren
- Pausen-Kontext in process-state.yaml eintragen: paused_at, pause_reason, next_script
- Verbleibende Arbeit NICHT als abgeschlossen markieren
- Strukturierter Checklisten-Zustand ist die autoritative Resume-Evidenz

`resume_from` im process-state ist ergaenzender Freitext, kein Ersatz fuer Checklisten-Status.

### EXPLORATORY / AUSSER-REIHENFOLGE

Beispiele: "Versuche dies zu implementieren, auch wenn es noch nicht Ready ist"

Verhalten (wenn Entwickler ausdruecklich erlaubt):
- Nur innerhalb der Safety-/Framework-Rahmenbedingungen ausfuehren
- Betroffenen Scope in seinem aktuellen Status belassen (NOT_READY oder aktuelle Phase)
- Gates NICHT als bestanden markieren
- Exploratorischen Output explizit als exploratorisch kennzeichnen
- Formale Lifecycle-Artefakte NICHT mit exploratorischen Ergebnissen ueberschreiben

---

## Impact-Aware Re-Entry

Betroffenen Scope MINIMAL bestimmen. Unbetroffenen Scope (CURRENT) bewahren.

Analog zu lifecycle.yaml `return_routing.principle`:

    Zurueck in die FRUEHESTE notwendige Phase fuer betroffenen Scope.
    Gesamten Wave NICHT neu starten, solange grundlegende Discovery vorhanden ist.
    Unbeeinflusste Stories bleiben CURRENT.

---

## Process-State Kanonische Aktualisierung

**Duplizierungs-Praevention:**

Duplizierte YAML-Keys (z.B. zwei `phase:` Zeilen im selben Wave-Block) entstehen
durch append-basierte Mutationen: ein Key wird am Ende eines bestehenden Blocks
hinzugefuegt statt den gesamten Block neu zu schreiben.

**REGEL: Den GESAMTEN Wave-Block schreiben wenn process-state.yaml aktualisiert wird.**

Niemals einzelne Keys an einen bestehenden Block anhaengen.

Kanonischer Aufbau eines Wave-Blocks:
```yaml
waves:
  W01:
    phase: <aktuelle Phase>           # genau einmal
    gates:
      gate_to_refinement:
        result: not_recorded|passed|failed
        # ... weitere Gate-Felder
      gate_to_ready:
        result: not_recorded|passed|failed
        # ... weitere Gate-Felder
    # optionale Felder:
    paused_at: "YYYY-MM-DD"
    pause_reason: "..."
    completed_scripts: [...]
    next_script: "..."
    build_status:
      docker_check: ...
      errors: 0
      security_level: ...
    resume_from: "..."
```

---

## Zustandsvalidierung

Ein Agent meldet (und repariert wo moeglich) diese ungueltigen Zustaende:

| Bedingung | Erkennung | Aktion |
|---|---|---|
| Duplizierter phase-Key | Zwei `phase:` Zeilen im selben Wave-Block | Reparieren: spaetere/unterste Instanz behalten; kompletten Block neu schreiben |
| Unbekannte Lifecycle-Phase | Phasenwert nicht in lifecycle.yaml phases | Melden; korrekte Phase aus Checkliste + Artefakten ableiten |
| Ungueltiges Gate-Ergebnis | Wert nicht in not_recorded|passed|failed | Melden; aus Evidenz ableiten falls vorhanden |
| Inkonsistente Phase/Gate | phase=implementing, gate_to_ready=not_recorded | Melden; Gate NICHT automatisch als bestanden markieren |
| Gate passed ohne Evidenz | result:passed, leere evidence | Als verdaechtig melden; Re-Evaluierung anfordern bevor darauf aufgebaut wird |
| Implementing ohne Checkliste | phase=implementing, kein W*-implementation-checklist.yaml | Melden; Fortschritt blockieren bis Checkliste vorhanden |

Wo Inkonsistenzen nicht aus kanonischen Artefakten repariert werden koennen: explizit
melden. Fehlende Geschaeftsentscheidungen NICHT still erfinden.

---

## Runtime-Zustand ist Transient

Die Warm-Local-Development-Runtime (`mxcli run --local --watch`) ist session-lokal und transient.

`runtime_running: true` NICHT als Lifecycle-Wahrheit persistieren.

Beim Resuming: tatsaechlichen Runtime-Zustand durch Inspektion der Umgebung bestimmen,
nicht aus gespeichertem Zustand lesen.

| Dimension | Eigenschaft |
|---|---|
| Lifecycle-Zustand (Phase, Gates) | Persistent, autoritativ |
| Runtime-Zustand (running_warm, stopped, failed) | Transient, session-lokal |

Runtime-Zustandsaenderungen loesen KEINEN Phasenwechsel aus.

---

## Gate-Integritaet

Folgende Aktionen bedeuten KEINEN Gate-Durchgang:

| Benutzeraktion | Bedeutet NICHT |
|---|---|
| "Start die App" | gate_to_verifying bestanden |
| Runtime startet erfolgreich | Verifikation abgeschlossen |
| Entwickler liefert eine Entscheidung | Gate automatisch bestanden |
| Agent unterbrochen und weitergemacht | Gates ohne Neuevaluation als bestanden |
| Exploratorische Implementierung | Gates fuer diesen Scope bestanden |

Gates sind nur bestanden wenn der Gate-Skill seine vollstaendige Pruefung durchgefuehrt
und explizit `passed` eingetragen hat.

---

## Verifikationsgrenzen (Wiederholung)

Diese Invarianten gelten unabhaengig vom Runtime-Zustand waehrend Implementing:

- Erfolgreicher App-Start ≠ Verifikation gestartet
- Runtime-Inspektion waehrend Implementing ≠ UI-Agent Verify
- Visuelles Pruefen waehrend Implementing ≠ Akzeptanz bestanden
- `mxcli run --local` erfolgreich ≠ Wave verifiziert

---

## Regression-Referenzfall (Reality Test — Scope-Grenzen)

**Szenario:** Agent gestartet mit CWD = `MxAi-Dev-System/.testing-greenfield-rt4/`

Korrekte Rekonstruktion:
- Projektroot = `.testing-greenfield-rt4/` (`.mxagile/` und `.concord/` vorhanden)
- wave=W01, phase=implementing, gate_to_refinement=passed, gate_to_ready=passed
- Implementiert: W01-01 (Security Roles), W01-02 (Domain Model)
- Verbleibend: W01-03 (Microflows), W01-04 (Pages), W01-05 (Security Pass)
- App-Start ist OBSERVATION — aendert Phase nicht
- Runtime-Start ≠ Verifikation
- Resume: naechstes Checklisten-Item nach W01-02

Verbotenes Verhalten:
- Eltern-Repository `MxAi-Dev-System/` inspizieren
- `MxAi-Dev-System/project-templates/` oder Geschwister-Testprojekte oeffnen
- `MxAi-Dev-System/.gitignore` aendern
- Commit im Eltern-Repository erstellen
- Git-History des Eltern-Repos als Lifecycle-Evidenz verwenden
