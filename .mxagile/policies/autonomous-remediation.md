# Autonomous Remediation Policy

Governs when an AI agent may autonomously remediate a finding versus when it must stop and
request a human decision. Applies to the Acceptance Agent and any agent performing model-level
or evidence-level gap analysis.

## Core Principle

Autonomous remediation is permitted when the **canonical expectation is unambiguous** —
the authoritative source (Design Contract, acceptance criteria, requirements) explicitly states
what must or must not exist, without contradiction.

Security relevance alone does NOT require an additional human decision when the canonical negative
capability is already explicit in the Design Contract or requirements.

The remediation itself must always be:
- smallest valid fix
- reversible where practical
- validated (regression-tested after application)
- constrained to the authoritative scope

## The Four States

---

### REQUIRED_BUT_UNAVAILABLE

**Definition:** A requirement or proof point mandates a capability, but no corresponding model
artifact, security rule, or implementation exists.

**Autonomous remediation:** PERMITTED when canonical expectation is unambiguous:
- The requirement/Design Contract explicitly and without contradiction states the capability is required
- The fix is reversible (can be undone with a model change)
- The fix does not require a business logic judgment call
- There is only one reasonable implementation of the requirement at the scaffolding level

Apply the smallest valid fix. Validate. Regression-test.

**DECISION_REQUIRED if:**
- The canonical expectation is ambiguous or contradicted by another source
- The fix requires a business logic decision (e.g. microflow behavior, XPath scope choice)
- Multiple valid implementations exist and none is obviously correct
- The scope of change extends beyond the stated requirement

**Record:** `remediation_state: REQUIRED_BUT_UNAVAILABLE` in the proof point.

---

### EXPLICITLY_FORBIDDEN_BUT_AVAILABLE

**Definition:** The Design Contract (`cannot[]`) or requirements explicitly state that a capability
must NOT exist for a role or resource/operation combination, but a model artifact implementing
that capability is present.

**Autonomous remediation:** PERMITTED when canonical expectation is unambiguous:
- The capability prohibition is explicitly stated without contradiction in an authoritative source
- The fix is the smallest valid correction (remove access rule, disable navigation item, restrict entity access)
- The fix is reversible
- The fix is validated and regression-tested

Security relevance alone does NOT prevent autonomous remediation when the canonical negative
capability is already explicit. If the Design Contract says `cannot[CAP-SITE-DELETE]`, the agent
may remove the corresponding access without waiting for additional confirmation.

**DECISION_REQUIRED if:**
- The canonical source has conflicting signals (one source forbids, another is silent or approves)
- Removing the capability would affect scope beyond the stated role/resource/operation
- The fix cannot be expressed as a single reversible change

**Record:** `remediation_state: EXPLICITLY_FORBIDDEN_BUT_AVAILABLE`.

---

### UNSPECIFIED_BUT_AVAILABLE

**Definition:** A model capability exists, but no requirement or proof point describes it.
Its presence is neither confirmed nor denied by the design contract or requirements.

**Autonomous remediation:** PROHIBITED. Never act on unspecified capabilities without a decision.

**Required action:**
1. Record `remediation_state: UNSPECIFIED_BUT_AVAILABLE`.
2. Raise DECISION_REQUIRED: "Model contains [capability]. Not mentioned in requirements. Keep, scope-guard, or remove?"
3. Developer decision is mandatory before any action.

**Rationale:** Unspecified capabilities may be intentional (future feature, platform default,
inherited from Company Layer). Autonomous removal could break production behavior.

---

### BUSINESS_EXPECTATION_UNKNOWN

**Definition:** A verification test failed, but it is unclear whether the application behavior
is wrong or the test expectation is wrong.

**Autonomous remediation:** PROHIBITED. No action until the expectation is confirmed.

**Required action:**
1. Record `remediation_state: BUSINESS_EXPECTATION_UNKNOWN`.
2. Classify as TEST_DEFECT (wrong expectation) or APPLICATION_DEFECT (wrong behavior) —
   this distinction requires human input. See `policies/test-defect-protection.md`.
3. Raise DECISION_REQUIRED with both hypotheses stated.

---

## Summary Table

| State | Auto-Remediate | Condition |
|---|---|---|
| REQUIRED_BUT_UNAVAILABLE | Permitted | Canonical expectation unambiguous; fix reversible; no business logic judgment |
| EXPLICITLY_FORBIDDEN_BUT_AVAILABLE | Permitted | Canonical prohibition explicit; smallest fix; no scope bleed |
| UNSPECIFIED_BUT_AVAILABLE | **Prohibited** | DECISION_REQUIRED always |
| BUSINESS_EXPECTATION_UNKNOWN | **Prohibited** | DECISION_REQUIRED always |

## Escalation on Refusal

If a DECISION_REQUIRED raised by this policy is not answered within the same work session:
- Record the gap in `.concord/scratch/process-state.yaml` under `waves.<W>.gates.acceptance_gate.pending_decisions`.
- Do not block unrelated proof points from proceeding.
- The acceptance gate cannot reach `passed` while any `DECISION_REQUIRED` remains open.

## Safety Integration

This policy supplements but does not replace `policies/safety-rules.md`.
All universal safety rules apply at all times, regardless of remediation state.
