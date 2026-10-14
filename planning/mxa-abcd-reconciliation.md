# MxAgile A/B/C/D Acceptance Campaign — Reconciliation Report

**Datum:** 2026-10-14
**Framework-Version zur Abnahme:** MxAgile 1.1 (Modes A/D) / MxAgile 1.5 (Modes B/C)
**Erstellt als:** Akzeptanz-Evidenz für den Post-Acceptance Hardening Pass (MxAgile 1.6)

---

## 1. Kampagnenübersicht

Vier CapTrack-Abnahmekampagnen wurden durchgeführt, um MxAgile-Kernverhalten,
Kontext-Optimierung und kombiniertes Modus-Verhalten zu verifizieren.

| Modus | Konfiguration | Framework-Version | Ziel |
|-------|--------------|------------------|------|
| A | Standard MxAgile, kein RTK, kein Context Mode | 1.1 | Baseline |
| B | MxAgile + RTK aktiviert | 1.5 | RTK-Ausgabe-Optimierung |
| C | MxAgile + Context Mode aktiviert | 1.5 | Context Mode WARM-Retrieval |
| D | MxAgile + RTK + Context Mode (kombiniert) | 1.1 | Kombinierter Betrieb |

---

## 2. Methodologische Einschränkungen (KRITISCH)

**Mode A und D liefen auf MxAgile 1.1.**
**Mode B und C liefen auf MxAgile 1.5.**

Daraus folgt:

- A/B/C/D waren **nicht vollständig methodologisch vergleichbar**.
- Mode D beweist KEINE Fehlerfreiheit der 1.5-verwalteten Kombination.
- Vergleiche zwischen Modes, die auf verschiedenen Framework-Versionen liefen, sind
  mit Vorbehalt zu interpretieren.
- Quantitative Framework-Version-spezifische Regression kann auf Basis dieser Kampagne
  **nicht** behauptet werden.

---

## 3. Befunde: Keine CapTrack-Applikationsdefekte

Über alle vier Kampagnen wurden **0 CapTrack-Applikationsdefekte** festgestellt.

Dies bedeutet:
- Keine durch MxAgile verursachten Applikationsfehler.
- Keine Regressionsfehler in der getesteten Anwendungslogik.
- Die kampagnenspezifischen Testskript-Befunde (z. B. Playwright-Navigations-Bugs)
  sind **Testskript-Befunde**, keine Applikationsdefekte.

---

## 4. Optimierungs-Telemetrie: NICHT GEMESSEN

### RTK (Rust Token Killer)

RTK-Laufzeitnutzung wurde **beobachtet**, aber:

- Quantitativer Token-/Komprimierungsvorteil wurde **nicht gemessen**.
- Byte/Zeichen-Schätzungen von RTK sind **keine** autoritativen Modell-Token-Zählungen.
- Das Kampagnen-Design enthielt keine Baseline-zu-RTK Kontrollgruppe auf identischer
  Framework-Version.

**Metrik-Klassifikation: UNAVAILABLE**

Behauptung "RTK spart X Token in MxAgile" ist auf Basis dieser Kampagne **nicht zulässig**.

### Context Mode

Context Mode Indizierung und Abruf wurden **beobachtet**, einschließlich
Anti-Dual-Memory-Verhalten. Aber:

- Quantitativer Token-Vorteil wurde **nicht gemessen**.
- Keine Kontrollgruppe mit identischer Framework-Version ohne Context Mode.

**Metrik-Klassifikation: UNAVAILABLE**

Behauptung "Context Mode reduziert Token-Nutzung in MxAgile" ist auf Basis
dieser Kampagne **nicht zulässig**.

---

## 5. Kombinierter Betrieb (Mode D)

Mode D zeigte **keine beobachteten Kombinationsdefekte**. Aber:

- Mode D lief auf MxAgile 1.1, nicht auf 1.5.
- Die 1.5-verwaltete Kombination wurde **nicht vollständig geprüft**.
- Mode D beweist nicht, dass RTK + Context Mode auf MxAgile 1.5 fehlerlos funktioniert.

---

## 6. Framework/Tooling/Runtime-Befunde (Wiederholbare Findings)

Die folgenden Befunde wurden über die Kampagnen hinweg wiederholt beobachtet
und bilden die Grundlage für den Hardening Pass:

| RF-ID | Kategorie | Befund |
|-------|----------|--------|
| RF-001 | Resume | Aktive Mission muss bei Resume Priorität über allgemeinen Produkt-Lifecycle-Zustand (z. B. FEATURE_SCOPE_COMPLETE) haben |
| RF-002 | Context Mode | INSTALLED ≠ REGISTERED ≠ LOADED ≠ ACTIVE — Framework unterschied diese Zustände nicht ausreichend |
| RF-003 | Context Mode | Einige Quellen referenzieren `ctx_store` statt des korrekten `ctx_index` (Authoring-Werkzeug) |
| RF-004 | Studio Pro | SP-Prozessdetektor kann bei langsamer Umgebung unbegrenzt hängen; kein Timeout; TIMEOUT ≠ CLOSED_AUTONOM |
| RF-005 | PowerShell | PS 5.x-Parsing-/Encoding-Probleme verursachten kryptische Mid-Install-Fehler; kein deterministischer Preflight |
| RF-006 | Runtime-Start | Ambiguous Start Result ≠ Application Not Started; Blind-Retry führt zu BindException |
| RF-007 | MxTest | Test-Harness injiziert Repository-Pollution (*.mxunit, javasource/mxtest etc.); keine Cleanup-Disziplin dokumentiert |
| RF-008 | mxcli | Bekannte mxcli-Limitierungen (CALL MICROFLOW, Windows attach/PID, OQL) wurden als Applikationsdefekte klassifiziert statt als Tooling-Limitierungen |
| RF-009 | Testskript | CapTrack-spezifische Playwright-Navigations-Bugs dürfen nicht in MxAgile Core-Semantik eingehen |
| RF-010 | Abschluss | Agent meldete Clean-Completion nach git-status-Check, der VOR der finalen Test-Harness-Aktion lag |

---

## 7. Nicht umgesetzte Empfehlungen (bewusst)

| Empfehlung | Begründung für Nicht-Umsetzung |
|-----------|-------------------------------|
| Jeden operationellen Epoch-Checkpoint committen | Widerspricht der Zwei-Stufen-Architektur (operationell gitignored, Handoff git-tracked). Overcorrection. Nicht umgesetzt. |
| RTK/Context Mode als Standardaktivierung | Kein gemessener Nutzen belegt. Bleiben optional. |
| Token-Telemetrie-Dashboard | Außerhalb Scope. Nur Measurement-Readiness-Vorbereitung. |

---

## 8. Metriken-Klassifikation (Endgültig)

| Metrik | Klassifikation | Begründung |
|--------|---------------|-----------|
| CapTrack-Applikationsdefekte | MEASURED: 0 | Direkt beobachtet und verifiziert |
| RTK Token-Vorteil | UNAVAILABLE | Nicht gemessen; Methodologie unzureichend |
| Context Mode Token-Vorteil | UNAVAILABLE | Nicht gemessen; Methodologie unzureichend |
| SP+Concord Kombinationsverhalten auf 1.5 | PROXY | Mode D lief auf 1.1, nicht 1.5 |
| Framework-Regressionssicherheit 1.1→1.5 | ESTIMATED | Strukturell validiert, kein direkter A/D-auf-1.5-Vergleich |

---

## 9. Kampagnen-Provenienz

Dieses Dokument ist die Akzeptanz-Evidenzbasis für:

- `docs/post-acceptance-hardening.md` (Hardening-Dokumentation)
- Tests in `tests/test-hardening-rf*.ps1` (Regressionstests)
- `version.yaml` Eintrag für MxAgile 1.6

Dieses Dokument darf nicht als Quelle für allgemeine Token-Effizienzbehauptungen
zitiert werden.

CapTrack-spezifische Testskript-Details dürfen nicht in generische MxAgile-Core-Semantik
übernommen werden.
