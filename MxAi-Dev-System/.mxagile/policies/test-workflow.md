# Test-Workflow

## Runtime-Strategie

MxAgile folgt der Strategie **Local First, Docker by Verification Need**
(vollstaendige Regeln: `policies/runtime-strategy.md`).

Playwright und Browser-Verifikation erfordern KEINE Docker-Umgebung.
Sie erfordern eine laufende, per Browser erreichbare Applikation.

Der bevorzugte Ablauf fuer Verifying ist Level 3 (lokaler Runtime):
1. `mxcli run --local --watch` starten (falls nicht bereits laufend)
2. Playwright gegen `http://localhost:<port>` ausfuehren
3. Ergebnis dokumentieren

Docker-Eskalation (Level 4, `scripts/run-docker-isolated.ps1`) ist nur angemessen wenn:
- Container-Umgebungs-Paritaet benoetigt wird
- Deployable-Build validiert werden soll
- Lokaler Runtime keine valide Verifikationsevidenz liefern kann
- `runtime.verification: docker` in `mxagile-project.yaml` konfiguriert ist
- CI-Umgebung ohne lokalen Runtime

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

1. Agent prueft mit `scripts/check-studio-pro-status.ps1`, ob dieses Projekt bereits
   offen ist — keine Rueckfrage beim Entwickler. Falls nicht, oeffnet der Agent es
   selbst mit `scripts/open-studio-pro.ps1`.
2. Im betroffenen Domain Model **Update security** ausfuehren (Entwickler)
3. Speichern (Entwickler)
4. Studio Pro schliessen (Entwickler)
5. Commit
6. Test erneut ausfuehren (lokal oder Docker je nach aktivem Level)
