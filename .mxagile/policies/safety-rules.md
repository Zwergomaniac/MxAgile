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


