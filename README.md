# Rhino-style navigation for Autodesk Fusion on a 3Dconnexion CadMouse

Make Fusion's viewport navigation work like Rhino's, so you don't have to retrain your hands every time you switch programs.

| CadMouse control | Fusion after setup | Rhino |
|---|---|---|
| Right button drag | Orbit | Rotate (in perspective views) |
| Middle button drag (the dedicated button) | Pan | Pan, with Rhino's middle button set to Pan in Options > Mouse (Shift + right drag pans too) |
| Wheel | Zoom | Zoom |
| Wheel click | Marking menu | |

Two parts do the work:

1. **A Fusion preference** (no script needed): the Tinkercad navigation preset gives orbit, pan and zoom.
2. **This script**: the Tinkercad preset moves Fusion's marking menu from the right button to Shift + right button. The script maps the CadMouse wheel click to Shift + right button in 3DxWare's Fusion profile, so a wheel click opens the marking menu.

Nothing is installed into Fusion. No add-in, no background program. The script edits one 3DxWare settings file, after backing it up.

## Requirements

- **Windows 10 or 11.** The script is for 3DxWare on Windows (macOS uses a different settings format).
- **Autodesk Fusion.**
- **A 3Dconnexion CadMouse** with **3DxWare** installed and running. Supported models: CadMouse, CadMouse Wireless, CadMouse Pro, CadMouse Pro Wireless, CadMouse Pro Wireless Left, CadMouse Compact, CadMouse Compact Wireless.
- **PowerShell 7 or newer.** The Windows PowerShell 5.1 that comes with Windows will not run it. To check, open a terminal and run `pwsh -v`. If that fails, install PowerShell 7 (see step 2).

**Tested on:** Windows 11 Pro, 3DxWare driver 17.9.15, CadMouse Compact, Fusion (November 2026). All seven models report the wheel click as the same button (`HIDButton_4`) in 3DxWare's device list, so the others should work the same way. If yours doesn't, please open an issue.

**Why a CadMouse?** On an ordinary mouse the wheel click *is* the middle button, so you can't have middle-button pan and a wheel-click marking menu at once. The CadMouse has a separate middle button between the main buttons, which makes this possible.

## Setup

### 1. Set Fusion's navigation preset

1. In Fusion, click your profile icon (top right) and choose **Preferences**.
2. Under **General**, set **Pan, Zoom, Orbit Shortcuts** to **Tinkercad**.
3. Click **OK**.

Right drag now orbits, middle drag pans and the wheel zooms. Steps 2 to 5 add the wheel-click marking menu.

### 2. Install PowerShell 7 (skip if `pwsh -v` works)

Run in any terminal (Windows Terminal, Command Prompt or PowerShell):

```powershell
winget install --id Microsoft.PowerShell --source winget
```

Close the terminal and open a new one afterward. Or download the installer from https://aka.ms/powershell-release?tag=stable .

### 3. Download this repository

On this page, click **Code > Download ZIP**, then extract the ZIP somewhere, for example `Downloads\Fusion-rhino3d-navigation`. (Or use `git clone`.)

### 4. Run the script

1. **Close Fusion.**
2. Open a terminal in the extracted folder (in File Explorer, right-click inside the folder and choose **Open in Terminal**).
3. Optional, to see what would change without changing anything:

   ```powershell
   pwsh -ExecutionPolicy Bypass -File .\scripts\Set-FusionMouseRemap.ps1 -WhatIf
   ```

4. Install:

   ```powershell
   pwsh -ExecutionPolicy Bypass -File .\scripts\Set-FusionMouseRemap.ps1
   ```

   It prints the profile it changed and the backup it made, for example:

   ```text
   Installed: C:\Users\you\AppData\Roaming\3Dconnexion\3DxWare\Cfg\Fusion360FS.xml
   Backup: C:\Users\you\AppData\Roaming\3Dconnexion\3DxWare\Cfg\Fusion360FS.xml.fusion-mouse-remap.20261114-153000.bak
   ```

`-ExecutionPolicy Bypass` applies only to this one command. It lets Windows run a script downloaded from the internet without changing your system settings.

### 5. Restart Windows

Restart (or sign out and back in) so 3DxWare loads the changed profile. Then open Fusion and try it: right drag, middle drag, wheel, wheel click.

## Check, undo and re-run

Run these in a terminal in the repository folder.

**Check that the mapping is in place:**

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\Set-FusionMouseRemap.ps1 -Mode Status
```

`Configured` means it's in place. It may also list CadMouse models that aren't set up. That's fine if you don't own them.

**Undo:**

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\Set-FusionMouseRemap.ps1 -Mode Restore
```

This puts back the profile as it was before the script first ran (the oldest backup). Any Fusion button changes you made in the 3Dconnexion settings since then are lost. Restart Windows afterward, and set Fusion's preset back under **Preferences > General** if you like.

**After a 3DxWare update** or reinstall, run the Status check. If it says `Not configured`, run the install command again and restart.

## Troubleshooting

| Message or symptom | What to do |
|---|---|
| `No 3DxWare Fusion profile at ...` | 3DxWare creates the Fusion profile the first time you change a CadMouse button for Fusion. Click into Fusion, open the 3Dconnexion settings (from the 3Dconnexion Home app or the 3Dconnexion icon in the system tray), set the wheel-click button to any command (the script replaces it), close the settings and run the script again. |
| `The script ... cannot be run because it contained a "#requires" statement for Windows PowerShell 7.0` | You ran it with Windows PowerShell 5.1 (`powershell`). Use `pwsh` as shown above, after installing PowerShell 7. |
| `pwsh` is not recognized | Install PowerShell 7 (step 2), then open a new terminal. |
| Wheel click does nothing in Fusion | Restart Windows. Check that 3DxWare is running (3Dconnexion icon in the tray). Run the Status check. |
| Wheel click opens the menu, but right drag doesn't orbit | Step 1: Fusion's preset must be **Tinkercad**. |

## What exactly changes

- **One file:** `%APPDATA%\3Dconnexion\3DxWare\Cfg\Fusion360FS.xml`, your personal 3DxWare profile for Fusion. It's backed up first, next to the original, as `Fusion360FS.xml.fusion-mouse-remap.<date-time>.bak`. Use `-NoBackup` to skip the backup.
- **What's added:** a macro named "Fusion Marking Menu" (Shift + right mouse button), and the wheel-click button set to that macro for every supported CadMouse model in every Fusion workspace (Design, Sketch, Surface, Sheet Metal, Render, Animation, Manufacture, Drawing and so on).
- **Not touched:** your other button settings, other programs' profiles, and the factory profile under `Program Files`. The script only reads the factory profile to learn Fusion's workspace names.

Running the install again is safe. It makes a new backup and leaves the result the same.

## For developers

Run the test (needs PowerShell 7; it uses a small sample profile in `tests/fixtures/` and writes to `.test-output/`):

```powershell
pwsh -File .\tests\Test-FusionMouseRemap.ps1
```

Options: `-ProfilePath` and `-FactoryProfilePath` point at other files; `-DeviceIds` limits or extends the device list (3DxWare's IDs, such as `ID_ProductID_C655`).

## License and trademarks

MIT, see [LICENSE](LICENSE).

Not affiliated with or endorsed by Autodesk, Robert McNeel & Associates or 3Dconnexion. Fusion is a trademark of Autodesk, Inc. Rhino and Rhinoceros are trademarks of Robert McNeel & Associates. 3Dconnexion, CadMouse and 3DxWare are trademarks of 3Dconnexion.

Made by [Precision Crab](https://precisioncrab.com).
