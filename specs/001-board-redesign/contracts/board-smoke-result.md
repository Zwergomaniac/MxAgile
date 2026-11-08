# Contract: Board Smoke (CS-7)

## Aufruf

- `python .mxagile/tools/board_smoke.py --project-root <p> [--format json|text] [--include-reconciliation] [--timeout 60]`
- `python .mxagile/tools/project_compatibility.py doctor --board-smoke [--format json]` — führt Doctor aus und anschließend den Smoke; ohne Flag bleibt Doctor unverändert browserfrei.
- `install-core.ps1`: nach erfolgreichem Doctor **nur interaktiv** eine Ja/Nein-Frage; Standardantwort Nein; nicht-interaktiv oder CI → kein Smoke, Bericht `Board Smoke: NOT RUN (non-interactive)`.

## Stufen und Budgets

| Stufe | Inhalt | Budget |
|---|---|---|
| S0 | Payload, freier Port, Python-Deps | 0,5 s |
| S1 | Serverstart `--port 0`, Ready-Zeile | 15 s Timeout (Ziel 1–3 s) |
| S2 | `/api/status` 200 + schema-valide; `/api/page-previews`; `/api/gallery?screen_id=<erste Page>` | 5 s |
| S3 | Browser: Routen der versionierten Liste sichtbar; kein `pageerror`, keine Console-Errors, kein „Project status unavailable" | 6 s |
| S4 | je 1 Wave-, Requirement-, Page-Drilldown (erste nach ID) | 2 s |
| S5 | ≤ 5 Links (Source, Reference, Design Preview, Capture, Parity-Source; jeweils nur falls vorhanden) | 2 s |
| S6 | 6 Konsistenzwerte UI = API (R-08) | 0,5 s |
| Cleanup | Browser zu, Server beenden, Port frei | 1 s |

Gesamt: Ziel ≤ 15 s, harte Grenze 60 s (`TIMEOUT`).

## Ergebnis

```json
{
  "check": "board_smoke", "schema_version": 1,
  "result": "PASS|FAIL|UNAVAILABLE|TIMEOUT|ERROR",
  "duration_seconds": 0.0, "core_version": "…", "project_fingerprint": "sha256:…",
  "route_list_version": 1,
  "browser": {"available": false, "engine": null, "source": "python-playwright|playwright-cli|none"},
  "stages": [{"id": "S0", "result": "PASS|FAIL|UNAVAILABLE|SKIPPED|TIMEOUT", "seconds": 0.0, "failures": [{"route": null, "kind": "…", "message": "…"}]}],
  "artifacts": {"failure_screenshots": ["<os-temp>/mxagile-board-smoke/<run>/<route>.png"]},
  "project_unchanged": true
}
```

- `result=UNAVAILABLE`, wenn S3/S4 mangels Browser UNAVAILABLE und alle übrigen Stufen PASS sind; nie PASS.
- `project_unchanged`: Vergleich `git status --porcelain` und Stat der kanonischen Wurzeln vor/nach.
- Exit-Codes: `0` PASS, `1` FAIL, `2` UNAVAILABLE, `3` TIMEOUT/ERROR.
- Screenshots nur bei FAIL, nur unter OS-Temp.
- Verboten: Mendix-Runtime, Visual Parity, Crawling, Regression-Suiten, Projektschreibzugriffe, Browser-Installation.
