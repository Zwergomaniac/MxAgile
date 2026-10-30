# Universelle Safety Rules

Diese Regeln gelten fuer alle AI-Agenten auf allen Plattformen.
Projektspezifische Ergaenzungen gehoeren in `AGENT.md`, nicht hierher.

## Versionskontrolle

- Commit-Autoritaet wird durch `policies/commit-authority.md` bestimmt.
- Standard: Commits interaktiv vorschlagen und auf Entwicklerbestaetigung warten.
- Wenn der aktuelle Nutzerauftrag ausdruecklich autonome lokale Checkpoint-Commits
  delegiert: kohaerente validierte Aenderungen committen; vollstaendiges Autoritaets-
  und Precondition-Modell siehe `policies/commit-authority.md`.
- `git push` bleibt immer manuell/nutzergesteuert — Push-Autoritaet wird NIEMALS
  aus Commit-Autoritaet abgeleitet.
- NIEMALS destruktive Versionskontrollbefehle ohne explizite Nutzeranfrage im
  selben Turn: `git reset --hard`, `git rebase` geteilter History, `git commit
  --amend` veroeffentlichter Commits, `git push --force`, `git clean -f`.

## Git Index Integrity Guard

Vor git add, Commit, Migration, Update, Modellmutation, Cleanup, Rebase oder Merge
in bestehenden getrackten Projekten ausfuehren:
`python .mxagile/tools/git_index_integrity.py --project-root .`
(Framework-Entwicklung: `scripts/git_index_integrity.py`). Read-only, Exit 0 erlaubt
Fortsetzung; jeder andere Exit blockiert normale Mutationen. Ein read-only
CONTROLLED_RECOVERY-Preflight und dessen eng autorisierte Recovery bleiben nach
dem folgenden Vertrag moeglich; das ist keine Freigabe normaler Mutationen. Keine Umdeutung eines
nicht pruefbaren Zustands als PASS. Unborn HEAD / Projekte ohne Git sind separat
NOT_APPLICABLE, nicht "repariert".

GIT_INDEX_INTEGRITY_FAILURE: HEAD > 0, Index = 0, staged deletions = HEAD und
betroffene Working-Tree-Dateien weiterhin vorhanden. Kompakt die drei Counts
und Working-Tree-Existenz melden. Keine tausenden Delete-Findings erzeugen,
keine Migration aus dem Dirty State ableiten, kein add -A, clean oder reset --hard.
Die verursachende Komponente ist UNBEWIESEN; keine Schuldzuweisung an Studio Pro,
Git, mxcli, Hooks oder MxAgile.

`git restore --source=HEAD --staged -- :/` stellt ausschliesslich den Index aus
HEAD wieder her, nicht den Working Tree. Dabei gehen vorhandene Staging-Auswahlen
verloren. Nur nach ausdruecklicher Recovery-Autorisierung bzw. einem eindeutig
anwendbaren vorhandenen Autonomievertrag ausfuehren, nie als Nebenwirkung des
Guards. Danach Guard erneut ausfuehren; Working Tree und HEAD vorher/nachher
vergleichen. Der Guard selbst bietet absichtlich keinen schreibenden Recovery-Schalter.

index.lock + beobachteter Git-Prozess: GIT_OPERATION_IN_PROGRESS; die Beobachtung
beweist nicht den Lock-Eigentuemer. Ohne beobachteten Prozess nur
GIT_INDEX_LOCK_STALE_CANDIDATE, bei fehlender Prozesssicht LOCK_UNVERIFIED.
Alle blockieren. Lock niemals allein aufgrund seiner Existenz/Alter loeschen.
Externe Git-/Studio-Pro-Prozesse werden nicht durch Agentenregeln abgefangen.

## CONTROLLED_RECOVERY

Safety darf eine ausdruecklich beauftragte, begrenzte Recovery nicht pauschal
verhindern. Aktivierung ausschliesslich bei belegtem beschaedigtem/unvollstaendigem
Git-State, bekanntem sicheren Ziel, ausdruecklichem Nutzerauftrag, technisch zum
aktuellen State passender Operation und zuvor diagnostiziertem Scope. Allgemeine
Commit-/Autonomie-Autoritaet reicht nicht. Keine Recovery im Frameworkauftrag an
CapTrack oder anderen fremden Projekten ausfuehren.

Read-only Preflight: `python .mxagile/tools/git_index_integrity.py --project-root .
--recovery merge-abort --user-authorized --scope-reviewed` (eine Kommandozeile).
Fuer den Index stattdessen `--recovery index-rebuild`. Die Flags dokumentieren
den tatsaechlichen Nutzerauftrag und die erfolgte Scope-Pruefung; der Agent darf
sie nicht aus eigenem Convenience-Bedarf setzen. Der Helper erteilt keine neue
Autoritaet und fuehrt keinen der ausgegebenen Git-Schreibbefehle aus.
Unmittelbar vor Ausfuehrung neu pruefen; bei geaendertem HEAD, Scope, Locks oder
Fingerprints den alten Plan verwerfen. Vorherigen READY-JSON-Befund ausserhalb
des Projekts sichern. Nach dem einzelnen autorisierten Git-Schritt dessen Exitcode
festhalten und `--verify-before <externe-baseline.json> --command-exit <code>`
aufrufen. Unbekannter Exitcode ist kein Erfolg. Snapshot/Diff-Fingerprints sind
Diagnostik, kein Ersatz fuer eine notwendige Sicherung fachlicher Aenderungen.
Der mechanische READY-Pfad ist bewusst auf Merge-Abort und leeren Index begrenzt;
andere Recovery-Klassen erfordern den beschriebenen manuellen, begrenzten Review,
keine staerkere automatische Fallback-Operation.

Auftraege und begrenzte Autoritaet:
- "Brich den fehlgeschlagenen Merge ab": nativer Tool-Abbruch, danach gegebenenfalls
  `git merge --abort`, nur bei aktuell belegtem MERGE_HEAD und Scope-Pruefung.
- "Stelle den Index aus HEAD wieder her": bei belegtem leerem beschaedigtem Index
  `git restore --source=HEAD --staged -- :/`, ohne Working-Tree-Reset.
- "Setze ausschliesslich diese fehlerhafte Aenderung zurueck": nur benannte Dateien
  und benannter Zielstand, nach Sicherung/Pruefung unabhaengiger Aenderungen.
- Rebase-/Cherry-Pick-Abbruch nur mit passendem explizitem Auftrag und aktuell
  belegten Git-Metadaten. Mendix-Cachefehler allein beweisen keinen Git-Merge.

Vor JEDEM Versuch: HEAD, Branch, `git status --porcelain=v1 -z`, echte Git-Metadaten
fuer Merge/Rebase/Cherry-Pick, Index Entry Count, staged/unstaged/untracked Scope,
Locks und beobachtbare Git-/SQLite-/Toolprozesse erfassen. `git rev-parse --git-path`
beruecksichtigt Worktrees. Keine Operation aus Erinnerung ableiten. Vorherigen
HEAD, Scope und unabhaengige Aenderungen pruefbar ausserhalb des Recovery-Scope
sichern. Bei unbekannter Vorher-Semantik/ueberlappenden fachlichen Aenderungen STOP
und gezielte Klaerung; eine User-Autorisierung erlaubt nicht deren stillen Verlust.

Hierarchie: funktionsfaehiger nativer Tool-Abbruch; Standard-Git-Abbruch zum
belegten Operationstyp; index-only/state-only; explizit dateigebundenes Restore.
Working-Tree-destruktive Recovery ist keine automatische naechste Stufe.
`git reset --hard`, `git clean -fd`, force checkout/destructive restore, Force Push,
History Rewrite, unbekannte untracked Dateien loeschen oder ungesicherte fachliche
Aenderungen ueberschreiben bleiben ohne weitere konkrete Grundlage gesperrt.
Wenn noetig: gezielte Nutzereskalation, kein stiller Fallback.

Bei recipe-cache.sqlite-shm / recipe-cache.sqlite-wal oder anderen unlink-Fehlern:
Tracked-Status und Zugehoerigkeit zum Recovery-Scope pruefen, Runtime-/Cache-Natur
von fachlichen Daten trennen, aktuelle Datei-Lock-/Prozessbeobachtung erfassen.
Ein Prozessname beweist keinen File-Handle-Eigentuemer; UNKNOWN bleibt UNKNOWN.
Nicht aggressiver loeschen, index.lock nicht entfernen, keine Prozesse blind
beenden. Vor Retry Ursache/Lock-Freigabe neu beobachten; gegebenenfalls Nutzer
zum normalen Schliessen des belegten Tools auffordern. Ephemeral bedeutet nicht
automatisch loeschbar, besonders bei getrackten Dateien.

Nach JEDEM Versuch: erwarteten HEAD, plausiblen Index, beendeten Operation-State,
`git status`, `git diff`, `git diff --cached`, erhaltene unabhaengige Aenderungen
und keine unerwarteten Dateiverluste pruefen. Raw-Diffs/Secrets nicht in Berichte
kopieren. Nur vollstaendig belegte Nachbedingungen erlauben RECOVERY_SUCCESS.
Sonst RECOVERY_PARTIAL / RECOVERY_FAILED und STOP, keine staerkere Folgeoperation.

Nach RECOVERY_SUCCESS ist Lifecycle-/Project-State-Re-Sync vor Fortsetzung Pflicht.
Vorherige Merge-/Working-Tree-Annahmen verwerfen. Recovery erfuellt keine Gates,
promotet keine Evidence, schliesst keine Findings und startet keine Migration.
Der bestehende Interrupt-/Resume-/Re-Sync-Vertrag bleibt unveraendert.

## Begrenzte Artefakt-Edits

- Bei ausdruecklich begrenzten Artefakt-Edits die kleinste konsistente Aenderung
  ausfuehren.
- Zusaetzliche Findings, Open Items, Tracking-Eintraege oder semantische
  Erweiterungen nicht allein zur Vervollstaendigung erzeugen.
- Folgeaenderungen sind nur zulaessig, wenn Schema, Invarianten oder ausdruecklich
  akzeptierter Scope sie verlangen.
- Autonomie erlaubt selbststaendige Ausfuehrung innerhalb des Scopes, nicht dessen
  Erweiterung.

## Modellaenderungen

- NIEMALS Model-Elemente (Entities, Attributes, Associations, Microflows, Pages,
  Domain Model) loeschen oder destruktiv aendern ohne EXPLIZITE Nutzerbestaetigung
  im SELBEN Turn.
- Vor JEDER destruktiven oder irreversiblen Operation: genau beschreiben was sich
  aendert, Bestaetigung einholen.
- MODEL writes: SP-MCP direkt zuerst. Concord's Write-Ladder ist nur FALLBACK.

## Credentials und Geheimnisse

- Lokale Werte wie Passwoerter, Tokens und PATs niemals ausgeben, in MDL schreiben
  oder versionieren.
- `.env.mendix`, `.mcp.json`, Bridge-Tokens und MCP-Clientkonfigurationen bleiben lokal.
- Secret-Werte NIEMALS in Reports, process-state.yaml, Screenshots, Logs oder anderen
  verfolgten Artefakten einschliessen.
- In Reports nur nicht-geheime Bereitschafts-Metadaten verwenden:
  PRESENT / MISSING / EMPTY / INVALID / VALID / USED / NOT_USED
- Credential-Werte duerfen weder in Context-Mode-Indizes oder Suchkorpora noch in
  Session-Zusammenfassungen oder Agent-/Subagent-Handoffs materialisiert werden.
- Secret Discovery bleibt von Context-Mode-Retrieval getrennt; auch bei gesundem Context
  Mode werden Credential-Dateien und Werte nicht indexiert.
- Vollstaendiger Credential-Discovery-Vertrag: `policies/credential-discovery.md`

## Credential-Mutations-Verbot

Ein fehlgeschlagenes Standard/Default-Credential berechtigt NICHT zu:

- `ALTER USER ... PASSWORD ...`
- Passwort-Reset oder -Rotation
- Konto-Neuerstellung
- Datenbank-Benutzer-Neuerstellung
- Datenbank-Reinitialisierung
- Credential-Ueberschreibung
- Destruktive Infrastruktur-Aenderungen jeglicher Art

Das korrekte Vorgehen bei einem fehlgeschlagenen Credential:

    Konfiguration entdecken
        ->
    Tatsaechlich konfigurierte Werte verwenden
        ->
    Validieren
        ->
    Ursache diagnostizieren

Credential-Mutation als Reaktion auf Authentifizierungsfehler ist ein Framework-Verstoss.
Gilt auch wenn die Mutation technisch durchfuehrbar waere.

## Company Layer Platform Modules

- Installierte Company Layer Platform-Module duerfen nicht modifiziert werden.
- Vor Eigenentwicklung pruefen ob ein installiertes Company Layer Modul die Funktion
  liefert (`.mxagile/layers/<layer-id>/platform-modules.yml` falls Layer vorhanden).

## Input-Resources

- Mockups und Eingabeartefakte unter `input-resources/` nicht veraendern, sofern
  nicht ausdruecklich beauftragt.
- Relevante Eingabeartefakte haben Vorrang vor Annahmen des Agenten.


