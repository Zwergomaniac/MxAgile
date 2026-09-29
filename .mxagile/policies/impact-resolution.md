# Impact Resolution

Canonical policy for resolving manual UI findings and change signals to existing canonical
Requirements and Specifications in MxAgile.

## Purpose

When a developer reports a UI finding ("The calendar filter should be above the calendar"),
the framework must reliably identify which existing Requirements and Specs are affected
before any artifact mutation occurs.

This policy defines the resolution algorithm, search priority, prohibited inferences,
and finding classification vocabulary.

---

## Search Priority

Agents must use structured resolution before falling back to text search.

```
Priority 1 — STRUCTURED TRACE RESOLUTION
  Query artifact-index.json for:
    - APPLIES_TO edges: requirements where PAGE-NNN in requirement.screens[]
    - DERIVED_FROM edges (reverse): requirements where requirement.derivedFrom == PAGE-NNN
    - VERIFIED_BY edges: scenarios where scenario.screen_id == PAGE-NNN,
      then scenario.traceability.requirements[]
  Merge, deduplicate. Result = structured candidate set.

Priority 2 — DIRECT CANONICAL TRAVERSAL (when index unavailable or stale)
  Scan requirements/*.yml:
    - requirement.screens[] contains PAGE-NNN
    - requirement.derivedFrom == PAGE-NNN
  Scan planning/scenarios/*.yaml:
    - scenario.screen_id == PAGE-NNN → scenario.traceability.requirements[]
  Result = verified candidates from authoritative files.

Priority 3 — SEMANTIC / TEXTUAL SEARCH (supplemental only)
  grep / rg requirements/ specs/ for keywords from the finding.
  Results are additional DISCOVERY CANDIDATES for human review only.
  These MUST NOT authorize mutation or creation on their own.
  Flag as: "found via text search — not confirmed via structured traceability."

Priority 4 — USER CLARIFICATION
  When genuine ambiguity remains after Priority 1–3, and product authority is required.
  Do NOT escalate to user clarification for deterministic facts (defect vs. refinement).
```

---

## Explicit Prohibitions

### P1 — Grep match does not authorize Requirement mutation

A textual match in `requirements/` is NOT sufficient authority to mutate an existing
Requirement. A grep result is a discovery candidate. The agent MUST:

1. Read the full Requirement: description, acceptance_criteria, business_rules, out_of_scope.
2. Compare the candidate's SCOPE and INTENT against the finding.
3. Confirm with the developer before mutating if classification is AMBIGUOUS.

A grep match that touches the wrong Requirement is worse than no match — it corrupts
the artifact that other downstream artifacts depend on.

### P2 — Missing Requirement does not authorize new Requirement creation

Failure to find a Requirement via any structured or textual method does NOT automatically
justify creating a new Requirement. Absence of a match may mean:
- The derivedFrom/screens fields have not been backfilled (index gap, not product gap)
- The finding is within scope of an existing Requirement that is not textually obvious
- The index is stale — rebuild and retry first

Before creating a new REQ-NNN, the agent MUST:
1. Rebuild the index if stale.
2. Confirm via canonical file scan that no existing Requirement covers the intent.
3. Present the absence to the developer as a classification question: NEW_REQUIREMENT or AMBIGUOUS.
4. Wait for developer confirmation before creating REQ-NNN.

### P3 — Structural relationship produces candidate, not mutation authority

Finding `REQ-034` in the artifact index as a candidate for a given screen does NOT
automatically authorize updating REQ-034. The agent must inspect the candidate's actual:
- Intent and description
- Acceptance criteria scope
- Related Specs and their behavior contracts
- Active target mockup state for the screen
- Any Decisions that constrain the behavior

Only after this inspection can the agent classify the finding and propose the correct action.

---

## Resolution Algorithm

```
RECEIVE: manual UI finding from developer

STEP 1 — Identify affected screen(s)
  If finding names a screen explicitly: map to PAGE-NNN via planning/ui-inventory/ lookup.
  If not explicit: identify from screen description or ask developer.
  Result: [PAGE-CALENDAR, ...]

STEP 2 — Structured index query (Priority 1)
  If .mxagile/state/artifact-index.json exists and is valid:
    Query APPLIES_TO edges for PAGE-NNN
    Query DERIVED_FROM edges (reverse) for PAGE-NNN
    Query VERIFIED_BY edges for scenarios on PAGE-NNN -> their traceability.requirements
  Merge results -> structured_candidates

STEP 3 — Direct canonical traversal (Priority 2; always run if index is absent/stale)
  Scan requirements/*.yml for screens[] containing PAGE-NNN
  Scan requirements/*.yml for derivedFrom == PAGE-NNN
  Scan planning/scenarios/*.yaml for screen_id == PAGE-NNN -> traceability.requirements[]
  Merge with structured_candidates -> verified_candidates

STEP 4 — Semantic text search (Priority 3; supplemental)
  Run keyword search on requirements/ for terms from the finding.
  Add results as additional_candidates (flagged as text-search only).

STEP 5 — Inspect each candidate
  For each candidate in verified_candidates + additional_candidates:
    Read full Requirement YAML (description, acceptance_criteria, business_rules)
    Determine: does this Requirement's SCOPE encompass the finding's concern?
    Read related Specs via spec.requirements[] reverse lookup
    Read active target mockup for PAGE-NNN (target_revision or target_mockup path)
    Apply source-priority.md for concern-specific authority

STEP 6 — Classify the finding (see Classification Vocabulary below)
  Apply classification rule based on inspection results.

STEP 7 — Propose action to developer
  State: screen identified, candidates found/not found, classification with rationale.
  DO NOT mutate any artifact in this step.
  Wait for developer confirmation where product authority requires it.
  See "When to Invoke Product Acceptance" below.

STEP 8 — Execute approved action
  Perform only the classified action.
  Preserve existing REQ/SPEC IDs when intent is being refined.
  Create new REQ-NNN only after developer confirmation.
  Record changes in planning/decisions/DEC-NNN.md if decision was required.
```

---

## Finding Classification Vocabulary

| Classification | Meaning | Typical action |
|---|---|---|
| `EXISTING_REQUIREMENT_REFINEMENT` | Finding is within scope of an existing Requirement; the Requirement text or acceptance criteria need updating | Update REQ-NNN (preserve ID); update related Specs if behavioral contract changes |
| `SPEC_REFINEMENT` | Requirement scope is correct; only the Spec behavioral detail needs updating | Update SPEC-NNN (preserve ID); Requirement unchanged |
| `MOCKUP_REFINEMENT` | Requirement is silent on the specific concern; accepted target mockup needs updating | Invoke Autonomous Refinement process; Requirement unchanged |
| `IMPLEMENTATION_DEFECT` | Requirement and Spec define the correct behavior; implementation diverges | File implementation defect; DO NOT modify Requirement, Spec, or mockup |
| `PARITY_DEFECT` | Accepted target mockup already shows the correct state; implementation shows different state | File parity defect in parity-verification YAML; DO NOT modify Requirement or mockup |
| `NEW_REQUIREMENT` | Finding introduces genuinely new user/system capability not in any existing Requirement | Present as NEW_REQUIREMENT candidate; developer must confirm before REQ-NNN is created |
| `DECISION_REQUIRED` | Classification is ambiguous or competing product authorities exist | Present to developer; do not resolve unilaterally |
| `AMBIGUOUS` | Multiple partial matches; none clearly encompass the intent | Present all candidates to developer with rationale; await guidance |

### Classification Rule (Decisive Cases)

```
Finding's concern is within scope of an existing Requirement's acceptance criteria
  AND accepted target mockup already shows the correct state
  AND implementation diverges from mockup
  -> PARITY_DEFECT

Finding's concern is within scope of an existing Requirement's acceptance criteria
  AND implementation diverges from Requirement AC
  AND mockup matches AC
  -> IMPLEMENTATION_DEFECT

Finding's concern is within scope of an existing Requirement
  BUT the Requirement AC is silent on the specific concern
  AND accepted target mockup also does not specify it
  -> MOCKUP_REFINEMENT (mockup update through Autonomous Refinement)

Finding's concern is within scope of an existing Requirement
  BUT the Requirement AC is silent on the specific concern
  AND Spec's behavior contract needs updating
  -> SPEC_REFINEMENT

Finding's concern would expand or change the meaning of an existing Requirement
  -> EXISTING_REQUIREMENT_REFINEMENT (update Req; keep ID)

Finding's intent is not covered by any existing Requirement after full inspection
  -> NEW_REQUIREMENT candidate (developer must confirm)

Multiple existing Requirements partially overlap the finding
  -> AMBIGUOUS or DECISION_REQUIRED
```

---

## When to Invoke Product Acceptance

Product authority is required when product-binding decisions change:
- `EXISTING_REQUIREMENT_REFINEMENT`: developer must approve before REQ update is written.
- `NEW_REQUIREMENT`: developer must confirm scope before REQ-NNN is created.
- `MOCKUP_REFINEMENT`: developer must accept via Autonomous Refinement process.
- `DECISION_REQUIRED` or `AMBIGUOUS`: developer must resolve.

Product authority is NOT required for deterministic diagnostic work:
- `PARITY_DEFECT`: recording the defect in parity-verification YAML is autonomous.
- `IMPLEMENTATION_DEFECT`: recording the defect is autonomous.
- Index rebuild when stale: fully autonomous.
- `SPEC_REFINEMENT` for non-scope-expanding behavioral detail: depends on project policy;
  consult source_authority in mxagile-project.yaml.

Do NOT create unnecessary human gates for deterministic facts. Turning every
resolver result into a mandatory user confirmation is a violation of MxAgile's
autonomous lifecycle behavior.

---

## Impact Resolver

Use `scripts/resolve_impact.py` to perform structured trace resolution.

```bash
python scripts/resolve_impact.py --path <project_root> PAGE-CALENDAR
python scripts/resolve_impact.py --path <project_root> REQ-034
python scripts/resolve_impact.py --path <project_root> SPEC-012
python scripts/resolve_impact.py --path <project_root> --mockup kidscompass-web
```

Resolver output contains FACTS AND CANDIDATES. It does NOT decide:
- Which Requirement to mutate
- Whether a finding is a new Requirement
- Whether product intent changed

Those remain agent/refinement reasoning decisions per this policy.

---

## Integration with Source Priority

Apply `policies/source-priority.md` concern resolution after candidate identification:

- `ui_visual` concern (layout, spacing, colors): authority = target mockup
- `ui_interaction` concern (navigation, actions): authority = target mockup
- `business_logic` concern: authority = Requirements
- `data_rules` concern: authority = Requirements / Specs

A conflict between mockup and Requirement within the SAME concern: DECISION_REQUIRED.
A difference between mockup and Requirement across DIFFERENT concerns: NOT a conflict — each concern has its own authority.

---

## Backward Compatibility

Projects without `screens[]` populated in Requirements can still use Priority 2 and 3.
The resolver falls back to scenario-based lookup and text search gracefully.
No existing Requirements are invalidated merely because screens[] is not yet populated.
