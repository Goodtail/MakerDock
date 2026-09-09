# MakerDock 0.1.1 — local build 17

- Completing an active print calculates elapsed time from its start and end timestamps instead of prefilling an estimate. Edit either timestamp or the duration before saving. Records retain both dates.
- Add Settings → Printer connection for a local IPv4 address, serial and LAN access code. Store the code in macOS Keychain; verify the printer using official Studio's public CA certificates.
- Receive printer progress, remaining time, paused/finished/failed state, and observed filament types. Explicitly link a live job to a queue entry. Queue planning uses fresh printer timing and blocks uncertain slots.
- Capture observed finish time, flag missed transitions for review, and prefill completion records. Recording and file moves remain user-confirmed. Failed work stays queued for retry.
- Include Korean, English, Japanese and Simplified Chinese text and setup instructions.

Verified with the core and app suites, native TLS mock-printer tests, and rendered narrow-window/form checks. Actual X2D connection testing needs the printer's connection details. Past cloud print history is not imported, and spool weight is not reported as material consumed.

This is a local update. The public version stays 0.1.1; internal build increases to 17.
