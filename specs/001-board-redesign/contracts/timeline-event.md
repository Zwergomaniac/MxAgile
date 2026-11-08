# Contract: Timeline Event (abgeleitet, CS-5)

Datei: `.mxagile/schemas/project-timeline.schema.json` (neu; **nicht kanonisch** — beschreibt eine Projektion).

```yaml
event_id: "EV-<sha256(type|source_path|commit|field|value)[:16]>"   # deterministisch
type: task.status_changed            # Liste siehe Plan D.2
authority_class: GIT_DERIVED         # CANONICAL_RECORD | GIT_DERIVED | COMMIT_TRAILER | GIT_MENTION
lane: attributed                     # attributed | unattributed
occurred_at: "2026-11-05T12:56:10+01:00"
time_basis: commit_time              # artifact_field | commit_time
title: "TASK-231 → blocked"
entities:
  - {type: task, id: TASK-231, derivation: touched_artifact}
  - {type: wave, id: W7, derivation: "task.wave_id"}
commit: {hash: "<40 hex>", first_parent: "<40 hex>", author: "…", subject: "…"} | null
source: {path: planning/tasks/TASK-231.yml, field: status, before: pending, after: blocked} | null
change_set_id: CS-… | null           # nur bei schema-validem Change-Set mit passendem Commit
mission_label: "…" | null            # Freitext aus Change-Set, nur Anzeige
mission_id: MISSION-… | null         # nur bei exakter Gleichheit mit mission-state
health: [CHANGE_SET_SCHEMA_INVALID] | []
```

## Regeln

1. `derivation` ∈ { `artifact_field`, `touched_artifact`, `commit_trailer`, `change_set_paths`, `canonical_field_link` (z. B. `task.wave_id`), `message_mention` }.
2. `lane = unattributed`, wenn keine `entities` außer `message_mention` existieren.
3. **Verboten**: Zuordnung aus Zeitnähe, Branch-Namen, Freitext-`mission_id` (außer exakter ID-Gleichheit), Datei-Ähnlichkeit.
4. Merge-Commits: First-Parent-Diff; zweiter Elternteil nur als Hinweis.
5. Index-Invalidierung, wenn `last_indexed_commit` kein Vorfahr von HEAD ist.
6. Zwei Läufe auf identischer Historie erzeugen identische `event_id`-Mengen.
7. Keine Live-/Harness-Telemetrie (OD-2).
