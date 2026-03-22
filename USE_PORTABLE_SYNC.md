# Use the Portable Sync Script

Prefer `sync_phone_portable.ps1` on the `chatgpt/fix-portable-sync` branch.

## Why

The original `sync_phone.ps1` is tied to a machine-specific local path and a pinned device serial.

The portable version instead:

- uses the repository directory as the default local path
- auto-detects a single connected authorized ADB device
- requires `-Serial` only when multiple devices are connected
- preserves preview mode and size verification

## Recommended usage

```powershell
& .\sync_phone_portable.ps1 -Preview
```

```powershell
& .\sync_phone_portable.ps1
```
