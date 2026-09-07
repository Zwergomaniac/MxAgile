# Platform & Reuse First

Mercedes-Benz Plattformmodule gelten als vorhandene Plattformfähigkeiten und sollen standardmäßig genutzt werden.

Eigene Entwicklung nur bei fachlich begründeter Abweichung.

Vor Eigenentwicklung prüfen:

1. Mercedes-Benz Plattformmodule
2. Mendix Marketplace (FOSS/Open Source)
3. Erst danach Eigenentwicklung

## Änderungsregel

Mercedes-Benz Plattformmodule dürfen nicht modifiziert werden.

Sie werden zentral gepflegt und erhalten Updates.

Erweiterungen erfolgen über:

- Konfiguration
- Rollenmapping
- Extension Points
- Projektspezifische Module

Nicht über Änderungen am Modul selbst.

## Plattformmodule

### MB_SSO

Authentifizierung und Mitarbeiterinformationen via Claims.
-> Detail-Referenz: `.dfc-ai/modules/MB_SSO.md`

### MB OIDC

Federation, OIDC, Rollen- und Claim-Mapping.

### MB No Access

Standardverhalten fuer Nutzer ohne fachliche Rolle.
-> Detail-Referenz: `.dfc-ai/modules/MB_NoAccess.md`

### MB UI

Designsystem, CSS, Layouts und Standardkomponenten.
-> Detail-Referenz: `.dfc-ai/modules/MB_UI.md`

### MB Databricks

Zugriff auf Datenprodukte. SQL-Know-how erforderlich.

### MB SimplifAI

AI- und LLM-Funktionen.

### Hierarchy Tree

Mitarbeiter Hierarchie Baum um Abteilungen aufzuschluesseln

### MB Governance Client

Pflichtmodul für Lizenzierung.

### MB Feedback

Standard fuer Nutzerfeedback.
-> Detail-Referenz: `.dfc-ai/modules/MB_Feedback.md`