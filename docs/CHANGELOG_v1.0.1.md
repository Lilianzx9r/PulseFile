# PulseFile v1.0.1

## Fix compilation Windows

Removed the unsupported `Directory.listRoots()` calls.

Windows drive enumeration now uses PowerShell's filesystem providers and returns
available drive roots such as `C:\`, `D:\`, etc.

macOS/Linux retain `/` as the local root.

This version is packaged with `PulseFile` as the archive root.
