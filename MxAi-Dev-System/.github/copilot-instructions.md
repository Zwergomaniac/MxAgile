<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->
# [PROJEKTNAME] — Verbindliche Agentenregeln

> **Single Source of Truth:** Diese Datei definiert die projektweiten Regeln fuer
> alle AI-Agenten. `AGENTS.md` und `CLAUDE.md` sind ausschliesslich Einstiegspunkte
> und werden nach `mxcli init` mit `./scripts/apply-project-agent-instructions.ps1`
> um die Regeln aus dieser Datei ergaenzt.
>
> **Projektkontext:** siehe `projekt.md`.
>
> **Setup pruefen:** Falls `projekt.md` noch TODO-Platzhalter enthaelt oder `.ai-context/`
> nicht existiert, ist das Agent-Setup unvollstaendig. Fuehre dann `mxcli init` aus und
> anschliessend `./scripts/apply-project-agent-instructions.ps1`. `mxcli init` erzeugt bzw. aktualisiert die
> MDL-Skills und Tool-Konfigurationen unter `.ai-context/` und `.claude/`; das Skript
> fuegt danach die Projektregeln in die erzeugten Einstiegspunkte ein, ohne die mxcli-
> Referenz zu ersetzen. Eine `.mcp.json` ist nur fuer eine
> Live-MCP-Anbindung an Studio Pro erforderlich, nicht fuer die lokale MDL-Arbeit.
> Fuer die Board-Synchronisierung `.env.mendix.example` nach `.env.mendix` kopieren;
> Zugangsdaten bleiben lokal und werden niemals gelesen, ausgegeben oder versioniert.
> Diese Datei gilt fuer generische AI-Agenten (GitHub Copilot, OpenAI Codex, etc.).
> Fuer tool-spezifische Regeln: `CLAUDE.md` (Claude Code) - `skillssource/AGENTS.md` (Maia).

---

## Multi-Agent-Struktur

| Agent | Instruktionsdatei | Gemeinsame Basis |
|---|---|---|
| Claude Code (VS Code) | `CLAUDE.md` -> `AGENT.md` | `projekt.md`, `.dfc-ai/` |
| Maia (Studio Pro) | `skillssource/AGENTS.md` | `projekt.md` |
| GitHub Copilot / Codex | `AGENTS.md` -> `AGENT.md` | `projekt.md`, `.dfc-ai/` |
| Concord MCP | `.concord/project-memory.md` | `projekt.md` |
| DFC-AI Prozess-Agenten | `.dfc-ai/agents/` (generiert) | `.dfc-ai/orchestrator.md` |

---

## Verbindlicher DFC-AI-Workflow — keine eigenmächtige Abkürzung

**Hintergrund:** In einem Referenzprojekt wurden mehrere Waves direkt implementiert,
ohne Discovery (`dfc-discovery-agent`/`dfc-ui-agent`, UI-Inventar) oder Verifying
(`dfc-ui-agent`/`dfc-acceptance-agent`, Wave-Report) zu durchlaufen. Ergebnis:
kein Mockup-Abgleich, unentdeckte UI-Abweichungen, Statusdrift in
`.concord/scratch/process-state.yaml`. Diese Regeln verhindern die Wiederholung:

1. **Phasenfolge ist bindend, kein Direktsprung.** Jede Story/Wave durchlaeuft
   Discovery → Refinement → Ready → Implementing → Verifying gemaess
   `.dfc-ai/orchestrator.md`. Ein Agent implementiert niemals direkt aus einer
   Anforderung heraus, ohne vorher zu pruefen, in welcher Phase sich die
   betroffene Wave laut `.concord/scratch/process-state.yaml` befindet.
2. **Vor der Implementierung:** Wenn Discovery (inkl. UI-Inventar unter
   `planning/ui-inventory/`) fuer die Wave nicht abgeschlossen ist, implementiert
   der Agent NICHT einfach weiter. Er sagt dem Entwickler explizit und konkret,
   was fehlt und was das bedeutet (z. B. "kein Mockup-Abgleich, Risiko: die Seiten
   entsprechen ggf. nicht dem Kunden-Mockup und muessen spaeter nachgearbeitet
   werden") und holt eine ausdrueckliche Ausnahme-Freigabe **im selben Turn** ein,
   bevor er weitermacht. Schweigen oder implizite Fortsetzung gilt nicht als
   Freigabe.
3. **Nach der Implementierung:** Eine Wave gilt erst als abgeschlossen, wenn
   Verifying durchlaufen wurde (Quality-Gate + UI-Agent + Acceptance-Agent,
   `planning/wave-reports/`). "Baut fehlerfrei" / "mxcli docker check ohne
   Fehler" ist ausdruecklich KEIN Ersatz fuer den UI-/Akzeptanz-Abgleich und darf
   dem Entwickler nicht als vollstaendige Bestaetigung dargestellt werden.
4. **Ausnahmen sind die Ausnahme.** Ein Phasen-Ueberspringen ist ausschliesslich
   als "begruendete Ausnahme mit ausdruecklicher Entwicklerfreigabe" zulaessig
   (siehe Orchestrator, Abschnitt "Uebergaenge und Ausnahmen"). Diese Freigabe
   wird eingeholt, bevor implementiert wird — nicht im Nachhinein rationalisiert,
   nachdem der Entwickler nachfragt.
5. **Zustand ehrlich fuehren.** Nach jeder Phase aktualisiert der Agent
   `.concord/scratch/process-state.yaml` mit dem tatsaechlichen Stand. Eine
   Abweichung zwischen dieser Datei und der Realitaet ist selbst ein Fehlerfall
   und wird dem Entwickler aktiv gemeldet, nicht stillschweigend uebergangen.

---

## Agenten-Betriebsmodus: Live-SP vs. Autonom (Selbstauskunft-Pflicht)

Ob ein Agent neben einer live laufenden Studio-Pro-Instanz arbeitet oder autonom auf
einem geschlossenen Modell, laesst sich nicht zuverlaessig aus Prozess- oder Lock-Zustand
ableiten: ein vergessenes SP-Fenster taeuscht einen Live-Zustand vor, obwohl der Nutzer
eigentlich autonom aus VS Code arbeiten will; ein haengender Lock kann ohne aktive Nutzung
bestehen bleiben. Die Unterscheidung erfolgt deshalb primaer ueber eine Selbstauskunft,
nicht ueber eine Systemvermutung.

1. Jeder Agent (Concord-CLI in Mendix, GitHub Copilot CLI, VS Code Copilot, Claude Code,
   Maia) fragt zu Sessionbeginn — oder sobald der Betriebsmodus im Verlauf unklar wird —
   explizit beim Nutzer nach: *"Arbeitest du gerade live mit einer geoeffneten Studio-Pro-
   Instanz an diesem Projekt, oder ist Studio Pro geschlossen und ich arbeite autonom?"*
2. Die Antwort wird als Session-Zustand festgehalten (`LIVE-SP` oder `CLOSED-AUTONOM`) und
   bestimmt fuer die restliche Session, welche Regeln aus diesem Dokument gelten. Sie wird
   nicht in einer versionierten Projektdatei gespeichert und bei jeder neuen Session neu
   erfragt.
3. **`LIVE-SP`**: nur read-only `SHOW`/`DESCRIBE`/`project-tree --json` direkt am
   kanonischen Modell. Schreibende Aktionen (`mxcli exec`, Security-Schreibvorgaenge)
   nur nach Ruecksprache mit dem Nutzer, da Studio Pro gleichzeitig auf das Modell
   zugreift.
4. **`CLOSED-AUTONOM`**: `mxcli docker check`, Security-Schreibvorgaenge, Speichern und
   volle MDL-Bearbeitung sind direkt am kanonischen Modell erlaubt, weil kein Live-Lock-
   Konflikt bestehen kann.
5. Ein technischer Zustandscheck (laufender `studiopro`-Prozess, `.mpr.lock`) bleibt als
   zusaetzliches Sicherheitsnetz bestehen, ersetzt die Selbstauskunft aber nicht.
   Widerspricht der gemessene Zustand der Selbstauskunft — Nutzer sagt "geschlossen", aber
   ein `studiopro`-Prozess laeuft nachweislich gegen dieses Projekt, oder umgekehrt — fragt
   der Agent vor jeder riskanten Aktion aktiv nach, ob ein Fenster vergessen wurde oder der
   Modus zu korrigieren ist, statt den Widerspruch stillschweigend aufzuloesen.
6. Ohne eindeutige Selbstauskunft und bei fortbestehendem Widerspruch gilt im Zweifel
   `LIVE-SP` als sichererer Default, bis der Nutzer den Modus bestaetigt.

---

## Allgemeine Entwicklungsregeln

- **Commits vorbereiten, dann bestaetigen lassen** — Agenten duerfen Staging und Commit-Vorschlag vorbereiten und fragen vor `git commit` nach ausdruecklicher Freigabe. Im explizit aktivierten Autopilot-Modus darf der Agent diese Freigabe selbst bestaetigen und den Commit ausfuehren. `git push` bleibt manuell.
- **`[Spec.md]` niemals modifizieren** — ist die unveraenderliche Produkt-Spezifikation
- Domain-Model: Englisch, PascalCase
- FOSS-Marketplace-Module vor Eigenentwicklung pruefen
- Annahmen: ASSUMPTION | Offene Entscheidungen: DECISION REQUIRED
- **Modul-Transferfaehigkeit:** Bei jedem neuen Modul pruefen: "Ist das applikationsspezifisch
  oder generisch wiederverwendbar? Wenn spezifisch: ist die Grenze sauber genug fuer ein
  Ersatzmodul?" Entity-Namen generisch halten (z.B. `employee`, `Group`, `Facility` statt
  produktspezifischer Begriffe). UX-Entscheidungen (Touch-Targets, Layout-Dichte, Farbschema)
  gehoeren ins UI-Modul, nicht in Fachmodule.
- **Mockup-Strategie:** Ein lebendes SPA-Mockup (`input-resources/ui-ux/`) mit zwei
  Detailstufen: Full Fidelity (interaktiv, alle Zustaende, realistische Daten) fuer aktuelle
  und naechste Sprints — Wireframe (grau, Sprint-Badge, nur Navigation funktional) fuer
  spaetere Sprints. Wireframes werden beim Erreichen des jeweiligen Sprints hochgezogen.

---

## Wo was nachschlagen

| Thema | Datei |
|---|---|
| Projektziel, Architektur, Module | `projekt.md` |
| Prozessfluss, Phasen, Gates | `.dfc-ai/orchestrator.md` |
| Prozess-Policies (Safety, Backlog, Tests) | `.dfc-ai/policies/` |
| Prozess-Skills (Discovery, Refinement, Gates) | `.dfc-ai/skills/` |
| mxcli-Befehle, Concord MCP, Tool-Routing | `CLAUDE.md` |
| Aktuelle User Stories und Sprint-Kontext | `sprints/generated/` nach `scripts/sync-epics-stories.ps1` |
| Synchronisierungsablauf | `sprints/sync-workflow.md` |
| Abgeleitete Spezifikationen und Tests | `planning/` nach `scripts/reconcile-derived-artifacts.ps1` |
| Sprint-Roadmap (Spec-Uebersicht) | `planning/sprint-roadmap.md` |
| Mockup-Strategie und Screen-Zuordnung | `planning/mockup-gesamtplan.md` |
| Mockup-Validierungsbericht | `planning/mockup-validation-report.md` |
| Mendix-Programmierregeln, Domain-Konventionen | `skillssource/AGENTS.md` |
| Architekturentscheidungen | `sprints/decisions.md` |
| Mercedes-Benz Plattformmodule | `.dfc-ai/modules/platform-modules.md` |
| Modul-spezifisches Plattformwissen | `.dfc-ai/modules/` |
| Projekt-input-Resourcen | `input-resources/` |

### Projektlokale Mendix-Skills

Der gesamte Ordner `.ai-context/skills/` ist die projektlokale Quelle fuer Mendix-
Arbeitsanweisungen und Skills. Vor einer passenden Aufgabe liest der Agent zuerst
`.ai-context/skills/README.md` und bei agentenbezogenen Themen
`.ai-context/skills/agents.md`, sofern diese Dateien vorhanden sind. Danach liest er
den konkreten Skill, zum Beispiel `generate-domain-model.md`, `manage-security.md`,
`test-app.md` oder `bulk-widget-updates.md`. Die Skills sind projektlokale
Referenzdokumente und werden nicht als globale Copilot-Skills vorausgesetzt.

## Plattformmodule

Vor Eigenentwicklung immer zuerst `.dfc-ai/modules/platform-modules.md` pruefen.

Mercedes-Benz Plattformmodule sind zu bevorzugen.

Modifikationen an Plattformmodulen sind nicht erlaubt.

### Input Resources

Der Ordner `input-resources/` enthaelt verbindliche Eingabeartefakte wie:

- interaktive HTML-Mockups
- UI-/UX-Referenzen
- fachliche Anforderungen
- Prozessdarstellungen
- Screenshots und weitere Referenzdateien

Vor Planung oder Implementierung einer Story muss geprueft werden, ob relevante
Artefakte in `input-resources/` vorhanden sind.

Relevante Eingabeartefakte haben Vorrang vor Annahmen des Agenten.

### Mendix Epics Board und abgeleitete Artefakte

Regeln fuer Board-Synchronisierung, abgeleitete Artefakte und Wave-Traceability:
siehe `.dfc-ai/policies/backlog-sync.md`.

### HTML-Mockups

Regeln fuer Mockup-Analyse mit Playwright: siehe `.dfc-ai/policies/mockup-analysis.md`.
Details zur Ablage und Verwendung: `input-resources/README.md`.

@projekt.md
@.claude/setup.md

> **Projektkontext:** `projekt.md` und `setup.md` sind oben via @-Include geladen.
> **Prozesssteuerung:** `.dfc-ai/orchestrator.md` definiert den Prozessfluss.
> **Policies:** `.dfc-ai/policies/` enthaelt wiederverwendbare Prozessregeln.
> **Setup:** `scripts/setup-agent-system.ps1` regeneriert alle Plattform-Skills.

---

## mxcli-Exklusiv (SP muss geschlossen sein fuer Writes)
Security-Rollen / User Roles / Demo Users / Security Level, Nanoflows CREATE,
View Entities (OQL), Indexes, REVOKE, MOVE, OData, Java Actions,
Navigation mit rollenbasierten Home-Pages, `mxcli lint`, `mxcli docker check`

### Entity-Security-Checkpoint und Wave-Schnitt

`CE0066` entsteht typischerweise nach strukturellen Domain-Model-Aenderungen, wenn
Mendix die Entity-Access-Metadaten als veraltet markiert. Betroffen sind insbesondere
neue oder geloeschte Entitaeten, neue oder entfernte Attribute und Associations sowie
Aenderungen an Generalisierung oder Entity-Security. Nach einem gebuendelten
Modellabschnitt `mxcli docker check` ausfuehren; bei `CE0066` **fragt der Agent den
Entwickler nicht, ob Studio Pro geoeffnet werden soll** — er prueft den Zustand selbst
mit `scripts/check-studio-pro-status.ps1` und oeffnet bei Bedarf selbst mit
`scripts/open-studio-pro.ps1` (siehe Ablauf unten). Fuer den Entwickler bleibt nur:
in jedem betroffenen Domain Model **Update security** klicken, speichern, Studio Pro
schliessen. Danach wiederholt der Agent den Check.

Waves werden deshalb so geschnitten, dass zusammengehoerige Domain-Model-Aenderungen
in einem Modellabschnitt liegen. Pro Wave gibt es hoechstens ein bewusstes
Entity-Security-Gate. Reine Seiten-, Microflow-, Test- und Dokumentationsarbeit folgt
erst nach diesem Gate und loest normalerweise kein neues `CE0066` aus. Alle Waves werden
grob als Roadmap geplant; nur die naechste Wave wird vollstaendig detailliert und
umgesetzt.

`mxcli docker check` darf direkt auf dem kanonischen Checkout ausgefuehrt werden.
Fuer reine MDL-/Referenzvalidierung genuegt
`mxcli check <script>.mdl -p <project>.mpr --references`.

Mehrere Studio-Pro-Instanzen fuer andere Projekte duerfen parallel geoeffnet bleiben.
Vor jedem Start prueft der Agent selbststaendig mit
`scripts/check-studio-pro-status.ps1`, ob dieses Projekt bereits offen ist (Exit-Code
0 = offen, 1 = geschlossen, 2 = Fehler) — er fragt dafuer nicht beim Entwickler nach.
Ist es bereits offen, startet er nichts neu und geht direkt zum Update-security-Schritt
ueber. Andernfalls oeffnet er es selbst mit `scripts/open-studio-pro.ps1 -WaitForClose`;
fuer den Entwickler bleibt dann ausschliesslich der Klick auf **Update security**,
Speichern und Schliessen. Der Launcher wartet nur auf die von ihm gestartete PID und
blockiert oder beendet keine anderen Studio-Pro-Instanzen.

### Wave-Report und Board-Traceability

Siehe `.dfc-ai/policies/backlog-sync.md` fuer Wave-Report-Regeln und Board-Traceability.
Wave-relevante Commits nennen die Story-IDs explizit:
`feat: implement foundation [{STORYPREFIX}-123] [{STORYPREFIX}-124]`.

### Docker-/Playwright-Test

Docker- und Playwright-Tests laufen ueber `scripts/run-docker-isolated.ps1` direkt
auf dem kanonischen Modell. Der Runner startet Docker mit einem Port-Offset.

Nach erfolgreichem Docker-Build und healthy Mendix-Container wird der integrierte
Playwright-Browser-Test als naechster Agentenschritt gegen die ausgegebene App-URL
ausgefuehrt. Die lokalen Werte `MENDIX_APP_TEST_USERNAME` und
`MENDIX_APP_TEST_PASSWORD` aus `.env.mendix` werden nur zur Laufzeit verwendet und
niemals ausgegeben, in MDL geschrieben oder versioniert.

Wenn MxBuild oder der Mendix-Konsistenzcheck `CE0066` meldet, muss **Update security**
im kanonischen Originalmodell ausgefuehrt werden. Ablauf: Der Agent prueft mit
`scripts/check-studio-pro-status.ps1`, ob das Projekt bereits offen ist, und oeffnet es
bei Bedarf selbst mit `scripts/open-studio-pro.ps1` — ohne Rueckfrage beim Entwickler.
Fuer den Entwickler bleibt nur: im betroffenen Domain Model **Update security**
ausfuehren, speichern, Studio Pro schliessen. Danach Commit, danach
Docker-/Playwright-Test erneut ausfuehren.

Bei MB_SSO-Konfiguration `MB_SSO.CONST_UserroleAppname` pruefen. Wenn sie leer oder
nicht einem eindeutigen 3-5-stelligen Uppercase-Kuerzel entspricht, das Kuerzel vor dem
Anlegen fachlicher Projektrollen festlegen. Projektrollen folgen dem Muster
`<APPSHORT>_<RoleName>`. Danach alle Projektrollen gegen dieses Schema pruefen.
Abweichende Approllen dem Entwickler mit Umbenennungsvorschlag vorlegen und erst nach
seiner Bestaetigung umbenennen oder migrieren.

---

# CONCORD SAFETY RULES (non-negotiable)
- Version-control write policy: agents may prepare staging and commit proposals. Before `git commit`, ask for explicit confirmation unless Autopilot mode is explicitly enabled. In Autopilot mode, the agent may self-confirm and run `git commit`. `git push` remains user-driven.
- NEVER run destructive version-control commands without explicit user request: `git/hg checkout`, `reset`, `clean`, `stash`, `merge`, `rebase`, `push`.
- NEVER delete or destructively modify model elements without EXPLICIT user confirmation in the SAME turn
- Before ANY destructive or irreversible operation: state exactly what will change, get confirm
- MODEL writes: SP-MCP directly first. Concord's write-ladder is FALLBACK only.

---

# Mendix Project: [PROJEKTNAME]

## Communication Style
- **Never show raw MDL scripts in chat.** Describe changes in plain language, get approval, then execute silently.
- **Always quote identifiers** in MDL with double quotes (`"Name"`).

## mxcli Location
<!-- TODO: Pfad zur mxcli-Installation -->
`mxcli` is available in PATH. Usage: `mxcli -p App.mpr -c "COMMAND"`

## Gemeinsame Dateien und lokaler Zustand

Versionieren: Mendix-Modell und Quellcode, `AGENT.md`, Projekt-/Prozessdokumentation,
`.ai-context/`, `.claude/`, `.devcontainer/`, `.playwright/`, `.mxcli/widgets/`,
`planning/` ausser `planning/generated/` sowie Skripte und Beispielkonfigurationen.

Lokal halten: `.env.mendix`, `.mcp.json`, `.codex/`, `.grok/`, `.mxcli/catalog.db`,
`sprints/generated/`, `planning/generated/`, Build-/Runtime-Ausgaben, IDE-Benutzerdateien
und Mendix-Locks. Concord-Bridge-Tokens und MCP-Clientkonfigurationen bleiben lokal.
Lokale Dateien weder committen noch loeschen, sofern nicht ausdruecklich beauftragt.

## MDL Validation

Before presenting any MDL change, validate its script:

```powershell
mxcli check script.mdl
mxcli check script.mdl -p App.mpr --references
```

Use `.ai-context/skills/check-syntax.md` before executing an MDL script. For full
project consistency checks, set up mxbuild with `mxcli setup mxbuild -p
App.mpr` and use the generated `mx` command.

Wenn eine Konsistenzpruefung `CE0066` meldet: zuerst `scripts/check-studio-pro-status.ps1`
ausfuehren (kein Nachfragen beim Entwickler, ob Studio Pro offen ist), dann bei Bedarf
`scripts/open-studio-pro.ps1`. Der Entwickler klickt in Studio Pro im betroffenen
Domaenenmodell **Update security**, speichert, schliesst Studio Pro wieder und der Agent
startet danach die Konsistenzpruefung erneut.

## Before Writing MDL Scripts
Read the relevant skill file first:
- `write-microflows.md` — before any microflow
- `generate-domain-model.md` — before domain model changes
- `manage-security.md` — before security/roles
- `check-syntax.md` — pre-flight validation
- `live-edit-with-studio-pro.md` — before writes with SP open

## Documentation Timing

Pflege In-App-Dokumentation beim Anlegen oder Aendern des Artefakts, nicht gesammelt am
Sprintende: Module, Entities, Enumerationen und Associations erhalten eine Beschreibung;
Microflows und Nanoflows dokumentieren Zweck, Parameter und Ergebnis. Fachliche
Entscheidungen gehoeren nach `sprints/decisions.md`; storybezogene technische Details,
Testmatrizen und Mockup-Beobachtungen nach `planning/stories/`. Der Lint `QUAL002` prueft
fehlende Entity- und Microflow-Dokumentation.

### HTML-Mockups und Playwright

Fuer HTML-Mockups unter `input-resources/ui-ux/`:

- zuerst `input-resources/README.md` lesen
- Mockups im Browser mit Playwright ausfuehren
- relevante Zustaende und Nutzerwege untersuchen
- zustandsabhaengige Varianten aktiv durchklicken und ihre Feldsemantik dokumentieren
- Screenshots als Implementierungsreferenz verwenden
- nach der Mendix-Umsetzung dieselben Nutzerwege gegen die laufende App pruefen

Der mxcli `test-app` Skill und die vorhandene Playwright-Konfiguration sind fuer
Browser-Automation und die Verifikation der laufenden Mendix-App zu verwenden.

Die Interpretation des Mockups richtet sich nach den Regeln in
`input-resources/README.md`.

<!-- END PROJECT AGENT INSTRUCTIONS -->
