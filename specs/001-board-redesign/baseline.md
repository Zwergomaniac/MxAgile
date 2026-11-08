# Baseline (T004) — vor CS-1

- **Datum:** 2026-11-05 · **Framework:** `e6a1481` (Board-Code unverändert seit `6b5091d`)
- **Referenzprojekt:** Referenzprojekt `dev/gb` @ `6d8923dc` (read-only; parallele Fremdarbeit aktiv: `.mpr` und 3 `mprcontents` modifiziert, neue untrackte Dateien)
- **Aufruf:** `PYTHONDONTWRITEBYTECODE=1 MXAGILE_BOARD_PROFILE=1 python -B scripts/serve_project_board.py --project-root <reference-project> --port 8797`
- **Projektzustand:** `git status --porcelain` vorher = nachher (keine Veränderung durch den Lauf); Port danach frei.

## Zeiten

| Anfrage | HTTP | Zeit |
|---|---|---|
| `/api/status` (kalt) | 200 | 15,72 s |
| `/api/status` (warm, Cache-Hit) | 200 | 4,69 s |
| `/api/page-previews` | 200 | 4,45 s |
| `/api/gallery` | 200 | 10,34 s |
| `/source/planning/decisions/DEC-053.yml` | 200 | 5,67 s |
| `/source/planning/parity/SCN-CAP-DEPARTMENTS-HTMLFIRST.yaml` | **404** | 6,05 s |
| `/reference/…rev37….html` | 200 | 5,95 s |

`/api/reconciliation` wurde bewusst nicht gemessen (dokumentiert 280–373 s, CT-FINDING-017).
Signaturberechnungen im Lauf: 11 (eine je Request und Rebuild-Validierung).

## Fakten für RC-01…03

| RC | Beobachtung |
|---|---|
| RC-01 | Reconciliation-Platzhalter: `availability: not_loaded`, `commit_range` ohne `to_commit`, Blocker `RECONCILIATION_NOT_LOADED` → Board rendert „BASELINE REQUIRED / HEAD UNKNOWN" |
| RC-02 | Page Previews: 11 Einträge (Status-Inventory: 10 Pages) |
| RC-03 | `source_references` enthält 0 Einträge vom Typ `parity_report`; Parity-Quelle → 404 |
