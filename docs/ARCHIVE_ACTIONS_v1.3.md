# PulseFile v1.3 — archive actions

Added archive actions to the local file manager:

- **Compresser vers…**: creates a ZIP in a temporary local workspace, then opens the common destination selector so the archive can be sent to Local, FTP, or HTTP.
- **Décompresser vers…**: extracts a ZIP into a temporary local workspace, then sends the extracted directory through the same destination selector.

The existing single-click selection and double-click opening behavior is preserved.

The temporary workspace is removed after the destination operation returns.
