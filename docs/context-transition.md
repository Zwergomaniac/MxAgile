# MxAgile Context Transition

Autonome Kontext-Komprimierung und Epochen-Übergangs-Orchestrierung für MxAgile-Missionen.

**Version eingeführt:** 1.7  
**Policy:** `.mxagile/policies/context-transition.md`  
**Konfiguration:** `.mxagile/config.yaml` → `context_lifecycle.transition:`  
**Capability Registry:** `.mxagile/capabilities.yaml`  
**Basisarchitektur:** `docs/context-lifecycle.md`

---

## Warum autonome Komprimierung erforderlich ist

MxAgile-Missionen überspannen mehrere Agent-Sessions und Kontext-Epochen. Wenn der
Kontext die Kapazitätsgrenze erreicht, muss die Mission sicher fortgesetzt werden.

Ein Design, das nur einen Checkpoint schreibt und auf manuelles `/compact`, eine neue
Session oder Copy-Paste-Resume wartet, ist **nicht ausreichend** als primäres
Betriebsmodell.

MxAgile muss harness-native Transition-Fähigkeiten automatisch nutzen, wo sie
verfügbar und verifiziert sind.

---

## Primäres Invariant

**MxAgile Mission Truth überlebt Kontext-Komprimierung unabhängig von der
harness-generierten Komprimierungszusammenfassung.**

Komprimierungszusammenfassungen sind **verlustbehafteter Kontext-Input**.
Sie sind KEINE autoritative MxAgile-Zustandsquelle.

Komprimierung darf NIEMALS direkt Evidenz befördern, Gates erfüllen, die Mission
abschließen, Scope verändern oder Re-Sync unterdrücken.

Autoritative Quellen: MxAgile Resume Contract + kanonische Repository-Artefakte.

---

## Transition-Strategien

### 1. COMPACT_CURRENT_SESSION (bevorzugt)

Harness-native Komprimierung in der gleichen dauerhaften Session.

**Wann:** Harness unterstützt Komprimierung (programmatisch oder nativ auto) +
gültiger Checkpoint + sichere Grenze.

**Verhalten:** Pre-Compaction-Checkpoint → Komprimierung beantragen/beobachten →
Post-Compaction Re-Sync → Mission fortsetzen.

### 2. FRESH_CONTEXT_EPOCH

Neuen Kontext bei erhaltener Mission via Checkpoint-Handoff.

**Wann:** COMPACT_CURRENT_SESSION nicht verfügbar + Checkpoint-Handoff möglich.

**Verhalten:** Vollständigen Checkpoint schreiben → Neue Session starten → Re-Sync.

### 3. EXTERNAL_ACTION_REQUIRED (Fallback)

Nur wenn kein unterstützter autonomer Übergang verfügbar ist.

**Verhalten:** Klare Anweisung an Nutzer + Checkpoint-Pfad bereitstellen.

---

## Harness-Fähigkeitsübersicht

| Harness | Auto-Compact | Programmatisch | PreCompact-Hook | Completion obs. | Strategie |
|---------|-------------|----------------|-----------------|-----------------|-----------|
| **OpenCode** | Ja | Ja (POST /api/…/compact) | Unbekannt | Ja (Events) | COMPACT_CURRENT_SESSION |
| **Claude Code** | Ja | Nein (UNSUPPORTED) | Ja (settings.json) | Nein | COMPACT_CURRENT_SESSION (hook-basiert) |
| **Copilot CLI** | Unbekannt | Nein | Nein | Nein | EXTERNAL_ACTION_REQUIRED |
| **Generic** | Nein | Nein | Nein | Nein | EXTERNAL_ACTION_REQUIRED |

---

## OpenCode-Adapter

**Basis:** `https://github.com/sst/opencode`  
**Live-Status:** LIVE_HARNESS_UNVERIFIED (kein aktives OpenCode in diesem Umfeld)

### Programmatische Komprimierung

```
POST /api/session/{sessionID}/compact
Body: { "id": "<stable-transition-id>" }
```

Idempotenz: optionales `id`-Feld — repeated requests coalesce.

### Completion-Beobachtung

```
session.compaction.started
session.compaction.completed
session.compaction.failed
```

### Session-Discovery

```
OPENCODE_SESSION_ID  ← bevorzugte Quelle
OPENCODE_BASE_URL    ← Base URL Override (Standard: http://localhost:4096)
```

**Wichtig:** Session-ID nicht erraten. Wenn nicht verfügbar → TRANSITION_BLOCKED.

### Overflow-Recovery

One-shot: Ein Komprimierungsversuch bei Provider-Context-Overflow.
`max_recovery_attempts: 1` — nicht endlos wiederholen.

---

## Claude Code Adapter

**Basis:** `https://docs.anthropic.com/claude-code`  
**Live-Status:** LOCALLY_VERIFIED (Hook-Struktur verifiziert; Live-Komprimierung nicht getriggert)

### Native Auto-Compaction

Claude Code komprimiert automatisch nahe dem Kontext-Limit. Diese Komprimierung
ist transparent — der Agent beobachtet sie nicht direkt.

### Programmatischer Trigger: UNSUPPORTED

`/compact` ist ein interaktives Slash-Command.  
**Niemals Terminal-Keystrokes injizieren** um `/compact` zu automatisieren.  
Programmatic triggering: **definitiv UNSUPPORTED**.

### PreCompact Hook Integration

MxAgile integriert über den `PreCompact`-Lifecycle-Hook in `.claude/settings.json`.

**Konfiguration:**

```json
{
  "hooks": {
    "PreCompact": [
      {
        "type": "command",
        "command": "powershell -File scripts/Invoke-MxAgilePreCompactionCheckpoint.ps1 -ProjectRoot $PWD"
      }
    ],
    "SessionStart": [
      {
        "type": "command",
        "command": "powershell -File scripts/Invoke-MxAgilePostCompactionResync.ps1 -ProjectRoot $PWD"
      }
    ]
  }
}
```

**Wichtig:**
- Hook-Installation erfordert explizite Nutzer-Autorisierung
- MxAgile installiert Hooks **nie stillschweigend**
- PostCompact-Hook: UNSUPPORTED → SessionStart übernimmt Re-Sync-Aufgabe

---

## Copilot CLI Adapter

**Status:** Komprimierungsfähigkeiten UNKNOWN/UNSUPPORTED (Stand: 2026-10-14)

Keine Compaction API, kein PreCompact-Hook in aktueller Upstream-Dokumentation
bestätigt. Strategie: immer EXTERNAL_ACTION_REQUIRED.

---

## Transition-Zustandsmaschine

```
IDLE → PRESSURE_OBSERVED → TRANSITION_REQUESTED
     ↓ (unsichere Grenze)
     PENDING_SAFE_BOUNDARY → TRANSITION_REQUESTED
     ↓ (sichere Grenze)
     CHECKPOINT_PREPARING → CHECKPOINT_VALIDATED
     ↓ (COMPACT_CURRENT_SESSION)
     COMPACTION_ADMITTED → COMPACTION_RUNNING → COMPACTION_COMPLETED
                                                 ↓
                                          POST_COMPACT_RESYNC_REQUIRED
                                                 ↓ (Re-Sync abgeschlossen)
                                          TRANSITION_COMPLETED
     ↓ (Fehler)
     TRANSITION_FAILED
     ↓ (FRESH_CONTEXT_EPOCH)
     FRESH_CONTEXT_READY → FRESH_CONTEXT_REQUESTED → TRANSITION_COMPLETED
     ↓ (kein Übergang verfügbar)
     TRANSITION_BLOCKED (→ EXTERNAL_ACTION_REQUIRED)
     UNSUPPORTED
```

---

## Safe Boundaries

Kein Übergang während:
- Laufendem Tool-Aufruf (`no_tool_call_in_flight`)
- Aktivem File-Write (`no_file_write_in_flight`)
- Aktivem Checkpoint-Write (`no_checkpoint_write_active`)
- Offenem Commit (`no_pending_commit`)

Bei Druck während unsicherer Arbeit:
→ `PENDING_SAFE_BOUNDARY` aufzeichnen → bei nächster sicherer Grenze fortfahren.

---

## Pre-Compaction-Protokoll (17 Schritte)

Ausgeführt von `scripts/Invoke-MxAgilePreCompactionCheckpoint.ps1`:

1. Aktive Mission identifizieren
2. Aktuelle Context Epoch identifizieren
3. Repository-Realität inspizieren
4-14. Missions-/Scope-/Phase-/Gate-/Blocker-/Override-/Evidenz-/Repository-/
      Operations-/Nächste-Aktion-/Evidenz-Referenzen persistieren
15. Optional: WARM-Context via Context Mode externalisieren
16. Checkpoint validieren
17. Transition-Request-ID persistieren

**Bei Validierungsfehler:** TRANSITION_BLOCKED, kein TRANSITION_COMPLETED.

---

## Post-Compaction Re-Sync

Ausgeführt von `scripts/Invoke-MxAgilePostCompactionResync.ps1`:

1. Re-Sync-Anforderung prüfen (`post_compaction_resync_required`)
2. Aktiven Missions-Checkpoint laden/validieren
3. Repository-Identität und Working-Tree prüfen
4. FAILED und UNVERIFIED bewahren
5. STALE-Regeln anwenden
6-11. Minimalen HOT-Kontext rekonstruieren → Mission autonom fortsetzen

**Checkpoint/Zusammenfassung-Konflikt → Checkpoint gewinnt.**

Der Agent fragt den Nutzer NICHT nach der Mission, wenn der Checkpoint ausreichend ist.

---

## Idempotenz

**Transition-Request-ID Format:** `TXN-{EpochId}-{Timestamp}`

Vor Einreichung persistiert. Für exakte Wiederholungen wiederverwendet.
Nie mehrere unabhängige Komprimierungen für einen MxAgile-Übergang.

---

## Asynchrone Completion (OpenCode)

```
Request admitted (COMPACTION_ADMITTED)
  ≠ Compaction running (COMPACTION_RUNNING)
  ≠ Compaction completed (COMPACTION_COMPLETED)
```

Auf `session.compaction.completed` oder `session.compaction.failed` warten.
Wenn Completion nicht beobachtbar: UNKNOWN markieren, TRANSITION_COMPLETED NICHT behaupten.

---

## Context Mode Interaktion

Context Mode ist optional. Bei Komprimierung:

**Vor Komprimierung:**
- Optionale WARM-Content-Externalisierung via `ctx_index`
- Context Mode ist NIEMALS die einzige Kopie von HOT-Missions-State
- Context Mode-Unavailability blockiert NICHT die Komprimierung

**Nach Komprimierung:**
- Nur benötigten WARM-Detail abrufen
- Anti-Dual-Memory-Regeln bewahren

---

## RTK Interaktion

RTK ist optional und unabhängig. RTK-Byte/Zeichen-Reduktion ≠ autoritative Token-Reduktion.
RTK-Unavailability blockiert NICHT Checkpoint, Komprimierung oder Re-Sync.

---

## Konfiguration

```yaml
context_lifecycle:
  enabled: true                  # Master switch
  checkpoint_resume: true        # Erforderlich für Transition
  transition:
    enabled: false               # Transition aktivieren
    autonomous: false            # Vollautonome Transitions (riskant — erst nach Tests)
    preferred_strategies:
      - compact_current_session
      - fresh_context_epoch
      - external_action_required
    compact:
      enabled: true
      require_valid_checkpoint: true
      require_safe_boundary: true
      recent_tail_tokens: null   # null = Harness-Default
      buffer_tokens: null
    fresh_context:
      enabled: true
    external_action_fallback: true
```

### Standardwerte

| Feature | Standard | Notiz |
|---------|---------|-------|
| `transition.enabled` | `false` | Explizit aktivieren |
| `transition.autonomous` | `false` | Erst nach Tests aktivieren |
| Pre-Compact Checkpointing | ON wenn Hook installiert | Harness-abhängig |
| Post-Compact Re-Sync | ON | Immer erforderlich |
| Programmatischer Trigger | OFF für Claude Code | UNSUPPORTED |
| Hook-Installation | Nie stillschweigend | Nutzer-Autorisierung |

---

## Diagnostik

`Get-MxAgileTransitionCapabilities.ps1 -OutputFormat human` zeigt:

- Harness-ID und erkannte Version
- Adapter-Ladestatus
- Compact-Fähigkeiten (auto/programmatisch/completion)
- PreCompact-Hook-Status
- Bevorzugte Strategie
- Ob autonome Komprimierung möglich ist

Vollständige Transitions-State in `context-epoch.yaml` → `context.transition_state`.

---

## Failure Safety

| Fehler | Verhalten |
|--------|-----------|
| Checkpoint-Validierung fehlgeschlagen | TRANSITION_BLOCKED, kein TRANSITION_COMPLETED |
| Compaction Request abgelehnt | TRANSITION_FAILED, Checkpoint erhalten |
| Request admitted, Completion unbekannt | COMPACTION_ADMITTED (kein TRANSITION_COMPLETED) |
| Adapter nicht verfügbar | EXTERNAL_ACTION_REQUIRED |
| Model-Overflow vor normalem Trigger | Recovery max. 1x (OpenCode), sonst berichten |
| Post-Compact-Checkpoint fehlt | TRANSITION_FAILED, erneutes Checkpoint-Schreiben |
| Zusammenfassung vs. Checkpoint | Checkpoint gewinnt, Abweichung diagnostisch |
| Gleichzeitige pending Transition | Zweite Anfrage NICHT erstellen |
| Repository geändert während Transition | Commit-STALE-Regeln nach Re-Sync |

---

## Messungen

Alle Messwerte klassifiziert als MEASURED / ESTIMATED / PROXY / UNAVAILABLE.

Aufgezeichnet (wo verfügbar):
- Harness + Model + Kontext-Limit
- Kontext-Nutzung vor/nach Komprimierung
- Druckzustand + Strategie + Recent-Tail-Einstellung
- Anfrage/Eingang/Abschluss-Zeiten
- Re-Sync-Konflikte
- Fehlgeschlagene Transitions
- Nutzer-Interventionen

**Keine erfundenen Token-Ersparnisse.**

---

## Sicherheit

- Keine Authentifizierungs-Credentials in Transition-Artefakten
- Keine Terminal-Keystroke-Injektion
- Keine erfundenen Fähigkeiten
- Keine stillen globalen Hook-Installationen
- Keine Mission Truth durch Zusammenfassungen ersetzen

---

## Rollback

Um Context Transition zu deaktivieren:

```yaml
context_lifecycle:
  transition:
    enabled: false
    autonomous: false
```

Pre-Compaction-Hooks aus `.claude/settings.json` entfernen (manuell).
Bestehende Checkpoints bleiben gültig — keine Migration erforderlich.

---

## Live-Validierungs-Status (2026-10-14)

| Fähigkeit | Status |
|-----------|--------|
| Claude Code PreCompact Hook (Struktur) | LOCALLY_VERIFIED |
| Claude Code SessionStart Re-Sync | LOCALLY_VERIFIED |
| Claude Code Programmatischer Trigger | UNSUPPORTED |
| OpenCode Compact API (Struktur) | LIVE_HARNESS_UNVERIFIED |
| OpenCode Completion Events | LIVE_HARNESS_UNVERIFIED |
| Copilot CLI Compaction | UNSUPPORTED |
| Generic Fallback | LOCALLY_VERIFIED |
