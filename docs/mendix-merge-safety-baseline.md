# MENDIX_MERGE_SAFETY_BASELINE

Audit: Git-Index-Integrität vs. native Mendix-Merge-Semantik.
Stand: 2026-11-09, Framework-`main` = `b0c6341`. Keine produktive Änderung in diesem Schritt.

Klassifikationen: `FIXED_CURRENT_MAIN`, `PARTIALLY_FIXED`, `STILL_OPEN`, `NOT_CAUSAL`, `UNKNOWN`.
Evidenzklassen: **MEASURED** (in diesem Audit ausgeführt), **READ** (Code/Historie gelesen),
**UNVERIFIED** (nicht ausführbar, z. B. Studio Pro interaktiv).

Anonymisierung (Repository-Hygiene): **R1** = Reality-Projekt mit parallelen Branches, **R2** = öffentliches
Mendix-Referenzprojekt für kontrollierte Messungen, **P2** = paralleler R1-Workstream mit MDL-Replay.
Commit-SHAs beziehen sich auf das R1-Repository.

## 0. Realer Integrationsworkflow (Maintainer-Klarstellung)

Der reale R1-Workflow integriert Branches auch in jüngerer Zeit grundsätzlich so:

```text
Studio Pro → "Merge Changes Here" → Konflikte → Concord zur Konfliktanalyse/-auflösung
```

Nicht der allgemeine Workflow ist `Git CLI merge → ours/theirs → Replay`. Die in §7 genannten
`ours`-/`theirs`-Integrationen (`b79d2351`, `6cf36a87`) sind **Einzelfälle** und kein Nutzerworkflow.
Der P2-Replay war eine bewusste Einzelentscheidung.

**Concord** ist in diesem Audit nicht als Ursache belegt. Es ist als **Conflict-Resolution-Consumer**
eingeordnet, also als Werkzeug, das die von Studio Pro gemeldeten Konflikte anschließend auflöst.

Kernursache in diesem Workflow:

```text
mxcli-/Studio-Pro-Serialisierungsunterschiede
    → künstlich vergrößerte Branch-Deltas
    → mehr Konflikte beim Studio-Pro-Merge
    → Concord muss diese Konflikte anschließend auflösen
```

Alle Messungen liefen in Wegwerf-Fixtures bzw. einem Wegwerf-Klon (`git clone --no-hardlinks`)
von Referenzprojekt R2 (Mendix 10.24.11, MPRv2, 1209 Units). R1 wurde ausschließlich
lesend analysiert (`git --no-optional-locks log/show/diff`). Kein Consumer-Repo wurde verändert.

---

## 1. Git Mutation Map (READ)

| Pfad | Git-Operationen | Mutiert Projekt-Repo? |
|---|---|---|
| `scripts/git_index_integrity.py` (Guard, Recovery-Preflight, Verify) | `rev-parse`, `ls-tree`, `ls-files --stage`, `diff --cached`, `status`, `symbolic-ref`, `for-each-ref`, jeweils mit `--no-optional-locks` | **Nein.** Recovery-Kommandos (`git merge --abort`, `git restore --source=HEAD --staged -- :/`) werden nur **ausgegeben**, nie ausgeführt |
| `scripts/reconciliation_git.py`, `scripts/reconcile_external_changes.py` | `diff-tree`, `rev-list`, `log`, `show`, `ls-files`, `check-ignore`, `interpret-trailers`, mit `--no-optional-locks` | Nein |
| `mxagile-setup*.ps1`, `scripts/fetch-layer.ps1`, `update-layer.ps1`, `mxagile-add-layer.ps1` | `git clone`, `checkout` | Nur in **temporären** Clone-Verzeichnissen |
| `scripts/reset-testing-instance.ps1` | `git init`, `config` | Nur im Test-Instance-Verzeichnis |
| Agent-Guidance (`.mxagile/**`, `AGENT.md`) | keine Anweisung zu `git add -A`, `.mpr`/`mprcontents`-Staging, `.gitattributes` oder Merge-Driver | n/a |

Es gibt kein `update-index`, `read-tree`, `write-tree`, `checkout-index`, kein Löschen von `.git/index`
oder `index.lock`, kein `stash`/`worktree add`/`reset` in Frameworkpfaden.

## 2. Index-Guard-Semantik (READ + MEASURED)

- **Prüft immer, mutiert nie.** Er klassifiziert ausschließlich, eine Index-Rekonstruktion durch den Guard gibt es nicht.
- `GIT_INDEX_INTEGRITY_FAILURE` nur bei: HEAD > 0, Index = 0, staged deletions = HEAD, Dateien im Worktree vorhanden.
- Lock: `index.lock` wird über `rev-parse --git-path` aufgelöst, **nie gelöscht**.
- Recovery-Preflight `index-rebuild` ist nur `RECOVERY_READY`, wenn **kein** Merge/Rebase/Cherry-Pick läuft, der Index der Damage-Signatur entspricht, keine Locks bestehen, kein Git-Prozess aktiv ist und Nutzerautorisierung plus Scope-Review vorliegen. Selbst dann führt das Framework das Kommando nicht aus.
- `verify_recovery` verlangt `unmerged_entry_count == 0` nach Recovery.

Staged-State: unverändert in allen Fällen (siehe §8). Untracked, staged deletion, rename: unverändert.

## 3. Worktree-Semantik (READ + MEASURED)

- `.git` als Datei (linked Worktree) wird über `Path.exists()` akzeptiert. Alle Metadatenpfade (`index.lock`, `MERGE_HEAD`, `CHERRY_PICK_HEAD`, `rebase-*`, `MERGE_AUTOSTASH`) laufen über `git rev-parse --git-path`, es gibt keine hart codierten `.git/index`-Pfade.
- Gemessen: main, Worktree A und Worktree B haben drei verschiedene Indexpfade. Ein Guard-Lauf in einem Worktree lässt die Indizes der beiden anderen byte- und mtime-identisch.
- Lücke (STILL_OPEN, gering): Ein Aufruf mit einem **Unterverzeichnis** als `--project-root` liefert `GIT_INDEX_NOT_APPLICABLE` mit `mutations_allowed=True` (fail-open), weil `root/.git` statt `rev-parse --show-toplevel` geprüft wird.

## 4. Merge-Conflict-Safety (MEASURED)

Index mit Stages 1/2/3 (echter Konflikt) → `GIT_INDEX_PLAUSIBLE`. Ein Konflikt-Index ist nie leer, daher
ist eine Klassifikation als „corrupt“ strukturell ausgeschlossen. `index-rebuild` bleibt dabei `RECOVERY_BLOCKED`,
nur `merge-abort` wird (mit Autorisierung) `RECOVERY_READY`. Cherry-Pick-Konflikt: Index unverändert,
`cherry-pick-abort` → `RECOVERY_ESCALATION_REQUIRED`.

**GIT_INDEX_GUARD_NOT_CAUSAL.**

## 5. Mendix-Serialisierungsanalyse (MEASURED)

### 5.1 `.mpr` in MPRv2

Die `.mpr` ist eine SQLite-DB. Jede Modellschreiboperation (gemessen mit mxcli) ändert:

- `Unit.ContentsHash` der berührten Unit; gemessen gilt `ContentsHash = base64(sha256(mxunit-Bytes))`;
- die **globale Einzelzeile `_Transaction`**, und zwar bei jedem Write.

Folge: **Jeder** Branch mit irgendeiner Modelländerung ändert die Binärdatei `.mpr`. Bei zwei Branches
ist ein Git-Konflikt auf der `.mpr` daher garantiert, auch bei vollständig unabhängigen Units.

### 5.2 Serializer-Signaturen mxcli vs. Studio Pro

Gleiche Microflow-Unit, identische Semantik (`create or modify` mit unveränderter DESCRIBE-Ausgabe):

| | int32 | int64 | Key-Reihenfolge | explizite Defaults |
|---|---|---|---|---|
| Studio Pro (HEAD) | 10 | 6 | Referenz | vorhanden |
| mxcli v0.20.0 | 16 | 0 | 7 von 36 Dokumenten umsortiert | 2 Strings entfallen |

### 5.3 R1 W13 (`90b087cb`, READ)

74 mxunits: 6 semantisch, 65 rein serialisierungsbedingt, 3 neu (deckt sich mit 6/68).
**55 der 65** rein serialisierungsbedingten Units wechseln von der mxcli- zur Studio-Pro-Signatur. Zuletzt
geschrieben wurden diese Units von mxcli-getriebenen Commits: W11 (22), **P2-Replay `6d8923dc` (20)**,
W12 (8), Departments (8). Nur 7 sind Studio-Pro→Studio-Pro-Rauschen.

Mechanismus („Serialization Ping-Pong“): mxcli schreibt Units in eigener Kodierung. Beim nächsten
Studio-Pro-Save werden sie normalisiert, in **dem** Branch, der gerade Studio Pro benutzt. Rauschen
entsteht damit zeitversetzt und branchfremd. Die Normalisierung trifft Units, die der aktuelle Branch
semantisch nicht angefasst hat, und kollidiert mit jedem anderen Branch, der dieselben Units per mxcli verändert.

### 5.4 Studio Pro allein (UNVERIFIED)

Ein interaktiver Studio-Pro-Roundtrip ohne MxAgile (§14 des Auftrags) wurde nicht ausgeführt.
Indirekt (W13) beträgt das reine Studio-Pro→Studio-Pro-Rauschen 7 von 65 Units. Gesamtmodell-Rewrites entstehen
bei Mendix-Versionsupgrades (`9b12c1c2`, 2583 Units) und bei MPR-Formatwechseln
(`mpr change` 17.09. / `mpr back to v2` 21.09., je ca. 1800 Units).

## 6. ID-Stabilität (MEASURED)

`$ID`s einer Microflow-Unit (26), gemessen gegen den Studio-Pro-HEAD:

| Mutation | `$ID` erhalten | neu |
|---|---|---|
| `create or modify`, identischer Inhalt | 16 | 10 |
| `create or modify`, +1 LOG-Aktivität | 16 | 16 |
| `drop` + `create`, identischer Inhalt | 1 | 24 |

- `create or modify` meldet „Replaced microflow“ und baut den Body mit neuen Aktivitäts-/Flow-IDs neu auf, auch ohne semantische Änderung.
- DROP+CREATE ist schlimmer, in R1 aber selten: 37 DROP-Statements gegenüber 830 `create or modify` und 247 `alter` in 391 MDL-Dateien.
- Unit-Datei-UUID (Pfad) blieb in allen drei Fällen erhalten.
- Relevanz: nur für **überlappende** Units. Ein Element-Matching per `$ID` (Studio-Pro-Merge) sieht dann Delete+Add statt Modify. Für unabhängige Units ist ID-Churn nicht merge-relevant.

## 7. Native Merge vs. Replay (MEASURED + READ)

Fixture am echten Modell: Branch A ändert nur `Administration.ShowPasswordForm`, Branch B nur
`Administration.ShowMyPasswordForm` (beide per mxcli).

- `git merge`: mxunits **konfliktfrei**, **einziger Konflikt: `R2.mpr`** (binär).
- Auflösung `.mpr = theirs`: beide Änderungen sind semantisch vorhanden (mxcli DESCRIBE), genau **1** von 1209 `ContentsHash`-Einträgen ist veraltet (die Unit von B).

Damit ist der `.mpr`-Konflikt bei unabhängigen Units reine Metadaten-Buchhaltung und **deterministisch
auflösbar**: Unit-Zeilen per UnitID dreiwegig mergen, `ContentsHash` aus den gemergten mxunits neu berechnen,
`_Transaction` neu setzen. Echte Konflikte bleiben nur bei gleicher Unit auf beiden Seiten oder bei
konkurrierenden Unit-Zeilen-Änderungen (Move/Container).

R1-Merges (READ): Die Mehrzahl der Merges erzeugt eine **neue** `.mpr`. Das passt zum realen
Workflow aus §0 (Studio Pro „Merge Changes Here“ mit anschließender Konfliktauflösung über Concord).
Native Merges funktionieren also. Die plain-Git-Messung oben zeigt, warum Studio Pro die `.mpr` immer selbst
auflösen muss. Die Konflikte, die beim Studio-Pro-Merge übrig bleiben und an Concord gehen, entstehen auf
**Unit-Ebene**, und dort vergrößert das Serialisierungsrauschen aus §5.3 die Deltas künstlich.
Einzelfälle, ausdrücklich **nicht** der Nutzerworkflow: `b79d2351` („resolve all conflicts with ours“)
und `6cf36a87` (`.mpr = THEIRS` bei 1488 Units Abstand).

P2: Das Replay (`6d8923dc`) war erfolgreich, schrieb aber 20 Units in mxcli-Signatur. Diese wurden in W13
von Studio Pro wieder normalisiert, das Replay hat also selbst Folgerauschen erzeugt.

## 8. Aktuelle Regressionen (MEASURED, Wegwerf-Fixture)

Für jeden Fall gilt: Index-SHA-256, Index-mtime, `ls-files --stage`, `diff --cached -M`, `status --porcelain=v2`
vor und nach Guard + allen drei Recovery-Preflights identisch (auch die Indizes der anderen Worktrees).

| Fall | Ergebnis |
|---|---|
| clean | PASS |
| R1 unstaged | PASS |
| R2 staged | PASS |
| R3 mixed staged+unstaged (gleiche Datei) | PASS |
| R4 rename | PASS |
| staged deletion | PASS |
| untracked | PASS |
| R5 Merge-Konflikt Stages 1/2/3 | PASS (`index-rebuild` blockiert) |
| Cherry-Pick-Konflikt | PASS |
| R6 linked Worktree A / B / main | PASS |
| Mendix independent units (echtes Modell) | mxunits clean, `.mpr`-Konflikt (§7) |
| Model reserialization noise | gemessen (§5) |
| Unterverzeichnis-Aufruf | Audit: **FAIL** (fail-open `NOT_APPLICABLE`); nach Fix 6 PASS |

Hinweis: Der erste Fixture-Lauf meldete zwei FAILs (untracked, Worktree A). Ursache war mein eigenes
Fixture, das `git status` ohne `--no-optional-locks` aufrief und so den Stat-Cache neu schreiben ließ.
Nach Korrektur PASS.

Prozessbeobachtung: Das ungefilterte `tasklist /FO CSV /NH` in `runtime_processes()` hat **kein Timeout** und hing auf
dem Audit-Host über 5 Minuten (der gefilterte Aufruf in `git_activity()` ebenfalls ohne Timeout). Für die Regression
wurde die Prozessbeobachtung gemockt. Zusätzlich hält GitHub Desktop laufend `git status`/`fetch`-Prozesse aktiv,
dadurch blockiert der Preflight real mit `LOCK_OR_CONCURRENT_GIT_STATE_NOT_CLEARED` (fail-closed, korrekt).

## 9. Konkrete Gaps

| ID | Gap | Klasse | Merge-kausal? |
|---|---|---|---|
| G1 | Keine Framework-Guidance für Mendix-Integration (Studio-Pro-Merge vs. Replay, Serialisierungsrauschen ≠ fachlicher Overlap, `.mpr`-Behandlung außerhalb Studio Pro) | FIXED_CURRENT_MAIN (Integrations-Wave: `policies/mendix-integration.md`, Preflight, Resolver) | indirekt |
| G2 | mxcli-Writes hinterlassen Fremd-Serialisierung, die später branchfremd normalisiert wird | PARTIALLY_FIXED (erkannt und getrennt gemeldet; Ursache bleibt upstream STILL_OPEN, `docs/upstream/mxcli-serialization-stability.md`) | **ja** |
| G3 | Kein deterministischer `.mpr`-Merge für MPRv2 (Unit-Tabelle + `ContentsHash` + `_Transaction`) | STILL_OPEN | **ja** |
| G4 | `create or modify` erzeugt ID-Churn auch ohne semantische Änderung; Guidance zu ALTER-first fehlt | PARTIALLY_FIXED (Guidance mit gemessenen Zahlen korrigiert, ALTER-first in Policy und Agent; Durchsetzung auf Tool-Ebene fehlt) | partiell |
| G5 | `test-harness-cleanup.md` klassifizierte `*.mxunit` pauschal als `TEMPORARY_TEST_HARNESS_ARTIFACT` mit deterministischem Restore, in MPRv2 sind das echte Modell-Units | FIXED_CURRENT_MAIN (Fix 5: explizite Ownership, `scripts/test_harness_cleanup.py`) | Risiko (Modellinkonsistenz/Revert), nicht nachgewiesen kausal |
| G6 | Guard fail-open bei Unterverzeichnis-Root | FIXED_CURRENT_MAIN (Fix 6) | nein |
| G7 | `tasklist` ohne Timeout im Recovery-Preflight | FIXED_CURRENT_MAIN (Fix 6: Timeout, Status `TIMEOUT`, fail-closed) | nein |
| G8 | Repo-Tests deckten Konflikt-Stages, Rename, Mixed-Staging, linked Worktrees nicht ab | FIXED_CURRENT_MAIN (Fix 6: `GuardHardeningMatrixTests`) | nein |

## 10. Vorgeschlagene Fixes (Stand: Fix 5/6 und Integrations-Wave umgesetzt; offen: `.mpr`-Merge-Werkzeug, mxcli-Upstream)

1. **Mendix-Integrationspolicy** (G1), canonical in `.mxagile/policies/`, mit Zielhierarchie:
   - unabhängige Units → normaler Git-Merge, `.mpr` deterministisch regenerieren (Fix 2) oder Studio-Pro-Merge;
   - überlappende Units → Studio-Pro-Merge;
   - nur bei semantischem Rekonstruktionsbedarf (gleiche Unit beidseitig, divergente Struktur, Format-/Versionsgrenze) → MDL-Replay.

   Dazu Verbote: kein `-X ours`/`--ours` auf `.mpr`/`mprcontents` für ganze Branches; Merge über
   MPR-Format- oder Mendix-Versionsgrenzen erst nach Angleichung.
2. **MPRv2-`.mpr`-Merge-Tool** (G3): dreiwegiger Merge der `Unit`-Tabelle per UnitID, `ContentsHash`-Neuberechnung,
   frische `_Transaction`. Ehrlicher Konflikt, wenn dieselbe Unit-Zeile beidseitig divergiert. Nutzbar als
   Git-Merge-Driver oder als Post-Merge-Reparatur. Vor Freigabe Validierung durch Studio Pro (`mx check`) → aktuell UNVERIFIED.
3. **Serialisierungsdisziplin** (G2):
   - Nach mxcli-Mutationen innerhalb **derselben** Mission per Studio Pro normalisieren (öffnen/speichern), bevor committed wird, oder einen separaten Normalisierungs-Commit setzen;
   - vor jedem Fan-out paralleler Branches eine normalisierte Basis committen;
   - semantische und serialisierungsbedingte Units im Commit trennen bzw. kennzeichnen (Classifier aus diesem Audit wiederverwendbar).
4. **ALTER-first-Guidance** (G4): bei bestehenden Dokumenten `alter` vor `create or modify`, DROP+CREATE nur mit
   Begründung. Upstream-Meldung an mxcli: Integer-Breite, Key-Reihenfolge, Defaults, ID-Erhalt bei `create or modify`.
5. **G5 korrigieren**: Harness-Pattern auf Harness-Pfade begrenzen, `mprcontents/**` explizit ausschließen.
6. **Guard-Kleinfixes** (G6/G7/G8): `--show-toplevel` statt `root/.git`, `timeout=` für `tasklist`, Regressionstests
   für Konflikt-Stages, Rename, Mixed-Staging und linked Worktrees in `tests/test_git_index_integrity.py`.

## 11. Antwort auf die Kernfrage

Wenn A nur Artefakt A und B nur Artefakt B ändert, ist der Merge auf **semantischer Unit-Ebene konfliktfrei**
(gemessen). Der reale Studio-Pro-Merge (§0) wird trotzdem schwerer:

1. **Hauptursache: mxcli↔Studio-Pro-Serialisierungs-Ping-Pong.** mxcli schreibt Units nicht Studio-Pro-stabil
   (§12). Studio Pro normalisiert sie später in irgendeinem Branch. Dadurch ändern beide Branches Units, die
   keiner von beiden fachlich angefasst hat (W13: 55 von 65 Rausch-Units). Die Branch-Deltas wachsen künstlich,
   der Studio-Pro-Merge meldet mehr Konflikte, und Concord muss sie anschließend auflösen. Das ist der
   MxAgile-spezifische Anteil, weil MxAgile mxcli als Mutationsroute nutzt.
2. **`.mpr` konfliktiert auf Git-Ebene immer** (`_Transaction` + `ContentsHash`). Das ist Mendix-MPRv2-Verhalten und
   kein MxAgile-Effekt. Studio Pro löst es beim Merge selbst. Relevant wird es nur außerhalb von Studio Pro.
3. **Verstärker:** Gesamtmodell-Rewrites (Mendix-Upgrade, MPR-Formatwechsel v2→v1→v2 rund um die
   MxAgile-Einführung) und, als Einzelfälle, `ours`/`theirs`- bzw. Replay-Integrationen.

Der Git-Index-Guard spielt dabei keine Rolle. Concord ist Konsument der Konflikte, nicht belegte Ursache.

## 12. Upstream-Fund: mxcli schreibt Units nicht Studio-Pro-stabil

Dieser Fund gehört an mxcli (upstream). Er wird hier bewusst **nicht** durch zusätzlichen MxAgile-Policytext kaschiert.

Evidenz:

- R1 W13 (`90b087cb`): **6 echte Änderungen** gegenüber **65/68** reinen Format-/Serialisierungsänderungen.
  68 ist die strukturelle BSON-Zählung des Maintainers; 65 ist die Zählung dieses Audits, zusätzlich 3 neue Units.
  55 der 65 wechseln von der mxcli- zur Studio-Pro-Signatur.
- Kontrollierter Re-Apply einer unveränderten `create or modify`-Definition (mxcli v0.20.0, Mendix 10.24.11):
  Die Unit ändert sich trotzdem, und 10 von 26 `$ID`s werden neu erzeugt.

Beobachtete Unterschiede mxcli gegenüber Studio Pro:

- **int32 / int64:** mxcli schreibt alle Integer als int32 (16/0), Studio Pro teilweise als int64 (10/6);
- **Feldreihenfolge:** 7 von 36 BSON-Dokumenten mit gleicher Key-Menge, aber anderer Reihenfolge;
- **List-Marker:** abweichende Array-Typ-Marker (in W13 beobachtet; der Classifier dieses Audits normalisiert sie);
- **explizite Defaults:** mxcli lässt explizite Default-Werte weg, die Studio Pro schreibt;
- **ID-Erhalt:** `create or modify` baut den Body neu auf, statt unveränderte Elemente zu erhalten.

Erwartetes Upstream-Ziel: mxcli schreibt Units byte-stabil im Studio-Pro-Format und erhält bei `create or modify`
die IDs unveränderter Elemente.

## 13. Reality-Validierung des Preflights (R1, ausschließlich lesend)

Der Preflight wurde gegen den realen R1-Integrationsstand ausgeführt (Target und Source als Branch-Spitzen, zwei Merge-Basen,
Criss-Cross). Nur `ls-tree`, `cat-file`, `merge-base` und der lesende Index-Guard liefen; Status, HEAD und Index-Zeitstempel
waren danach unverändert. Laufzeit 16 s für rund 2200 Units je Seite.

| Befund | Messwert |
|---|---|
| Mendix-Version beider Spitzen | 11.16.0, `.mpr` auf beiden Seiten gegenüber beiden Basen geändert |
| Registry-Konsistenz der Spitzen | beide konsistent |
| Merge-Basen | 2, eine historisch beschädigt: 111 Orphans (entspricht 2132 Registry-Einträge gegen 2243 mxunits), nur Warnung |
| echte Identitätsdivergenzen | **10** (`DUPLICATE_AFTER_MERGE`, je zwei UUID-Linien); zusätzlich 56 deterministische `TARGET_LINE_WINS`, harmlos |
| geteilte semantische Units | 7, davon 6 basisabhängig (`BASE_DEPENDENT`); DomainModel mit beidseitiger Änderung |
| sicherheitskritisch | 3: zwei `GUARD_COLLAPSE` (Target `$KC/CanEditRegions`, Source `true`) und das DomainModel (Attribut `CanEditRegions` nur im Target, markergetrieben) |
| Serialisierungsrauschen | vorhanden, zwischen den Spitzen nur 2 Units, daher kaum zusätzliche Konfliktfläche |
| **Strategie** | `STUDIO_PRO_MERGE_WITH_TARGETED_CONFLICT_REVIEW` mit Identity-Reconciliation (10) und Security-Entscheidungen (3), **nicht** Replay |

Die zwei Guard-Microflows sind keine Identitätsdivergenzen, sondern Units mit gleicher UnitID, die beide Seiten unterschiedlich
geändert haben. Gemessene Ergebnisse je Merge-Basis: gegenüber der einen Basis ändern beide Seiten (beidseitiger Konflikt),
gegenüber der anderen ändert nur die Source. Bei dieser zweiten Basis würde die Source-Linie (`true`) ohne jeden Konflikt gewinnen
und den Guard-Ausdruck `$KC/CanEditRegions` still verdrängen. Genau dieser Fall darf nicht durch eine beliebige Merge-Basis entschieden werden. Der Reality-Stand dient als Vorlage der
anonymisierten Fixture R in `tests/test_mendix_merge_preflight.py`; R1 selbst wurde nicht verändert und es wurde nicht gemergt.
