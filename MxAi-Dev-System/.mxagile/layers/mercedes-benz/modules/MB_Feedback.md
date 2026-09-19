# MB_Feedback

## Kategorie

Mercedes-Benz Plattformmodul (v2.0.1)

Siehe auch:
- .MxAgile/modules/platform-modules.md

## Zweck

MB_Feedback stellt eine Standard-Feedback-Funktion bereit: Nutzer koennen die App bewerten (Sterne-Rating) und Freitext-Feedback abgeben. Das Modul liefert UI-Seiten, Snippets und die Persistenzlogik.

## Plattformregel

MB_Feedback darf nicht veraendert werden. Eigene Feedback-Mechanismen nur wenn MB_Feedback die Anforderung nicht abdeckt.

## Artefakte

### Entity

| Entity | Typ | Zweck |
|---|---|---|
| `MB_Feedback.AppRating` | Persistent | Speichert Bewertung (2 Attribute) |

### Seiten

| Seite | Zweck |
|---|---|
| `MB_Feedback.ShareFeedback` | Feedback-Dialog (Popup, 1 Parameter) |
| `MB_Feedback.Manage_Rating` | Admin-Ansicht aller Bewertungen |

### Snippets

| Snippet | Zweck |
|---|---|
| `MB_Feedback.SNIP_Feedback` | Einbettbares Feedback-Widget fuer beliebige Seiten |
| `MB_Feedback.README` | Importanleitung |

### Microflows

| Microflow | Zweck |
|---|---|
| `MB_Feedback.DS_AppRating` | DataSource: Laedt aktuelle Bewertung des Users |
| `MB_Feedback.PopulateAttributes` | Befuellt AppRating-Attribute nach Erstellung |

### Nanoflows

| Nanoflow | Zweck |
|---|---|
| `MB_Feedback.ACT_Open_Feedback_Modal` | Oeffnet den Feedback-Dialog als Popup |
| `MB_Feedback.DS_Feedback_Populate` | Client-seitige DataSource fuer Feedback-Widget |

### Module Roles

| Rolle | Zweck |
|---|---|
| `MB_Feedback.Restricted` | Nutzer kann eigenes Feedback abgeben |
| `MB_Feedback.Priviledged` | Admin kann alle Bewertungen einsehen (Manage_Rating) |

## Integration

Um Feedback in die App einzubinden:
1. `MB_Feedback.SNIP_Feedback` als SnippetCall in eine bestehende Seite einfuegen (z.B. Footer oder Navigation)
2. Oder `MB_Feedback.ACT_Open_Feedback_Modal` als Button-Action verwenden
3. Module Roles mappen: `MB_Feedback.Restricted` -> alle {APP}_*-User-Rollen, `MB_Feedback.Priviledged` -> Admin-Rolle

## Agent-Regeln

1. Wenn PO Feedback-Feature anfordert: zuerst pruefen ob MB_Feedback die Anforderung abdeckt
2. `SNIP_Feedback` in bestehende Seiten einbetten statt eigene Feedback-Seiten zu bauen
3. Keine eigene AppRating-Entity anlegen — `MB_Feedback.AppRating` verwenden
4. Rollemapping nicht vergessen: ohne `Restricted` koennen Nutzer kein Feedback abgeben

