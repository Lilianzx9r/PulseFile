# v1.4.8 — compilation fix

Fixed malformed `await` insertion around `closeTransferProgressDialog`.

The function is now valid Dart and call sites use exactly one `await` when
called from asynchronous methods.
