<#
.SYNOPSIS
    Sets up the Windows half of LucasSetup: AutoHotkey window manager + PowerToys.

.DESCRIPTION
    Installs Brave, AutoHotkey v2, Windows Terminal and PowerToys (via winget),
    detects where they actually landed on THIS machine, rewrites the machine-specific
    paths baked into the PowerToys backup, and wires the AHK script to run at login.

    The committed .ptb was captured on another PC, so it hardcodes that machine's
    username and Brave location. This script replaces those with the real ones.

.PARAMETER SkipInstall
    Don't run winget. Only detect paths, patch the backup and set up AutoHotkey.

.PARAMETER ApplyDirect
    Write the patched settings straight into PowerToys' live settings folder instead
    of leaving a .ptb for you to restore through the GUI. Stops PowerToys first and
    backs up the existing settings. Faster, but the GUI restore is the supported path.

.PARAMETER NoStartup
    Don't create the Startup shortcut for WindowManager.ahk.

.EXAMPLE
    .\Setup.ps1
    .\Setup.ps1 -SkipInstall -ApplyDirect
#>

[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [switch]$ApplyDirect,
    [switch]$NoStartup
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# Paths as they were baked into the committed backup, on the machine it came from.
$OldUserLocal = 'C:\Users\lucasdonald\AppData\Local'
$OldBrave     = "$OldUserLocal\BraveSoftware\Brave-Browser\Application\brave.exe"
$OldWinDir    = 'C:\Windows'

function Write-Step { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    OK   $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "    WARN $m" -ForegroundColor Yellow }
function Write-Info { param($m) Write-Host "    $m" -ForegroundColor DarkGray }

# ---------------------------------------------------------------- install ----

function Install-WingetPackage {
    param([string]$Id, [string]$Name)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warn  "winget not found - install $Name manually"
        return
    }

    $installed = winget list --id $Id --exact --accept-source-agreements 2>$null | Out-String
    if ($installed -match [regex]::Escape($Id)) {
        Write-Ok "$Name already installed"
        return
    }

    Write-Info "installing $Name ($Id) ..."
    winget install --id $Id --exact --silent `
        --accept-package-agreements --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok "$Name installed" }
    else { Write-Warn  "winget exited $LASTEXITCODE for $Name - continuing" }
}

# ----------------------------------------------------------------- detect ----

function Find-Brave {
    # App Paths registry key is what Windows itself uses, so try it first.
    foreach ($root in 'HKLM:', 'HKCU:') {
        $key = "$root\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe"
        if (Test-Path $key) {
            $p = (Get-ItemProperty $key).'(default)'
            if ($p -and (Test-Path $p)) { return $p }
        }
    }
    $candidates = @(
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
        "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"
        "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

function Find-AutoHotkey {
    $candidates = @(
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe"
        "${env:ProgramFiles(x86)}\AutoHotkey\v2\AutoHotkey32.exe"
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    # Newer installers ship a launcher that dispatches by #Requires directive.
    foreach ($c in @("$env:ProgramFiles\AutoHotkey\AutoHotkey.exe",
                     "$env:LOCALAPPDATA\Programs\AutoHotkey\AutoHotkey.exe")) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

# -------------------------------------------------------------- ptb patch ----

function Update-PowerToysBackup {
    param(
        [string]$SourcePtb,
        [string]$DestPtb,
        [hashtable]$Replacements
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Read every entry into memory first - we rewrite the archive wholesale so that
    # entry names keep their forward slashes (Compress-Archive mangles them).
    $entries = [ordered]@{}
    $zip = [IO.Compression.ZipFile]::OpenRead($SourcePtb)
    try {
        foreach ($e in $zip.Entries) {
            $ms = New-Object IO.MemoryStream
            $s = $e.Open()
            try { $s.CopyTo($ms) } finally { $s.Dispose() }
            $entries[$e.FullName] = $ms.ToArray()
        }
    } finally { $zip.Dispose() }

    $patchedFiles = @()
    foreach ($name in @($entries.Keys)) {
        if ($name -notlike '*.json') { continue }

        $text = [Text.Encoding]::UTF8.GetString($entries[$name])
        $original = $text

        foreach ($from in $Replacements.Keys) {
            $to = $Replacements[$from]
            if (-not $to) { continue }
            # Paths inside JSON are backslash-escaped, so escape both sides to match.
            $text = $text.Replace($from.Replace('\','\\'), $to.Replace('\','\\'))
        }

        if ($text -ne $original) {
            # Fail loudly rather than shipping a backup PowerToys will reject.
            try { $null = $text | ConvertFrom-Json }
            catch { throw "Patching '$name' produced invalid JSON: $($_.Exception.Message)" }

            $entries[$name] = [Text.Encoding]::UTF8.GetBytes($text)
            $patchedFiles += $name
        }
    }

    if (Test-Path $DestPtb) { Remove-Item $DestPtb -Force }
    $out = [IO.Compression.ZipFile]::Open($DestPtb, 'Create')
    try {
        foreach ($name in $entries.Keys) {
            $entry = $out.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
            $s = $entry.Open()
            try { $s.Write($entries[$name], 0, $entries[$name].Length) } finally { $s.Dispose() }
        }
    } finally { $out.Dispose() }

    return $patchedFiles
}

function Expand-IntoLiveSettings {
    param([string]$Ptb, [string]$SettingsRoot)

    $running = Get-Process PowerToys -ErrorAction SilentlyContinue
    if ($running) {
        Write-Info 'stopping PowerToys ...'
        $running | Stop-Process -Force
        Start-Sleep -Seconds 2
    }

    if (Test-Path $SettingsRoot) {
        $backup = "$SettingsRoot.before-lucassetup-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item $SettingsRoot $backup -Recurse -Force
        Write-Ok "existing settings backed up to $backup"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Ptb)
    try {
        foreach ($e in $zip.Entries) {
            if ($e.FullName -eq 'manifest.json') { continue }   # backup metadata, not a setting
            $target = Join-Path $SettingsRoot $e.FullName.Replace('/', '\')
            $dir = Split-Path -Parent $target
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
        }
    } finally { $zip.Dispose() }

    return [bool]$running
}

# ================================================================== main =====

Write-Host 'LucasSetup - Windows' -ForegroundColor White
Write-Info "running from $ScriptDir"

foreach ($f in 'WindowManager.ahk', 'VD.ah2', 'powertoys-settings.ptb') {
    if (-not (Test-Path (Join-Path $ScriptDir $f))) {
        throw "Missing $f - run this script from the repo's windows\ folder."
    }
}

# --- 1. install ---------------------------------------------------------------
if ($SkipInstall) {
    Write-Step 'Install (skipped)'
} else {
    Write-Step 'Installing packages'
    Install-WingetPackage -Id 'Brave.Brave'               -Name 'Brave'
    Install-WingetPackage -Id 'AutoHotkey.AutoHotkey'     -Name 'AutoHotkey v2'
    Install-WingetPackage -Id 'Microsoft.WindowsTerminal' -Name 'Windows Terminal'
    Install-WingetPackage -Id 'Microsoft.PowerToys'       -Name 'PowerToys'
}

# --- 2. detect ----------------------------------------------------------------
Write-Step 'Detecting paths on this machine'

$bravePath = Find-Brave
if ($bravePath) {
    Write-Ok "Brave        $bravePath"
} else {
    Write-Warn  'Brave not found - the Win+B remap will keep the old path.'
    Write-Info  'Install Brave, then re-run with -SkipInstall to fix it up.'
}

$wtPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
if (Test-Path $wtPath) { Write-Ok "Terminal     $wtPath" }
else { Write-Warn  "Windows Terminal not at $wtPath - Win+T may not launch." }

Write-Ok "User local   $env:LOCALAPPDATA"
Write-Ok "Windows dir  $env:WINDIR"

$ahkExe = Find-AutoHotkey
if ($ahkExe) { Write-Ok "AutoHotkey   $ahkExe" }
else { Write-Warn  'AutoHotkey v2 not found - startup shortcut will use the file association.' }

# NewPlus points at a templates folder that may not exist yet on a fresh install.
$newPlusTemplates = "$env:LOCALAPPDATA\Microsoft\PowerToys\NewPlus\Templates"
if (-not (Test-Path $newPlusTemplates)) {
    New-Item -ItemType Directory -Path $newPlusTemplates -Force | Out-Null
    Write-Ok "created NewPlus templates folder"
}

# --- 3. patch the PowerToys backup -------------------------------------------
Write-Step 'Rewriting machine-specific paths in the PowerToys backup'

$replacements = [ordered]@{}
# Most specific first: Brave may not live under LocalAppData at all.
if ($bravePath) { $replacements[$OldBrave] = $bravePath }
$replacements[$OldUserLocal] = $env:LOCALAPPDATA
$replacements[$OldWinDir]    = $env:WINDIR

$backupDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerToys\Backup'
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }

$stamp     = Get-Date -Format 'yyyyMMddHHmmss'
$destPtb   = Join-Path $backupDir "settings_lucassetup_$stamp.ptb"
$sourcePtb = Join-Path $ScriptDir 'powertoys-settings.ptb'

$patched = @(Update-PowerToysBackup -SourcePtb $sourcePtb -DestPtb $destPtb -Replacements $replacements)

if ($patched.Count -gt 0) {
    foreach ($p in $patched) { Write-Ok "patched $p" }
} else {
    Write-Info 'nothing needed rewriting (paths already match this machine)'
}
Write-Ok "wrote $destPtb"

# --- 4. apply -----------------------------------------------------------------
$settingsRoot = "$env:LOCALAPPDATA\Microsoft\PowerToys"

if ($ApplyDirect) {
    Write-Step 'Applying settings directly'
    $wasRunning = Expand-IntoLiveSettings -Ptb $destPtb -SettingsRoot $settingsRoot
    Write-Ok "settings written to $settingsRoot"
    if ($wasRunning) {
        $ptExe = "$env:ProgramFiles\PowerToys\PowerToys.exe"
        if (Test-Path $ptExe) { Start-Process $ptExe; Write-Ok 'PowerToys restarted' }
        else { Write-Warn  'start PowerToys manually' }
    }
} else {
    Write-Step 'Next step for PowerToys (manual)'
    Write-Host '    Open PowerToys Settings -> General -> Backup & restore -> Restore,' -ForegroundColor White
    Write-Host "    and pick:  $(Split-Path -Leaf $destPtb)" -ForegroundColor White
    Write-Info 'then restart PowerToys'
}

# --- 5. AutoHotkey at login ---------------------------------------------------
if ($NoStartup) {
    Write-Step 'Startup shortcut (skipped)'
} else {
    Write-Step 'Setting up AutoHotkey at login'

    $ahkScript = Join-Path $ScriptDir 'WindowManager.ahk'
    $startup   = [Environment]::GetFolderPath('Startup')
    $lnk       = Join-Path $startup 'WindowManager.lnk'

    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($lnk)
    if ($ahkExe) {
        # Point at the interpreter directly so it works even if .ahk isn't associated.
        $sc.TargetPath = $ahkExe
        $sc.Arguments  = "`"$ahkScript`""
    } else {
        $sc.TargetPath = $ahkScript
    }
    $sc.WorkingDirectory = $ScriptDir      # the script #Includes VD.ah2 from here
    $sc.Description = 'LucasSetup window manager'
    $sc.Save()
    Write-Ok "startup shortcut -> $lnk"

    if (-not (Get-Process AutoHotkey* -ErrorAction SilentlyContinue)) {
        if ($ahkExe) {
            Start-Process $ahkExe -ArgumentList "`"$ahkScript`"" -WorkingDirectory $ScriptDir
            Write-Ok 'WindowManager.ahk started'
        } else {
            Write-Warn  'AutoHotkey v2 not found - start WindowManager.ahk by hand'
        }
    } else {
        Write-Info 'an AutoHotkey process is already running - not starting another'
    }
}

Write-Step 'Done'
Write-Info 'Keep this folder where it is - the Startup shortcut points at it.'
if (-not $ApplyDirect) { Write-Info 'PowerToys restore is still waiting for you (step 4 above).' }
