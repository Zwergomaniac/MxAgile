# Stories

Eine Story-Spezifikation je Requirement: `{STORYPREFIX}-<Nr>.md`, zum Beispiel
`{STORYPREFIX}-001.md`. `{STORYPREFIX}` wird beim Projekt-Setup festgelegt
(siehe `SETUP.md`).

Entsteht in der Discovery-Phase (`.dfc-ai/skills/discovery.md`), aus
Requirements-Dokument, Mockup und bestehendem Modell.

## Pflicht-Frontmatter

Siehe `planning/story-spec.schema.json` fuer das vollstaendige Schema und
`planning/README.md` fuer das storybezogene Frontmatter (Board-Anbindung,
Reconciliation-Felder).

## Inhalt

- Fachlicher Kontext, User Stories, Akzeptanzkriterien
- Vorgeschlagene Entities, Attribute, Associations, Microflows, Pages
- Offene Punkte als `DECISION REQUIRED` oder `ASSUMPTION`

Wird in der Refinement-Phase vervollstaendigt, bevor das Gate `dfc-gate-to-ready`
daraus die wave-bezogene Implementierungscheckliste erzeugt.
