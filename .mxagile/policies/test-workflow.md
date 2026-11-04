# Test-Workflow

## Runtime-Strategie

MxAgile folgt der Strategie **Local First, Docker by Verification Need**
(vollstaendige Regeln: `policies/runtime-strategy.md`).

Playwright und Browser-Verifikation erfordern KEINE Docker-Umgebung.
Sie erfordern eine laufende, per Browser erreichbare Applikation.

Der bevorzugte Ablauf fuer Verifying ist Level 3 (lokaler Runtime):
1. Das C1-aufgeloeste Runtime-Recipe im autonomen Modus ausfuehren, falls nicht bereits eine kompatible
   Runtime laeuft — siehe `policies/local-runtime-profile.md` und `development-runtime.md`
2. Readiness Gate abwarten: APPLICATION_REACHABLE per HTTP-Poll bestaetigen
3. Playwright gegen `http://localhost:<port>` ausfuehren
4. Ergebnis dokumentieren

Docker-Eskalation (Level 4, `scripts/run-docker-isolated.ps1`) ist nur angemessen wenn:
- Container-Umgebungs-Paritaet benoetigt wird
- Deployable-Build validiert werden soll
- Lokaler Runtime keine valide Verifikationsevidenz liefern kann
- `runtime.verification: docker` in `mxagile-project.yaml` konfiguriert ist
- CI-Umgebung ohne lokalen Runtime

## Testlauf-Kostenbewusstsein

Testauswahl folgt dem autoritativen Impact-Resolver und der erforderlichen Gate-Tiefe.
Kosten duerfen die Auswahl, erforderliche Coverage oder PASS/FAIL/INCOMPLETE-Einstufung
niemals abschwaechen.

### Testklassen

| Klasse | Beispiele | Einsatz |
|---|---|---|
| `CHEAP/FOCUSED` | Einzelne Unit-/Contract-Suite, Parser-/Schema-Check, `git diff --check` | Waehrend Implementierung bedarfsgerecht wiederholen. |
| `TARGETED` | Kleine, unmittelbar betroffene Suite-Menge | Nach einem stabilisierten Teilpaket oder zur Verifikation eines konkreten Fixes. |
| `BROAD/EXPENSIVE` | Grosser Impact-Plan, Tier 2/3, Full Regression, Full Release Gate | Bewusst budgetieren; vor Start Gate-Autoritaet und benoetigte Suite-Abdeckung klaeren. |

### Standard waehrend Implementierung

Der Default ist:

```text
CHANGE -> kleinste relevante fokussierte Pruefung -> weiter implementieren
   -> bei stabilisiertem Changeset einmaliger autorisierter Impact-/Gate-Lauf
```

Wiederholte Broad-Laeufe zwischen kompatiblen Aenderungen sind nicht der Standard. Ein
bereits erfolgreich ausgefuehrter Broad-Lauf wird nicht allein aus Gewohnheit wiederholt.
Nach einem fehlgeschlagenen Broad-Lauf zuerst nur die fehlgeschlagene bzw. unmittelbar
betroffene Suite gezielt erneut ausfuehren, Root Cause beheben und danach den Impact-Resolver
neu konsultieren. Ein weiterer Broad-Lauf ist nur zulaessig, wenn die aktuelle Gate-Authority
ihn nach der Aenderung weiterhin verlangt und sich relevante Evidence/Codebasis geaendert hat.

### Broad-Run Preflight

Vor jedem `BROAD/EXPENSIVE`-Lauf intern beantworten:

1. Welche konkrete Evidence bzw. welches Gate fehlt?
2. Welche Authority verlangt den Lauf?
3. Welche Suiten waehlt der aktuelle Impact-Plan aus?
4. Gibt es gueltige Evidence fuer denselben unveraenderten Codezustand?
5. Reicht eine fokussierte oder targeted Suite?
6. Wurde in diesem Changeset bereits ein Broad-Lauf ausgefuehrt?
7. Welche relevante Aenderung rechtfertigt einen weiteren Broad-Lauf?

Ohne klare Begruendung keinen Broad-Lauf starten. Innerhalb eines Changesets keinen zweiten
oder weiteren Broad-Lauf mit "zur Sicherheit nochmal" begruenden. Wenn ein autorisierter
Auftrag den Broad-Lauf bereits eindeutig erlaubt, nicht bei jeder Suite erneut um Freigabe
bitten. Bei notwendigem Start knapp kommunizieren: `Broad verification required: <reason>`.

Ein Full Release Gate nur ausfuehren, wenn die aktuelle Repository-/Release-Gate-Authority
es verlangt oder der Nutzer es ausdruecklich freigibt. Nach einem fehlgeschlagenen oder
unterbrochenen Full Gate keine automatische Wiederholungsschleife starten; Einzelbefunde
gezielt diagnostizieren. Unterbrechung bleibt `INCOMPLETE`, getrennte Laeufe werden nicht
aggregiert.

### Dauer und Skip-Sicherheit

Wenn ein Runner Suite-Dauern ausgibt, diese als beobachtete Telemetrie dokumentieren und fuer
spaetere Reihenfolge-/Budget-Awareness verfuegbar halten. Historische Laufzeiten sind keine
festen Grenzwerte und werden nicht in Testlogik hardcodiert. Dauer darf die Reihenfolge
beeinflussen, aber niemals eine erforderliche Suite aus dem autoritativen Impact-Plan entfernen.
Kein kostenbasierter `SKIP`; fehlende/unvollstaendige Evidence bleibt `NOT EXECUTED` oder
`INCOMPLETE`, nicht `PASS`.

## Docker-/Playwright-Test (Level 4 Eskalation)

Wenn Docker-Eskalation benoetigt wird, laeuft der Test ueber `scripts/run-docker-isolated.ps1`
direkt auf dem kanonischen Modell. Der Runner startet Docker mit einem Port-Offset.

### Ablauf

1. `mxcli docker check` — Konsistenzpruefung
2. Docker-Build und Container-Start
3. Healthcheck abwarten
4. Playwright-Browser-Test gegen die App-URL ausfuehren
5. Ergebnis dokumentieren

### Credentials

Die lokalen Werte `MENDIX_APP_TEST_USERNAME` und `MENDIX_APP_TEST_PASSWORD`
aus `.env.mendix` werden nur zur Laufzeit verwendet und niemals ausgegeben,
in MDL geschrieben oder versioniert.

### CE0066-Behandlung

Wenn MxBuild oder der Konsistenzcheck `CE0066` meldet:

1. Agent prueft mit `.mxagile/tools/check-studio-pro-status.ps1`, ob dieses Projekt bereits
   offen ist — keine Rueckfrage beim Entwickler. Falls nicht, oeffnet der Agent es
   selbst mit `scripts/open-studio-pro.ps1`.
2. Im betroffenen Domain Model **Update security** ausfuehren (Entwickler)
3. Speichern (Entwickler)
4. Studio Pro schliessen (Entwickler)
5. Commit
6. Test erneut ausfuehren (lokal oder Docker je nach aktivem Level)
