# MB_SSO

## Kategorie

Mercedes-Benz Plattformmodul

Siehe auch:
- .dfc-ai/modules/platform-modules.md

## Zweck

MB_SSO stellt die Authentifizierung von Mercedes-Benz Benutzern bereit.

Es liefert Benutzerauthentifizierung sowie Mitarbeiterinformationen über Claims.

## Standardregel

MB_SSO ist die bevorzugte Authentifizierungslösung.

Wenn Authentifizierung benötigt wird, ist MB_SSO standardmäßig zu verwenden, sofern keine fachlichen oder technischen Anforderungen etwas anderes verlangen.

## Verwenden wenn

- Benutzeridentität benötigt wird
- Mitarbeiterinformationen benötigt werden
- Rollen auf Benutzerinformationen basieren
- SSO gefordert ist

## Nicht verwenden wenn

- fachliche Anforderungen ausdrücklich eine andere Authentifizierung verlangen

## Plattformregel

MB_SSO ist ein Plattformmodul.

Das Modul darf nicht verändert werden.

Begründung:

- zentrale Pflege
- regelmäßige Updates
- mehrere Anwendungen können von Änderungen betroffen sein

## Erweiterungen

Erweiterungen erfolgen über:

- Konfiguration (Konstanten)
- Rollenmapping (User Roles → Module Roles)
- Extension Points (projektspezifische Module)

Nicht über Änderungen am Modul selbst.

## Zentrale Entity: MBUser

`MB_SSO.MBUser` (persistent, 33 Attribute) ist die zentrale Benutzer-Entity.

Wichtige Attribute:

- UserID, Email, FirstName, LastName, FullName
- Department, DepartmentDescription, departmentId
- Plant, PlantOrganization
- Supervisor, ManagementLevel
- CompanyID, OrganizationalUnit
- UserState (Enum: INTERNAL, EXTERNAL, JOINTVENTURE)

Association: `MB_SSO.MBUser_Account` → `Administration.Account`

Projektspezifische Benutzerdaten werden NICHT in MBUser ergaenzt, sondern in einer eigenen Entity mit Association zu MBUser.

## Konstanten

| Konstante | Wert | Bedeutung |
|---|---|---|
| `CONST_UserroleAppname` | _{App}_ | Praefix fuer Projektrollen → `{APP}_<RoleName>` |
| `CONST_DefaultUserRole` | MB_NoAccess | Nutzer ohne Rolle landen auf NoAccess-Seite |
| `CONST_Domain` | mercedes-benz.com | SSO-Domain |

## Rollen

| Module Role | MBUser-Zugriff |
|---|---|
| Restricted | Read (eingeschraenkt auf Stammdaten, kein write) |
| Priviledged | Create, Delete, Read *, Write * |
| Developer | Create, Delete, Read *, Write * |

## Projektrollen-Schema

Projektrollen folgen dem Muster `{APP}_<RoleName>` (abgeleitet von `CONST_UserroleAppname`).

Ausnahme: `NewSSOUser` bleibt als SSO-Onboarding-/No-Access-Rolle bestehen.

## Bekannte Stolperfallen

- MBUser nicht direkt erweitern — eigene Entity mit Association verwenden
- `CONST_UserroleAppname` muss VOR dem Anlegen fachlicher Rollen gesetzt sein
- Abweichende Approllen-Namen dem Entwickler vorlegen, nicht selbst umbenennen

## Agent-Regel

1. Benutzerdaten immer ueber MBUser beziehen, nicht System.User
2. Projektrollen dem Schema `{APP}_<RoleName>` folgen
3. Bei neuen Rollen: MB_SSO Module Roles im Rollenmapping beruecksichtigen
4. MBUser-Attribute nicht duplizieren — ueber Association lesen