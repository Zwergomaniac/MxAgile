# MB_SSO

## Kategorie

Mercedes-Benz Plattformmodul

Siehe auch:
- skillssource/platform-modules.md

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

- Konfiguration
- Rollenmapping
-