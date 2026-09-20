Jetzt klappt es. Ich kann die angehängte dfc-ai COPILOT-Edit.zip vollständig lesen und habe den aktuellen Stand gegen das Zielbild aus REPO-masterprompt.md und majorchange.md geprüft. Ergebnis: MxAgile ist konzeptionell deutlich vorangekommen, aber die neue Architektur ist derzeit ein Hybrid aus belastbarer Prozessschicht und mehreren noch prototypischen beziehungsweise defekten Lifecycle-Skripten.

Gesamturteil

Realistischer Reifegrad: etwa 55 bis 65 Prozent des angestrebten Zielbilds.

Diese Einschätzung ist meine technische Bewertung, keine im Repository hinterlegte Kennzahl. Der entscheidende Fortschritt ist, dass MxAgile nicht mehr nur aus einer Idee oder majorchange.md besteht: Die agentenagnostische Prozessarchitektur, spezialisierte Agents, Gates, Policies, Adapter, Mockup-/Page-YAML-Konzept, Mendix-Teststrategie und MB-Plattformregeln sind tatsächlich angelegt. Dagegen sind Init, Traceability, Refinement, Clarification, Planung, Tasks, Convergence und Brownfield Adoption noch nicht durchgängig produktionsfähig.

Nachweisbar umgesetzt
✅ DONE: Agentenagnostische MxAgile-Kernarchitektur

Unter .mxagile/ existiert eine klar abgegrenzte neutrale Prozessschicht mit Orchestrator, Skills, Agents, Policies, Plattformmodulen, Schemas, Templates, Adaptern, State und Versionierung. Die README beschreibt genau das gewünschte Modell: neutrale Fachlogik als Quelle und daraus generierte plattformspezifische Kopien für Claude Code, GitHub Copilot, Codex, Grok, OpenCode und Hermes.

Das ist ein wesentlicher Fortschritt gegenüber dem alten, stärker promptgebundenen Ansatz.

✅ DONE: Verbindlicher Delivery-Prozess mit Gates

Der Ablauf Intake → Discovery → Refinement → Ready → Implementing → Verifying ist konkret definiert. Besonders stark ist, dass Direktimplementierung ausdrücklich verhindert werden soll und Verifying nicht durch einen bloßen erfolgreichen Build ersetzt werden darf. Gate-Ergebnisse sollen in process-state.yaml dokumentiert werden.

✅ DONE: Spezialisierte Rollen statt eines Monolith-Agenten

Es sind fünf fachlich getrennte Agents vorhanden:

Discovery-Agent für Requirements, Modell und optional Board
UI-Agent mit Generate-, Analyze- und Verify-Modus
Refinement-Agent für Entscheidungen und Widersprüche
Implementation-Agent für check-listengesteuerte MDL-Umsetzung
Acceptance-Agent für Modellprüfung und Playwright-Journeys

Das entspricht deinem ursprünglichen Ziel einer echten Orchestrierung für Discovery, UI/UX, Implementierung und Abnahme.

✅ DONE: Mockup bleibt zentrales Discovery-Artefakt

Das System stärkt den gewünschten Dreiklang:

HTML-Mockup
    ↓ Playwright-Analyse
Page YAML / UI-Inventar
    ↓ zusammen mit Requirements
Implementierungscheckliste / Tasks
    ↓
Mendix-Implementierung
    ↓
UI- und Acceptance-Vergleich


Der UI-Agent muss Mockups im echten Browser ausführen, Zustände durchklicken, Screenshots erstellen und pro Seite ein schema-validierbares YAML-Inventar erzeugen. In Verifying wird dasselbe Inventar gegen die laufende Mendix-App geprüft.

✅ DONE: Mendix-native Trennung von WHAT/WHY und HOW

Die Prozessschicht entscheidet über Anforderungen, Phasen, Gates und Traceability. Die technische Mendix-Umsetzung bleibt bei mxcli, MDL und den projektlokalen .ai-context/skills/. Damit wurde gerade nicht der High-Code-orientierte Spec-Kit-Ansatz blind übernommen.

✅ DONE: Mehrstufige Verifikation ist sauber modelliert

Die Verifying-Phase trennt:

technisches Quality Gate mit Syntax, Lint, Mendix-Konsistenz, Docker und Security,
UI-Soll-Ist-Prüfung,
fachliche Acceptance-Prüfung mit Modellinspektion und Browser-Journeys.

Bei Fehlern werden gezielt nur betroffene Checklisten-Items zurückgeführt. Das ist deutlich reifer als ein einfacher „Build erfolgreich“-Flow.

✅ DONE: MB-spezifische Plattform- und Governance-Schicht

Glossar und Modulwissen für MB_SSO, MB_UI, MB_NoAccess, MB_Feedback und MB_Governance sind umfangreich vorhanden. Die Regeln adressieren Rollenpräfix, MBUser-Nutzung, Layouts, Design Tokens, unveränderliche Plattformmodule und Reuse-First.

✅ DONE: Agent-Instruktionen und technische Skills werden getrennt

AGENT.md ist als projektweite Regelquelle vorgesehen. apply-project-agent-instructions.ps1 verteilt diese Regeln, ohne die durch mxcli init erzeugten technischen Referenzen einfach zu ersetzen. setup-agent-system.ps1 bildet dafür einen gemeinsamen Einstiegspunkt.

✅ DONE: Schutz gegen ungeprüfte MDL-Ausführung

mxcli-exec-guarded.ps1 prüft Wave-Zuordnung und Gate-Status und verlangt bei fehlenden Gates explizite Freigabe. Das ist ein konkreter technischer Guard und nicht nur eine Prompt-Regel.

Teilweise umgesetzt
🟡 PARTIAL: Spec-Kit-inspirierter Artifact Lifecycle

requirements/, specs/, planning/tasks/, waves/, constitution.md, State und Trace-Index sind vorhanden. Allerdings existiert parallel weiterhin der alte Flow über planning/stories/ und planning/checklists/. Dokumentation und Skripte verwenden beide Welten gleichzeitig.

Beispiele:

.mxagile/orchestrator.md arbeitet noch mit planning/stories und wave-bezogenen Implementation Checklists.
README.md beschreibt requirements, specs und planning/tasks.
planning/tasks/README.md trägt noch die Überschrift „Checklists“.
requirements/README.md beschreibt weiterhin Story-Spezifikationen.
majorchange.md erklärt die neue Welt bereits teilweise als umgesetzt.

Deklaration: Architektur vorbereitet, Migration noch nicht konvergiert.

🟡 PARTIAL: Page YAML als First-Class Artifact

Ein page.schema.json und der UI-Agent-Workflow existieren. Das Schema selbst ist aber noch relativ schmal. Außerdem fehlt im ZIP ein echtes erzeugtes Page-YAML-Beispiel. planning/ui-inventory/ enthält nur eine README.

Deklaration: Methode und Schema vorhanden, End-to-End-Nachweis fehlt.

🟡 PARTIAL: Refinement Engine

mxagile-refine.ps1, refine.py, Hashing, HTML-Parsing, Veränderungstypen und mockup-report.md sind vorhanden. Der Bericht erkennt beispielsweise eine Änderung am H2-Inhalt. Das ist ein funktionierender Anfang.

Gegen das Zielbild fehlen aber belastbar:

vollständige Baseline-Verwaltung
Beziehungen zu Page YAML, Requirements, Specs, Plänen, Tasks und Mendix-Artefakten
„definitely/probably/potentially affected“
kontrollierte Reconciliation
Stale-Markierungen
Schutz manuell gepflegter Artefakte
Nachweis von Security-, Data-, Validation- und Integration-Änderungen

Deklaration: SCAFFOLDED/PARTIAL, noch keine vollständige Refinement Engine.

🟡 PARTIAL: Traceability

build_trace_index.py, trace.py, Wrapper und trace-index.json existieren. Der Index kann Dateien hashen und einige Artefakttypen erfassen. trace.py kann Requirement-zu-Spec-Beziehungen vereinfacht verfolgen.

Aber:

Aufgaben werden im Index initialisiert, jedoch nicht eingelesen.
Mockups stehen separat in der bestehenden Indexdatei, werden vom Builder aber nicht erzeugt.
Der Builder scannt nur *.yml, während zahlreiche zentrale Artefakte Markdown oder YAML mit anderer Endung sind.
Beziehungen sind auf ein einzelnes Feld Relates reduziert.
Page YAML, Plan, Validation, Mendix-Artefakte und mehrere Requirement-Referenzen fehlen.

Deklaration: technischer Proof of Concept, noch kein vollständiger Traceability Graph.

🟡 PARTIAL: Global Analyze und Convergence

analyze.py prüft aktuell nur verwaiste Specs und ungenutzte Requirements. converge.py kontrolliert nur, ob pro Requirement eine Datei nach dem Muster validation/TC-REQ-XYZ.md existiert.

Damit sind beide Namen deutlich weiter als die tatsächliche Funktion:

Analyze prüft noch nicht die gesamte Artifact Chain.
Converge prüft weder Page-YAML-Ausrichtung noch Spec-, Plan-, Task-, Mendix- oder Teststatus.
Eine vorhandene Evidence-Datei wird inhaltlich nicht bewertet.
Es werden keine gezielten Resttasks erzeugt.

Deklaration: SCAFFOLDED, nicht als echte Konvergenz deklarierbar.

🟡 PARTIAL: Company Layers

Ein Mercedes-Benz-Layer mit Manifest, Glossar, Plattformmodulen und Dokumentation existiert. Auch mxagile-add-layer.ps1 ist vorhanden. Gleichzeitig liegen dieselben Inhalte noch an mehreren Stellen:

.mxagile/modules/
.mxagile/GLOSSARY.yaml
company-layers/mercedes-benz/
projektnahes glossary.yaml
projektnahes platform-modules.yaml

Dadurch ist die gewünschte klare Ownership noch nicht erreicht. Außerdem verwendet das Skript .mxagile/layers, während die eigentlichen MB-Daten prominent unter company-layers/ liegen.

Deklaration: Konzept vorhanden, Konsolidierung erforderlich.

🟡 PARTIAL: Greenfield Init

mxagile-init.ps1 installiert Python-Abhängigkeiten, sucht mxcli.exe, legt Verzeichnisse an und erkennt vorhandene Layers.

Es fehlen beziehungsweise sind nicht nachweisbar:

vollständige Template-Kopie
Baseline-Konfiguration
robuste Projektklassifikation
partielle Migration
non-interactive Parameter
echte Layer-Auswahl und Anwendung
Schema-/Template-Installation aus einer kanonischen Quelle
Tests für wiederholte Ausführung

Deklaration: Basisscaffold vorhanden, kein fertiges Greenfield Bootstrap.

Nicht umgesetzt oder blockiert
❌ MISSING: Brownfield Adoption

Die Dokumentation und brownfield-adoption.md beschreiben den Ansatz. Eine in README, majorchange.md und TODO erwartete mxagile-adopt.ps1 ist im ZIP jedoch nicht vorhanden.

Damit ist das für dich besonders wichtige Ziel**„Altprojekte realistisch migrieren“ noch nicht implementiert**.

❌ MISSING: Vollständige Framework-Test-Suite

Vorhanden ist ein anwendungsbezogener Playwright-Test für einen Demo-User-Switcher. Die in TODO und Masterprompt geforderten Tests für Init, Adopt, Refine, Traceability und Migration fehlen. specs/good.yml und bad.yml sind lediglich kleine Testfixtures.

❌ MISSING: Wirklich lebender Spec-Lifecycle

Feature Specs existieren als Konzept und Beispiel. Es gibt aber noch keinen belastbaren Mechanismus für:

Versionierung akzeptierter Anforderungen
Stale-Propagation
kontrolliertes Flow-back aus Implementierungsentdeckungen
Reconciliation ohne Überschreiben
genehmigte Baselines
Spec-zu-Plan-zu-Task-Invalidierung
❌ MISSING: Funktionsfähige Plan-/Task-Pipeline

mxagile-plan.ps1, mxagile-plan-wave.ps1 und mxagile-tasks.ps1 existieren, sind aber nicht auf dem Niveau des Zielbilds. Die Wave-Planung erzeugt einen Prompt, der pauschal ein konsolidiertes Domain-Model-MDL erstellen soll. Das ist deutlich enger als ein Mendix-nativer Plan mit Pages, Microflows, Security, Navigation, Integrationen und Tests.

Kritische Findings
🔴 P0: Mehrere Skripte wirken syntaktisch beschädigt oder abgeschnitten

Im aktuellen ZIP zeigen mehrere PowerShell-Dateien offensichtlich fehlende Ausdrücke, unvollständige Pipelines, falsche Join-Path-Aufrufe oder fehlende Blöcke. Besonders auffällig:

install-mxcli.ps1
generate-dfc-platform-skills.ps1
mxagile-clarify.ps1
mxagile-reconcile.ps1
mxagile-tasks.ps1
reset-testing-instance.ps1
run-docker-isolated.ps1

Das passt zu deinem heutigen Parserfehler beim mxcli-Installer. Ich würde diese Dateien nicht als einsatzfähig deklarieren, bevor sie mit dem PowerShell-Parser und Smoke-Tests geprüft wurden.

🔴 P0: Sicherheitsproblem in .env.mendix.example

Die Beispielkonfiguration enthält ein konkretes Admin-Passwort. Auch wenn es ein Demo-Wert sein soll, sollte eine versionierte Beispieldatei keinen realistisch nutzbaren Standardwert enthalten. Stattdessen besser:

MENDIX_APP_ADMIN_PASSWORD=


oder ein expliziter nicht lauffähiger Platzhalter.

🔴 P1: Namensdrift .MxAgile versus .mxagile

Dokumentation und Skripte verwenden unterschiedliche Groß-/Kleinschreibung. Auf Windows fällt das oft nicht auf, im Devcontainer/Linux jedoch schon. Das kann genau dort Pfade brechen, wo du plattformübergreifend arbeiten möchtest.

Empfehlung: ein kanonischer Name, bevorzugt .mxagile, und ein einmaliges Migrationsskript.

🔴 P1: Widersprüchliche Tool- und Sicherheitsregeln

Beispiele:

AGENTS.md sagt, mxcli liege im Projektroot und müsse mit ./mxcli aufgerufen werden.
Andere Skripte erwarten mxcli im PATH.
run-docker-isolated.ps1 verlangt, dass Studio Pro vollständig geschlossen ist.
Die Agentenregeln unterscheiden dagegen projektspezifisch zwischen Live-SP und Closed-Autonom.
majorchange.md beschreibt neue Verzeichnisse als eingeführt, während der produktive Orchestrator noch alte Pfade nutzt.

Diese Widersprüche erhöhen die Wahrscheinlichkeit, dass verschiedene Agents denselben Prozess unterschiedlich ausführen.

🟠 P1: Veraltete Dokumentation und Altstrukturen

docs/installation.md, docs/waves.md, README.md, majorchange.md, planning/README.md und der aktuelle Orchestrator beschreiben teilweise unterschiedliche Systeme. Dazu kommen company-layers/ und .mxagile/layers/ sowie alte und neue Planning-Artefakte parallel.

🟠 P2: Offensichtlicher Sample-/Restcode

WebScraper.py mit einem öffentlichen Books-to-Scrape-Beispiel gehört nicht erkennbar zum Kernsystem. Ebenso sind specs/good.yml, specs/bad.yml und das reine Login-Mockup klar Testartefakte, aber nicht sauber als Fixtures isoliert.

Fortschrittsdeklaration gegenüber dem Masterprompt
Phase A: Repository Analysis

DONE
 Die Architektur wurde analysiert und durch majorchange.md sowie README-Strukturen dokumentiert.

Phase B: Documentation Baseline

DONE, aber veraltet
 majorchange.md ist umfangreich, entspricht aber nicht überall dem tatsächlichen Implementierungsstand.

Phase C: Foundation

PARTIAL bis weitgehend DONE
 Version, State, Constitution-Scaffold, Schemas, Templates, neutrale Prozessschicht und Adapter existieren.

Phase D: Init and Adopt

Init PARTIAL, Adopt MISSING

Phase E: Traceability

PARTIAL

Phase F: Discovery 2.0

Architektur DONE, operative End-to-End-Belege PARTIAL

Phase G: Refinement

SCAFFOLDED/PARTIAL

Phase H: Spec Lifecycle

SCAFFOLDED

Phase I: Plan/Tasks

SCAFFOLDED, derzeit nicht robust

Phase J: Global Analysis

SCAFFOLDED

Phase K: mxcli Integration

DONE in der Architektur, PARTIAL in Skriptrobustheit

Phase L: Validation/Convergence

Mendix-Verifikation weitgehend DONE, Convergence SCAFFOLDED

Phase M: Agent Adapters

Claude/Copilot/Codex weitgehend DONE, OpenCode/Hermes nur Stub

Phase N: Framework Tests

MISSING

Phase O: Documentation Finalization

MISSING/PARTIAL

Meine klare Priorisierung
Alle Skripte parserfest machen und Smoke-Tests ergänzen.
.MxAgile/.mxagile sowie alte/neue Artifact-Pfade konsolidieren.
Eine einzige kanonische Lifecycle-Linie festlegen.
Brownfield adopt tatsächlich implementieren.
Trace Index zu einem echten Graphen erweitern.
Refinement mit Baseline, Impact und kontrollierter Reconciliation vervollständigen.
Plan/Tasks Mendix-nativ neu ausrichten, nicht aus MDL per Semikolon ableiten.
Convergence auf echte Coverage und Validation Evidence erweitern.
Framework-Test-Suite für Init, Adopt, Refine, Trace und Migration aufbauen.
Erst danach README, majorchange.md und TODO auf den realen Stand synchronisieren.
Kurzfazit

Das Projekt ist nicht gescheitert und auch kein bloßer Dokumentationsentwurf mehr. Die wichtigste Architekturentscheidung ist gelungen: MxAgile bleibt Mendix-nativ, mockupgetrieben, agentenagnostisch und trennt Prozesslogik von mxcli-Engineering. Der große offene Block ist nun weniger konzeptionell als technisch: Die Lifecycle-Skripte und Artefaktpfade müssen auf eine konsistente, getestete Implementierung zusammengeführt werden.