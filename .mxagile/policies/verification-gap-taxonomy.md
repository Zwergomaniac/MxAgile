# Verification Gap Taxonomy

Defines the vocabulary for classifying verification coverage gaps when a new or refined
Requirement enters the canonical model. Consumed by Discovery Agent, Refinement Agent,
and the test-contract skill.

This taxonomy prevents overreaction: not every new Requirement should trigger TC/PP/VPL
materialization. Use the smallest justified classification and let the late-materialization
principle govern what actually gets created.

Full late-materialization contract: `policies/verification-materialization.md`.

---

## Gap Classification Vocabulary

### NO_TC_YET

**No Test Contract currently covers this Requirement or its domain.**

This is a statement of absence — it does NOT automatically trigger TC materialization.

Applicable when:
- A Requirement is newly created and no existing TC references it
- A domain is newly identified with no historical TC coverage
- The Requirement is in DRAFT status and implementation is not yet planned

**What NO_TC_YET does NOT authorize:**
- Creating a TC
- Creating Proof Points
- Creating a VPL
- Creating executable tests
- Collecting Evidence

TC creation is deferred until the Requirement is accepted (status: accepted) AND has
stable, reviewed acceptance criteria. Creating a TC against a DRAFT requirement is
pre-materialization churn.

**Next action:** Record the gap in the story specification as `verification_gap: NO_TC_YET`.
Revisit when the Requirement transitions to `accepted` and passes the Testability Gate.

---

### VERIFICATION_COVERAGE_GAP

**An existing TC covers the relevant domain but does not yet cover the new or expanded
Requirement scope.**

Applicable when:
- A Requirement is new but falls within the domain of an existing active TC
- A Requirement is refined with new acceptance criteria that are not covered by any
  existing PP claim in the domain TC
- The existing TC covers related but not identical functionality

This gap signals an EXTEND candidate — the existing TC may be extended with new PPs
rather than creating an entirely new TC from scratch.

**Distinction from NO_TC_YET:**
- NO_TC_YET: no TC for this domain exists at all
- VERIFICATION_COVERAGE_GAP: a TC exists but its coverage does not include the new scope

**What VERIFICATION_COVERAGE_GAP does NOT automatically authorize:**
- Creating a new TC (extending the existing one may be more appropriate)
- Creating VPL entries
- Creating executable tests
- Collecting Evidence for the gap

**Next action:** Record the gap as `verification_gap: VERIFICATION_COVERAGE_GAP` with
`related_tc_id` pointing to the existing TC. Evaluate using EXTEND action
(see `policies/verification-materialization.md`) when the Requirement is accepted.

---

### TEST_BINDING_GAP

**Stable TC and PP verification intent exists but executable binding or materialization
is absent or insufficient.**

Applicable when:
- A TC/PP exists and is active
- The PP claim is stable and reviewed
- No VPL entry, no Playwright steps, or no locator binding exists for this PP
- The PP has `execution_binding_stale: true`

This gap is NOT about missing intent — the what-to-prove is known. The gap is in the
HOW-to-execute.

This gap is the appropriate classification for the REMATERIALIZE action:
the PP claim is unchanged, but the technical execution binding must be refreshed.

**Next action:** Classify as REMATERIALIZE in `policies/verification-materialization.md`.
Generate or refresh VPL entries. Do NOT reassess the PP claim unless the claim itself changed.

---

### EVIDENCE_STALE

**Verification definition (TC/PP/VPL) remains valid but existing evidence no longer proves
the current implementation.**

Applicable when:
- TC status is `active`, PP status is `active`, VPL is `active`
- The implementation changed since evidence was collected
- Evidence manifest entries have `parity_result: STALE` or `STALE_REEXECUTION_REQUIRED`
- The last wave's evidence was produced against a prior implementation version

**Distinction from TEST_BINDING_GAP:**
- TEST_BINDING_GAP: the executable binding is stale or missing
- EVIDENCE_STALE: the binding is valid but evidence is outdated

**Next action:** Classify as REEXECUTE in `policies/verification-materialization.md`.
Rerun the existing executable tests without rewriting them. Do NOT change TC/PP/VPL.

---

## Classification Decision Table

| Observation | Correct classification |
|---|---|
| New Requirement, no TC in this domain | `NO_TC_YET` |
| New Requirement, existing TC for related domain | `VERIFICATION_COVERAGE_GAP` |
| Existing TC/PP, no VPL, implementation stable | `TEST_BINDING_GAP` |
| Existing TC/PP, VPL active, locators stale | `TEST_BINDING_GAP` → REMATERIALIZE |
| Existing TC/PP/VPL/evidence, implementation changed | `EVIDENCE_STALE` → REEXECUTE |
| Requirement scope expanded, existing TC partially covers | `VERIFICATION_COVERAGE_GAP` → EXTEND |
| Requirement AC changed, TC claim affected | Not a gap classification — trigger REASSESS |

---

## Late-Materialization Invariant

The following cascade MUST NOT be triggered automatically by a new or refined Requirement:

```
New/refined Requirement
  → NO automatic TC creation
  → NO automatic PP creation
  → NO automatic VPL creation
  → NO automatic executable test generation
  → NO automatic Evidence collection
```

A gap classification (NO_TC_YET / VERIFICATION_COVERAGE_GAP / TEST_BINDING_GAP /
EVIDENCE_STALE) is a DIAGNOSTIC — not an execution trigger.

The only authorized triggers for materialization below the boundary are:
1. Requirement status is `accepted` AND Testability Gate has passed
2. Implementation is sufficiently stable (checklist terminal state known)
3. An explicit developer-authorized decision to proceed

---

## Integration Points

- `policies/verification-materialization.md` — defines the action vocabulary (EXTEND, REASSESS, etc.)
- `policies/test-staleness.md` — defines TC/PP status transitions
- `schemas/requirement.schema.json` — Requirements may carry `source_ac_coverage` (P0 gap detection)
- `agents/discovery-agent.md` — Discovery Agent records initial gap classification
- `skills/gate-to-ready.md` — Testability Gate checks gap classifications before allowing TC creation
