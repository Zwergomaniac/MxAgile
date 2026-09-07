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
- **Versionskontrolle:** Mendix Team Server (KEIN manuelles git commit)

---

## Architektur-Prinzipien

<!-- TODO: Welche Kern-Architekturentscheidungen gelten projektübergreifend? -->

### [Prinzip 1]
...

### [Prinzip 2]
...

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
| `sprints/decisions.md` | Architekturentscheidungen | Lesen vor jeder Entscheidung |
| `projekt.md` | Diese Datei | Alle Agenten lesen |

---

## Planungs-Regeln

<!-- TODO: Projektspezifische Planungsregeln ergänzen -->

- Annahmen markieren: ⚠️ ASSUMPTION
- Offene Entscheidungen markieren: ⚠️ DECISION REQUIRED