# BG3 Save Scavenger (macOS)

Automates the `profile8.lsf` cleanup for Baldur's Gate 3 on macOS.
It finds your `profile8.lsf`, backs it up twice, converts to LSX, removes the `DisabledSingleSaveSessions` block(s), then converts back to LSF.

## One‑shot (curl | sh)

```bash
curl -fsSL <PUT_YOUR_EPIC_BG3_LINK_HERE> | bash
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

---

> Placeholder link: waiting for a hero to cast `Git Push` and open the portal.
