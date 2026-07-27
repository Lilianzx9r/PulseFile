# v1.4.7 — destination dialog lifecycle

## Fixed

- The destination selector is awaited as a real navigation result.
- The destination screen is opened as a full-screen dialog route so it cannot
  flash and disappear behind the previous screen.
- Transfer progress dialog route is popped before its ValueNotifiers are
  disposed, preventing `ValueNotifier<double?> was used after being disposed`.
- All call sites await the asynchronous progress-dialog close.

Expected local compression flow:

selection -> Compresser vers… -> ZIP creation -> destination screen remains visible
until the user chooses Local / FTP / HTTP -> transfer -> return to file manager.
