# Contributing

## Ground rules

- Keep changes focused and easy to review.
- Prefer small pull requests with a clear purpose.
- Do not commit secrets, exported tokens, or personal device dumps.

## Local checks

Before opening a pull request:

1. Run `& .\sync_phone.ps1 -Preview` and confirm the script still parses and reports correctly.
2. If you changed PowerShell, keep syntax valid and readable.
3. Update `README.md` when behavior or setup changes.

## Pull requests

- Explain the change in plain language.
- Include the commands you ran to validate it.
- Call out any ADB, device, or environment assumptions.
