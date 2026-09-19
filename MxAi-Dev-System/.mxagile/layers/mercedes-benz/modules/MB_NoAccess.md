# MB_NoAccess

## Kategorie

Mercedes-Benz Plattformmodul (v1.0.3)

Siehe auch:
- .MxAgile/modules/platform-modules.md

## Zweck

MB_NoAccess stellt eine Standard-Landing-Page fuer Benutzer bereit, die sich erfolgreich per SSO angemeldet haben aber noch keine fachliche Rolle ({APP}_*) besitzen. Der User sieht eine Hinweisseite mit Kontaktinformationen statt einer Fehlermeldung.

## Plattformregel

MB_NoAccess darf nicht veraendert werden.

## Wann greift MB_NoAccess?

1. Neuer Nutzer meldet sich erstmals an
2. MB_SSO erstellt den MBUser-Datensatz
3. `MB_SSO.CONST_DefaultUserRole` = `MB_NoAccess` -> User bekommt die Rolle `MB_NoAccess.User`
4. Navigation Home fuer `MB_NoAccess.User` zeigt `MB_NoAccess.Home_Web`
5. Erst wenn ein Admin dem User eine {APP}_*-Rolle zuweist, sieht er die eigentliche App

## Artefakte

### Seite

| Seite | Zweck |
|---|---|
| `MB_NoAccess.Home_Web` | Landing-Page "Kein Zugriff" mit Hinweistext und Link zur Berechtigungsanfrage |

### Snippets

| Snippet | Zweck |
|---|---|
| `MB_NoAccess.READ_ME` | Importanleitung (nicht fuer Endnutzer) |
| `MB_NoAccess.ToDo_after_import` | Setup-Schritte nach Modulimport |

### Nanoflow

| Nanoflow | Zweck |
|---|---|
| `MB_NoAccess.NACT_OpenLinkAlice` | Oeffnet Link zur Berechtigungsverwaltung (ALICE) |

### Module Role

| Rolle | Zweck |
|---|---|
| `MB_NoAccess.User` | Standard-Rolle fuer Nutzer ohne fachliche Berechtigung |

## Agent-Regeln

1. Navigation-Konfiguration muss `MB_NoAccess.Home_Web` als Home fuer `MB_NoAccess.User` setzen
2. Neue {APP}_*-Rollen brauchen KEIN Mapping auf `MB_NoAccess.User` — das ist die Default-Rolle
3. Keine eigene "Kein Zugriff"-Seite bauen — `MB_NoAccess.Home_Web` existiert bereits
4. Bei User-Role-Mapping: `MB_NoAccess.User` wird automatisch ueber `CONST_DefaultUserRole` zugewiesen, nicht manuell

