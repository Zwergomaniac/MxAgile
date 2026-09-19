# MB_UI

## Kategorie

Mercedes-Benz Plattformmodul (v2.1.2)

Siehe auch:
- .MxAgile/modules/platform-modules.md

## Zweck

MB_UI stellt das Mercedes-Benz Designsystem fuer Mendix-Anwendungen bereit: Layouts, CSS-Styles, Farbpaletten, UI-Komponenten, NavigationBar und Theme-Handling.

## Plattformregel

MB_UI darf nicht veraendert werden. Erweiterungen erfolgen ausserhalb des Moduls. Eigene UI-Komponenten sollen MB_UI ergaenzen, nicht ersetzen.

## Layouts (USE_ME/Layout)

| Layout | Zweck |
|---|---|
| `MB_UI.MB_Main_Layout` | Standard fuer alle neuen Seiten |
| `MB_UI.MB_Main_Layout_With_Background` | Seiten mit Hintergrundbild |
| `MB_UI.MB_Popup` | Standard-Popup-Dialog |
| `MB_UI.MB_Popup_blank` | Leeres Popup ohne Vorstruktur |

Legacy-Layouts (NICHT fuer neue Seiten verwenden):

| Layout | Status |
|---|---|
| `MB_UI.MercedesBenz_MenuBar` | Backward Compatibility — nicht verwenden |
| `MB_UI.MercedesBenz_TopBar` | Backward Compatibility — nicht verwenden |
| `MB_UI.MercedesBenz_Popup` | Backward Compatibility — nicht verwenden |

## Snippets und Building Blocks

| Artefakt | Zweck |
|---|---|
| `MB_UI.SNIP_NavigationBar_AppLogo` | App-Logo in der NavigationBar |
| `MB_UI.SNIP_NavigationBar_UserMenu` | User-Menu mit Abmelden, Theme-Switch |
| `MB_UI.ElevatedContainer` | Building Block: Container mit Schatten/Elevation |

## Konstanten (USE_ME/Constant)

| Konstante | Typ | Wert | Zweck |
|---|---|---|---|
| `MB_UI.AppName` | String | _{Projektname}_ | App-Name in NavigationBar |
| `MB_UI.CONST_EnableButtonEffects` | Boolean | True | Button-Hover-/Klick-Effekte |
| `MB_UI.CONST_ShowLanguageSelector` | Boolean | True | Sprachauswahl im UserMenu |
| `MB_UI.CONST_ShowThemeSwitch_NavBar` | Boolean | False | Theme-Switch in NavigationBar |
| `MB_UI.CONST_ShowThemeSwitch_UserMenu` | Boolean | False | Theme-Switch im UserMenu |

## Entities

| Entity | Typ | Zweck |
|---|---|---|
| `MB_UI.UserInfo` | Non-Persistent | Aktueller Benutzerkontext (FullName, Tag, Department, MBUserID) |
| `MB_UI.UserSetting` | Persistent | Theme-Praeferenz pro User (Light/Dark/Auto) |
| `MB_UI.AppLogo` | Persistent | App-Logo (extends System.Image) |

`MB_UI.UserInfo` wird intern aus `MB_SSO.MBUser` befuellt (via `SUB_Update_UserInfoWithMBUserData`).

## Module Roles

| Rolle | Zweck |
|---|---|
| `MB_UI.User` | Standardrolle — alle normalen Nutzer |
| `MB_UI.Admin` | Administration (AppLogo-Verwaltung) |

## Design Tokens und CSS-Variablen

MB_UI liefert ~236 CSS Custom Properties (`--mbui-*`) plus ~300 Atlas-Bridge-Variablen.
Theme-Varianten: Light, Dark, Auto (folgt System-Praeferenz).

### Quelldateien

Alle Token-Definitionen liegen unter `themesource/mb_ui/web/`:

| Datei | Inhalt |
|---|---|
| `mbui-design-tokens/resources/_mbui-colorplatte.scss` | Farbpalette (grey/blue/yellow/red, je 19 Stufen) |
| `mbui-design-tokens/_base.scss` | Theme-unabhaengig: Transitions, Breakpoints, Border-Radius, Z-Index |
| `mbui-design-tokens/_light.scss` | Light-Theme semantische Farben |
| `mbui-design-tokens/_dark.scss` | Dark-Theme semantische Farben |
| `mbui-design-tokens/resources/_mbui-font.scss` | Font-Familien, -Groessen, -Gewichte, Line-Heights |
| `mbui-design-tokens/resources/_boxshadow.scss` | Box-Shadows (25 Level) |
| `mbui-design-tokens/resources/_navigation.scss` | NavigationBar-Tokens |
| `_atlas-mapping.scss` | Bridge: mappt `--mbui-*` auf Atlas-Variablen (`--brand-*`, `--btn-*`, `--form-*`) |
| `_color-variants.scss` | Generiert `--brand-primary-{50..900}` etc. |
| `_mbui-fonts.scss` | Font-Face-Deklarationen (MBCorpoSText, MBCorpoSTitle, MBCorpoATitle) |

### Semantische Farben (Light/Dark-aware)

Diese Tokens aendern ihren Wert je nach aktivem Theme:

| Token | Zweck |
|---|---|
| `--mbui-primary` | Primaerfarbe (blue45 light / blue50 dark) |
| `--mbui-success` | Erfolg-Gruen |
| `--mbui-warning` | Warnung-Gelb |
| `--mbui-error` | Fehler-Rot |
| `--mbui-info` | Info-Blau |
| `--mbui-background-default` | Standard-Hintergrund (grey90 light / grey5 dark) |
| `--mbui-background-paper` | Karten-/Panel-Hintergrund |
| `--mbui-font-color-primary` | Haupttextfarbe |
| `--mbui-font-color-secondary` | Sekundaertextfarbe |
| `--mbui-font-color-disabled` | Deaktivierter Text |
| `--mbui-divider-color` | Trennlinien |
| `--mbui-color-base` | Basis (weiss light / schwarz dark) |
| `--mbui-color-contrast` | Kontrast (schwarz light / weiss dark) |
| `--mbui-action-hover` | Hover-Zustand |
| `--mbui-action-selected` | Selektiert-Zustand |
| `--mbui-action-focus` | Fokus-Zustand |

### Farbpalette

Jede Farbreihe hat 19 Abstufungen (`5` bis `95` in 5er-Schritten):

- `--mbui-grey5` .. `--mbui-grey95`
- `--mbui-blue5` .. `--mbui-blue95`
- `--mbui-yellow5` .. `--mbui-yellow95`
- `--mbui-red5` .. `--mbui-red95`

### Typography

| Token | Wert | Zweck |
|---|---|---|
| `--mbui-font-family-stext` | MBCorpoSText, Arial | Standard-Fliesstext |
| `--mbui-font-family-stitle` | MBCorpoSTitle, Arial | Titel |
| `--mbui-font-family-atitle` | MBCorpoATitle, Arial | Alternative Titel |
| `--mbui-font-size-h1` .. `--mbui-font-size-h6` | 3rem .. 1.125rem | Ueberschriften |
| `--mbui-font-size-body1` / `body2` | 1rem / 0.875rem | Fliesstext |
| `--mbui-font-size-button` | 0.875rem | Button-Label |
| `--mbui-font-size-caption` | 0.75rem | Beschriftungen |
| `--mbui-font-weight-regular` | 400 | Normal |
| `--mbui-font-weight-semibold` | 550 | Mittel |
| `--mbui-font-weight-bold` | 700 | Fett |

### Spacing und Layout (via Atlas-Bridge)

`_atlas-mapping.scss` mappt MBUI-Tokens auf Atlas-Spacing-Variablen:

| Token | Zweck |
|---|---|
| `--spacing-smallest` .. `--spacing-largest` | 7-stufige Abstandsskala |
| `--gutter-size` | Grid-Gutter |
| `--layout-spacing-*` | Layout-Abstaende |
| `--border-radius-s` / `m` / `l` | Eckenradien |

### Navigation

| Token | Wert | Zweck |
|---|---|---|
| `--mbui-nav-banner-bg-color` | #000 | NavigationBar Hintergrund |
| `--mbui-nav-banner-color` | #fff | NavigationBar Textfarbe |
| `--mbui-nav-banner-height` | 64px | NavigationBar Hoehe |
| `--mbui-nav-font-size` | 18px | Hauptmenue Schriftgroesse |
| `--mbui-nav-sub-font-size` | 14px | Untermenue Schriftgroesse |
| `--mbui-nav-usermenu-width` | 350px | User-Menu Breite |
| `--mbui-nav-max-width-topbar` | 1440px | Maximale Breite TopBar |

### Elevation und Schatten

- `--mbui-boxshadow-level0` .. `--mbui-boxshadow-level24` (25 Stufen, von `none` bis Multi-Layer)
- `--mbui-paper-elevation-1` .. `--mbui-paper-elevation-9` (Paper-Hintergruende mit leichter Aufhellung)

### Atlas-Bridge

`_atlas-mapping.scss` erzeugt ~300 Atlas-Framework-Variablen die intern auf `--mbui-*` Tokens verweisen:
`--brand-*`, `--btn-*-bg/color/border`, `--form-input-*`, `--grid-*`, `--tabs-*`, `--modal-*`, `--font-*`.
Agents sollten bevorzugt die `--mbui-*` Tokens direkt verwenden; die Atlas-Variablen sind fuer Mendix-Widget-Kompatibilitaet.

## Agent-Regeln

### Vor Erstellung neuer Seiten

1. Layout: `MB_UI.MB_Main_Layout` verwenden (oder `MB_Popup` fuer Dialoge)
2. Pruefen ob `MB_UI.ElevatedContainer` oder ein bestehendes Snippet passt
3. Keine eigenen Layouts, Header oder Navigationsstrukturen erstellen

### Bei Custom Styling

1. Zuerst `--mbui-*` Tokens pruefen (`themesource/mb_ui/web/mbui-design-tokens/`)
2. Dann `--brand-*` / `--btn-*` Atlas-Bridge-Tokens pruefen (`themesource/mb_ui/web/_atlas-mapping.scss`)
3. Erst wenn kein passender Token existiert: eigene CSS-Werte verwenden
4. Keine redundanten Design Tokens anlegen

## Anti-Patterns

- Eigene Layouts statt MB_UI.MB_Main_Layout
- Hex-Farbcodes verwenden wenn ein `--mbui-*` Token existiert (z.B. `#000` statt `var(--mbui-nav-banner-bg-color)`)
- Schriftgroessen fest im CSS statt `--mbui-font-size-*` Tokens
- MB Corporate Colors manuell kopieren
- Eigene NavigationBar statt MB_UI Snippets
- Legacy-Layouts (MercedesBenz_*) fuer neue Seiten verwenden
- MB_UI.UserInfo-Attribute manuell befuellen statt ueber MB_UI Microflows

