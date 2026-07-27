# v1.4.6 — compression transfer crash fix

Fixed the actual causes found in the source:

- HTTP and FTP remote downloads are now awaited before the downloaded file is
  passed to `ZipFileEncoder`.
- Progress dialogs are no longer closed before the ZIP operation has completed.
- `TransferProgressController.dispose()` is now truly idempotent, preventing a
  second `ValueNotifier.dispose()` from throwing.
- The destination selector remains the next step after successful ZIP creation.

Expected flow:

Local:
selection -> ZIP creation -> destination selector -> transfer

FTP/HTTP:
remote download (awaited) -> ZIP creation -> destination selector -> transfer
