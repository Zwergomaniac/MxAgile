# Test-Workflow

## Docker-/Playwright-Test

Docker- und Playwright-Tests laufen ueber `scripts/run-docker-isolated.ps1` direkt
auf dem kanonischen Modell. Der Runner startet Docker mit einem Port-Offset.

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
6. Docker-/Playwright-Test erneut ausfuehren
