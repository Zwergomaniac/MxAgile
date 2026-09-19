# Checklists

Eine Implementierungscheckliste je Wave: `W<n>-implementation-checklist.yaml`,
zum Beispiel `W1-implementation-checklist.yaml`.

Entsteht im Gate `dfc-gate-to-ready` aus UI-Inventar und Story-Spezifikationen
(siehe `.MxAgile/skills/gate-to-ready.md`). Nicht manuell vor dem Gate anlegen.

Jedes Item nennt die betroffenen Requirements im Feld `req` — das ist die
Traceability zwischen Wave-Arbeit und Einzelanforderung.

## Formatreferenz

`implementation-checklist.template.yaml` in diesem Ordner zeigt das vollstaendige
Item-Schema inklusive `test:`- und `inspect:`-Block sowie die erlaubten `state`-
und `status`-Werte (u.a. `verification_failed` fuer eine gescheiterte Wave-Abnahme).

## Ablauf

1. Gate erzeugt die Checkliste fuer die naechste Wave.
2. Implementation-Agent arbeitet `pending`- und `failed`-Items ab.
3. Acceptance-Agent traegt `test_result` / `inspect_result` ein.
4. Bei Abweichungen: betroffene Items auf `status: failed`, kein Ruecklauf der
   gesamten Checkliste.

