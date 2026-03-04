<#
.SYNOPSIS
  WinUninstaller (Classic) - label-driven Windows uninstaller.

.DESCRIPTION
  This is a simplified, resilient runner designed to be stable across machines.

  What it does:
   1) Load a label (.psd1)
   2) Stop configured processes/services (best effort)
   3) Find uninstall commands from registry uninstall keys
   4) Execute uninstall (prefers QuietUninstallString)
   5) Apply ONLY safe silent hints when -Silent is used:
        - MSI: add /qn /norestart if not present
        - Chrome setup.exe: add --force-uninstall if not present
   6) Cleanup leftover paths and (optional) per-user paths

  Design goals:
   - Keep it simple.
   - Never assume properties exist.
   - Never assume arrays.
   - Do not stop on non-critical errors.

.PARAMETER Label
  Label name (filename without .psd1)

.PARAMETER LabelsPath
  Path to labels folder

.PARAMETER Silent
  Attempt silent/unattended uninstall where possible.

.PARAMETER RemoveUserData
  Remove per-user leftovers defined in the label.

.EXAMPLE
  .\WinUninstaller.ps1 -Label googlechrome -LabelsPath .\labels -Silent -RemoveUserData -Verbose
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true)]
  [string]$Label,

  [string]$LabelsPath = (Join-Path -Path $PSScriptRoot -ChildPath 'labels'),

  [switch]$Silent,
  [switch]$RemoveUserData
)

$ErrorActionPreference = 'Stop'

function Log {
  param([string]$msg,[string]$lvl='INFO')
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host ("[{0}][{1}] {2}" -f $ts, $lvl, $msg)
}

function AsArray($x) { @($x) }

function HasProp($obj, $name) {
  try { return $null -ne $obj.PSObject.Properties[$name] } catch { return $false }
}

function IsAdmin {
  try {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent();
    $p=New-Object Security.Principal.WindowsPrincipal($id);
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

function GetProfiles {
  $profiles=@()
  try {
    $pl='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $profiles = Get-ChildItem $pl -ErrorAction Stop | ForEach-Object {
      $p = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
      if ($p -and (Test-Path $p)) { $p }
    }
  } catch {
    $profiles = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
  }
  $skip=@('C:\Users\Default','C:\Users\Default User','C:\Users\Public','C:\Users\All Users')
  $profiles | Where-Object { $skip -notcontains $_ }
}

function StopProcesses($names) {
  foreach ($n in AsArray $names) {
    if ([string]::IsNullOrWhiteSpace($n)) { continue }
    try {
      foreach ($p in (Get-Process -Name $n -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess(("process {0} (PID {1})" -f $p.Name,$p.Id),'Stop')) {
          Log ("Stopping process: {0} (PID {1})" -f $p.Name,$p.Id)
          try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
      }
    } catch { Log ("Process stop failed for {0}: {1}" -f $n,$_.Exception.Message) 'DEBUG' }
  }
}

function StopServices($names) {
  foreach ($n in AsArray $names) {
    if ([string]::IsNullOrWhiteSpace($n)) { continue }
    try {
      $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
      if ($svc -and $svc.Status -ne 'Stopped') {
        if ($PSCmdlet.ShouldProcess(("service {0}" -f $n),'Stop')) {
          Log ("Stopping service: {0}" -f $n)
          try { Stop-Service -Name $n -Force -ErrorAction SilentlyContinue } catch {}
        }
      }
    } catch { Log ("Service stop failed for {0}: {1}" -f $n,$_.Exception.Message) 'DEBUG' }
  }
}

function GetUninstallEntries($regex) {
  $paths=@(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  $items=@()
  foreach ($rp in $paths) {
    try {
      $items += Get-ItemProperty $rp -ErrorAction SilentlyContinue | Where-Object {
        (HasProp $_ 'DisplayName') -and $_.DisplayName -and ($_.DisplayName -match $regex)
      }
    } catch { Log ("Registry query failed for {0}: {1}" -f $rp,$_.Exception.Message) 'DEBUG' }
  }
  $items | Sort-Object DisplayName, DisplayVersion -Descending |
    Select-Object DisplayName, DisplayVersion, UninstallString, QuietUninstallString
}

function ApplySilentHints($cmd, $labelCfg) {
  if (-not $Silent) { return $cmd }
  $c = $cmd.Trim()

  # MSI
  if ($c -match '(?i)\bmsiexec(\.exe)?\b') {
    if ($c -notmatch '(?i)\s/(q|quiet|qn)\b') { $c = "$c /qn /norestart" }
    return $c
  }

  # Chrome setup.exe
  if ($c -match '(?i)Google\\Chrome\\Application\\.*\\Installer\\setup\.exe') {
    if ($c -notmatch '(?i)--force-uninstall') { $c = "$c --force-uninstall" }
    return $c
  }

  # Optional EXE silent args if label provides them
  if ($labelCfg.ContainsKey('ExeSilentArgs') -and $labelCfg.ExeSilentArgs) {
    $c = "$c $($labelCfg.ExeSilentArgs)"
  }

  return $c
}

function RunCmd($cmd) {
  Log ("Executing uninstall: {0}" -f $cmd)
  if ($PSCmdlet.ShouldProcess($cmd,'Execute')) {
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmd -Wait -PassThru -WindowStyle Hidden
    Log ("Uninstall exit code: {0}" -f $p.ExitCode)
    return $p.ExitCode
  }
  return 0
}

function RemovePath($path) {
  if ([string]::IsNullOrWhiteSpace($path)) { return }
  try {
    if (Test-Path -LiteralPath $path) {
      if ($PSCmdlet.ShouldProcess($path,'Remove')) {
        Log ("Removing path: {0}" -f $path)
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
  } catch { Log ("Failed removing {0}: {1}" -f $path,$_.Exception.Message) 'DEBUG' }
}

function FindChromeSetup {
  $roots=@('C:\Program Files\Google\Chrome\Application','C:\Program Files (x86)\Google\Chrome\Application')
  $setups=@()
  foreach ($r in $roots) {
    if (Test-Path $r) {
      try {
        $setups += Get-ChildItem $r -Directory -ErrorAction SilentlyContinue | ForEach-Object {
          $p = Join-Path $_.FullName 'Installer\setup.exe'
          if (Test-Path $p) { $p }
        }
      } catch {}
    }
  }
  foreach ($prof in GetProfiles) {
    $u = Join-Path $prof 'AppData\Local\Google\Chrome\Application'
    if (Test-Path $u) {
      try {
        $setups += Get-ChildItem $u -Directory -ErrorAction SilentlyContinue | ForEach-Object {
          $p = Join-Path $_.FullName 'Installer\setup.exe'
          if (Test-Path $p) { $p }
        }
      } catch {}
    }
  }
  $setups | Select-Object -Unique
}

# --- Start ---
if (-not (IsAdmin)) { Log 'WARNING: Not running as Administrator. Uninstall/cleanup may fail.' 'WARN' }

$labelFile = Join-Path -Path $LabelsPath -ChildPath ("{0}.psd1" -f $Label)
if (-not (Test-Path $labelFile)) { throw ("Label file not found: {0}" -f $labelFile) }

$cfg = Import-PowerShellDataFile $labelFile
Log ("Loaded label: {0} - {1}" -f $cfg.Label,$cfg.Title)

StopProcesses $cfg.ProcessesToStop
StopServices  $cfg.ServicesToStop

$entries = @()
try { $entries = AsArray (GetUninstallEntries $cfg.DisplayNameRegex) } catch { $entries=@() }

if ((AsArray $entries).Count -eq 0) {
  Log ("No installed product matched: {0}" -f $cfg.DisplayNameRegex) 'WARN'
} else {
  foreach ($e in AsArray $entries) {
    $cmds=@()
    if (HasProp $e 'QuietUninstallString' -and $e.QuietUninstallString) { $cmds += $e.QuietUninstallString }
    if (HasProp $e 'UninstallString' -and $e.UninstallString) { $cmds += $e.UninstallString }

    if ($cmds.Count -eq 0) { continue }

    foreach ($raw in $cmds) {
      try {
        $cmd = ApplySilentHints $raw $cfg
        $exit = RunCmd $cmd
        if ($exit -eq 0) { break }
      } catch { Log ("Uninstall attempt failed: {0}" -f $_.Exception.Message) 'WARN' }
    }
  }
}

# Chrome fallback if requested
if ((HasProp $cfg 'AppId') -and $cfg.AppId -eq 'chrome') {
  $still = AsArray (GetUninstallEntries $cfg.DisplayNameRegex)
  if ($still.Count -gt 0) {
    Log 'Chrome still appears installed; trying setup.exe fallback.' 'WARN'
    foreach ($setup in FindChromeSetup) {
      $cmd = ('"{0}" --uninstall --multi-install --chrome --system-level' -f $setup)
      if ($Silent) { $cmd = "$cmd --force-uninstall" }
      try {
        $exit = RunCmd $cmd
        if ($exit -eq 0) { break }
      } catch { Log ("Chrome setup fallback failed: {0}" -f $_.Exception.Message) 'WARN' }
    }
  }
}

# Cleanup
foreach ($p in AsArray $cfg.RemovePaths) { RemovePath $p }

if ($RemoveUserData) {
  foreach ($prof in GetProfiles) {
    foreach ($rel in AsArray $cfg.PerUserPaths) {
      if ([string]::IsNullOrWhiteSpace($rel)) { continue }
      RemovePath (Join-Path $prof $rel)
    }
  }
} else {
  if ($cfg.PerUserPaths) { Log 'Per-user cleanup skipped (use -RemoveUserData to remove user data).' }
}

Log 'Done.'
