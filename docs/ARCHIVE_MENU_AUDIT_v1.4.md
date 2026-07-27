# PulseFile v1.4 — archive menu audit

The archive actions are now explicitly present in the visible item menus:

- Local file manager: `Compresser vers…`; `.zip` files also show `Décompresser vers…`.
- FTP explorer: files show `Compresser vers…`; `.zip` files show `Extraire`.
- HTTP explorer: files show `Compresser vers…`; `.zip` files show `Extraire`.

Local compression already uses the common `TransferDestinationScreen`, so the destination can be Local, FTP, or HTTP.

Remote compression downloads the selected remote file to a temporary local workspace, creates a ZIP, places it in the universal clipboard, and opens the same common destination selector.

The archive root is `PulseFile/`.
