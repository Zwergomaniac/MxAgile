# Quality Gate

Technische Validierung nach Abschluss der Implementing-Phase.
Prueft ausschliesslich technische Korrektheit — UI-Treue und fachliche Akzeptanz
werden vom UI-Agent und Acceptance-Agent separat geprueft.

## Trigger

Nach Abschluss der Implementing-Phase, bevor UI-Agent und Acceptance-Agent starten.
Quality-Gate MUSS bestehen bevor die anderen Agents laufen koennen.

Ein waehrend Implementing laufender Development-Runtime (`mxcli run --local`) ersetzt
weder das Quality-Gate noch die formale Verifikation. Entwicklungs-Feedback waehrend
Implementing ist kein Verifikationsnachweis (siehe `policies/development-runtime.md`).

## Pruefungen

1. **Syntax** — `mxcli check <script>.mdl` fuer alle neuen/geaenderten Scripts
2. **Referenzen** — `mxcli check <script>.mdl -p <project>.mpr --references`
3. **Lint** — `mxcli lint -p <project>.mpr` — keine kritischen Findings
4. **Konsistenz** — `mxcli docker check -p <project>.mpr` — keine CE-Fehler
   (bei CE0066 → Update security, siehe `.mxagile/policies/consistency-check.md`)
5. **Runtime** — Applikation laeuft und ist erreichbar (per Runtime-Strategie):
   - Standard: `mxcli run --local --watch` (Level 3 — warmer lokaler Runtime)
   - Fallback auf Docker nur wenn Level 3 nicht moeglich oder Container-Paritaet
     explizit benoetigt — Begruendung angeben (siehe `policies/runtime-strategy.md`)
6. **Security** — Security Level mindestens Prototype wenn Security-Pass ausgefuehrt (D48)

## Output

- Technischer Validierungsbericht
- Bei Erfolg: Applikation laeuft (lokal oder Docker per Strategie) →
  UI-Agent und Acceptance-Agent koennen parallel starten
- Bei Fehlern: zurueck in die Implementing-Phase mit konkretem Fehlerbericht


