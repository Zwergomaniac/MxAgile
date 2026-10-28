# mxcli Known Tooling Limitations

**Source:** MxAgile A/B/C/D acceptance campaign evidence (2026-10)
**Classification:** KNOWN TOOLING LIMITATIONS — not application defects

This document records mxcli behavior limitations discovered during acceptance
campaigns. These are tooling characteristics that projects cannot control.

---

## How to Use This Document

These limitations inform how MxAgile selects verification paths.

**Do NOT:**
- Treat these as application defects
- Record them as MxAgile lifecycle failures
- Use a failing mxcli command as evidence of an application problem

**DO:**
- Select the strongest supported verification method for the specific assertion
- Document project-specific workarounds in project `.concord/` or `planning/`
- Report new mxcli issues to the Mendix mxcli team as upstream findings

---

## Known Limitations

### KL-001: CALL MICROFLOW — Not Available in Tested Versions

**Symptom:** `mxcli exec call-microflow` command not recognized or exits with error.
**Observed in:** Selected mxcli versions during CapTrack acceptance campaign (2026-10).
**Impact:** Microflow invocation via mxcli not available for acceptance testing.
**Evidence basis:** Campaign finding; command returned non-zero exit with "unknown command" or similar.
**Metric classification:** PROXY (campaign observation; may not apply to all mxcli versions)

**Recommended alternative:**
- Use `mxcli test` with unit-test runner where supported.
- Use Playwright/browser-based acceptance tests to trigger microflows via the UI.
- Use OQL queries (see KL-003) only for state verification, not microflow invocation.
- Consult current mxcli documentation for the command status in your installed version.

---

### KL-002: Windows Attach / PID Resolution Issue

**Symptom:** `mxcli attach` or PID-based process attachment fails or is unreliable on Windows.
**Observed in:** Windows developer workstation environments during campaign.
**Impact:** Programmatic attach to running Mendix runtime may not work reliably for process management.
**Evidence basis:** Campaign finding; sporadic failures in Windows PID resolution.
**Metric classification:** PROXY (observed; specific mxcli version not recorded)

**Recommended alternative:**
- Use port-based reachability check (`HTTP GET localhost:<port>`) instead of PID attachment.
- Use `.mxagile/tools/check-studio-pro-status.ps1` for Studio Pro process detection.
- Do not rely on PID attachment for APPLICATION_REACHABLE verification.

---

### KL-003: OQL Invocation Expectations

**Symptom:** OQL-based verification commands may require specific runtime state or configuration
to function (active database connection, module access, runtime reachability).
**Observed in:** Campaign environment.
**Impact:** OQL is not a universally applicable verification mechanism for all Mendix projects.
**Evidence basis:** Campaign observation; OQL queries failed in some runtime states.
**Metric classification:** PROXY

**Important:** OQL is NOT the correct verification path for all Mendix assertions.

**Selection guidance — choose the strongest supported verification method:**

| Assertion type | Preferred method |
|----------------|-----------------|
| UI navigation and display | Playwright browser test |
| Business logic result | Playwright + UI-visible outcome, OR mxcli test (if supported) |
| Database state | OQL via mxcli (if runtime ACTIVE and OQL supported) |
| Microflow execution | Playwright (trigger via UI), OR mxcli test |
| Model consistency | `mxcli check --references`, `mxcli lint` |
| Runtime reachability | HTTP GET probe (APPLICATION_REACHABLE) |

Do not use OQL as the only verification method for assertions that can be
verified by stronger evidence (e.g., Playwright acceptance tests).

---

## Classification Note

All items in this document are classified as:

`MXCLI_TOOLING_BEHAVIOR` — Observations about mxcli behavior that projects cannot control.

These are recorded as upstream findings. They do not represent MxAgile framework defects
or application defects in consumer projects.

---

## Version Sensitivity

mxcli capabilities change between versions. Before relying on any command:
1. Run `mxcli --version` to identify the installed version.
2. Consult the Mendix mxcli changelog for command availability.
3. Use `mxcli help <command>` to verify the command is available.

Do not hard-code mxcli command assumptions into MxAgile policies.
