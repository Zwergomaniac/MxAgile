# Implementierungssteuerung

## Wave-Schnitt

Implementation Waves unter `planning/execution-waves.md` sind technische Reihenfolge,
keine lokalen Sprints.

Waves werden so geschnitten, dass zusammengehoerige Domain-Model-Aenderungen in einem
Modellabschnitt liegen. Pro Wave gibt es hoechstens ein bewusstes Entity-Security-Gate.
Reine Seiten-, Microflow-, Test- und Dokumentationsarbeit folgt erst nach diesem Gate
und loest normalerweise kein neues `CE0066` aus.

Alle Waves werden grob als Roadmap geplant; nur die naechste Wave wird vollstaendig
detailliert und umgesetzt.

## Change Significance Classification

Bevor eine Wave in die Ready-Phase eintritt, klassifiziert der Agent den Aenderungsumfang.
Die Klassifikation erfolgt bei gate-to-ready und bestimmt die Tiefe der Architektur-Pruefung.
Keine numerischen Schwellenwerte — massgeblich ist der Charakter der Aenderung.

**LOCAL**
- Abgegrenzte Aenderung innerhalb einer bereits etablierten Capability/Domain/Modul-Grenze
- Bestehende Architektur und Modul-Ownership bleiben unveraendert gueltig
- Kein neuer Architektur-Entscheid erforderlich
- GAP-Repair verbleibt auf dem begrenzten Repair-Pfad

**FEATURE**
- Zusammenhaengende Produktaenderung innerhalb oder Ergaenzung der bestehenden Architektur
- Capability-, Domain- und Modul-Ownership muessen vor der Checklisten-Erstellung explizit
  bestaetigt oder neu festgelegt werden
- Normales Wave-Planning gilt

**CROSS_CUTTING**
- Betrifft mehrere Capabilities, Module oder gemeinsam genutzte Querschnittsbelange
  (Security, Persistence, Audit, geteilte Microflows/Pages/Snippets)
- Architektur-Ownership-Assessment vor Readiness erforderlich
- Kann DEC-Eintrag fuer neue Ownership-Entscheide erfordern

**ARCHITECTURALLY_SIGNIFICANT**
- Erstellt eine neue Modul- oder Capability-Grenze
- Verschiebt Ownership zwischen Modulen
- Fuehrt neue moduluebergreifende Abhaengigkeit ein
- Aendert Security/Authorization-Grenze (Rollen, XPath-Constraints, Entity Access Rules)
- Aendert Integrations- oder Platform-Grenze
- Erweitert oder ersetzt Company-Layer/Platform-Funktionalitaet
- Fuehrt breit wiederverwendbare Komponenten ein (Microflows, Pages, Snippets, Domain-Entitaeten)
- Erhoetzt Kopplung oder vergroessert ein bestehendes General-Purpose-Modul materiell
- Signifikanter Persistence- oder Domain-Model-Redesign
- Expliziter DEC-Eintrag (`decision_type: architecture`) vor Readiness erforderlich

## Architecture Escalation Triggers

Der Agent eskaliert auf ARCHITECTURALLY_SIGNIFICANT wenn eines der folgenden zutrifft:

- Ein neues Mendix-Modul wird benoetigt
- Eine neue Capability- oder Domain-Grenze wird gezogen
- Eine Entitaet oder ein Domain-Konzept wird in ein Modul gelegt, dessen bestehende
  Verantwortlichkeit sich davon unterscheidet (fremde Domain in bestehendes Modul)
- Ownership eines bestehenden Concern wechselt zwischen Modulen
- Eine neue moduluebergreifende Abhaengigkeit wird eingefuehrt
- Eine Security- oder Authorization-Grenze aendert sich
- Eine Integrations- oder Platform-Grenze aendert sich
- Company-Layer- oder Platform-Modul wird erweitert oder ersetzt
- Ein geteilter/wiederverwendbarer Microflow, Page oder Snippet wird moduluebergreifend benoetigt
- Mehrere Capabilities sind betroffen
- Signifikanter Persistence- oder Domain-Model-Redesign
- Die Aenderung erhoetzt Kopplung oder vergroessert materiell ein bestehendes Modul (Monolith-Risiko)

Eskalation NICHT allein aufgrund der Anzahl geaenderter Dateien oder Requirements.

## Architecture Drift Guard

Das folgende Muster ist explizit verboten (LOCAL_REQUIREMENT_OPTIMIZATION):

```
REQ A → einfachste lokale Platzierung
REQ B → einfachste lokale Platzierung
REQ C → einfachste lokale Platzierung
→ unbeabsichtigte Architektur
```

Stattdessen gilt fuer FEATURE/CROSS_CUTTING/ARCHITECTURALLY_SIGNIFICANT Scope:

```
akzeptierter/verfeinenter Scope
→ Significance-Klassifikation
→ Capability/Domain-Gruppierung
→ Architecture-Ownership-Assessment (10 Fragen)
→ Wave-Planning mit Modul-Ownership
→ Checklisten-Erstellung mit Platzierungskontext
→ Implementierung
```

Wenn Modul-Ownership nicht aus bestehenden akzeptierten Architekturentscheiden oder
Spezifikationen abgeleitet werden kann: Readiness fuer diese Architektur-Frage pausieren
— ohne unabhaengigen Scope zu blockieren.

## Wave Entry Format

Fuer FEATURE/CROSS_CUTTING/ARCHITECTURALLY_SIGNIFICANT Waves enthaelt der Eintrag
in `planning/execution-waves.md` folgende Felder (Markdown-Format):

```markdown
## Wave W1 — [Kurzer Wave-Titel]

**Significance:** FEATURE | CROSS_CUTTING | ARCHITECTURALLY_SIGNIFICANT
**Capability:** [Business-Capability dieser Wave]
**Domain:** [Betroffene Domain(s)]
**Module Ownership:** [Mendix-Modul(e); EXISTING oder NEW]
**Architecture Decision(s):** DEC-001 [Referenz]
**Board Stories:** {STORYPREFIX}-001, {STORYPREFIX}-002
**Dependencies:** W0 (falls zutreffend)
```

LOCAL-Waves duerfen diese Felder weglassen.

Ziel ist kohaerente Capability/Domain-Ownership — NICHT maximale Modularisierung.
Vermeiden: alles in einem Modul UND ein Modul pro Requirement.

## Proportionalitaet

**GREENFIELD / INITIALER GROSSAUFBAU**
Vor der ersten Wave-Detaillierung eine uebergeordnete Modul/Capability-Karte erstellen,
die den gesamten akzeptierten Scope abdeckt. Verhindert, dass erste Requirements
implementiert werden bevor wesentliche Ownership-Grenzen sichtbar sind.

**ETABLIERTES PRODUKT / FEATURE-ENTWICKLUNG**
Bestehende Architektur verwenden wo gueltig. FEATURE-Wave erfordert explizite
Ownership-Angabe, aber keine neue Architektur-Review wenn Grenzen unveraendert bleiben.

**KLEINE REFINEMENT**
Bestehende Architektur wiederverwenden. Kein Architektur-Assessment erforderlich
wenn Significance LOCAL ist.

**CROSS-CUTTING REFINEMENT**
Auf CROSS_CUTTING oder ARCHITECTURALLY_SIGNIFICANT eskalieren — auch wenn das
individuelle UI/Produkt-Delta klein erscheint.

**GAP REPAIR**
Begrenzter Repair-Pfad wenn Architektur unveraendert. Nur eskalieren wenn der
Repair eine architektur-signifikante Schuld oder ein Ownership-Problem aufdeckt.

## Implementierungspflichten

- Jede MDL-Aenderung wird vor Ausfuehrung validiert:
  `mxcli check <script>.mdl -p <project>.mpr --references`
- Keine MDL-Scripts im Chat zeigen — Aenderungen in Klartext beschreiben, Freigabe
  einholen, dann still ausfuehren
- Alle Bezeichner in MDL mit doppelten Anfuehrungszeichen quoten
- Betriebsmodus (CLOSED-AUTONOM / LIVE-SP-CURRENT / LIVE-SP-OTHER / AMBIGUOUS-SP-STATE)
  bestimmt die verfuegbaren Werkzeuge — Erkennungsalgorithmus: `policies/operating-mode.md`

## Security-Timing (D48)

| Zeitpunkt | Aktion | Grund |
|---|---|---|
| Bei CREATE ENTITY | Entity Access Rules sofort setzen (erstmal `*` auf alle Module Roles) | CE0066 sofort eliminiert |
| Waehrend Page/MF-Bau | Keine Access Rules | Development-Modus, entspanntes Bauen |
| Nach letztem Domain-Model-Item | Dedizierter Security-Pass | Realistischer Test mit echten Rollen vor Verifying |

Der Security-Pass umfasst:
- User Roles definieren/aktualisieren
- Page Access pro User Role setzen
- Microflow Access pro User Role setzen
- Demo Users aktualisieren
- Security Level auf Prototype oder Production setzen

Die `implementation-checklist.yaml` enthaelt Security-Items am Ende der Liste.
Das Quality-Gate prueft ob der Security Level mindestens Prototype ist.

## Artefakt-Timing

Pflege In-App-Dokumentation beim Anlegen oder Aendern des Artefakts, nicht gesammelt
am Sprintende:

- Module, Entities, Enumerationen und Associations erhalten eine Beschreibung
- Microflows und Nanoflows dokumentieren Zweck, Parameter und Ergebnis
- Fachliche Entscheidungen gehoeren nach `sprints/decisions.md`
- Storybezogene technische Details nach `planning/stories/`
