# Policy: MxAgile Context Lifecycle

Definiert Kontext-Epochen, Checkpoint/Resume, Kontext-Druck-Modell und Rollover-Semantik
für MxAgile-Missionen über mehrere Agent-Sessions hinweg.

Schema: `.mxagile/schemas/context-epoch.schema.json`
Konfiguration: `.mxagile/config.yaml` → `context_lifecycle:`
Dokumentation: `docs/context-lifecycle.md`

---

## Grundprinzip

Eine Mission ist nicht dasselbe wie eine Agent-Session.

```
MISSION
  ├── Context Epoch 1: Discovery und Analyse
  ├── durables Checkpoint
  ├── Context Epoch 2: Implementierung
  ├── durables Checkpoint
  └── Context Epoch 3: Verifikation und Abnahme
```

Der Übergang zwischen Epochen bewahrt den dauerhaften Missionszustand,
trägt aber NICHT die vollständige Konversationshistorie in jeden neuen Kontext.

MxAgile bleibt die alleinige Autorität für:
- Mission-Lifecycle und Phasenzustand
- Scope- und Eigentümerschaft
- Gate-Evaluierung und Akzeptanz
- Evidenzzustand
- Checkpoint-Erstellung
- Resume und Re-Synchronisierung
- Kontext-Druck-Politik
- Abschlussentscheidungen

Externe Skills (Ponytail, Superpowers-abgeleitete) verbessern Implementierungsverhalten.
Sie ersetzen die MxAgile Mission-State-Autorität nicht.

---

## Feature Controls

Context Lifecycle ist standardmäßig **deaktiviert**, um Rückwärtskompatibilität zu
gewährleisten. Aktivierung erfolgt schrittweise:

| Feature | Config-Key | Standard |
|---------|-----------|---------|
| Context Lifecycle gesamt | `context_lifecycle.enabled` | `false` |
| Checkpoint/Resume | `context_lifecycle.checkpoint_resume` | `false` |
| Manueller Rollover | `context_lifecycle.manual_rollover` | `false` |
| Druck-Empfehlungen | `context_lifecycle.pressure_recommendations` | `false` |
| Automatischer Rollover | `context_lifecycle.auto_rollover` | `false` |

`auto_rollover: true` darf nur aktiviert werden wenn `checkpoint_resume: true` und
`manual_rollover: true` bereits aktiviert und in der Praxis erprobt sind.

Wenn `enabled: false`:
- Kein Checkpoint wird erstellt
- Kein Resume-Kontrakt wird gelesen oder geschrieben
- Kein Kontext-Druck wird berechnet
- Alle bestehenden MxAgile-Abläufe arbeiten unverändert
- Vorhandene `planning/lifecycle/context-epoch.yaml` Dateien werden ignoriert

---

## Kontext-Klassen

### HOT CONTEXT

Kleine, stets benötigte Information — muss in jeder Epoche vorhanden sein:

- Aktuelles Nutzerziel und Missions-ID
- Aktive Lifecycle-Phase und aktive Context Epoch
- Framework/Company-Layer/Projekt-Scope
- Aktueller Task und offene Gates
- Aktuelle Blocker
- Kurze Repository-Zustandszusammenfassung
- Nächste geplante Aktion
- Geltende Nutzer-Overrides

**HOT Context darf keine vollständige COLD-Evidenz enthalten.**
HOT Context darf Referenzen auf COLD-Evidenz enthalten.

### WARM CONTEXT

Dauerhaft verfügbare, abrufbare Information — nicht immer eingefügt:

- Frühere Entscheidungen und Rationale
- Architektur-Findings
- Zusammenfassungen früherer Checkpoints
- Modulanalysen
- Bekannte offene Probleme
- Graphify-Findings (wenn verfügbar)
- Historischer, noch relevanter Task-Zustand
- Referenzen auf frühere Implementierungsberichte

### COLD EVIDENCE

Kanonische Evidenz — wird NIE durch eine Zusammenfassung ersetzt:

- Rohe Befehlsausgaben
- Vollständige Logs
- Vollständige Diffs (wo erforderlich)
- Screenshots
- Testergebnis-Dateien
- Laufzeit-Traces
- mxcli-Dumps
- Strukturierte Prüfausgaben
- Große JSON-Fixtures
- Abnahmeberichte
- Generierte Diagnose-Artefakte

COLD Evidence wird durch Referenzen im Context Epoch Kontrakt angesprochen,
nicht direkt in den aktiven Kontext geladen.

---

## Kontext-Druck-Modell

### Druckstufen

| Stufe | Bedeutung |
|-------|-----------|
| `UNKNOWN` | Keine zuverlässige Tokenmessung verfügbar. Darf keine Rollover-Entscheidungen autorisieren oder unterdrücken. Standardzustand wenn keine Harness-/Gateway-Messung vorliegt. |
| `NORMAL` | Zuverlässige Messung vorhanden und unterhalb des konfigurierten Schwellenwerts |
| `PRESSURE` | Nähert sich dem Schwellenwert; Checkpoint empfehlenswert |
| `ROLLOVER_RECOMMENDED` | Checkpoint verfügbar; Rollover ratsam bei nächster sicherer Grenze |
| `ROLLOVER_REQUIRED` | Muss bei nächster sicherer Grenze überlaufen |

**UNKNOWN ist nicht NORMAL.**
NORMAL setzt eine zuverlässige Messung voraus, die unterhalb des Schwellenwerts liegt.
UNKNOWN bedeutet: kein Messwert verfügbar — der Agent darf weder Rollover anfordern noch unterdrücken.

### Druckstufen-Eingaben

Die Druckstufe kann durch folgende Faktoren beeinflusst werden:
- Extern gemessene oder gemeldete Kontextgröße (Token-Zählung vom Harness oder Gateway)
- Lifecycle-Grenzenverfügbarkeit
- Verfügbarkeit eines gültigen Checkpoints
- Laufender Tool-Aufruf oder Dateiwrite
- Persistenzzustand der Evidenz
- Ungelöster kritischer Reasoning-Zustand
- Nutzerpräferenz
- Harness-Fähigkeiten

**Keine Tokenanzahl lokal erfinden.** Wenn keine externe Messung verfügbar:
- Extern gelieferte Messungen unterstützen
- Klar beschriftete Proxies (z. B. Anzahl geladener Dateien) nur als Hinweise verwenden
- Nie behaupten, einen genauen Token-Schwellenwert durchgesetzt zu haben

Schwellenwerte sind **Konfiguration**, nicht hartcodierte Lifecycle-Wahrheit.
Der 150k-Beobachtungswert aus Gateway-Telemetrie ist ein Evaluierungsparameter,
kein Produktionsschwellenwert.

### Schwellenwert-Konfiguration

```yaml
context_lifecycle:
  pressure_thresholds:
    pressure_tokens: null          # null = nicht lokal gemessen
    rollover_recommended_tokens: null
    rollover_required_tokens: null
```

`null` bedeutet: Schwellenwert unbekannt — Druckstufe kann nicht automatisch berechnet werden.
Agent meldet `NORMAL` wenn keine Messung verfügbar ist.

---

## Resume Mission Priority (RF-001)

### Zustandsdimensionen beim Resume

Beim Resume müssen vier Zustandsdimensionen klar unterschieden werden:

| Dimension | Beschreibung | Quelle |
|-----------|-------------|--------|
| **Allgemeiner Produkt-Lifecycle** | FEATURE_SCOPE_COMPLETE, offene Waves usw. | `planning/lifecycle/process-state.yaml` |
| **Aktive MxAgile-Mission** | Laufende, nicht abgeschlossene Mission mit aktiver Checkpoint | `context-epoch.yaml` (mission_scope + checkpoint) |
| **Akzeptanz-/Overlay-Kampagne** | Laufende A/B/C/D-Kampagne oder ähnliche | `context-epoch.yaml` → `mission_scope.campaign` |
| **Operationelle Context Epoch** | Laufende Epoch mit Druck-Zustand und HOT-Kontext | `context-epoch.yaml` → `epoch_id` |

### Aktive Mission gewinnt bei Resume

Wenn ein gültiger aktiver Missions-Checkpoint existiert, **muss** der Agent diese
Mission priorisieren — NICHT auf den allgemeinen Produkt-Lifecycle-Zustand zurückfallen.

**Verboten:**
Ein Agent darf NICHT `FEATURE_SCOPE_COMPLETE` oder einen anderen allgemeinen
Produkt-Lifecycle-Zustand aus `process-state.yaml` als Begründung verwenden,
eine laufende Mission (aktiver Checkpoint) zu ignorieren oder zu überschreiben.

**Korrekte Resume-Logik:**

```
1. Checkpoint lesen (operationeller Store → Handoff-Store → kein Checkpoint)
2. Checkpoint vorhanden?
   NEIN → normaler Startup Re-Sync ohne Mission-Priority
   JA →
     mission_scope.status = "active" UND checkpoint.is_valid = true?
     JA → Aktive Mission priorisieren; allgemeinen Lifecycle nur als Kontext verwenden
     NEIN (status = "completed" oder is_valid = false) →
       normaler Startup Re-Sync; Checkpoint für Audit aufbewahren
3. Ambiguität (fehlende Diskriminatoren, fehlende mission_scope.status)?
   → Ambiguität berichten; Nutzer NICHT auffordern, die Mission selbst zu rekonstruieren
```

### mission_scope Diskriminator im Checkpoint

Das `context-epoch.yaml`-Schema muss folgende Felder unterstützen:

```yaml
mission_scope:
  status: active | completed | suspended
  description: "<kurze Missionsbezeichnung>"
  campaign: "<Kampagnenname wenn applicable, sonst null>"
  mission_id: "<stabile ID, z.B. Ticket-Nummer oder UUID>"
```

**Rückwärtskompatibilität:**

- Checkpoints OHNE `mission_scope` → verhalten sich wie bisher (kein aktiver
  Missions-Checkpoint; normaler Startup Re-Sync).
- Checkpoints MIT `mission_scope.status: active` → Mission-Priority-Regel greift.
- Checkpoints MIT `mission_scope.status: completed` → kein Mission-Priority; normaler
  Startup Re-Sync.
- `mission_scope.status` fehlt aber Checkpoint existiert → behandle als kein aktiver
  Missions-Checkpoint; berichte Ambiguität wenn Kontext darauf hindeutet.

### Akzeptanz-/Overlay-Kampagne

Laufende Akzeptanz-Kampagnen (wie CapTrack A/B/C/D) nutzen `mission_scope.campaign`
als Scoping-Diskriminator.

Ein Checkpoint einer laufenden Kampagne hat VORRANG vor `process-state.yaml`
bezüglich der aktuellen aktiven Arbeit — NICHT bezüglich des Produkt-Lifecycle-Status
von bereits abgeschlossenen Waves.

### Checkpoint-Durability (Abschnitt 12 Kontrakt)

Ein Checkpoint ist nur gültig, wenn er dauerhaft und innerhalb des beabsichtigten
Resume-Scopes erreichbar ist:

| Resume-Scope | Gültige Checkpoint-Quelle |
|-------------|--------------------------|
| Gleiche Maschine, gleiche Working Copy | Operationeller Store (`.concord/`) ausreichend |
| Fresh Clone / andere Maschine / expliziter Handoff | Operationeller Store NICHT ausreichend; Handoff-Store (`planning/lifecycle/`) mit committed `context-epoch.yaml` erforderlich |

**Konsequenz:**
- Lokaler gitignorierter Checkpoint ist KEIN Nachweis für maschinen-übergreifende
  Missions-Fortsetzbarkeit.
- Der Agent muss den beabsichtigten Resume-Scope beim Erstellen eines Checkpoints
  explizit berücksichtigen.
- Bei explizitem Handoff-Bedarf: `-WriteHandoffCopy` verwenden und den
  Handoff-Store committen.

---

## Durable Resume Contract

### Speicherorte

```
.concord/context-epoch.yaml           ← Primär operationell, gitignored
planning/lifecycle/context-epoch.yaml ← Expliziter Handoff/Audit-Store, Git-tracked
```

**Zwei-Stufen-Modell** (Rationale: Risikovermeidung):

1. **Operationeller Store** (`.concord/context-epoch.yaml`, gitignored)
   - Geschrieben bei jedem Checkpoint
   - Kein Git-Lärm im Working Tree
   - Löst Self-Interference: git-status-Prüfung wird nicht durch den eigenen
     Checkpoint-Write verfälscht
   - Verhindert Merge-Konflikte bei paralleler Entwicklung
   - Verloren bei Fresh Clone — korrekt: Session-State reist nicht via Git

2. **Handoff-Store** (`planning/lifecycle/context-epoch.yaml`, Git-tracked)
   - Nur bei explizitem Request geschrieben (manueller Rollover, `-WriteHandoffCopy`)
   - Überlebt Fresh Clone — für echten Missions-Handoff gedacht
   - Erstellt Git-Change nur wenn bewusst committed

**Priorität beim Lesen:** Operationeller Store (`.concord/`) hat Vorrang.
Fallback: Handoff-Store (`planning/lifecycle/`).
Fehlen beider Pfade: kein Checkpoint vorhanden — kein State erfinden.

Das Fehlen des operationellen Stores darf keine kanonische Mission-Information
zerstören, solange der Handoff-Store existiert.

### Schema-Version

`schema_version: "1.0"` ist Pflichtfeld.

Bei unbekannter Schema-Version:
- Checkpoint nicht blind lesen
- Klaren Conflict-Zustand erzeugen
- Nutzer über Inkompatibilität informieren
- Beschreiben, was für eine manuelle Migration erforderlich ist

### Keine Secrets

Das Context Epoch Dokument darf NIEMALS enthalten:
- Passwörter, Tokens, API-Keys
- Anmeldedaten oder Zugriffsdaten
- Persönliche Identifikationsdaten
- Sensitive Umgebungswerte

Verwende `process-state.yaml → prerequisite_state` für nicht-sensitive Bereitschaftsstatus.

---

## Re-Synchronisierungs-Protokoll

Bei Resume nach Unterbrechung oder Context Epoch Rollover:

1. **Durable Resume Contract laden** — `planning/lifecycle/context-epoch.yaml` lesen
2. **Schema und Version validieren** — bei unbekannter Version: Conflict-Zustand erzeugen
3. **Repository-Identität prüfen** (`repository_identity`) — Remote-Origin oder Projektroot-Marker
4. **Branch, Commit und Working-Tree** inspizieren (tatsächlicher Zustand, nicht aus Checkpoint)
5. **Aktuellen Zustand mit Checkpoint vergleichen** — Commits und Working-Tree seit Checkpoint
6. **Referenzierte Artefakte prüfen** — existieren lokal angegebene Pfade noch?
7. **Änderungen seit Checkpoint identifizieren** — welche Dateien wurden geändert?
8. **Betroffene Claims als STALE markieren** — wenn `stale_if_commit_changes: true`
9. **FAILED und UNVERIFIED-Zustände bewahren** — diese werden nie "aufgewertet"
10. **Nur benötigten HOT Context rekonstruieren** — kein komplettes Replay der Konversation
11. **WARM/COLD Material nur bei Bedarf abrufen** — keine vollständige Vorab-Ladung
12. **Sichere nächste Aktion bestimmen** — aus `next_action` plus aktueller Repository-Realität
13. **Bereits verifizierten Work nicht unnötig wiederholen**
14. **Re-Synchronisierungs-Ergebnis aufzeichnen** — in `context-epoch.yaml` aktualisieren

### Repository-Inkompatibilität

Wenn der Repository-Zustand inkompatibel mit dem Checkpoint ist:

- **Nicht blind fortfahren**
- **Checkpoint nicht verwerfen**
- **Klaren Conflict-Zustand erzeugen** mit Beschreibung der Unstimmigkeit
- **Nutzerarbeit bewahren**
- **Kleinste sichere Recovery-Aktion identifizieren**

Conflict-Typen:

| Conflict | Erkennung | Recovery |
|---------|-----------|---------|
| Branch gewechselt | `repository.branch` ≠ aktueller Branch | Nutzer informieren; Checkpoint für alten Branch aufbewahren |
| Commit divergiert | `repository.commit` nicht in aktueller History | Nutzer informieren; betroffene VERIFIED Claims → STALE |
| Artefakt verschwunden | Referenzierter Pfad existiert nicht mehr | Unverified-Eintrag für betroffene Claims erzeugen |
| Schema inkompatibel | `schema_version` unbekannt | Manuell migrieren, Checkpoint nicht lesen |

**Staleness-Trigger** (welche Repository-Änderungen lösen STALE aus):

- Commit-Hash geändert → Claims mit `stale_if_commit_changes: true` werden STALE
- Checklist-Datei modifiziert → betroffene Checklist-basierte Claims werden STALE
- Story-Spec geändert → Verifikationsansprüche für betroffene Stories werden STALE
- Input-Resource geändert → Discovery-Befunde für betroffenen Scope werden STALE

---

## Rollover-Sicherheitsbedingungen

Ein automatischer Context Epoch Rollover darf NUR stattfinden wenn:

1. Ein gültiger, schema-validierter Checkpoint wurde erfolgreich geschrieben
2. Erforderliche Evidenz ist persistiert
3. Kein kritischer Tool-Aufruf, File-Write, Migration, Commit oder Laufzeit-Übergang
   ist aktiv
4. Der aktuelle Repository-Zustand ist im Checkpoint festgehalten
5. Die nächste Aktion kann im Checkpoint repräsentiert werden
6. Rollback/Resume ist verfügbar
7. Das aktive Harness kann sicher einen frischen Kontext starten oder anfordern

**Wenn diese Bedingungen nicht erfüllt sind:**
Rollover-Empfehlung ausgeben oder auf die nächste sichere Grenze verschieben.

### Sichere Grenzen für Rollover

Bevorzugte Rollover-Punkte (in absteigender Sicherheit):

1. Nach Abschluss einer vollständigen Lifecycle-Phase
2. Nach Erreichung eines Gate-Ergebnisses
3. Nach Abschluss eines Checklist-Items
4. Nach einem expliziten Nutzer-Pause-Befehl
5. Zwischen unabhängigen Analyse-Tasks

**Unsichere Rollover-Punkte (verboten):**
- Mitten in einem laufenden Tool-Aufruf
- Während eines aktiven File-Writes
- Zwischen dem Starten und Bestätigen einer Datenbankoperation
- Während eines Verifikations-Campaigns (nach dem ersten bewiesenen Proof Point)

---

## Unterbrechungs-Semantik

Unterbrechungsklassen (siehe auch `lifecycle-resync.md`):

### A: Informationelle Unterbrechung (OBSERVATION)
Nutzer stellt Frage während Arbeit läuft.
→ Antworten; Lifecycle-Phase unverändert (UNVERAENDERT); Danach fortsetzen

### B: Zwischenzeitliche Arbeitsanforderung (CLARIFICATION / intermediate task)
Nutzer bittet um begrenzte Nebenaufgabe.
→ Ausführen; Lifecycle-Wahrheit bewahren; Re-Sync vor Fortfahren

### C: Scope-ändernde Anweisung (CHANGE)
Nutzer ändert Mission oder schließt Arbeit ein/aus.
→ Als expliziten `user_override` im Checkpoint aufzeichnen; Früheststes betroffenes
  Lifecycle-Element re-evaluieren; Unbetroffenen Scope bewahren

### D: Stop/Pause-Anweisung (PAUSE)
Aktuelle Aktivität muss an sicherer Grenze stoppen.
→ Abgeschlossene Checklist-Items bewahren; Checkpoint schreiben; `interrupted: true` setzen

**In allen Fällen gilt:**
- Unterbrochener Missionszustand wird bewahrt
- Aktive Gates werden nicht als abgeschlossen markiert nur weil der Fokus wechselte
- Re-Sync vor dem Fortfahren mit der Haupt-Mission
- Scope-ändernde Anweisungen als explizite Overrides aufzeichnen
- Konversationsabweichung wird nicht als Missions-Aufgabe behandelt

---

## Rollback

Wenn Context Lifecycle deaktiviert werden muss:

1. `context_lifecycle.enabled: false` in `.mxagile/config.yaml` setzen
2. `planning/lifecycle/context-epoch.yaml` nicht löschen (für Audit-Zwecke aufbewahren)
3. `.concord/context-epoch.yaml` kann gelöscht werden (operationeller Session-Store, gitignored)
4. Bestehende MxAgile-Prozesse arbeiten unverändert mit `process-state.yaml`
5. Keine Migration bestehender Projekte erforderlich

**Welche Änderungen sind rein additiv:**
- `context-epoch.schema.json` (neues Schema, ignoriert wenn nicht aktiviert)
- `context-lifecycle.md` (neue Policy, Rückwärtskompatibel)
- `context_lifecycle:` Sektion in `config.yaml` (ignoriert wenn `enabled: false`)
- `planning/lifecycle/context-epoch.yaml` (nur gelesen/geschrieben wenn aktiviert)

**Welche Änderungen ändern Verhalten:**
- Nur wenn `context_lifecycle.enabled: true` gesetzt ist

---

## Harness-Adapter-Verantwortlichkeiten

Das Harness (Claude Code, Copilot, Codex, etc.) ist verantwortlich für:

1. Tatsächliche Kontextgröße messen oder melden (Token-Zählung)
2. Den `estimated_context_tokens` Wert im Checkpoint bereitstellen, wenn verfügbar
3. Einen frischen Kontext starten wenn Rollover angefordert wurde
4. Den Resume-Kontrakt-Pfad beim Start einer neuen Session übergeben

Das Harness entscheidet NICHT über:
- MxAgile-Lifecycle-Zustand
- Gate-Evaluierungen
- Evidenz-Gültigkeit
- Checkpoint-Inhalt

Wenn Harness-Fähigkeiten nicht verfügbar sind:
- Druck-Empfehlungen können nicht auf Token-Zählung basieren
- `ROLLOVER_REQUIRED` kann nur manuell gesetzt werden
- `auto_rollover` muss auf `false` bleiben bis Harness-Integration verfügbar ist

---

## Graphify-Hinweis

Graphify ist ein optionales Orientierungsmittel. Es wird in dieser Architektur-Änderung
**nicht** erweitert oder neu gestaltet, weil:

1. Der beobachtete Nutzen wurde als mittel eingestuft
2. Graphify löst nicht das Kernproblem der Token-Akkumulation über Sessions
3. Keine direkte Messlücke erfordert eine Änderung

Graphify-Findings können als WARM Context referenziert werden.
Sie sind KEIN Ersatz für kanonische Lifecycle-Artefakte.

---

## Erweiterungspunkte

Zukünftige optionale Erweiterungen (nicht Teil dieser Implementierung):

- **RTK (Retrieval Tool Kit)**: Könnte als WARM-Context-Abruf-Mechanismus fungieren.
  Erweiterungspunkt: `context_lifecycle.warm_retrieval_provider: rtk`
- **Context Mode**: Harness-native Kontext-Kompressions-Funktion.
  Erweiterungspunkt: `context_lifecycle.compression_provider: context_mode`
- **Token-Messung**: Direktes API-basiertes Token-Counting.
  Erweiterungspunkt: `context_lifecycle.token_counter: api`

Diese Erweiterungspunkte existieren als Platzhalter in der Konfiguration,
aber keine Implementierung davon ist Teil dieser Mission.
