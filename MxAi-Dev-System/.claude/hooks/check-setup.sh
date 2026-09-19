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
  ERRORS+=("   → mxcli init . ausfuehren oder projekt.md aus dem Template-Payload kopieren.")
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
  WARNINGS+=("   → PATH pruefen oder mxcli installieren (siehe README.md im Projektroot).")
fi

# Check 5: AGENTS.md nicht leer
if [ ! -s "AGENTS.md" ]; then
  WARNINGS+=("⚠️  AGENTS.md ist leer — generische Agent-Instruktionen fehlen.")
  WARNINGS+=("   → scripts/apply-project-agent-instructions.ps1 ausfuehren.")
fi

# Check 6: .dfc-ai/ vorhanden
if [ ! -d ".dfc-ai" ]; then
  WARNINGS+=("⚠️  .dfc-ai/ fehlt — DFC-AI Prozesssteuerung nicht vorhanden.")
  WARNINGS+=("   → Aus Template kopieren oder scripts/setup-agent-system.ps1 ausfuehren.")
elif [ ! -f ".dfc-ai/orchestrator.md" ]; then
  WARNINGS+=("⚠️  .dfc-ai/orchestrator.md fehlt — Prozessfluss nicht definiert.")
fi

# Check 7: Generierte DFC-Skills vorhanden und Frontmatter-Contract eingehalten
# Claude-Skills liegen unter .claude/skills/dfc-<name>/SKILL.md, nicht mehr
# unter .claude/skills/dfc/<name>/. YAML-Frontmatter MUSS in Zeile 1 stehen,
# sonst wird der Skill von keiner Plattform erkannt (siehe .dfc-ai/adapters/).
if [ -d ".dfc-ai/skills" ]; then
  dfc_skill_dirs=(.claude/skills/dfc-*/)
  if [ ! -e "${dfc_skill_dirs[0]}" ]; then
    WARNINGS+=("⚠️  .dfc-ai/skills/ existiert, aber keine .claude/skills/dfc-*/ generiert.")
    WARNINGS+=("   → scripts/generate-dfc-platform-skills.ps1 ausfuehren.")
  else
    for skill_file in .claude/skills/dfc-*/SKILL.md; do
      [ -f "$skill_file" ] || continue
      first_line="$(head -n 1 "$skill_file")"
      if [ "$first_line" != "---" ]; then
        ERRORS+=("❌ $skill_file: Zeile 1 ist nicht '---' — YAML-Frontmatter-Contract verletzt.")
        ERRORS+=("   → Skill wird von keiner Plattform erkannt. scripts/generate-dfc-platform-skills.ps1 neu ausfuehren.")
      fi
    done
  fi
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

  echo "Vollständige Anleitung: README.md (Projektroot)"
  echo "Setup-Validator:        /validate-agent-setup"
  echo ""
fi