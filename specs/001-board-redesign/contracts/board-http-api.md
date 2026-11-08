# Contract: Board HTTP API (read-only, Loopback)

Alle Endpunkte: nur `GET`, nur `127.0.0.1`, Header `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, CSP wie heute. Kein Endpunkt schreibt ins Projekt.

## Bestehend (Verhalten präzisiert)

| Endpunkt | Changeset | Verhalten |
|---|---|---|
| `GET /api/status` | CS-2 | liefert aktuellen Snapshot ohne synchronen Scan; enthält `projection_state{state, age_seconds, validated_age_seconds, reason, built_at_head, rebuilding}`; 503 nur bei `PROJECTION_ERROR` ohne letzten Stand |
| `GET /api/reconciliation` | CS-1, CS-2 | CS-1: `head`/`branch` auch ohne Watermark; CS-2: gecacht pro (HEAD, Watermark, Worktree-Hash), ≤ 10 s für 26 Commits |
| `GET /api/page-previews` | CS-1 | ohne Standalone-Interaction-Artefakte; Paritätsfeld `NOT_LOADED` ohne Wertanmutung, bis die Page-Gallery geladen ist |
| `GET /api/gallery[?screen_id=]` | CS-1, CS-2 | einzige serverseitige Regel für „letzter Lauf" |
| `GET /source/<path>` | CS-1, CS-2 | Allowlist enthält `parity_report`; Auflösung gegen Snapshot-Allowlist, ohne Neuberechnung (≤ 200 ms) |
| `GET /reference/…`, `/capture/…`, `/design-preview/…`, `/design-preview-source/…`, `/diagnostic-source/…` | CS-2 | gegen Snapshot-Allowlist; keine Signaturberechnung im Request |

## Neu

| Endpunkt | Changeset | Antwort |
|---|---|---|
| `GET /api/health` | CS-3 | `{projection, observation_states{bereich: state}, diagnostics_by_group{group: [..]}, counts}` |
| `GET /api/timeline?from=&to=&type=&wave=&requirement=&page=&mission=&change_set=&authority=&lane=&cursor=&limit=` | CS-5 | `{events: [TimelineEvent], next_cursor, index{state, last_indexed_commit, age_seconds}}`; `limit ≤ 200`, Standard 50 |
| `GET /api/page/<PAGE-ID>` | CS-6 | `PageHubEntry` (data-model §8) |
| `GET /api/requirement/<REQ-ID>` | CS-6 | Requirement + Traceability + `DeliveryAssessment` |

Fehlercodes: `400` ungültige Parameter (Whitelist wie heute), `404` unbekannte ID/nicht in Allowlist, `503` nur `PROJECTION_ERROR` ohne letzten Stand.

## Server-CLI

`serve_project_board.py --project-root <p> [--port <n>|0]` — `--port 0` (CS-7) wählt einen freien Port; Ready-Zeile unverändert `MxAgile Board: http://127.0.0.1:<port>/`.
Umgebungsvariablen: `MXAGILE_BOARD_PROFILE=1` (Timings), `MXAGILE_BOARD_CACHE_DIR` (Test-Override), `MXAGILE_BOARD_LEGACY_CACHE=1` (CS-2-Rückfall, ein Release).
