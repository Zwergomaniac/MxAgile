<!-- concord-v2 begin -->
<!-- Dieser Block wird von Concord verwaltet und bei Updates überschrieben. NICHT manuell bearbeiten. -->
<!-- concord-v2 end -->

@projekt.md
@.claude/setup.md

> **Projektkontext:** `projekt.md` und `setup.md` sind oben via @-Include geladen.
> Diese Datei enthält nur Claude Code-spezifische Inhalte (Tool-Routing, mxcli, Safety Rules).
> Diese Datei enthält nur Claude Code-spezifische Inhalte (Tool-Routing, mxcli, Safety Rules).

---

# Tool-Entscheidung: Concord · SP-MCP · mxcli

## Entscheidungsmatrix

| Situation | Tool | Befehl / Aufruf |
|-----------|------|-----------------|
| **"Wie mache ich X in Mendix?"** | **Concord `mx.ask`** | `concord_discover` → `concord_invoke mx.ask` |
| Session-Start: Projekt verstehen | Concord `mx.project-brief` | `concord_invoke mx.project-brief` |
| Model-Write, **SP ist offen** | SP-MCP via mxcli | `mxcli --mcp http://localhost/mcp --mcp-dial localhost:7782 -p App.mpr -c "..."` |
| Security-Rollen, Nanoflows, Lint | **mxcli** — SP muss **geschlossen** sein | `mxcli exec script.mdl -p App.mpr` |
| App starten / Logs lesen | **Concord** (SP muss offen sein) | `concord_invoke concord.run_and_await_ready` |
| Mendix CE-Vollvalidierung | mxcli | `mxcli docker check -p App.mpr` |

## Concord-Exklusiv (nicht in mxcli)
- `mx.ask` — Mendix-Wissensfragen. NIEMALS aus Gedächtnis antworten — immer `mx.ask` aufrufen.
- `mx.project-brief` — Projektüberblick beim Session-Start
- `concord.run_and_await_ready`, `read_run_log`, `read_build_errors` — App-Lifecycle
- `concord.open_browser_url`, `close_document`, `close_active_editor`, `close_all_editors`
- `concord.sync_files`, `concord.save-all`

## mxcli-Exklusiv (SP muss geschlossen sein für Writes)
Security-Rollen / User Roles / Demo Users / Security Level, Nanoflows CREATE,
View Entities (OQL), Indexes, REVOKE, MOVE, OData, Java Actions,
Navigation mit rollenbasierten Home-Pages, `mxcli lint`, `mxcli docker check`

---

# CONCORD SAFETY RULES (non-negotiable)
- NEVER run version-control WRITE commands: no git/hg add/commit/checkout/reset/clean/stash/push/merge/rebase
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

## Before Writing MDL Scripts
Read the relevant skill file first:
- `write-microflows.md` — before any microflow
- `generate-domain-model.md` — before domain model changes
- `manage-security.md` — before security/roles
- `check-syntax.md` — pre-flight validation
- `live-edit-with-studio-pro.md` — before writes with SP open