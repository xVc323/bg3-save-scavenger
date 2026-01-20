# BG3 Save Scavenger (macOS + Windows)

Automates the `profile8.lsf` cleanup for Baldur's Gate 3 on macOS.
This removes the `DisabledSingleSaveSessions` block(s) so Honor mode runs stop being flagged after a failure.
In practice, it turns a failed Honor run (custom rules) back into Honor.
The script finds `profile8.lsf`, backs it up twice, converts to LSX, edits the block, then converts back to LSF.

> [!WARNING]
> Use this at your own risk. Always make a manual backup before running, even though the script makes two backups.  
> Larian could change save formats or validation at any time; if that happens, this tool may stop working or could damage saves.

## Easiest way to run (Copy/Paste this in your terminal)

- **macOS/Linux (Terminal)**
  ```bash
  curl -fsSL https://raw.githubusercontent.com/xVc323/bg3-save-scavenger/refs/heads/main/fix_profile8.sh | bash
  ```
- **Windows (PowerShell)**
  ```powershell
  irm https://raw.githubusercontent.com/xVc323/bg3-save-scavenger/refs/heads/main/fix_profile8.ps1 | iex
  ```

## What this does

- Edits only `profile8.lsf` (global difficulty flags)
- Removes `DisabledSingleSaveSessions` entries
- Creates two automatic backups (next to the file and in `~/Documents/bg3_backups/`)

## What this does not do

- It does **not** edit individual save files (`*.lsv`) or campaign saves
- It does **not** guarantee compatibility with future game updates

## Local usage

```bash
git clone https://github.com/xVc323/bg3-save-scavenger.git
cd bg3-save-scavenger
./fix_profile8.sh
```

```powershell
git clone https://github.com/xVc323/bg3-save-scavenger.git
cd bg3-save-scavenger
.\fix_profile8.ps1
```

## Requirements

- macOS/Linux script execution needs `python3`
- macOS auto-build needs `git` and `dotnet`
- Windows script execution needs PowerShell 5+
- Windows needs `dotnet` if your LSLib tool is a `.dll`
- Missing `git`/`dotnet` fails fast and leaves your file untouched
- Quick install (macOS):
  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  brew install git dotnet python
  ```

## Notes

- macOS default path is auto‑detected under:
  `~/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles`
- Windows default path is auto‑detected under:
  `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\PlayerProfiles\Public`
- Backups are saved next to the file **and** in `~/Documents/bg3_backups/`
- If no nodes are found, the script continues by default
- Colors are enabled by default (use `--color never` or `NO_COLOR=1` to disable)
- You can run the script from any folder (it targets the file path directly)

## Troubleshooting

- **Error: `profile8.lsf not found`**
  The script couldn’t auto-detect your file. Re‑run it and pass the exact path:
- **Custom profile path (macOS/Linux):**
  ```bash
  ./fix_profile8.sh --profile "/path/to/profile8.lsf"
  ```
- **Custom profile path (Windows):**
  ```powershell
  .\fix_profile8.ps1 -ProfilePath "C:\Path\To\profile8.lsf"
  ```

## Credits

- Norbyte for LSLib / Divine: https://github.com/Norbyte/lslib

---
