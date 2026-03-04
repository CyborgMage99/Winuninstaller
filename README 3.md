# WinUninstaller (Windows) – Label‑Driven App Removal Framework

This repository documents how to set up and use **WinUninstaller**, a simple, resilient, label‑driven Windows uninstaller inspired by the *erikstam/uninstaller* workflow on macOS.

The design goal is **stability over cleverness**:
- No StrictMode
- No fragile object assumptions
- Registry‑based uninstall first
- Safe silent hints only
- Cleanup always runs

---

## Contents of This Package

```
WinUninstaller├── WinUninstaller.ps1
└── labels    └── googlechrome.psd1
```

---

## How It Works (Concept)

1. **Runner script** (`WinUninstaller.ps1`)
   - Generic engine
   - Does not know about any specific app

2. **Label files** (`labels\*.psd1`)
   - One label per application
   - Defines what to stop, how to identify the app, and what leftovers to remove

You uninstall apps by **calling the runner with a label name**.

---

## Step‑by‑Step Setup

### 1. Create the folder structure

Create a permanent location (recommended):

```
C:\Tools\WinUninstaller
```

Inside it:

```
C:\Tools\WinUninstaller\labels
```

---

### 2. Copy the files

Place the files exactly as follows:

- `WinUninstaller.ps1` → `C:\Tools\WinUninstaller\WinUninstaller.ps1`
- `googlechrome.psd1` → `C:\Tools\WinUninstaller\labels\googlechrome.psd1`

> Folder and file names **must match exactly**.

---

### 3. Verify PowerShell execution

Run PowerShell **as Administrator**.

Optional but recommended test:

```
Test-Path "C:\Tools\WinUninstaller\WinUninstaller.ps1"
Test-Path "C:\Tools\WinUninstaller\labels\googlechrome.psd1"
```

Both should return `True`.

---

## Running an Uninstall (Google Chrome Example)

This is the exact command used and verified:

```
powershell.exe -ExecutionPolicy Bypass -NoProfile   -File "C:\Tools\WinUninstaller\WinUninstaller.ps1"   -Label googlechrome   -LabelsPath "C:\Tools\WinUninstaller\labels"   -Silent   -RemoveUserData   -Verbose
```

### What each switch does

| Switch | Purpose |
|------|--------|
| `-Label googlechrome` | Tells the runner which label to load |
| `-LabelsPath` | Explicit path to labels (avoids relative path issues) |
| `-Silent` | Adds safe silent hints (MSI `/qn`, Chrome `--force-uninstall`) |
| `-RemoveUserData` | Removes per‑user Chrome profiles (AppData) |
| `-Verbose` | Shows detailed progress |

---

## Expected Behavior

- Stops Chrome and Google Update processes
- Uses registry uninstall commands first
- Forces Chrome silent uninstall when applicable
- Removes leftover program files
- Optionally removes user profile data
- **Does not error if Chrome is already removed**

If Chrome is not installed, you will see:

```
No installed product matched: Google Chrome
```

This is **normal and expected**.

---

## Adding More Applications

1. Copy an existing label:

```
labels\googlechrome.psd1
```

2. Rename it:

```
labelsmwareplayer.psd1
```

3. Update these fields inside the label:

- `Label`
- `Title`
- `DisplayNameRegex`
- `ProcessesToStop`
- `ServicesToStop`
- `RemovePaths`
- `PerUserPaths` (optional)

No changes to `WinUninstaller.ps1` are required.

---

## Design Rules (Important)

- **Do not** add StrictMode
- **Do not** rely on `.Count` or `.Length` without wrapping in `@()`
- Prefer vendor uninstallers over forced deletion
- Keep labels conservative by default

---

## Recommended Use Cases

- Intune Win32 app uninstall commands
- RMM / MDM remediation scripts
- Break‑glass cleanup for broken installs
- Admin‑initiated removals

---

## Known Safe Extensions

Future enhancements that fit this model:

- Additional labels (VMware Player, Zoom, Slack, etc.)
- Separate `*_nuke.psd1` labels for aggressive cleanup
- Optional logging to file

---

## Support Philosophy

This framework is intentionally:
- Boring
- Predictable
- Easy to debug

If it says **"Done."**, the run completed.

---

✅ **You now have a working, repeatable Windows uninstall framework.**