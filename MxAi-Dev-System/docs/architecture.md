# MxAgile Architecture

---

## Section 1: Installation Architecture (Current)

```mermaid
flowchart TD
    A[install-mxagile.ps1\nGeneric Bootstrap] --> C[scripts/install-core.ps1\nCanonical Installer]
    B[install-mxagile-mercedes.ps1\nMercedes Bootstrap] --> C

    C --> I[scripts/mxagile-init.ps1\nInitialization]
    C --> U[update-mxcli.ps1\ndistributed to project]
    C --> S[scripts/setup-agent-system.ps1\nAgent System]
    C --> L[Optional: Company Layer\nfetch-layer.ps1 or Local]

    I --> D1[Create .mxagile dirs]
    I --> D2[Install mxcli.exe]
    I --> D3[Create placeholder\nAGENT.md AGENTS.md CLAUDE.md]

    S --> P[scripts/apply-project-agent-instructions.ps1\nInstruction Projection]
    S --> G[scripts/generate-mxagile-platform-skills.ps1\nPlatform Skill Generation]
```

---

## Section 2: Ownership Architecture

```mermaid
flowchart LR
    subgraph CS[".mxagile/ — Canonical Source"]
        SK[skills/*.md]
        AG[agents/*.md]
        PO[policies/*.md]
        OR[orchestrator.md]
    end

    subgraph GEN["generators"]
        GPG[generate-mxagile-platform-skills.ps1]
        APA[apply-project-agent-instructions.ps1]
    end

    subgraph PP["Platform Projections (GENERATED — do not edit)"]
        CL[".claude/skills/mxagile-*/SKILL.md\n.claude/agents/mxagile-*.md"]
        CO[".github/skills/mxagile-*/SKILL.md"]
        CX[".agents/skills/mxagile/"]
        GR[".grok/skills/mxagile/"]
    end

    subgraph NPI["Neutral Project Instructions"]
        AM[AGENT.md\nProject-owned canonical source]
    end

    subgraph PIE["Platform Instruction Entry Points (SHARED)"]
        AS[AGENTS.md\nuser content + MANAGED BLOCK]
        CMD[CLAUDE.md\nuser content + MANAGED BLOCK]
        GH[.github/copilot-instructions.md\nuser content + MANAGED BLOCK]
    end

    SK --> GPG
    AG --> GPG
    GPG --> CL
    GPG --> CO
    GPG --> CX
    GPG --> GR

    AM --> APA
    APA --> AS
    APA --> CMD
    APA --> GH
```

---

## Section 3: Canonical Lifecycle

Canonical machine-readable definition: `.mxagile/lifecycle.yaml` (schema_version: 1).
Narrative expansion: `.mxagile/orchestrator.md`.
Unit of progression: **wave** (a set of requirements processed together).

### Phase Flow

```mermaid
flowchart LR
    IT([Intake\noptional/external]):::optional --> DI

    DI[Discovery] -->|gate-to-refinement| RF[Refinement]
    RF -->|gate-to-ready| RD[Ready\ngate state]
    RD -->|developer approval| IM[Implementing]
    IM --> VR[Verifying]
    VR --> Done([Done])

    RF -->|scope returns| DI
    IM -->|spec issue| RF
    IM -->|missing context| DI
    VR -->|impl defect\nfailed items only| IM
    VR -->|spec/refinement issue| RF
    VR -->|missing context| DI

    classDef optional fill:#f9f,stroke:#999,stroke-dasharray:5 5
```

### Return Routing

| Condition | Return to | Scope |
|---|---|---|
| Implementation defect found in Verifying | Implementing | Failed checklist items only |
| Specification or refinement defect found | Refinement | Affected story specifications |
| Fundamental missing context or changed input | Discovery | Affected stories; unaffected remain CURRENT |

### Change Propagation

```mermaid
flowchart TD
    CS[Changed Source Artifact] --> IA[Impact Assessment:\nwhich stories/specs are affected?]
    IA --> AS[Affected Scope\nwave + story granularity]
    AS --> EN[Earliest Necessary Phase\nfor affected scope only]
    EN --> FL[Forward Lifecycle]
    FL --> Done([Done])

    IA -->|unaffected scope| CUR[Remains CURRENT]
```

| Source change | May affect | Earliest return |
|---|---|---|
| Mockup changed | Story specs, UI inventory, implementation, verification | Discovery |
| Spec changed after implementation | Checklist, implementation, verification | Refinement |
| Implementation defect | Verification evidence | Implementing |

MxAgile skills implement individual phases. The installer provides the foundation; lifecycle execution requires an active agent session.

---

## Section 4: Current vs Target Gaps

| Area | Current | Target | Status |
|------|---------|--------|--------|
| Managed block markers | `<!-- BEGIN PROJECT AGENT INSTRUCTIONS -->` | `<!-- MXAGILE:MANAGED:START -->` | MIGRATION IMPLEMENTED — `apply-project-agent-instructions.ps1` detects and migrates old markers |
| Skill directory naming (Codex/Grok/etc.) | `dfc/` | `mxagile/` | FIXED — `generate-mxagile-platform-skills.ps1` now uses `mxagile/` |
| Managed block position | Block inserted at TOP (before user content) | Block inserted at END (user content first) | FIXED — new `Apply-ManagedBlock` function appends at end on first insert |
| Malformed/duplicate block detection | Silent overwrite | Fail with diagnostic | FIXED — `Apply-ManagedBlock` fails with clear error on DUPLICATE or MALFORMED |
| Mercedes layer `.git/` in dev repo | Present (staged for deletion) | Absent (stripped on install) | `fetch-layer.ps1` and `install-core.ps1` strip `.git/` on install; dev repo had it temporarily |
| System Check skill | Absent | `.mxagile/skills/system-check.md` | CREATED |
| Injection Contract document | Absent | `docs/injection-contract.md` | CREATED |
| Post-install validation prompt | Absent | Shown after successful install | ADDED to `install-core.ps1` |
| Agent behavioral validation | Not systematic | System Check skill (section H) | CREATED |
| Script canonical name (generator) | `generate-dfc-platform-skills.ps1` | `generate-mxagile-platform-skills.ps1` | RENAMED |
| Canonical lifecycle source | Narrative only in `orchestrator.md`; wrong phase names in architecture.md (Requirements, Planning, Convergence) | `lifecycle.yaml` (machine-readable) + corrected diagrams | CREATED |
| Architecture lifecycle diagram | CURRENT/TARGET split with non-canonical phase names | Canonical phases + feedback-loop diagram + change-propagation diagram | FIXED |
| System Check lifecycle validation | Hardcoded phase string referencing `orchestrator.md` | Reads `lifecycle.yaml` to validate canonical source exists | FIXED |

---

## Section 5: File Ownership Summary

| File / Directory | Owned By | Edit How |
|-----------------|----------|----------|
| `.mxagile/skills/*.md` | MxAgile Framework Developer | Edit canonical source; regenerate projections |
| `.mxagile/agents/*.md` | MxAgile Framework Developer | Edit canonical source; regenerate projections |
| `.claude/skills/mxagile-*/` | MxAgile (generated) | Do NOT edit — rerun generator |
| `.github/skills/mxagile-*/` | MxAgile (generated) | Do NOT edit — rerun generator |
| `.claude/agents/mxagile-*.md` | MxAgile (generated) | Do NOT edit — rerun generator |
| `.agents/skills/mxagile/` | MxAgile (generated) | Do NOT edit — rerun generator |
| `AGENT.md` | Project / User | Edit freely |
| `AGENTS.md` | Shared (user + MxAgile block) | Edit user sections freely; managed block auto-replaced |
| `CLAUDE.md` | Shared (user + MxAgile block) | Edit user sections freely; managed block auto-replaced |
| `.github/copilot-instructions.md` | Shared (user + MxAgile block) | Edit user sections freely; managed block auto-replaced |
| `requirements/`, `specs/`, `planning/` | Project / User | Edit freely; never overwritten |
| `*.mpr` | Mendix Studio Pro | Never touched by MxAgile |
