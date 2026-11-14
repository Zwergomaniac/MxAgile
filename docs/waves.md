# Planning in Waves

To manage complexity and group related features, MxAgile uses the concept of "Waves". A wave is a collection of specifications (`.spec` files) that are planned and implemented as a single unit.

## Canonical lifecycle Wave identifiers

The canonical identifier grammar is the existing `wave_id` pattern in
[`task.schema.json`](../.mxagile/schemas/task.schema.json): `^W[A-Za-z0-9_-]+$`.
This permits numeric IDs, alphabetic suffixes and existing legacy forms; it is not
replaced by a narrower numeric-only grammar. Examples: `W15`, `W16a`, `W16b`,
`W17e`, `W18a`, `W18b`, `W123`, and `WAVE-01`. The leading `W` is uppercase.
Identifiers are case-sensitive and preserved exactly: no suffix removal, case
conversion, numeric normalization or collision between `W18a` and `W18b`.

[`wave_ids.py`](../scripts/wave_ids.py) reads this schema definition for plan headings,
checklist paths, timeline mentions and natural Board/Timeline ordering. A heading
must contain a complete identifier, not a prefix of an invalid token. Mission,
Process State, Handoff and Run/Event fields preserve their exact identifiers; their
other schema constraints remain independent. Finding uses the same identifier pattern.
Natural sorting orders numeric components before their suffixes; it never changes identity.

A plan heading establishes only planned membership. Canonical lifecycle registration
and phase come from `planning/lifecycle/process-state.yaml`, with the active Wave
bound by `planning/mission/mission-state.yaml`. Git commit names and timeline mentions
are historical evidence, not permission to create retroactive Wave registrations or
mark Waves done. The legacy `.wave` grouping described below is not an automatic
lifecycle registration mechanism.

After an identifier-related Guard fix, reconcile lifecycle from canonical evidence
before project implementation: distinguish planned/history-only Waves from registered,
not_started, implementing/partial and done Waves. Require current Framework/migration
compatibility, fresh compatible Doctor, canonical active Wave, resolved revision
Reconciliation/Acceptance boundary and an understood working tree before the
Pre-Implementation Checkpoint. Do not promote a Revision or change `active_target`
to bypass the regular handoff-ready/previous_revision Reconciliation contract.

## How it Works

1.  **Define Specs:** First, create individual `spec` files for each distinct piece of functionality (e.g., a new entity, a new page, a modified process).

2.  **Group in a Wave:** Create a new `.wave` file in the `/waves` directory. This file lists all the `Spec` IDs that should be included in the wave.

    **Example: `waves/WAVE-01_Initial_Features.wave`**
    ```
    ID: WAVE-01
    Description: The first wave, implementing core customer features.
    Spec: SP-001
    Spec: SP-002
    ```

3.  **Update the Index:** Run the trace indexer to make the framework aware of the new wave and its contents.
    ```powershell
    ./scripts/mxagile-build-trace-index.ps1
    ```

4.  **Plan the Wave:** Use the `mxagile-plan-wave.ps1` script with the wave's ID. This script will find all associated specs, process them, and generate a single, combined `.mdl` script for the entire wave.

    ```powershell
    ./scripts/mxagile-plan-wave.ps1 -WaveId WAVE-01
    ```

5.  **Result:** The output will be a file like `planning/plans/WAVE-01.mdl`, which contains all the Mendix changes for the entire wave, ready to be executed.

This approach allows developers to work on small, manageable specs while still delivering larger, coordinated feature sets to the Mendix application.
