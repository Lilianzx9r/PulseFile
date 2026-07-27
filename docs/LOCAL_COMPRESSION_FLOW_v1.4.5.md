# v1.4.5 — local compression flow

The local `Compresser vers…` action must follow this order:

1. Read the selected local files/directories using their absolute paths.
2. Ask for the archive name.
3. Ask for the destination connection/path.
4. Create the ZIP in a temporary local workspace.
5. Copy/upload the resulting ZIP to the selected destination.
6. Clean up the temporary workspace.

The local source path must never be passed through `HttpService.download()`.

The destination selector must be opened before the compression operation starts.
