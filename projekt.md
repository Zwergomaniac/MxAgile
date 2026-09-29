# [PROJEKTNAME] — Projekt-Kontext

> **Gemeinsame Grundlage für alle Agenten.**
> Lies diese Datei zuerst. Tool-spezifische Regeln stehen in `CLAUDE.md` (Claude Code),
> `skillssource/AGENTS.md` (Maia) und `AGENTS.md` (generische Agenten) — nicht hier.

---

## Projektziel

<!-- TODO: Was soll das System leisten? Für wen? Welches Problem löst es? -->

**[PROJEKTNAME]** ist ...

**Zielnutzer:** ...

---

## Tech Stack

<!-- TODO: Mendix-Version, Deployment-Ziel, Integrationen -->

- **Plattform:** Mendix Studio Pro [VERSION]
- **Deployment:** [Mendix Cloud / On-Premise / PaaS]
- **Distribution:** [Web / PWA / Native Mobile]
- **Integrationen:** [REST, OData, externe Systeme]
- **Backlog:** [Mendix Epics Board / andere Quelle; Source of Truth festlegen]
- **Versionskontrolle:** Mendix Team Server (KEIN manuelles git commit)

## Gemeinsamer Stand und lokaler Zustand

Im Team geteilt werden Modell, Quellcode, Agentenregeln, Skripte, Beispielkonfigurationen,
Input-Resources und versionierte Artefakte unter `planning/`. Lokal bleiben Zugangsdaten in
`.env.mendix`, der mxcli-Katalog `.mxcli/catalog.db`, generierte Board-Snapshots unter
`sprints/generated/`, Reconciliation-Berichte unter `planning/generated/` sowie Runtime-
und IDE-Ausgaben. Die lokale `.env.mendix` nie in eine Projektvorlage kopieren.

---

## Architektur-Prinzipien

<!-- TODO: Welche Kern-Architekturentscheidungen gelten projektübergreifend? -->

### [Prinzip 1]
...

### [Prinzip 2]
...

### Abgeleitete Arbeitsartefakte

Wenn Mendix Epics als Backlog-Quelle festgelegt ist, liegen versionierte technische
Spezifikationen, Testmatrizen, Traceability- und Abhaengigkeitsmatrizen unter `planning/`.
Sie referenzieren Board-Story-ID und Source Fingerprint, sind kein zweites Backlog und
werden nach jedem Board-Sync mit `scripts/reconcile-derived-artifacts.ps1` geprueft.
Implementation Waves unter `planning/execution-waves.md` sind technische Reihenfolge,
keine lokalen Sprints. `planning/generated/board-action-report.md` nennt nur manuell im
Board nachzuziehende Aktionen.

---

## Rollen & Stakeholder

<!-- TODO: Welche Nutzerrollen gibt es? Welche Verantwortlichkeiten? -->

| Role | Beschreibung |
|---|---|
| `Administrator` | ... |
| `[Rolle]` | ... |

---

## Module

<!-- TODO: Alle Module mit Einzeiler-Beschreibung -->

| Modul | Zweck |
|---|---|
| `Core` | [Stammdaten, Infrastruktur, ...] |
| `[Modul]` | ... |

---

## Sprint-Struktur

<!-- TODO: Phasen, Sprints, MVP-Definition -->

| Phase | Sprints | Inhalt |
|---|---|---|
| MVP | 0–? | ... |
| Phase 2 | ?–? | ... |

---

## Schlüsseldateien

<!-- TODO: Wo liegt die Spezifikation? Welche Dateien niemals modifizieren? -->

| Datei | Zweck | Regel |
|---|---|---|
| `[Spec.md]` | Produkt-Spezifikation | **NIEMALS modifizieren** |
| `sprints/sync-workflow.md` | Mendix-Epics-Synchronisierung | Vor Story-Arbeit lesen, wenn das Board als Backlog-Quelle konfiguriert ist |
| `planning/README.md` | Regeln fuer abgeleitete Arbeitsartefakte | Vor neuer Spezifikation lesen |
| `planning/execution-waves.md` | Technische Reihenfolge innerhalb der Board-Sprints | Nach Board-Sync pruefen |
| `sprints/decisions.md` | Architekturentscheidungen | Lesen vor jeder Entscheidung |
| `projekt.md` | Diese Datei | Alle Agenten lesen |

---

## Planungs-Regeln

<!-- TODO: Projektspezifische Planungsregeln ergänzen -->

- Annahmen markieren: ⚠️ ASSUMPTION
- Offene Entscheidungen markieren: ⚠️ DECISION REQUIRED
- Wenn Mendix Epics als Backlog-Quelle festgelegt ist: Vor Story-Arbeit
	`scripts/sync-epics-stories.ps1` ausfuehren und den lokalen Snapshot lesen.
- Danach `scripts/reconcile-derived-artifacts.ps1` ausfuehren; lokale Artefakte nur
	mit Board-ID und Source Fingerprint unter `planning/` anlegen.
- Board-Status und Tasks nicht lokal fortschreiben; fuer manuelle Board-Aktionen
	`scripts/generate-board-action-report.ps1` verwenden.