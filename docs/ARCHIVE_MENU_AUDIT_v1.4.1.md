# Archive menu audit v1.4.1

The archive actions must be visible in the actual context menus, not only implemented
in a service.

## Required behavior

### Windows local explorer
For a selection containing one or more non-ZIP items:
- Renommer
- Copier
- Couper
- Déplacer
- Compresser vers…
- Propriétés
- Supprimer

For a selection containing a ZIP:
- Décompresser vers… must be visible.

### Android local explorer
The same archive actions must be visible in the context menu.

### Android remote connections
Opening FTP and HTTP connections must require the configured unlock/security step
before remote content is made accessible.

## Relevant menu implementations found in this source tree
- `lib/screens/http_explorer_screen.dart`
- `lib/screens/ftp_screen.dart`
- `lib/screens/file_manager_screen.dart`
