# MB_UI

## Kategorie

Mercedes-Benz Plattformmodul

Siehe auch:
- skillssource/platform-modules.md

## Zweck

MB_UI stellt das Mercedes-Benz Designsystem für Mendix-Anwendungen bereit.

Es enthält standardisierte:

- Layouts
- CSS-Styles
- Farbpaletten
- UI-Komponenten

## Standardregel

MB_UI ist die bevorzugte Quelle für Benutzeroberflächen.

Vor Erstellung eigener Oberflächenlösungen immer prüfen, ob bestehende MB_UI-Komponenten verwendet werden können.

## Verwenden wenn

- neue Seiten erstellt werden
- neue Dialoge erstellt werden
- Navigation erstellt wird
- Standardlayouts benötigt werden

## Plattformregel

MB_UI darf nicht verändert werden.

Begründung:

- zentrale Pflege
- regelmäßige Updates
- konsistentes Look & Feel

## Erweiterungen

Erweiterungen erfolgen außerhalb des Moduls.

Eigene UI-Komponenten sollen MB_UI ergänzen und nicht ersetzen.

## Bevorzugen gegenüber

- eigenen Layouts
- eigenen Headern
- eigenen Navigationsstrukturen
- lokal definierten Corporate-Styles

## Bekannte Stolperfallen

⚠️ TO BE VERIFIED

Beispiele:

- bestehende Layouts nicht wiederverwenden
- eigenes Styling statt Plattformstandards
- Duplizieren von UI-Komponenten

## Agent-Regel

Vor Erstellung neuer Seiten zuerst prüfen:

1. Existiert bereits ein passendes Layout?
2. Existiert bereits eine passende Komponente?
3. Kann MB_UI direkt genutzt werden?

Nur falls alle Antworten Nein sind, Eigenentwicklung erwägen.

## Design Tokens

MB_UI enthält zentrale Design Tokens für:

- Farben
- Typography
- Spacing
- UI Styling

Diese Tokens bilden die Grundlage für individuelles Styling.

## Agent-Regel

Bei Custom Styling:

1. Bestehende MB_UI Tokens prüfen
2. Vorhandene Tokens wiederverwenden
3. Keine Hardcoded Corporate Colors
4. Keine redundanten Design Tokens anlegen

## Anti-Patterns

- Farben fest im CSS definieren
- MB Corporate Colors manuell kopieren
- Schriftarten lokal überschreiben
- Eigene Design Token erstellen obwohl passende MB_UI Tokens existieren
