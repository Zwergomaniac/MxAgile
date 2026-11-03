# Quality Gate

Technische Validierung nach Abschluss der Implementing-Phase.
Prueft ausschliesslich technische Korrektheit — UI-Treue und fachliche Akzeptanz
werden vom UI-Agent und Acceptance-Agent separat geprueft.

## Trigger

Nach Abschluss der Implementing-Phase, bevor UI-Agent und Acceptance-Agent starten.
Quality-Gate MUSS bestehen bevor die anderen Agents laufen koennen.

Eine waehrend Implementing laufende Development-Runtime ersetzt
weder das Quality-Gate noch die formale Verifikation. Entwicklungs-Feedback waehrend
Implementing ist kein Verifikationsnachweis (siehe `policies/development-runtime.md`).

## Pruefungen

1. **Syntax** — `mxcli check <script>.mdl` fuer alle neuen/geaenderten Scripts
2. **Referenzen** — `mxcli check <script>.mdl -p <project>.mpr --references`
3. **Lint** — `mxcli lint -p <project>.mpr` — keine kritischen Findings
4. **Konsistenz** — `mxcli docker check -p <project>.mpr` — keine CE-Fehler
   (bei CE0066 → Update security, siehe `.mxagile/policies/consistency-check.md`)
5. **Runtime** — Applikation laeuft und ist erreichbar (per Runtime-Strategie):
  - Vor jedem mxcli-Aufruf Projektbinary und Version gemaess `policies/local-runtime-profile.md`
    aufloesen; widerspruechliche Tool-/Skill-Anweisungen und aktuelle CLI-Capabilities gemaess
    `policies/tool-instruction-conflict.md` pruefen. Kein PATH-Fallback ohne Projektfreigabe.
  - Operating Mode und Tool Authority bestimmen, danach Capability Discovery aus der Help
    genau dieser Binary ausfuehren und ein vollstaendiges `resolved_runtime_recipe` erzeugen.
    Das Rezept muss den aufgeloesten Runtime-/Backend-Pfad, `db_name`, `app_url`/Port,
    Constants und alle erforderlichen Invocation-Argumente enthalten.
  - Datenbank-Credentials nur fuer den ausgewaehlten Recipe-Pfad pruefen. Fehlende externe
    DB-Credentials blockieren keinen geeigneten lokalen Backend-Pfad. Credential-Werte nie
    in Analyse oder Bericht laden.
  - Die Runtime ausschliesslich mit Executable und Argument-Array des Recipes starten;
    keine Teilflags aus Beispielen neu zusammensetzen.
  - Nach Start Runtime-Erreichbarkeit, Backend/DB-Identifier soweit autoritativ verfuegbar,
    Fixture und Test Identity getrennt gegen das Recipe pruefen. Bei Recipe-Abweichung die
    nachgelagerte Fixture-/Login-Diagnose fuer diesen Versuch verwerfen.
   - Readiness Gate: APPLICATION_REACHABLE muss per HTTP-Poll bestaetigt sein bevor
     UI-Agent und Acceptance-Agent starten (keine Playwright-Interaktion vor Readiness)
   - Fallback auf Docker nur wenn Level 3 nicht moeglich oder Container-Paritaet
     explizit benoetigt — Begruendung angeben (siehe `policies/runtime-strategy.md`)
6. **Security** — Security Level mindestens Prototype wenn Security-Pass ausgefuehrt (D48)

## Output

- Technischer Validierungsbericht
- Bei Erfolg: Applikation laeuft (lokal oder Docker per Strategie) →
  UI-Agent und Acceptance-Agent koennen parallel starten
- Bei Fehlern: zurueck in die Implementing-Phase mit konkretem Fehlerbericht


