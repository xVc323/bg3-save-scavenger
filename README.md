# BG3 Save Scavenger (macOS)

Automates the `profile8.lsf` cleanup for Baldur's Gate 3 on macOS.
This removes the `DisabledSingleSaveSessions` block(s) so Honour mode runs stop being flagged after a failure.
In practice, it turns a failed Honour run (custom rules) back into Honour.
The script finds `profile8.lsf`, backs it up twice, converts to LSX, edits the block, then converts back to LSF.

## One‑shot (curl | sh)

Copy/paste this line into a Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/xVc323/bg3-save-scavenger/refs/heads/main/fix_profile8.sh | bash
```

## Local usage

```bash
./fix_profile8.sh
```

## Notes

- Default path is auto‑detected under:
  `~/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles`
- Backups are saved next to the file **and** in `~/Documents/bg3_backups/`
- If no nodes are found, the script continues by default
- Colors are enabled by default (use `--color never` or `NO_COLOR=1` to disable)

## Credits

- Norbyte for LSLib / Divine: https://github.com/Norbyte/lslib

---
