# UI action audit v1.2

## Interaction model

Across Local, FTP and HTTP explorers:

- single click selects an item;
- double click opens a directory or opens/views a file;
- right click opens the contextual action menu;
- the inline `…` menu exposes the same actions where available.

## Contextual actions

Local:
- Renommer
- Copier vers…
- Déplacer vers…
- Copier
- Couper
- Compresser / Extraire ZIP
- Partager
- Propriétés
- Supprimer

FTP / HTTP:
- Télécharger vers…
- Copier vers… (same multi-connection destination chooser)
- Éditer
- Extraire ZIP when applicable
- Renommer
- Copier / Couper
- Déplacer
- Propriétés
- Supprimer

## Validation still recommended

Run:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build windows
```
