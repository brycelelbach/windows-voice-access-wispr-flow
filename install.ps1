[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$NoStart,
    [string]$ProfileRoot
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\voice-commands.ps1')
if ($ProfileRoot) {
    # Alternate profile used by the integration tests.
    $roaming = [IO.Path]::GetFullPath($ProfileRoot)
    $startup = Join-Path $roaming 'Startup'
} else {
    $roaming = [Environment]::GetFolderPath('ApplicationData')
    $startup = [Environment]::GetFolderPath('Startup')
}
$folder = Join-Path $roaming 'VoiceAccess\WisprModeMemory'
$configPath = Join-Path $roaming 'VoiceAccess\CustomCommands\en-US\CustomCommands.json'
$exe = Join-Path $folder 'VoiceModeMemory.exe'
$license = Join-Path $folder 'LICENSE'
$template = Join-Path $folder 'Default action.lnk'
$login = Join-Path $startup 'Wispr Voice Access Mode Memory.lnk'
$release = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'release.json') | ConvertFrom-Json
$sourceLicense = Join-Path $PSScriptRoot 'LICENSE'
$shell = New-Object -ComObject WScript.Shell
$created = [Collections.Generic.List[string]]::new()
$newProcess = $null

function Assert-FileHash([string]$File, [string]$Hash) {
    if ((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Hash) { throw "Unexpected file at $File (SHA-256 mismatch)." }
}
function Test-ExpectedLink([string]$Path, [string]$Arguments) {
    if (![IO.File]::Exists($Path)) { return $false }
    $link = $shell.CreateShortcut($Path)
    if ($link.TargetPath -ine $exe -or [string]$link.Arguments -cne $Arguments) { throw "Another shortcut already uses $Path." }
    return $true
}
function Add-Link([string]$Path, [string]$Arguments) {
    if (Test-ExpectedLink $Path $Arguments) { return }
    $temp = Join-Path ([IO.Path]::GetDirectoryName($Path)) ("." + [guid]::NewGuid() + ".lnk")
    try {
        $link = $shell.CreateShortcut($temp)
        $link.TargetPath = $exe
        $link.WorkingDirectory = $folder
        $link.Arguments = $Arguments
        $link.Save()
        [void](Test-ExpectedLink $temp $Arguments)
        [IO.File]::Move($temp, $Path)
        $created.Add($Path)
    } finally { [IO.File]::Delete($temp) }
}
function Add-File([string]$Source, [string]$Target, [string]$Hash) {
    if ([IO.File]::Exists($Target)) { Assert-FileHash $Target $Hash; return }
    $temp = "$Target.$([guid]::NewGuid()).tmp"
    try {
        [IO.File]::Copy($Source, $temp)
        Assert-FileHash $temp $Hash
        [IO.File]::Move($temp, $Target)
        $created.Add($Target)
    } finally { [IO.File]::Delete($temp) }
}
function Get-HelperProcess {
    # Scope process operations to this session and the exact install path.
    $session = (Get-Process -Id $PID).SessionId
    Get-Process -Name VoiceModeMemory -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $session -and $_.Path -ieq $exe }
}

$lock = [Threading.Mutex]::new($false, 'Local\WisprVoiceAccessModeMemorySetup')
$owned = $false
try {
    try { $owned = $lock.WaitOne(30000) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (!$owned) { throw 'Another setup is in progress.' }
    $update = Get-CommandUpdate $configPath $folder $Uninstall.IsPresent
    $licenseHash = (Get-FileHash -LiteralPath $sourceLicense).Hash
    if ([IO.File]::Exists($exe)) { Assert-FileHash $exe $release.sha256 }
    if ([IO.File]::Exists($license)) { Assert-FileHash $license $licenseHash }
    [void](Test-ExpectedLink $template 'action')
    [void](Test-ExpectedLink $login '')

    if ($Uninstall) {
        $backup = Save-CommandUpdate $configPath $update
        foreach ($process in @(Get-HelperProcess)) {
            $process | Stop-Process -ErrorAction Stop
            if (!$process.WaitForExit(5000)) { throw 'The helper is still running. Retry uninstall.' }
        }
        foreach ($path in @($login, $template, (Join-Path $folder 'Return to default.lnk'), $exe, $license)) {
            if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
        }
        if ([IO.Directory]::Exists($folder) -and [IO.Directory]::GetFileSystemEntries($folder).Length -eq 0) { [IO.Directory]::Delete($folder) }
    } else {
        $source = Join-Path $PSScriptRoot 'VoiceModeMemory.exe'
        if (![IO.File]::Exists($source)) { $source = (& (Join-Path $PSScriptRoot 'build.ps1')).FullName }
        Assert-FileHash $source $release.sha256
        [void][IO.Directory]::CreateDirectory($folder)
        [void][IO.Directory]::CreateDirectory($startup)
        Add-File $source $exe $release.sha256
        Add-File $sourceLicense $license $licenseHash
        Add-Link $template 'action'
        Add-Link $login ''
        if (!$NoStart -and !(Get-HelperProcess)) {
            $newProcess = Start-Process -FilePath $exe -PassThru -WindowStyle Hidden
            if ($newProcess.WaitForExit(1000)) { throw "Helper exited with code $($newProcess.ExitCode). Check for another running copy or a conflict with Ctrl+Alt+Shift+F9/F10." }
        }
        $backup = Save-CommandUpdate $configPath $update
    }
    [pscustomobject]@{ Executable = $exe; StartupShortcut = $login; VoiceShortcuts = $configPath; ConfigChanged = $update.Changed; Backup = $backup }
} catch {
    if (!$Uninstall) {
        if ($newProcess -and !$newProcess.HasExited) { $newProcess.Kill(); $newProcess.WaitForExit() }
        foreach ($path in $created) { [IO.File]::Delete($path) }
    }
    throw
} finally {
    if ($owned) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
