#!/usr/bin/env bash
# SessionStart Hook: Prüft ob das Mendix Multi-Agent-Setup vollständig ist.
# Gibt nur Ausgabe wenn etwas fehlt — kein Output bei vollständigem Setup.
# Claude Code liest diesen Output und muss darauf reagieren.

ERRORS=()
WARNINGS=()

# Check 1: .mcp.json (Concord MCP-Konfiguration)
if [ ! -f ".mcp.json" ]; then
  ERRORS+=("❌ .mcp.json fehlt — Concord MCP nicht konfiguriert.")
  ERRORS+=("   → Mendix Marketplace: 'Concord' installieren → Studio Pro neu starten.")
  ERRORS+=("   → Concord schreibt .mcp.json automatisch nach der Installation.")
fi

# Check 2: projekt.md vorhanden und ausgefüllt
if [ ! -f "projekt.md" ]; then
  ERRORS+=("❌ projekt.md fehlt — Projektkontext nicht angelegt.")
  ERRORS+=("   → Template kopieren: cp .claude/templates/mx-project/projekt.md .")
elif grep -q "TODO" "projekt.md" 2>/dev/null; then
  WARNINGS+=("⚠️  projekt.md hat noch TODO-Platzhalter — Projektkontext unvollständig.")
  WARNINGS+=("   → projekt.md öffnen und alle <!-- TODO: --> Abschnitte ausfüllen.")
fi

# Check 3: .ai-context (mxcli init)
if [ ! -d ".ai-context" ]; then
  ERRORS+=("❌ .ai-context/ fehlt — 'mxcli init' noch nicht ausgeführt.")
  ERRORS+=("   → Terminal: mxcli init . --tool claude")
fi

# Check 4: mxcli im PATH
if ! command -v mxcli &>/dev/null; then
  WARNINGS+=("⚠️  mxcli nicht im PATH gefunden.")
  WARNINGS+=("   → PATH prüfen oder mxcli installieren (siehe .claude/templates/mx-project/README.md)")
fi

# Check 5: AGENTS.md nicht leer
if [ ! -s "AGENTS.md" ]; then
  WARNINGS+=("⚠️  AGENTS.md ist leer — generische Agent-Instruktionen fehlen.")
  WARNINGS+=("   → Template kopieren: cp .claude/templates/mx-project/AGENTS.md .")
fi

# Ausgabe nur wenn Probleme gefunden
TOTAL=$((${#ERRORS[@]} + ${#WARNINGS[@]}))
if [ $TOTAL -gt 0 ]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║        MENDIX PROJEKT-SETUP UNVOLLSTÄNDIG           ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""

  if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "FEHLER (müssen vor dem Arbeiten behoben werden):"
    for err in "${ERRORS[@]}"; do
      echo "  $err"
    done
    echo ""
  fi

  if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo "WARNUNGEN (sollten zeitnah behoben werden):"
    for warn in "${WARNINGS[@]}"; do
      echo "  $warn"
    done
    echo ""
  fi

  echo "Vollständige Anleitung: .claude/templates/mx-project/README.md"
  echo "Setup-Validator:        /validate-agent-setup"
  echo ""
fi