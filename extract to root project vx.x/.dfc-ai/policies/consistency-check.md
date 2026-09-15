# Konsistenzpruefung (CE0066-Handling)

## Entity-Security-Checkpoint

`CE0066` entsteht typischerweise nach strukturellen Domain-Model-Aenderungen, wenn
Mendix die Entity-Access-Metadaten als veraltet markiert. Betroffen sind insbesondere:

- Neue oder geloeschte Entitaeten
- Neue oder entfernte Attribute und Associations
- Aenderungen an Generalisierung oder Entity-Security

## Ablauf bei CE0066

1. `mxcli docker check` ausfuehren
2. Bei `CE0066`: Agent prueft selbststaendig mit `scripts/check-studio-pro-status.ps1`,
   ob dieses Projekt bereits in Studio Pro offen ist — keine Rueckfrage beim
   Entwickler. Ist es nicht offen, oeffnet der Agent es selbst mit
   `scripts/open-studio-pro.ps1`.
3. In jedem betroffenen Domain Model **Update security** ausfuehren (Entwickler)
4. Speichern (Entwickler)
5. Studio Pro schliessen (Entwickler)
6. Check wiederholen (Agent)

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
