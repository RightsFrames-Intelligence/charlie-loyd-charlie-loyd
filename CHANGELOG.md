# Changelog

All notable changes to this repository are documented here from confirmed git history.

## Unreleased

- Added `tests/sync_phone.tests.ps1` to cover path quoting, remote mapping, and dot-sourced command exposure.
- Refactored `sync_phone.ps1` to expose reusable functions when dot-sourced and only execute the sync flow when run directly.
- Updated `.github/workflows/validate-powershell.yml` to execute repo-local PowerShell tests after syntax validation.

## 2026-03-14

- Added Apache-2.0 licensing and normalized the license text for GitHub detection.
- Polished repository presentation and the phone sync workflow.
- Added `SECURITY.md`.

## 2026-03-13

- Initial repository bootstrap.
