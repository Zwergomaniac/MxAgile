# Universelle Safety Rules

Diese Regeln gelten fuer alle AI-Agenten auf allen Plattformen.
Projektspezifische Ergaenzungen gehoeren in `AGENT.md`, nicht hierher.

## Versionskontrolle

- Agenten duerfen Staging und Commit-Vorschlag vorbereiten.
- Vor `git commit` nach ausdruecklicher Freigabe fragen, ausser Autopilot-Modus
  ist explizit aktiviert.
- `git push` bleibt immer manuell/nutzergesteuert.
- NIEMALS destruktive Versionskontrollbefehle ohne explizite Nutzeranfrage:
  `git/hg checkout`, `reset`, `clean`, `stash`, `merge`, `rebase`, `push`.

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

## Plattformmodule

- Mercedes-Benz Plattformmodule (MB_SSO, MB_UI, MB OIDC, etc.) duerfen nicht
  modifiziert werden.
- Vor Eigenentwicklung immer `.mxagile/modules/platform-modules.md` pruefen.

## Input-Resources

- Mockups und Eingabeartefakte unter `input-resources/` nicht veraendern, sofern
  nicht ausdruecklich beauftragt.
- Relevante Eingabeartefakte haben Vorrang vor Annahmen des Agenten.


