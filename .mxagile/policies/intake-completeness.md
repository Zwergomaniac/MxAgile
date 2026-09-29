# Intake Completeness Policy

Regeln fuer den Completeness-Check des Intake-Bots.

## Mindestanforderungen Mockup

Ein Mockup gilt als COMPLETE wenn:
1. Mindestens ein Seitentyp dargestellt (Uebersicht, Detail, Dashboard, etc.)
2. Felder und Beschriftungen erkennbar
3. Aktionen/Buttons mit gewuenschtem Verhalten benannt
4. Navigation zwischen Seiten angedeutet (wenn mehrseitig)

## Mindestanforderungen Spezifikation

Ein Spezifikationsdokument gilt als COMPLETE wenn:
1. Geschaeftszweck beschrieben (was soll erreicht werden?)
2. Benutzerrollen definiert (wer arbeitet damit?)
3. Kernentitaeten benannt (welche Daten werden verwaltet?)
4. Geschaeftsregeln formuliert (Pflichtfelder, Berechnungen, Validierungen)
5. Mindestens ein Akzeptanzkriterium pro User Story

## PARTIAL-Behandlung

Wenn der Completeness-Check PARTIAL liefert:
- Bot nennt konkret die fehlenden Punkte (keine generischen Hinweise)
- Bot bietet dem Kunden einen Agent-Link zur Klarifizierung
- Bot schlaegt Formulierungen vor, die der Kunde bestaetigen oder korrigieren kann
- Maximal 3 Iterationen — danach: Artefakte mit PARTIAL-Markierung weitergeben
  und offene Punkte als `DECISION REQUIRED` in die Discovery-Phase eskalieren

## Uebergabe an Discovery

Wenn COMPLETE (oder PARTIAL nach 3 Iterationen):
- Artefakte in `input-resources/` ablegen
- Completeness-Status als Metadaten im Dokument-Header notieren
- Falls PARTIAL: offene Punkte als Liste im Header auflisten
