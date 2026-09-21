# Quality Gate

Technische Validierung nach Abschluss der Implementing-Phase.
Prueft ausschliesslich technische Korrektheit — UI-Treue und fachliche Akzeptanz
werden vom UI-Agent und Acceptance-Agent separat geprueft.

## Trigger

Nach Abschluss der Implementing-Phase, bevor UI-Agent und Acceptance-Agent starten.
Quality-Gate MUSS bestehen bevor die anderen Agents laufen koennen (Docker muss laufen).

Ein waehrend Implementing laufender Development-Runtime (`mxcli run --local`) ersetzt
weder das Quality-Gate noch die formale Verifikation. Entwicklungs-Feedback waehrend
Implementing ist kein Verifikationsnachweis (siehe `policies/development-runtime.md`).

## Pruefungen

1. **Syntax** — `mxcli check <script>.mdl` fuer alle neuen/geaenderten Scripts
2. **Referenzen** — `mxcli check <script>.mdl -p <project>.mpr --references`
3. **Lint** — `mxcli lint -p <project>.mpr` — keine kritischen Findings
4. **Konsistenz** — `mxcli docker check -p <project>.mpr` — keine CE-Fehler
   (bei CE0066 → Update security, siehe `.mxagile/policies/consistency-check.md`)
5. **Runtime** — Docker-Build und Container-Start erfolgreich
6. **Security** — Security Level mindestens Prototype wenn Security-Pass ausgefuehrt (D48)

## Output

- Technischer Validierungsbericht
- Bei Erfolg: Docker-App laeuft → UI-Agent und Acceptance-Agent koennen parallel starten
- Bei Fehlern: zurueck in die Implementing-Phase mit konkretem Fehlerbericht


