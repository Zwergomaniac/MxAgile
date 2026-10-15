Jetzt habe ich das vollständige Bild. Lasse mich den Plan formulieren.

---

## Plan: MxMocketeer Hardening durch Copilot Skills

### Ausgangslage

MxMocketeer v3 hat heute eine **dreiteilige Architektur**:

| Schicht | Mechanismus | Zuverlässigkeit |
|---------|-------------|-----------------|
| Instructions | System Prompt (1× copy-paste) | **Deterministisch** — wird immer ausgeführt |
| Knowledge | 7 TXT-Dateien via RAG-Retrieval | **Probabilistisch** — wird nur gefunden, wenn der Retriever es für relevant hält |
| Suggested Prompts | 7 Einstiegspunkte | Deterministisch (UI-gesteuert) |

Das Problem hat [agent-builder-setup.md](products/MxMocketeer/agent-builder-setup.md#L19) selbst dokumentiert:

> *"Critical rules are deliberately kept in the instructions because knowledge retrieval must not be treated as guaranteed program execution."*

Deshalb ist der System Prompt aufgebläht — er muss alles tragen, was nicht ausfallen darf. Knowledge ist nur "best effort".

### Was Copilot Skills ändern

Skills sind **deklarative Fähigkeiten mit YAML-Frontmatter** (Name + Beschreibung). Sie werden dem Agent als strukturierte Capability zugeordnet — nicht als RAG-Dokument. Das ist ein **dritter Zuverlässigkeitsgrad** zwischen Instructions und Knowledge:

| Schicht | Zuverlässigkeit | Geeignet für |
|---------|-----------------|-------------|
| Instructions | Garantiert | Identität, Kernregeln, Stop Conditions |
| **Skills** | **Strukturiert + abrufbar** | **Prozesse, Schemata, Validierungslogik** |
| Knowledge | Probabilistisch | Referenz-Beispiele, Golden Mockup, Hintergrundwissen |

### Vorgeschlagene Skill-Zerlegung

**7 Skills** aus dem heutigen monolithischen System Prompt + Knowledge extrahieren:

#### Skill 1: `discovery` — Discovery & Requirements Elicitation
- **Quelle:** System Prompt §Discovery + §Requirements vs. Decisions + [discovery-assessment.txt](products/MxMocketeer/knowledge/discovery-assessment.txt)
- **Inhalt:** Discovery-Dimensionen, Fragestrategie, Status-Taxonomie (CONFIRMED/DERIVED/ASSUMPTION/...), Requirements vs. Decisions Trennung
- **Hardening:** Assessment-Dimensionen und Gap-Taxonomie werden garantiert geladen, nicht RAG-abhängig

#### Skill 2: `design-contract` — Design Contract Schema & Validation
- **Quelle:** System Prompt §Mandatory Embedded Design Contract + §Element Traceability + [design-contract.txt](products/MxMocketeer/knowledge/design-contract.txt)
- **Inhalt:** Vollständiges Contract-Schema v1.1, Pflichtfelder, Enum-Werte, Validierungsregeln
- **Hardening:** Schema-Verletzungen (fehlende Felder, falsche Enums) sind heute die häufigste Fehlerklasse — deterministischer Zugriff eliminiert "Schema wurde nicht gefunden"-Ausfälle

#### Skill 3: `refinement` — Refinement & Transformation Classification
- **Quelle:** System Prompt §Refining an Existing Mockup + [refinement-transformations.txt](products/MxMocketeer/knowledge/refinement-transformations.txt)
- **Inhalt:** Edit-Klassifikation (LOCAL_EDIT → FULL_REGENERATION), Transformation Spec Schema, Safe Target Resolution
- **Hardening:** Korrekte Klassifikation ist kritisch — falsches FULL_REGENERATION zerstört Preservation; falsches LOCAL_EDIT produziert unvollständige Patches

#### Skill 4: `preservation` — Revision Ledger & Preservation Check
- **Quelle:** System Prompt §Revision Ledger + Preservation-Teile aus [design-contract.txt](products/MxMocketeer/knowledge/design-contract.txt)
- **Inhalt:** revision_history (append-only), preservation block, revision_delta, STOP-on-FAILED Regel
- **Hardening:** Die Preservation-Logik ist die wichtigste Sicherheitsschranke — wenn sie ausfällt, gehen bestätigte Requirements verloren

#### Skill 5: `business-flows` — Business Flow Modeling
- **Quelle:** System Prompt §Business Flows + [business-flows.txt](products/MxMocketeer/knowledge/business-flows.txt)
- **Inhalt:** Flow-Schema, Step-Types, FLOW-NNN/FLOWSTEP-NNN IDs, Transitions, Mermaid-Generierung
- **Hardening:** Flow-Modellierung ist heute optional und wird oft übersprungen, weil das Knowledge nicht zuverlässig geladen wird

#### Skill 6: `mockup-generation` — HTML Mockup Implementation
- **Quelle:** System Prompt §Mockup Concept + §Interaction States + Teile von [mendix-design-guide.txt](products/MxMocketeer/knowledge/mendix-design-guide.txt)
- **Inhalt:** HTML-Generierungsregeln, CSS/JS-Anforderungen, Responsive/A11y, Mock-Data Markierung, UI-States Enum
- **Hardening:** Konsolidiert die verstreuten Generierungsregeln an einem Ort

#### Skill 7: `handoff` — Development Handoff & Maturity Gate
- **Quelle:** System Prompt §Handoff Readiness + §Maturity Assessment + [mxagile-handoff.txt](products/MxMocketeer/knowledge/mxagile-handoff.txt)
- **Inhalt:** Handoff-Kriterien, Readiness-Levels, MxAgile-Mapping, Mendix-Boundary
- **Hardening:** Verhindert voreiligen Handoff ohne Assessment

### Was im System Prompt bleibt (schlanker Kern)

Nur noch ~30% des heutigen Umfangs:

- **Role** — 1 Satz Identität
- **Working Method** — Kernprinzipien (nie erfinden, Konflikte identifizieren, etc.)
- **Stop Conditions** — Safety-kritisch, muss immer geladen sein
- **Process** — 7-Schritt-Ablauf als Orchestrierung der Skills
- **Output per Iteration** — Output-Format-Vertrag
- **Platform Boundary Scope Rule** — Kurze Sicherheitsregel
- **Incoming v1.0 Contracts** — Migrations-Trigger

### Was in Knowledge bleibt

- [golden-mockuphtml.txt](products/MxMocketeer/knowledge/golden-mockuphtml.txt) — 26 KB Referenz-HTML, zu groß für einen Skill, und RAG-Retrieval ist hier akzeptabel (wird nur bei Generierung gebraucht)
- [mendix-design-guide.txt](products/MxMocketeer/knowledge/mendix-design-guide.txt) — Hintergrundwissen, kein kritischer Pfad

### Dateistruktur (neu)

```
products/MxMocketeer/
    system-prompt.md              — SCHLANK: nur Kern-Identität + Orchestrierung
    agent-builder-setup.md        — AKTUALISIERT: neue Setup-Anleitung mit Skills
    suggested-prompts.md          — unverändert
    README.md                     — AKTUALISIERT

    skills/                       — NEU
        discovery.md              — SKILL.md Format (YAML + Inhalt)
        design-contract.md
        refinement.md
        preservation.md
        business-flows.md
        mockup-generation.md
        handoff.md

    knowledge/                    — REDUZIERT
        golden-mockuphtml.txt     — bleibt (Referenz-Beispiel)
        mendix-design-guide.txt   — bleibt (Hintergrund)

    tests/
        preservation-acceptance.md
        test-mocketeer-validation.ps1  — ERWEITERT: validiert Skills
        test-transformations.ps1
```

### SKILL.md Format (Beispiel)

```yaml
---
name: preservation
description: >
  Revision ledger management and preservation validation for MxMocketeer
  Design Contracts. Ensures append-only revision history, preservation checks,
  and STOP-on-FAILED safety gate.
---

# Preservation & Revision Ledger

## Revision History (append-only)
...
```

### Umsetzungsschritte

1. **Skills extrahieren** — Inhalte aus System Prompt + Knowledge in 7 SKILL.md-Dateien zerlegen
2. **System Prompt verschlanken** — Nur Kern behalten, Skills referenzieren
3. **agent-builder-setup.md aktualisieren** — Neue Setup-Anleitung (Instructions + 7 Skills + 2 Knowledge)
4. **README.md anpassen** — Package Structure und Setup Order
5. **Validierungstest erweitern** — SKILL.md YAML-Frontmatter validieren, Pflichtfelder prüfen
6. **Preservation Acceptance Test** — Bestehenden Test mit Skill-Setup durchlaufen

### Risiken und Mitigierung

| Risiko | Mitigierung |
|--------|-------------|
| Copilot Skills-Retrieval noch nicht getestet — evtl. auch nicht deterministisch | Skill 4 (Preservation) und Stop Conditions bleiben zusätzlich im System Prompt als Safety Net |
| Maximale Skill-Anzahl oder -Größe unbekannt | ZIP-Packaging als Fallback (Screenshot zeigt ZIP-Support) |
| Bestehende v3-Deployments müssen migriert werden | Parallel-Betrieb: v3 (Instructions-only) und v3.1 (Skills) als separate Agent-Versionen |

### Empfehlung

Start mit **Skill 2 (design-contract)** und **Skill 4 (preservation)** — das sind die beiden, bei denen RAG-Ausfall heute den größten Schaden anrichtet. Danach die restlichen 5 in einem zweiten Schritt.

---

Soll ich mit der Umsetzung beginnen? Wenn ja — komplett (alle 7 Skills auf einmal) oder inkrementell (erst die beiden kritischen)?