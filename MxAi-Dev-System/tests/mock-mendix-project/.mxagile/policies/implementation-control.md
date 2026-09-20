# Implementierungssteuerung

## Wave-Schnitt

Implementation Waves unter `planning/execution-waves.md` sind technische Reihenfolge,
keine lokalen Sprints.

Waves werden so geschnitten, dass zusammengehoerige Domain-Model-Aenderungen in einem
Modellabschnitt liegen. Pro Wave gibt es hoechstens ein bewusstes Entity-Security-Gate.
Reine Seiten-, Microflow-, Test- und Dokumentationsarbeit folgt erst nach diesem Gate
und loest normalerweise kein neues `CE0066` aus.

Alle Waves werden grob als Roadmap geplant; nur die naechste Wave wird vollstaendig
detailliert und umgesetzt.

## Implementierungspflichten

- Jede MDL-Aenderung wird vor Ausfuehrung validiert:
  `mxcli check <script>.mdl -p <project>.mpr --references`
- Keine MDL-Scripts im Chat zeigen — Aenderungen in Klartext beschreiben, Freigabe
  einholen, dann still ausfuehren
- Alle Bezeichner in MDL mit doppelten Anfuehrungszeichen quoten
- Betriebsmodus (CLOSED-AUTONOM / LIVE-SP) bestimmt die verfuegbaren Werkzeuge

## Security-Timing (D48)

| Zeitpunkt | Aktion | Grund |
|---|---|---|
| Bei CREATE ENTITY | Entity Access Rules sofort setzen (erstmal `*` auf alle Module Roles) | CE0066 sofort eliminiert |
| Waehrend Page/MF-Bau | Keine Access Rules | Development-Modus, entspanntes Bauen |
| Nach letztem Domain-Model-Item | Dedizierter Security-Pass | Realistischer Test mit echten Rollen vor Verifying |

Der Security-Pass umfasst:
- User Roles definieren/aktualisieren
- Page Access pro User Role setzen
- Microflow Access pro User Role setzen
- Demo Users aktualisieren
- Security Level auf Prototype oder Production setzen

Die `implementation-checklist.yaml` enthaelt Security-Items am Ende der Liste.
Das Quality-Gate prueft ob der Security Level mindestens Prototype ist.

## Artefakt-Timing

Pflege In-App-Dokumentation beim Anlegen oder Aendern des Artefakts, nicht gesammelt
am Sprintende:

- Module, Entities, Enumerationen und Associations erhalten eine Beschreibung
- Microflows und Nanoflows dokumentieren Zweck, Parameter und Ergebnis
- Fachliche Entscheidungen gehoeren nach `sprints/decisions.md`
- Storybezogene technische Details nach `planning/stories/`
