# PulseFile v1.0

- Windows/Desktop now enumerates all local roots using `Directory.listRoots()`, not only `C:`.
- The storage switcher exposes each local drive as a selectable local source.
- Android external storage roots are deduplicated after path normalization, preventing duplicate `External` entries.
- Existing Android internal storage and quick folders remain available.
