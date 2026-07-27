# v1.4.3 — archive transfer fix

## Fixed issues

1. Local Windows compression must not call `HttpService.download`.
2. Remote HTTP compression may use a temporary local download before ZIP creation.
3. `TransferProgressController.dispose()` is idempotent to avoid double-dispose assertions.

## Expected dispatch

- Local source -> local compression path.
- FTP source -> FTP download/temporary path, then compression.
- HTTP source -> HTTP download/temporary path, then compression.

The destination selector remains shared across Local / FTP / HTTP.
