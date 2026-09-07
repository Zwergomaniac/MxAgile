# [PROJEKTNAME] — Agent Instructions

> **Projektkontext:** siehe `projekt.md`.
>
> **Neues Projekt? Setup prüfen:**
> Falls `projekt.md` noch TODO-Platzhalter enthält, `.mcp.json` fehlt oder `.ai-context/`
> nicht existiert → lies zuerst `.claude/templates/mx-project/README.md` und führe den
> Nutzer durch die Setup-Schritte bevor du mit anderen Aufgaben beginnst.
> Diese Datei gilt für generische AI-Agenten (GitHub Copilot, OpenAI Codex, etc.).
> Für tool-spezifische Regeln: `CLAUDE.md` (Claude Code) · `skillssource/AGENTS.md` (Maia).

---

## Multi-Agent-Struktur

| Agent | Instruktionsdatei | Gemeinsame Basis |
|---|---|---|
| Claude Code (VS Code) | `CLAUDE.md` | `projekt.md` |
| Maia (Studio Pro) | `skillssource/AGENTS.md` | `projekt.md` |
| GitHub Copilot / Codex | `AGENTS.md` (diese Datei) | `projekt.md` |
| Concord MCP | `.concord/project-memory.md` | `projekt.md` |

---

## Allgemeine Entwicklungsregeln

- **KEIN manuelles git commit/push** — Mendix Team Server übernimmt Versionskontrolle
- **`[Spec.md]` niemals modifizieren** — ist die unveränderliche Produkt-Spezifikation
- Domain-Model: Englisch, PascalCase
- FOSS-Marketplace-Module vor Eigenentwicklung prüfen
- Annahmen: ⚠️ ASSUMPTION | Offene Entscheidungen: ⚠️ DECISION REQUIRED

---

## Wo was nachschlagen

| Thema | Datei |
|---|---|
| Projektziel, Architektur, Module | `projekt.md` |
| mxcli-Befehle, Concord MCP, Tool-Routing | `CLAUDE.md` |
| Mendix-Programmierregeln, Domain-Konventionen | `skillssource/AGENTS.md` |
| Architekturentscheidungen | `sprints/decisions.md` |