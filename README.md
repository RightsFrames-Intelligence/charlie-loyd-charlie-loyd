# Charlie 2.0

Charlie 2.0 is the GitHub home for the project files and device-sync workflow used to keep the PC copy and Android phone copy aligned.

## What is in this repo

- `sync_phone.ps1`: One-way ADB sync from the local repo to the phone.

## Current workflow

The sync script compares local files against the phone copy, skips `.git`, and only pushes files that are missing or newer on the PC.

Default phone target:

```text
/sdcard/CHARLIE 2.0 CODES
```

## Requirements

- Windows PowerShell or PowerShell 7
- `adb` available in `PATH`
- USB debugging enabled on the Android device
- The target phone authorized for ADB

## Usage

Preview the sync without copying files:

```powershell
& .\sync_phone.ps1 -Preview
```

Run the sync:

```powershell
& .\sync_phone.ps1
```

Override the target path:

```powershell
& .\sync_phone.ps1 -RemotePath '/sdcard/Some Other Folder'
```

## Notes

- The script verifies copied file sizes after each push.
- The default device serial is pinned in the script and can be overridden at runtime.
- This repo is currently in a bootstrap state and will expand as Charlie 2.0 grows.
