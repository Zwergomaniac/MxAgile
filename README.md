# Mendix AI Project Framework

Dieses Repository pflegt wiederverwendbare Arbeitsgrundlagen fuer AI-unterstuetzte Mendix-Projekte im Mercedes-Benz-Umfeld. Es ist kein Mendix-Projekt selbst: Es kombiniert ein kopierbares Projekt-Template mit zentral bereitgestellten Copilot-Prompts fuer die fachliche Vorbereitung und Projektsteuerung.

## Bestandteile

| Bereich | Zweck | Zielgruppe |
|---|---|---|
| `extract to root project vx.x/` | Kopierbare Projektvorlage mit DFC-AI-Prozess, Regeln, Skills, Skripten und Planungsstruktur | Mendix-Entwicklungsteams |
| `MxMocketeer/` | Copilot-Prompts fuer Discovery, Anforderungsklaerung und interaktive HTML-Klickdummys | Fachbereich, Product Owner, UX und Entwicklung |
| `MxScrumMaster/` | Copilot-Prompts fuer Backlog-Qualitaet, Mendix Epics Board und Projektplanung | Product Owner, Projektleitung und Entwicklung |
| `extract to root project vx.x/.dfc-ai/GLOSSARY.yaml` | Gemeinsame interne Begriffe und Orientierung zu Mercedes-Benz Plattformmodulen | Alle Nutzer und AI-Assistenten |
| `.github/agents/` | Copilot-Agenten fuer die Pflege und die unabhängige Pruefung dieses Frameworks | Framework-Verantwortliche |

## Zielbild

Das Framework verbindet die fachliche Vorarbeit mit einer kontrollierten Mendix-Umsetzung:

```text
Anforderungen und Klickdummy
        -> Discovery
        -> Refinement
        -> Ready
        -> Implementierung
        -> Verifizierung
```

Mocketeer hilft, Prozesse und Oberflaechen frueh sichtbar und diskutierbar zu machen. ScrumMaster erzeugt daraus ein belastbares, Board-geführtes Backlog. Die Projektvorlage stellt sicher, dass die anschliessende Umsetzung, Sicherheit, Nachvollziehbarkeit und Tests im konkreten Mendix-Projekt einheitlich ablaufen.

Wenn das Mendix Epics Board eingerichtet ist, ist es die operative Quelle fuer Epics, Stories, Akzeptanzkriterien, Status und Sprintzuordnung. Lokale Dateien im Template sind abgeleitete Arbeitsartefakte, keine zweite Backlog-Wahrheit.

## Verwendung

1. Den Inhalt von `extract to root project vx.x/` in das Stammverzeichnis eines neuen Mendix-Projekts kopieren.
2. Die Setup-Anleitung unter [extract to root project vx.x/README.md](extract%20to%20root%20project%20vx.x/README.md) und `SETUP.md` im kopierten Template durchlaufen.
3. `projekt.md` mit dem projektspezifischen Ziel, Stack, Rollen, Modulen und der Backlog-Quelle ausfuellen.
4. Die zentralen Mocketeer- und ScrumMaster-Prompts fuer Discovery und Backlog-Arbeit verwenden.

Die Template-Struktur und ihr DFC-AI-Prozess sind in [extract to root project vx.x/.dfc-ai/orchestrator.md](extract%20to%20root%20project%20vx.x/.dfc-ai/orchestrator.md) beschrieben.

## Begriffe und Plattformmodule

Das [GLOSSARY.yaml](extract%20to%20root%20project%20vx.x/.dfc-ai/GLOSSARY.yaml) ist die gemeinsame Einstiegshilfe fuer interne Begriffe und die Arbeit mit Mercedes-Benz Plattformmodulen. Bei Mendix-Modellierung, Rollen, Benutzerzugriff, UI, Feedback oder Wiederverwendung zuerst das Glossar lesen. Anschliessend die Plattformuebersicht und bei Bedarf das passende Moduldetail im kopierbaren Template konsultieren:

- [platform-modules.md](extract%20to%20root%20project%20vx.x/.dfc-ai/modules/platform-modules.md)
- [MB_SSO.md](extract%20to%20root%20project%20vx.x/.dfc-ai/modules/MB_SSO.md)
- [MB_UI.md](extract%20to%20root%20project%20vx.x/.dfc-ai/modules/MB_UI.md)
- [MB_NoAccess.md](extract%20to%20root%20project%20vx.x/.dfc-ai/modules/MB_NoAccess.md)
- [MB_Feedback.md](extract%20to%20root%20project%20vx.x/.dfc-ai/modules/MB_Feedback.md)
- [MB_Governance.md](extract%20to%20root%20project%20vx.x/.dfc-ai/modules/MB_Governance.md)

Bei einem Widerspruch gilt die jeweilige Moduldetail-Referenz vor dem Glossar.

## Framework weiterentwickeln

Fuer Änderungen an diesem Repository stehen zwei Copilot-Agenten bereit:

- **Mendix AI Framework Maintainer** fuer konkrete Weiterentwicklungen und Konsolidierung.
- **Mendix AI Framework Reviewer** fuer eine unabhängige, read-only Pruefung von Konsistenz, Portabilitaet und Release-Risiken.

Die allgemeinen Arbeitsregeln fuer AI-Coding-Assistenten stehen in [.github/copilot-instructions.md](.github/copilot-instructions.md). Neue Regeln sollen nur dann in das kopierbare Template aufgenommen werden, wenn sie fuer jedes neue Mendix-Projekt gelten.