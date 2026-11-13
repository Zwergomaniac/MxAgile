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

## Task/Wave Decomposition

`Task` already has concrete semantics in `.mxagile/schemas/task.schema.json`: one bounded
action/change with `action`, status, optional `depends_on` and task-specific `test`. A Task
uses the existing checklist/task artifact and has no separate lifecycle, gate, or recovery
strategy. Verify it with the targeted check appropriate to that action.

A `Wave` groups one or more related Tasks into the smallest coherent, meaningfully
completable/recoverable outcome. **KEEP RELATED WORK TOGETHER.** The routine choice belongs
to the agent; do not ask the user whether ordinary work should be one Wave or two.

1. Derive concrete Tasks from the authorized work using existing checklist/task artifacts.
2. Group Tasks that share an outcome, context/dependencies, execution sequence, and compatible
  completion/verification in the same Wave.
3. Add a Wave only when a meaningful split creates a useful independent outcome or recovery
  point. A real dependency/gate, uncertainty result, checkpoint/recovery need, independent
  parallel outcome, or materially separate context/verification can justify that boundary.
4. Ask: "Would completing this split leave a useful intermediate result or recovery point?"
  If not, keep the Tasks in the same Wave.

Task count is only a soft decomposition check, never a threshold. Do not split just for multiple
files, tools, skills, tests, elapsed time, token use, or a possible subagent. Task/Wave boundaries
may inform delegation and verification but do not determine them; the existing delegation and
proportional test-workflow contracts remain authoritative. Escalate only when the choice affects
user-owned scope, acceptance meaning, destructive risk, or release strategy.

| Work shape | Default decomposition |
|---|---|
| Small policy/configuration change plus its direct test | One Task in one Wave. |
| Several restore/reconcile/consistency Tasks with one intended state | One Wave is valid, regardless of Task count. |
| Investigation that must decide whether implementation can proceed | Separate Waves when the investigation is its own useful gate/recovery point. |
| Feature with independently completable outcomes and a real dependency/acceptance boundary | Split only when completing a Wave is useful on its own. |
| Independent, separately verifiable outcomes | Separate Waves may support parallel work; possible delegation alone is not a split reason. |

Use only current sources: `execution-waves.md` for planned scope/dependencies, Tasks/checklists for
action and status, `process-state.yaml` for Wave phase/gates, `mission-state.yaml` for mission
criteria/blockers, and existing reports/campaigns for evidence. Mission remains the durable user
objective and may span Waves; an Acceptance Campaign groups verification within a Wave; optional
`workpackage_id`/delegation work packages are grouping or handoff details, not required planning
levels. Do not add a parallel Wave metadata store.

Record each Wave's intended outcome and a concise grouping/boundary rationale in the existing
`planning/execution-waves.md`: why its Tasks belong together, and, when Waves are split, which
meaningful outcome, dependency, gate, uncertainty, recovery, parallelism, or verification boundary
justifies the split. This is planning rationale, not lifecycle state; derive current/active/completed
status from the existing canonical lifecycle artifacts.

After interruption, use the existing lifecycle re-sync and evidence to reconstruct Wave progress;
do not invent another state model (`policies/lifecycle-resync.md`). A Wave completes only through
its existing implementation, verification, and acceptance lifecycle. A Wave by itself never
requires a Full Suite (`policies/test-workflow.md`).

### Waves after DONE and Wave registration

A Wave whose `process-state.yaml` phase is `done` is never reopened for later work. New or changed
authorized scope, a new revision and remediation after DONE are planned as a new Wave;
`Significance: LOCAL` is sufficient. Provenance to the older Wave stays in the existing records
(`Finding.wave_id` = affected Wave, `repair_task_id`, `Task.wave_id` = executing Wave); do not
rewrite the DONE Wave. While the affected Wave is not yet `done`, GAP repair stays part of its
verification cycle (`policies/gap-verification-repair.md`).

When a Wave is authorized (its entry in `execution-waves.md`), register it in the same step in the
canonical `planning/lifecycle/process-state.yaml` as a complete Wave block: `phase: discovery` and
`gate_to_refinement` / `gate_to_ready` with `result: not_recorded`. The optional `testability_gate`
and `acceptance_gate` are written when those gates run (`acceptance_gate.result` may be `pending`,
see `policies/autonomous-remediation.md`). `process-state.yaml` is then the complete
machine-readable Wave register and `execution-waves.md` stays the human plan. Do not add a second
Wave metadata store and do not register Waves retroactively from commits, timestamps or names.

If work is observed outside every registered Wave (for example all Waves are `done` and no Mission
is active), report that fact. Do not assign that work to a Wave from timestamps, Git proximity or
naming similarity.

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

## Semantische Erhaltung bei Mendix-Writes

Vor `REBUILD`, `REPLACE` oder struktureller Neu-Erzeugung eines bestehenden Artefakts:

1. Beobachte das Original und identifiziere seine semantischen Elemente, Parameter, Rollen,
   Rückgabewerte und Referenzen, soweit sie über das Modell oder generierten Code zugänglich sind.
   Prüfe insbesondere Microflow-/Nanoflow-Aktionen (einschließlich `ChangeObjectAction`),
   Navigation-/Client-/Page-Aktionen, Security-Elemente, Parameter-Mappings und Return Values.
2. Prüfe, ob das Zielwerkzeug alle unveränderten Elemente und gewünschten Änderungen ausdrücken
   kann. Ein erfolgreicher Toolaufruf beweist nur technischen Erfolg, nicht semantische Erhaltung.
3. Klassifiziere das Ergebnis als `LOSSLESS_SUPPORTED`, `PARTIALLY_SUPPORTED`,
   `UNSUPPORTED_ELEMENT` oder `NOT_OBSERVABLE`.

Bei `PARTIALLY_SUPPORTED` oder `UNSUPPORTED_ELEMENT` darf ein bestehendes Artefakt nicht
verlustbehaftet ersetzt werden: hart blockieren und einen nachweislich geeigneten Alternativpfad
verwenden. Bei `NOT_OBSERVABLE` keine semantische Vollständigkeit behaupten; vor einer
destruktiven Ersetzung anhalten und Beobachtbarkeit oder eine fachliche Entscheidung einholen.
Das Ergebnis ist als `SEMANTIC_COMPLETENESS_NOT_OBSERVABLE` auszuweisen.
Eine explizite Ausnahme erfordert die dokumentierte fachliche Entscheidung des zuständigen
Projektverantwortlichen. Keine universelle Model-Diff-Engine voraussetzen.

## Scope-basierte Mendix-Artefakt-Invarianten

Vor Abschluss nur die Invarianten prüfen, die vom tatsächlichen Wave-Artefaktscope betroffen sind:

- `EXECUTABLE_NANOFLOW_ROLE_INVARIANT`: Ein ausführbarer Nanoflow besitzt die laut
  akzeptiertem Security-Vertrag erforderlichen erlaubten Rollen.
- `REPLACEMENT_TARGET_INVARIANT`: Ersetzt eine Wave eine aktive Page, zeigen Navigation und
  relevante Navigations-Flows auf die neue aktive Page, nicht auf eine Backup-/ersetzte Page,
  sofern das nicht ausdrücklich beabsichtigt ist.
- `JS_ACTION_PARAMETER_INVARIANT`: User-Code referenziert exakt die tatsächlich generierten,
  case-sensitiven JavaScript-Identifier. Die Studio-Pro-Anzeige allein ist kein Beleg.
- `HTML_BRIDGE_MATERIALIZATION_INVARIANT`: Benötigte Templates und DOM-Ressourcen liegen
  innerhalb des tatsächlich importierten Bridge-Scopes oder werden nachweislich separat geladen.
  Der Root-Selector stammt aus dem projektspezifischen Bridge-Vertrag; keine konkrete ID global
  hardcoden.

Jede Invariante endet mit `PASS`, einem belegten Fehler oder `NOT_OBSERVABLE`. Bei
`NOT_OBSERVABLE` keine Annahme aus Namen oder Tool-Erfolg ableiten. Diese gezielten Checks
erweitern die vorhandenen Model-/Runtime-Prüfungen; sie lösen keinen globalen Artefakt-Scan aus.
Führe jede scopespezifisch anwendbare Invariante als ID in
`proof_points[].artifact_invariants` des bestehenden Test Contracts und ordne ihr die
erforderlichen Verification-Layer zu. Fehlende Beobachtbarkeit bleibt dort ein Evidence-Gap,
kein erfolgreicher Gate-Status.

## Mendix UserRole Identity in XPath

When XPath logic refers to a concrete application-level Mendix User Role, use Mendix's
documented role system variable rather than comparing `System.UserRole.Name` to free text.
Mendix documents these equivalent role-membership forms:

```xpath
[System.UserRoles = '[%UserRole_Developer%]']
[System.UserRoles/System.UserRole[id = '[%UserRole_Developer%]']]
```

The role token is generated for a User Role that exists in the app. Before authoring or repairing
one, inspect the actual role with the project-selected `mxcli describe -p <project.mpr> userrole <RoleName>` and
verify the token against the actual Mendix model/version. Never use wildcard, `contains()`,
substring, prefix, or suffix matching for role identity. `mxcli GRANT` binds a Module Role in
security metadata; it is not a substitute for checking an application User Role in XPath.

The documented token syntax does not, by itself, guarantee rename-aware refactoring in every
Studio Pro or mxcli version. After a User Role rename, re-inspect the role, update/rebind the token
as supported, and run the project's actual model/consistency validation. Do not claim `mxcli check`
validates embedded XPath unless that exact version demonstrably does so. An unresolved role token
or mismatch is a validation failure, never a fallback to string matching.

UserRole identity is not business capability. A capability such as `CanEditRegions` may depend on
the role plus organizational scope, KnowledgeContext, lifecycle, record status, or other approved
business rules. Keep those conditions explicit; replacing a role-name comparison must not remove
scope or lifecycle checks, nor trigger a blanket conversion to Entity Access.

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
