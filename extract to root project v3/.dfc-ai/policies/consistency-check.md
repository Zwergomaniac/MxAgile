# Konsistenzpruefung (CE0066-Handling)

## Entity-Security-Checkpoint

`CE0066` entsteht typischerweise nach strukturellen Domain-Model-Aenderungen, wenn
Mendix die Entity-Access-Metadaten als veraltet markiert. Betroffen sind insbesondere:

- Neue oder geloeschte Entitaeten
- Neue oder entfernte Attribute und Associations
- Aenderungen an Generalisierung oder Entity-Security

## Ablauf bei CE0066

1. `mxcli docker check` ausfuehren
2. Bei `CE0066`: Studio Pro oeffnen
3. In jedem betroffenen Domain Model **Update security** ausfuehren
4. Speichern
5. Studio Pro schliessen
6. Check wiederholen

## Wave-Integration

Waves werden so geschnitten, dass zusammengehoerige Domain-Model-Aenderungen in
einem Modellabschnitt liegen. Pro Wave gibt es hoechstens ein bewusstes
Entity-Security-Gate.

## Validierungsstufen

| Stufe | Befehl | Prueft |
|---|---|---|
| Syntax | `mxcli check script.mdl` | MDL-Syntax |
| Referenzen | `mxcli check script.mdl -p <project>.mpr --references` | Existenz referenzierter Elemente |
| Lint | `mxcli lint -p <project>.mpr` | Best Practices und Konventionen |
| Konsistenz | `mxcli docker check -p <project>.mpr` | Vollstaendige Mendix-Validierung |
