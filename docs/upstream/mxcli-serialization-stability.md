# Upstream-Fund: mxcli schreibt Units nicht Studio-Pro-stabil

Status: **Fund mit Evidenz, Issue-Entwurf. Noch nicht upstream eingereicht** (Einreichung ist eine Maintainer-Entscheidung).
Betroffen: mxcli `v0.20.0` (2026-08-28), Mendix 10.24.11 und 11.x, MPRv2 (`mprcontents/**/*.mxunit`).
Ursachenzuordnung: Der Fund liegt bei mxcli, nicht bei MxAgile. MxAgile erkennt und meldet das Rauschen (`mendix_merge_preflight.py`)
und behebt es **nicht** durch zusätzlichen Policytext.

## Kurzfassung

mxcli (`exec`/`CREATE OR MODIFY`/`DROP` + `CREATE`) schreibt Modell-Units in einer Form, die Studio Pro beim nächsten Speichern
wieder normalisiert. Dadurch entstehen große Diffs ohne fachliche Änderung. Branches, die beide Werkzeuge nutzen, bekommen
künstlich vergrößerte Deltas und beim Studio-Pro-Merge mehr Konflikte, die anschließend aufgelöst werden müssen.

## Evidenz 1: reales Projekt (anonymisiert)

Ein einzelner Commit eines Reality-Projekts (Studio-Pro-Sitzung nach mehreren mxcli-Wellen):

| Zählung | Wert |
|---|---|
| geänderte mxunits | 74 |
| semantisch geändert | 6 |
| rein serialisierungsbedingt | 65 (Maintainer-Zählung: 68) |
| neu hinzugekommen | 3 |
| davon 55 von mxcli- zu Studio-Pro-Signatur | 55 von 65 |

Die serialisierungsbedingten Units waren zuletzt überwiegend von mxcli-getriebenen Commits geschrieben worden (die vier größten Quellcommits mit 22, 20, 8 und 8 Units).
Nur 7 waren Studio-Pro-zu-Studio-Pro-Rauschen. Die Unterscheidung nutzt strukturellen BSON-Vergleich (kein Textdiff).

## Evidenz 2: kontrollierter Re-Apply (reproduzierbar)

Messung an einer Wegwerf-Kopie eines öffentlichen MPRv2-Referenzprojekts (1209 Units), ein Microflow mit 26 `$ID`s.

```bash
git clone --no-hardlinks <mpr-v2-projekt> repro && cd repro
echo "DESCRIBE MICROFLOW <Modul>.<Name>;" | mxcli exec - --project <App>.mpr > described.mdl
#   Kopfzeile "Connected to: ..." und das abschliessende "/" aus described.mdl entfernen
mxcli exec described.mdl --project <App>.mpr          # unveränderte Definition, create or modify
python scripts/mendix_merge_preflight.py classify-changes --base HEAD
```

| Variante | geänderte Units | `$ID` erhalten | Rest nach Normalisierung |
|---|---|---|---|
| `create or modify`, unveränderte `DESCRIBE`-Ausgabe | 1 | 16 von 26 (10 neu) | **nur `Caption` von 2 Aktivitäten** |
| `create or modify` + 1 `LOG`-Aktivität | 1 | 16 von 26 | echte Änderung, bleibt `SEMANTIC` |
| `DROP` + `CREATE`, unveränderte Definition | 1 | 1 von 26 (24 neu) | neue `StableId`, `Items`, Caption; Pointer-Abweichungen teils Sortier-Gleichstände |

Nach Normalisierung von Feldreihenfolge, int-Breite, regenerierten `$ID`s, Reihenfolge von `Objects`/`Flows`, Defaults und
Layout bleibt beim ersten Fall **nur ein echter Round-Trip-Verlust**: `DESCRIBE` gefolgt von `CREATE OR MODIFY` ist kein No-Op,
weil die Captions der beiden Aktivitäten verloren gehen. Der Unit-Dateiname (UnitID) bleibt in allen Varianten gleich.

## Beobachtete Unterschiede mxcli gegenüber Studio Pro

| Unterschied | Evidenz |
|---|---|
| **int32 / int64** | Studio Pro: 10 × int32 und 6 × int64; mxcli: 16 × int32, 0 × int64 (Kontrollmessung); im Reality-Commit überwiegt der Wechsel zur int64-Signatur |
| **Feldreihenfolge** | 7 von 36 BSON-Dokumenten mit gleicher Key-Menge, aber anderer Reihenfolge (Kontrollmessung) |
| **List-Marker** | im Reality-Commit beobachtet (Maintainer-Evidenz), in der Kontrollmessung **nicht isoliert**; der Classifier normalisiert sie |
| **explizite Defaults** | mxcli lässt Default-Werte weg, die Studio Pro explizit schreibt (z. B. `Documentation`, `HasVariableNameBeenChanged`) |
| **Reihenfolge der Graph-Arrays** | `Objects` und `Flows` eines Microflows werden in anderer Reihenfolge geschrieben |
| **Layout** | Größen, Positionen und Kurven-Vektoren werden zurückgesetzt bzw. neu berechnet |
| **`$ID`-Erhalt** | `create or modify` erzeugt IDs unveränderter Elemente neu (10 von 26) |
| **Caption-Verlust** | explizite Captions gehen beim Round-Trip verloren |

## Erwartetes Verhalten

1. Unit-Bytes für unveränderte Elemente bleiben beim Re-Apply stabil, also keine Änderung ohne fachlichen Grund.
2. mxcli schreibt im Studio-Pro-kompatiblen Format (Integer-Breite, Feldreihenfolge, List-Marker, explizite Defaults, Layout).
3. `create or modify` erhält `$ID`, `StableId` und Layout unveränderter Elemente (identity-preserving).
4. `DESCRIBE` → `CREATE OR MODIFY` ist ein Round-Trip ohne Verlust (Captions).

## Warum das ein Merge-Thema ist

Beide Werkzeuge schreiben dasselbe Modell. Das Rauschen verlagert sich in den Branch, der Studio Pro als Nächstes benutzt,
und trifft dort Units, die der Branch fachlich nicht angefasst hat. Studio Pro meldet beim Merge dann mehr Konflikte, als fachlich
existieren. Der Preflight trennt `SEMANTIC` von `SERIALIZATION_ONLY`, `DEFAULTS_ONLY` und `PRESENTATION_ONLY`, damit dieses Rauschen
nicht als fachlicher Overlap zählt. Die Ursache beseitigt er nicht.

## Einschränkungen dieser Evidenz

- Kontrollmessung: ein Microflow, ein Projekt, mxcli `v0.20.0`. Keine Aussage über andere Dokumenttypen (Pages, Domain Models).
- `mxcli bson compare` wurde nicht als Gegencheck verwendet; der Vergleich ist die eigene strukturelle Normalisierung.
- Der Vergleich behandelt nur `Objects` und `Flows` als reihenfolgefrei. Gleichartige Geschwisterknoten können dabei zu Gleichständen
  führen, was zu `SEMANTIC` tendiert (konservativ).
