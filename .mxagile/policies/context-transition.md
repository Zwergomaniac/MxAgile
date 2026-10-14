# Policy: MxAgile Context Transition

Definiert autonome Kontext-Komprimierung, Epochen-Übergänge und Harness-Adapter-Semantik
für MxAgile-Missionen.

Schema: `.mxagile/schemas/harness-adapter.schema.json`
Konfiguration: `.mxagile/config.yaml` → `context_lifecycle.transition:`
Dokumentation: `docs/context-transition.md`
Basiert auf: `.mxagile/policies/context-lifecycle.md`

---

## Primäres Invariant

**MxAgile Mission Truth überlebt Kontext-Komprimierung unabhängig von der
harness-generierten Komprimierungszusammenfassung.**

Eine Komprimierungszusammenfassung ist verlustbehafteter Kontext-Input.
Sie ist KEINE autoritative MxAgile-State-Quelle.

Komprimierung darf NIEMALS direkt:
- Evidenz befördern (UNVERIFIED → VERIFIED)
- Ein Gate erfüllen
- Eine Mission abschließen
- Scope verändern
- Einen Blocker löschen
- Einen Checkpoint validieren
- Re-Sync unterdrücken
- STALE zu VERIFIED konvertieren

Autoritative Zustandsquellen bleiben:
- MxAgile Resume Contract (`.concord/context-epoch.yaml`)
- Kanonische Repository/Evidenz-Artefakte

---

## Transition-Strategien

### COMPACT_CURRENT_SESSION

Harness-native Komprimierung in der gleichen dauerhaften Session.

Voraussetzungen:
- Harness unterstützt Komprimierung (automatisch oder programmatisch)
- Gültiger Checkpoint existiert und wurde validiert
- Sichere Grenze ist erreicht
- Keine unsichere Operation läuft

Verhalten:
- Pre-Compaction-Checkpoint-Protokoll ausführen (17 Schritte)
- Komprimierung beantragen/beobachten
- Post-Compaction-Re-Sync anfordern
- Mission autonom fortsetzen

### FRESH_CONTEXT_EPOCH

Neuen Kontext/neue Session bei erhaltener MxAgile-Mission erstellen.

Voraussetzungen:
- Harness kann neue Session/frischen Kontext starten
- Gültiger Checkpoint persistiert
- Resume-Contract erreichbar in der neuen Session

Verhalten:
- Vollständigen Checkpoint schreiben
- `-WriteHandoffCopy` für neue Session sicherstellen
- Neue Session/Epoch starten
- Re-Sync in der neuen Epoche ausführen
- Mission fortsetzen

### EXTERNAL_ACTION_REQUIRED

Nur wenn kein unterstützter autonomer Übergang verfügbar ist.

Verhalten:
- Klare Anweisung an Nutzer/Betreiber ausgeben
- Checkpoint-Pfad und Resume-Anweisung bereitstellen
- Keine falschen TRANSITION_COMPLETED-Claims

---

## Präferenzreihenfolge

Standard (konfigurierbar):
1. COMPACT_CURRENT_SESSION
2. FRESH_CONTEXT_EPOCH
3. EXTERNAL_ACTION_REQUIRED

An sauberen Missions-Hauptgrenzen kann FRESH_CONTEXT_EPOCH bevorzugt sein.

---

## Transition-Zustandsmaschine

```
IDLE
  │ (Druck ROLLOVER_RECOMMENDED/REQUIRED)
  ▼
PRESSURE_OBSERVED
  │ (sichere Grenze + Strategie ausgewählt)
  ▼
TRANSITION_REQUESTED
  │ (unsichere Grenze)
  ├─► PENDING_SAFE_BOUNDARY → TRANSITION_REQUESTED
  │
  │ (sichere Grenze)
  ▼
CHECKPOINT_PREPARING
  │ (Validation fehlgeschlagen)
  ├─► TRANSITION_BLOCKED
  │
  │ (Checkpoint validiert)
  ▼
CHECKPOINT_VALIDATED
  │ (COMPACT_CURRENT_SESSION)
  ├─► COMPACTION_ADMITTED
  │     │ (Harness bestätigt Eingang)
  │     ▼
  │   COMPACTION_RUNNING
  │     │ (abgeschlossen)
  │     ├─► COMPACTION_COMPLETED
  │     │     ▼
  │     │   POST_COMPACT_RESYNC_REQUIRED
  │     │     │ (Re-Sync abgeschlossen)
  │     │     ▼
  │     │   TRANSITION_COMPLETED
  │     │
  │     └─► TRANSITION_FAILED
  │
  │ (FRESH_CONTEXT_EPOCH)
  ├─► FRESH_CONTEXT_READY
  │     │ (neue Session/Epoch gestartet)
  │     ▼
  │   FRESH_CONTEXT_REQUESTED
  │     │ (Re-Sync abgeschlossen)
  │     ▼
  │   TRANSITION_COMPLETED
  │
  │ (EXTERNAL_ACTION_REQUIRED)
  └─► TRANSITION_BLOCKED (externe Aktion erforderlich)

UNSUPPORTED: Kein unterstützter autonomer Übergang verfügbar
```

Bestehende Rollover-Zustände werden wiederverwendet:
- `rollover_recommended` → ROLLOVER_RECOMMENDED-Druck
- `rollover_pending_safe_boundary` → PENDING_SAFE_BOUNDARY
- `rollover_ready` → CHECKPOINT_VALIDATED
- `rollover_performed` → TRANSITION_COMPLETED
- `rollover_blocked` → TRANSITION_BLOCKED
- `rollover_unsupported_by_harness` → UNSUPPORTED

---

## Pre-Compaction-Protokoll (17 Schritte)

Vor jeder MxAgile-initiierten oder Harness-beobachteten Komprimierung:

1. Aktive Mission identifizieren
2. Aktuelle Context Epoch identifizieren
3. Repository-Realität inspizieren
4. Missions-Ziel persistieren
5. Scope persistieren
6. Lifecycle-Phase persistieren
7. Offene Gates persistieren
8. Blocker persistieren
9. Nutzer-Overrides persistieren
10. Evidenz-Zustände persistieren
11. Repository-Identität persistieren
12. Aktuellen Operations-Zustand persistieren
13. Nächste Aktion persistieren
14. Erforderliche kanonische Evidenz sichern (Referenzen)
15. Optional: WARM-Context via Context Mode externalisieren
16. Checkpoint validieren
17. Transition-Request/Idempotenz-Identität aufzeichnen

Bei Validation-Fehler:
- NICHT TRANSITION_COMPLETED melden
- Transition-Zustand NICHT vorwärts setzen
- Vorherigen gültigen Checkpoint bewahren
- Sicher blockieren und berichten

---

## Post-Compaction-Protokoll

Nach Komprimierung (COMPACTION_COMPLETED):

1. MxAgile Re-Sync anfordern (POST_COMPACT_RESYNC_REQUIRED setzen)
2. Aktiven Missions-Checkpoint neu laden/validieren
3. Repository-Identität und Working-Tree-Zustand prüfen
4. FAILED und UNVERIFIED bewahren
5. STALE-Regeln anwenden
6. Minimalen HOT-Kontext rekonstruieren
7. Nicht vollständige WARM-History neu laden
8. WARM-Kontext nur bei Bedarf abrufen
9. COLD-Evidenz-Referenzen erhalten
10. Nächste Aktion verifizieren
11. Mission autonom fortsetzen

**Checkpoint/Zusammenfassung-Konflikt:**
MxAgile Checkpoint und Repository-Evidenz gewinnen.
Abweichungen diagnostisch aufzeichnen.

Der Agent darf die Mission NICHT nach eigenem Ermessen beenden oder neu starten.

---

## Sicheres-Grenze-Integration

Wiederverwendung der bestehenden Rollover-Sicherheitsbedingungen.

Kein Übergang während:
- Unbekannem Mutations-Ergebnis
- Laufendem Tool-Aufruf
- Partiellem File/Model-Write
- Unbekanntem Commit-Ergebnis
- Ambigem Laufzeit-Übergang
- Aktivem Checkpoint-Write
- Nicht-persistierter notwendiger Evidenz
- Nicht sicher repräsentierbarem Missions-Zustand

Bei Druck während unsicherer Arbeit:
- Übergang als PENDING_SAFE_BOUNDARY aufzeichnen
- Bis zur nächsten sicheren Grenze fortfahren
- Dann Checkpoint und Übergang ausführen

---

## Idempotenz-Anforderungen

Ein Kontext-Übergang muss retry-sicher sein.

Wo Harness Request-IDs unterstützt:
- Stabile Transition-ID generieren
- Vor Einreichung persistieren
- Für exakte Wiederholungen wiederverwenden
- Konflikte erkennen
- Nie mehrere unabhängige Komprimierungen für einen MxAgile-Übergang erstellen

Wo Harness keine Idempotenz bietet:
- Anfragen lokal serialisieren
- Nie neue Anfrage stellen wenn Prior-Status UNKNOWN

---

## Abschluss-Beobachtung

Request-Annahme ≠ Komprimierung-Abgeschlossen.

Adapter müssen unterscheiden:
REQUESTED → ADMITTED → RUNNING → COMPLETED / FAILED / UNKNOWN

Wenn Abschluss nicht beobachtbar:
- UNKNOWN markieren
- TRANSITION_COMPLETED NICHT behaupten
- Sicherstes dokumentiertes Fortsetzungsverhalten verwenden

---

## Überlauf-Recovery

Nur wo Harness dokumentiertes Recovery unterstützt:
- Checkpoint zuerst persistieren/prüfen wenn möglich
- Maximal die dokumentierte sichere Recovery-Anzahl durchführen
- Sicherstellen, dass fehlgeschlagene Model-Request keine Nebeneffekte hatte
- Nicht bei unsicheren Effekten wiederholen
- Wiederholten Überlauf berichten statt endlos zu wiederholen

OpenCode's dokumentiertes One-Shot-Overflow-Recovery gilt NICHT allgemein für andere Harnesses.

---

## Autonomie-Politik

Gewünschtes Betriebsverhalten ist autonom.

Wenn alle Bedingungen erfüllt sind:
- Zuverlässiger Druck-Zustand (nicht UNKNOWN)
- Sichere Grenze
- Gültiger Checkpoint
- Unterstützter programmatischer Übergang
- Übergangs-Abschluss beobachtbar

→ MxAgile führt den Übergang OHNE Nutzer-Frage durch.

NICHT fragen: "Soll ich jetzt komprimieren?"
wenn die Policy automatische Komprimierung bereits autorisiert.

Nutzer/Mensch-Beteiligung verbleibt angemessen für:
- Globale Installations-/Konfigurationsänderungen
- Nicht-unterstützten Harness-Übergang
- Destruktive Ambiguität
- Sicherheit/Credential-Anforderungen
- Policy die explizit als manuell konfiguriert ist

---

## Harness-Capability-Statusvokabular

Für jeden Übergangsfähigkeit gilt:

| Status | Bedeutung |
|--------|-----------|
| SUPPORTED | Framework weiß wie diese Fähigkeit genutzt wird |
| AVAILABLE | Erforderliche Umgebung/Abhängigkeit erkannt und kompatibel |
| ENABLED | Projekt-Konfiguration erlaubt Nutzung |
| ACTIVE | Fähigkeit wird aktuell genutzt |
| DEGRADED | Betrieb teilweise oder über Fallback |
| UNAVAILABLE | Umgebung/Abhängigkeit fehlt oder inkompatibel |
| UNKNOWN | Zustand nicht bestimmbar |

Unbekannte Werte verbleiben UNKNOWN.
Harness-Fähigkeiten werden NIE erfunden.

---

## Live-Validierungs-Klassifikationen

| Status | Bedeutung |
|--------|-----------|
| LOCALLY_VERIFIED | Im lokalen Testumfeld strukturell verifiziert |
| LIVE_HARNESS_VERIFIED | Mit einem echten Harness live getestet |
| LIVE_HARNESS_UNVERIFIED | Nicht live getestet, aber dokumentiert |
| UNSUPPORTED | Harness unterstützt diese Fähigkeit definitiv nicht |

---

## Optionale Integrations-Abhängigkeiten

Bestimmte Optimierungen sind OPTIONAL. Ihre Unavailability darf Übergänge nicht blockieren.

### Context Mode

Context Mode unavailability must not block Checkpoint, Komprimierung oder Re-Sync.
Context Mode darf Transition nicht blockieren.

Wenn Context Mode nicht verfügbar ist:
- Pre-Compaction-Schritt 15 (`SkipContextModeExternalization`) aktivieren
- `contextModeSkipped: true` im Checkpoint aufzeichnen
- Übergangsequenz OHNE Context Mode fortsetzen

### RTK (Request-Token-Kürzung)

RTK ist eine optionale Token-Optimierung. RTK unavailability must not block transition.

Wenn RTK nicht verfügbar ist:
- Checkpoint ohne RTK-Optimierung schreiben
- Übergangsequenz unabhängig von RTK fortsetzen

---

## Sicherheits-Anforderungen

- Keine Authentifizierungs-Credentials in Transition-Artefakten
- Keine Terminal-Keystroke-Injektion für Slash-Commands
- Keine erfundenen Token-Ersparnisse berichten
- Kein endloser Wiederholungsversuch
- Keine gleichzeitigen Komprimierungs-Anfragen
- Keine stille globale Hook-Installation
- Mission Truth nie durch Zusammenfassungen ersetzen
