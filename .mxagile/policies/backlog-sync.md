# Backlog-Synchronisierung und abgeleitete Artefakte

## Board Authority Contract

The external Mendix Epics Board is an **optional organizational status projection**.

Direction of authority:

```
MxAgile authorized scope / lifecycle
→ implementation + verification
→ accepted/completed state
→ optional Board status reflection
```

Board content MUST NOT:
- create MxAgile scope
- extend an existing mission
- authorize implementation
- create or reopen a Wave
- reactivate historical scope
- select or prioritize the next work item
- prevent mission completion
- become the default continuation for "Continue with the project."

A Board item may become input **only** when the developer or authorized product
authority explicitly selects it as new scope. Mere existence on the Board is not
authorization.

Projects not using Board integration MUST experience no Board-related lifecycle
behavior or prompts.

## Mendix Epics Board (optional, D52)

Das Mendix Epics Board ist ein optionales Management-Instrument fuer organisatorisches
Tracking und Priorisierung. Es ist NICHT die primaere fachliche Quelle — Mockup +
Requirements-Dokument haben Vorrang (siehe `policies/source-priority.md`).

Nicht jedes Projekt hat ein Board. Wenn kein Board konfiguriert ist, entfallen die
folgenden Sync-Schritte ohne den Prozess zu blockieren.

Wenn ein Board vorhanden ist, vor Planung oder Umsetzung einer Board-Story:

1. `scripts/sync-epics-stories.ps1` ausfuehren
2. Passenden generierten Snapshot unter `sprints/generated/` lesen
3. Snapshots sind read-only; Story- und Statusaenderungen werden ausschliesslich
   im Mendix Epics Board vorgenommen

Board-Sync ist eine **read-only Kontextanreicherung**. Es importiert oder autorisiert
keinen neuen Scope.

## Abgeleitete Arbeitsartefakte

Technische Spezifikationen, Testmatrizen, Traceability- und Abhaengigkeitsmatrizen
unter `planning/` koennen — wenn ein Board konfiguriert ist — enthalten:

- Board-Story-ID (optional; Traceability, nicht Autoritaet)
- `Source fingerprint` aus dem aktuellen Snapshot (optional)

Nach jedem Board-Sync `scripts/reconcile-derived-artifacts.ps1` ausfuehren.
Bei abweichendem oder fehlendem Board-Input das Artefakt als `Review required`
markieren; die autoritative Quelle fuer den Scope bleibt das MxAgile-Lifecycle
(Requirements, Decisions, mission-state.yaml).

## Wave-Reports und Board-Traceability

Nach Abschluss einer Wave erstellt der Agent einen versionierten Bericht unter
`planning/wave-reports/`. Er nennt:

- Betroffene Board-Story-IDs
- Erledigten Umfang
- Testnachweise
- Offene Gates
- Manuelle Board-Aktionen

Wave-relevante Commits nennen die Story-IDs explizit:
`feat: implement foundation [{STORYPREFIX}-123] [{STORYPREFIX}-124]`

Das ist Traceability und aendert keinen Board-Status. Das manuelle Abhaken erfolgt
erst nach Pruefung des Berichts und ueber `scripts/generate-board-action-report.ps1`.

## Board-Completed-Scope Reflection

After existing authorized MxAgile work reaches its legitimate terminal state, the
developer may be informed which Board items can organizationally be marked completed.
This is a **status reflection** — the Board receiving the result, not driving it.

## Scope-Separation Guard

The following are explicitly FORBIDDEN:

| Action | Why forbidden |
|---|---|
| Board-Sync discovers new stories → agent adds them to mission scope | Board does not authorize scope |
| Board story changes → Wave reopened or new Wave created automatically | Board does not drive lifecycle |
| Feature Scope complete → agent runs Board-Sync to find next work | Board is not the continuation source |
| "Continue with the project" → agent selects a Board story | Developer/product authority selects scope |
| Board item exists but no developer selection → scope assumed | Existence is not authorization |
| Board disabled/not configured → Board-related prompts or behavior shown | Optional means invisible when absent |

Explicit user selection of a Board story may enter normal intake/refinement as newly
authorized input, without granting the Board itself lifecycle authority. The developer
selects the scope; the Board is only the surface the developer looked at.
