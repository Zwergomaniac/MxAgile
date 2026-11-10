# Wave: Mendix Merge Safety & Integration Strategy

Status: **IMPLEMENTIERT** (diese Wave). Evidenz: [mendix-merge-safety-baseline.md](mendix-merge-safety-baseline.md).
Policy: `.mxagile/policies/mendix-integration.md`. Tool: `scripts/mendix_merge_preflight.py`
(verteilt als `.mxagile/tools/mendix_merge_preflight.py`).

## Ziel

Vor einer Mendix-Branchintegration deterministisch bestimmen: normaler Studio-Pro-Merge, gezielte Konfliktauflösung, semantische
Reconciliation oder Replay, und nach der Integration prüfen, ob das Modell konsistent ist. Nicht mehr aus „`.mpr` auf beiden Branches
geändert“ auf hohes Risiko schließen.

## Vertrag

- **Studio Pro** ist die Mendix-aware Merge-Engine, **Concord** der Conflict-Resolution-/Investigation-Consumer. Concord ist nicht als Ursache belegt.
- `CLOSED-AUTONOM` darf einen anderen Pfad nur nutzen, wenn er technisch validiert gleichwertig und sicher ist.
- Replay ist Fallback, nicht Default. Ein eigener `.mpr`-Merge-Driver und `.gitattributes`-Änderungen sind **nicht** Teil dieser Wave.
- Keine neuen CLI-Namen: das Werkzeug folgt dem bestehenden Tool-Vertrag (`python .mxagile/tools/<tool>.py`).

## Umgesetzt

| Baustein | Inhalt |
|---|---|
| **Preflight** | `preflight --target --source [--base]`: löst die Revisionen über Git auf (auch Unterverzeichnisse und linked Worktrees), bestimmt alle Merge-Basen (`merge-base --all`), liest `.mpr`-Registry, Format und Mendix-Version, vergleicht Units strukturell auf BSON-Ebene |
| **Serialization Noise** | Klassen `SERIALIZATION_ONLY`, `DEFAULTS_ONLY`, `PRESENTATION_ONLY`, `SEMANTIC`; Feldreihenfolge, int-Breite, List-Marker, `$ID`-Churn und Reihenfolge von `Objects`/`Flows` zählen nicht als Overlap; Gegenprobe an gemessenen mxcli-Fällen |
| **Strategy Resolver** | genau eine Empfehlung: `STUDIO_PRO_MERGE` (`MERGE_NATIVE`), `STUDIO_PRO_MERGE_WITH_TARGETED_CONFLICT_REVIEW` (`MERGE_NATIVE_WITH_CONFLICT_REVIEW`), `SEMANTIC_RECONCILIATION`, `REPLAY_REQUIRED`, `BLOCKED` |
| **Criss-Cross / Basisabhängigkeit** | Ergebnis je Merge-Basis (`TARGET`/`SOURCE`/`BOTH`); weicht es ab, ist es `BASE_DEPENDENT` und keine Basis darf entscheiden |
| **Concord-Konfliktumfang** | `concord_scope` im Preflight-Report: nur echte offene Punkte (geteilte semantische Units, Delete/Modify, echte Identitätsdivergenzen, Sicherheitsentscheidungen); Rauschen, einseitige Änderungen und deterministische Ersetzungen sind ausdrücklich außerhalb des Umfangs |
| **Identity** | `IDENTITY_DIVERGENCE` mit Wirkung je Basis; explizite Identity-Reconciliation; Wiederherstellen vor Neuanlage (`restore_from`, `restore_path`) |
| **Security** | `GUARD_COLLAPSE` (Boolesches Literal gegen Guard-Ausdruck), `PROTECTED_MARKER`, `Security$*`; erzwingt eine ausdrückliche, protokollierte Entscheidung |
| **Gestuftes Post-Merge-Gate** | `postcheck --stage studio-pro-merge` (offener Concord-Umfang erlaubt, Exit 5), `concord-resolution` (nichts Offenes) und `final` (einzige Stufe mit `final_integrity_gate: PASS`) |
| **Post-Merge Integrity Gate** | `postcheck`: Konflikte aufgelöst, `.mpr` ↔ `mprcontents` konsistent (fehlend, verwaist, Hash), keine doppelten Artefaktnamen, keine verlorenen Units, erwartete Features beider Branches, geschützte Marker; `PASS` / `FAIL` / `INCOMPLETE` |
| **Observability** | Report mit Target/Source/Basen, Modellversion, Registry-Konsistenz, semantischen Units je Seite, Rauschen, geteilten Units, UUID-Divergenzen, Strategie, Blockern |
| **Orchestrierung** | Policy, Verweise in `implementation-agent`, `safety-rules`, `commit-authority` (PASS als Commit-Evidenz) und `operating-mode`; Installer verteilt das Tool; generierte Agent-Projektion neu erzeugt |
| **Korrigierte Guidance** | ALTER-first mit gemessenen Zahlen: `CREATE OR MODIFY` erzeugt 10 von 26 IDs neu und verliert Captions, `DROP` + `CREATE` 24 von 26 plus neue `StableId` |
| **Normalisierung** | kein Dauer-Workflow mit Pflicht-Formatierungscommit; ein begrenzter Durchlauf ist ausdrücklich als **WORKAROUND** gekennzeichnet |
| **Upstream-Fund** | [upstream/mxcli-serialization-stability.md](upstream/mxcli-serialization-stability.md) mit reproduzierbarer Evidenz (Issue-Entwurf, nicht eingereicht) |

## Regression Fixtures (`tests/test_mendix_merge_preflight.py`)

| Fixture | Erwartung |
|---|---|
| A: zwei Branches ändern verschiedene Microflows (`.mpr` auf beiden Seiten geändert) | `STUDIO_PRO_MERGE` |
| B: beide ändern denselben Microflow | `STUDIO_PRO_MERGE_WITH_TARGETED_CONFLICT_REVIEW` |
| C: mxcli-Serialisierung auf A, echte Änderung auf B | Rauschen nicht als Overlap, `STUDIO_PRO_MERGE` |
| D: gleicher Name, andere UUID-Linie, Basis-Änderung auf der anderen Seite | `SEMANTIC_RECONCILIATION` (`REBUILD_CONFLICT`) |
| E: `.mpr` ↔ mxunit inkonsistent (verwaist, fehlend, Hash) | `BLOCKED` |
| F: Format-, Minor-Versionswechsel; Patch-Unterschied nur Warnung | `REPLAY_REQUIRED` bzw. Warnung |
| G: Post-Merge verliert Unit; offener Git-Konflikt; ohne Preflight | Postcheck `FAIL` bzw. `INCOMPLETE`, nie `PASS` |
| H: linked Worktrees | richtige Heads, Merge-Basis, eigener Index, eigene Artefakte |
| **R: Concord-Scope und Stufen** | Scope enthält genau 10 Identitätsdivergenzen und 4 geteilte Units, 3 Entscheidungen, kein Rauschen; Studio-Pro-Stufe `OPEN_ITEMS` mit Exit 5, strukturelle Schäden bleiben dort `FAIL`; nach Auflösung `concord-resolution` PASS ohne Final-Freigabe, `final` PASS |
| **R: Reality-Fixture (Criss-Cross, 2 Basen)** | `STUDIO_PRO_MERGE_WITH_TARGETED_CONFLICT_REVIEW`, 10 Identitätsdivergenzen, 2 × `GUARD_COLLAPSE`, geteilter DomainModel-Konflikt, Rauschen kein Overlap, Basis nur Warnung; Postcheck-Varianten (Duplikate, kollabierter Guard, verlorene Unit, Orphans, falscher Hash) |

Die Reality-Fixture ist anonymisiert und synthetisch; das reale Projekt wurde ausschließlich lesend analysiert (siehe Baseline §13).

## Bewusst nicht Teil dieser Wave

- Aktivierung eines `.mpr`-Merge-Drivers oder von `.gitattributes` für das Modell (G3 bleibt `STILL_OPEN`).
- Behebung der mxcli-Serialisierung (Upstream-Aufgabe; Einreichung ist eine Maintainer-Entscheidung).
- Änderung von Consumer-Repositories.

## Grenzen des Verfahrens

- `GUARD_COLLAPSE` erkennt ein Boolesches Literal gegen einen Variablenpfad im selben Feld. Andere Formen konkurrierender Sicherheitslogik
  fängt nur ein deklarierter `--protected-marker` oder ein `Security$*`-Unit ab.
- Der Schwellenwert für `REPLAY_REQUIRED` bei komplexer gemeinsamer Mutation (100 echte geteilte Units) ist eine Heuristik, kein Messwert.
- Der strukturelle Vergleich behandelt `Objects` und `Flows` als reihenfolgefrei; Gleichstände strukturell identischer Geschwister
  führen zu `SEMANTIC` (konservativ).
- Der Preflight sagt voraus, wie riskant die Integration ist. Er ersetzt weder Studio Pro noch Concord.
