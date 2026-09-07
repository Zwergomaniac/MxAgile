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

### MB OIDC

Federation, OIDC, Rollen- und Claim-Mapping.

### MB No Access

Standardverhalten für Nutzer ohne fachliche Rolle.

### MB UI

Designsystem, CSS, Layouts und Standardkomponenten.

### MB Databricks

Zugriff auf Datenprodukte. SQL-Know-how erforderlich.

### MB SimplifAI

AI- und LLM-Funktionen.

### MB Governance Client

Pflichtmodul für Lizenzierung.

### MB Feedback

Standard für Nutzerfeedback.