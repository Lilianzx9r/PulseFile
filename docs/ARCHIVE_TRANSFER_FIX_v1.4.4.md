# v1.4.4 — compression transfer crash fix

## Fixed

- HTTP remote compression now awaits `HttpService.download(...)`; the previous
  call started an asynchronous download and immediately attempted to compress
  a file that did not yet exist.
- Transfer progress dialogs now dispose their `ValueNotifier`s only after the
  dialog route has completed. Closing the dialog no longer disposes a notifier
  while `ValueListenableBuilder` is still mounted.
- `TransferProgressController.dispose()` remains idempotent.

## Expected behavior

For a local Windows source:
- local compression path is used;
- no `HttpService.download` is called.

For an HTTP source:
- download is awaited;
- progress is updated;
- the downloaded file is then compressed.
